//! The wave 3 plumbing: the handle tags of the network and secret handles, reading a JSON
//! argument, writing a JSON or byte result, and mapping each source's failure onto a status
//! code with its message. No `extern "C"` function lives here; the exports are in
//! `network.rs` and `data.rs`, which `build.rs` hands to csbindgen beside `lib.rs`.

use std::ffi::c_void;

use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use storyarc_core::downloads::LandingError;
use storyarc_core::downloads::transfer::TransferError;
use storyarc_core::io::CancelToken;
use storyarc_core::net::HttpError;
use storyarc_core::portability::DocumentFailure;
use storyarc_core::portability::sealing::SealingFailure;
use storyarc_core::sources::kavita::KavitaError;
use storyarc_core::sources::opds::{OpdsEntry, OpdsError, OpdsFeed, OpdsSection};
use storyarc_core::sources::smb::SmbError;

use crate::{
    STORYARC_ERROR_CANCELLED, STORYARC_ERROR_INVALID_ARGUMENT, STORYARC_ERROR_NOT_FOUND,
    STORYARC_ERROR_STORAGE, STORYARC_ERROR_UNAUTHORIZED, STORYARC_ERROR_UNREACHABLE,
    STORYARC_ERROR_UNREADABLE, STORYARC_ERROR_UNSUPPORTED, StoryArcBuffer, fail,
};

pub(crate) const RUNTIME: u32 = u32::from_be_bytes(*b"SArt");
pub(crate) const HTTP: u32 = u32::from_be_bytes(*b"SAht");
pub(crate) const SHARE: u32 = u32::from_be_bytes(*b"SAsm");
pub(crate) const VAULT: u32 = u32::from_be_bytes(*b"SAvt");

/// `len` bytes of UTF-8 JSON at `data` as a `T`, or `INVALID_ARGUMENT` naming `what`.
///
/// # Safety
///
/// `data` must point to `len` readable bytes, or be null when `len` is zero.
pub(crate) unsafe fn json_arg<T: DeserializeOwned>(
    data: *const u8,
    len: usize,
    what: &str,
) -> Result<T, i32> {
    // SAFETY: the caller's promise, passed on.
    let text = unsafe { crate::seam::utf8(data, len, what)? };
    serde_json::from_str(text).map_err(|e| {
        fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("{what} is not the expected JSON: {e}"),
        )
    })
}

/// `len` raw bytes at `data`, copied.
///
/// # Safety
///
/// As [`json_arg`].
pub(crate) unsafe fn bytes_arg(data: *const u8, len: usize, what: &str) -> Result<Vec<u8>, i32> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if data.is_null() {
        return Err(fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("{what} is null but its length is not zero"),
        ));
    }
    // SAFETY: the caller promises `len` readable bytes at the non-null `data`.
    Ok(unsafe { std::slice::from_raw_parts(data, len) }.to_vec())
}

/// Writes `bytes` to `out` as a buffer Rust owns.
///
/// # Safety
///
/// `out` must be null or point to one writable `StoryArcBuffer`.
pub(crate) unsafe fn write_bytes(out: *mut StoryArcBuffer, bytes: Vec<u8>) -> Result<(), i32> {
    // SAFETY: the caller's promise, passed on.
    unsafe { crate::seam::write(out, StoryArcBuffer::from_vec(bytes), "out") }
}

/// Writes `value` to `out` as UTF-8 JSON.
///
/// # Safety
///
/// As [`write_bytes`].
pub(crate) unsafe fn write_json(
    out: *mut StoryArcBuffer,
    value: &impl Serialize,
) -> Result<(), i32> {
    let bytes = serde_json::to_vec(value)
        .map_err(|e| fail(crate::STORYARC_ERROR_INTERNAL, &e.to_string()))?;
    // SAFETY: the caller's promise, passed on.
    unsafe { write_bytes(out, bytes) }
}

/// Zeroes `out` before any work, so a failing call leaves an empty buffer to free.
///
/// # Safety
///
/// As [`write_bytes`].
pub(crate) unsafe fn clear(out: *mut StoryArcBuffer) -> Result<(), i32> {
    // SAFETY: the caller's promise, passed on.
    unsafe { write_bytes(out, Vec::new()) }
}

/// The caller's token, or a fresh one that never fires.
///
/// # Safety
///
/// `cancel` must be null or a live token from `storyarc_cancel_token_new`.
pub(crate) unsafe fn token(cancel: *const c_void) -> CancelToken {
    if cancel.is_null() {
        return CancelToken::new();
    }
    // SAFETY: the caller's promise.
    unsafe { &*cancel.cast::<CancelToken>() }.clone()
}

pub(crate) fn invalid(message: &str) -> i32 {
    fail(STORYARC_ERROR_INVALID_ARGUMENT, message)
}

pub(crate) fn smb_failure(error: &SmbError) -> i32 {
    let code = match error {
        SmbError::HostUnreachable => STORYARC_ERROR_UNREACHABLE,
        SmbError::ShareNotFound | SmbError::FileNotFound(_) => STORYARC_ERROR_NOT_FOUND,
        SmbError::AuthenticationRejected => STORYARC_ERROR_UNAUTHORIZED,
        SmbError::ProtocolUnsupported | SmbError::EncryptionRequired => STORYARC_ERROR_UNSUPPORTED,
        SmbError::Unexpected(_) => STORYARC_ERROR_UNREADABLE,
    };
    let message = match error.remedy() {
        Some(remedy) => format!("{error}. {remedy}"),
        None => error.to_string(),
    };
    fail(code, &message)
}

pub(crate) fn http_failure(error: &HttpError) -> i32 {
    let code = match error {
        HttpError::Unreachable(_) | HttpError::TimedOut => STORYARC_ERROR_UNREACHABLE,
        HttpError::Untrusted(_) => STORYARC_ERROR_UNAUTHORIZED,
        HttpError::Cancelled => STORYARC_ERROR_CANCELLED,
        HttpError::Sink(_) => STORYARC_ERROR_STORAGE,
        HttpError::Downgrade | HttpError::RefusedAddress | HttpError::TooManyRedirects => {
            STORYARC_ERROR_INVALID_ARGUMENT
        }
    };
    fail(code, &error.to_string())
}

pub(crate) fn opds_failure(error: &OpdsError) -> i32 {
    let code = match error {
        OpdsError::Unreachable(_) => STORYARC_ERROR_UNREACHABLE,
        OpdsError::Unauthorized(_) | OpdsError::Untrusted(_) => STORYARC_ERROR_UNAUTHORIZED,
        OpdsError::Http(404) => STORYARC_ERROR_NOT_FOUND,
        OpdsError::Downgrade | OpdsError::RefusedAddress | OpdsError::Redirect => {
            STORYARC_ERROR_INVALID_ARGUMENT
        }
        _ => STORYARC_ERROR_UNREADABLE,
    };
    // The untrusted certificate's fingerprint and the challenge are in the message, for the
    // pin sheet and the sign-in prompt.
    fail(code, &error.to_string())
}

pub(crate) fn kavita_failure(error: &KavitaError) -> i32 {
    let code = match error {
        KavitaError::Unreachable(_) => STORYARC_ERROR_UNREACHABLE,
        KavitaError::KeyRejected => STORYARC_ERROR_UNAUTHORIZED,
        KavitaError::BadAddress => STORYARC_ERROR_INVALID_ARGUMENT,
        KavitaError::Http(404) | KavitaError::RouteMissing(_) => STORYARC_ERROR_NOT_FOUND,
        KavitaError::Http(_) | KavitaError::UnexpectedResponse => STORYARC_ERROR_UNREADABLE,
    };
    fail(code, &error.to_string())
}

pub(crate) fn landing_failure(error: &LandingError) -> i32 {
    let code = match error {
        LandingError::Transfer(TransferError::Network(e)) => return http_failure(e),
        LandingError::Transfer(TransferError::Cancelled) => STORYARC_ERROR_CANCELLED,
        LandingError::Transfer(TransferError::Http(404)) => STORYARC_ERROR_NOT_FOUND,
        LandingError::Transfer(TransferError::Http(401 | 403)) => STORYARC_ERROR_UNAUTHORIZED,
        LandingError::Transfer(TransferError::Http(_) | TransferError::Short { .. }) => {
            STORYARC_ERROR_UNREACHABLE
        }
        LandingError::Transfer(TransferError::Disk(_)) | LandingError::Disk(_) => {
            STORYARC_ERROR_STORAGE
        }
        LandingError::Unreadable => STORYARC_ERROR_UNREADABLE,
        LandingError::Unsupported(_) => STORYARC_ERROR_UNSUPPORTED,
    };
    fail(code, &error.to_string())
}

pub(crate) fn document_failure(error: &DocumentFailure) -> i32 {
    let code = match error {
        DocumentFailure::NewerThanThisApp { .. } | DocumentFailure::NoMigrationPath { .. } => {
            STORYARC_ERROR_UNSUPPORTED
        }
        _ => STORYARC_ERROR_UNREADABLE,
    };
    fail(code, &error.to_string())
}

pub(crate) fn sealing_failure(error: &SealingFailure) -> i32 {
    let code = match error {
        SealingFailure::WrongPassphraseOrDamaged => STORYARC_ERROR_UNAUTHORIZED,
        SealingFailure::Unsupported => STORYARC_ERROR_UNSUPPORTED,
        SealingFailure::EmptyPassphrase => STORYARC_ERROR_INVALID_ARGUMENT,
        SealingFailure::Malformed | SealingFailure::NoRandomness => STORYARC_ERROR_UNREADABLE,
    };
    fail(code, &error.to_string())
}

fn section(section: &OpdsSection) -> Value {
    json!({ "title": section.title, "href": section.href.as_str(), "count": section.count })
}

fn entry(entry: &OpdsEntry) -> Value {
    json!({
        "id": entry.id,
        "title": entry.title,
        "authors": entry.authors,
        "summary": entry.summary,
        "series": entry.series,
        "seriesIndex": entry.series_index,
        "updated": entry.updated,
        "cover": entry.cover.as_ref().map(|u| u.as_str()),
        "thumbnail": entry.thumbnail.as_ref().map(|u| u.as_str()),
        "best": entry.best_acquisition().map(|a| json!({
            "href": a.href.as_str(), "mediaType": a.media_type, "length": a.length,
        })),
        "unreadableFormats": entry.unreadable_formats(),
    })
}

/// A catalogue page as the Windows app reads it.
pub(crate) fn feed(feed: &OpdsFeed) -> Value {
    json!({
        "title": feed.title,
        "dialect": match feed.version {
            storyarc_core::sources::opds::OpdsVersion::Atom => "atom",
            storyarc_core::sources::opds::OpdsVersion::Json => "json",
        },
        "navigation": feed.navigation.iter().map(section).collect::<Vec<_>>(),
        "publications": feed.publications.iter().map(entry).collect::<Vec<_>>(),
        "groups": feed.groups.iter().map(|g| json!({
            "title": g.title,
            "navigation": g.navigation.iter().map(section).collect::<Vec<_>>(),
            "publications": g.publications.iter().map(entry).collect::<Vec<_>>(),
            "more": g.more.as_ref().map(|u| u.as_str()),
        })).collect::<Vec<_>>(),
        "facets": feed.facets.iter().map(|f| json!({
            "group": f.group, "title": f.title, "href": f.href.as_str(),
            "count": f.count, "isActive": f.is_active,
        })).collect::<Vec<_>>(),
        "next": feed.next.as_ref().map(|u| u.as_str()),
        "searchable": feed.search_template.is_some() || feed.search_description.is_some(),
    })
}
