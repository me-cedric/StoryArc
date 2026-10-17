//! What every export shares: tagged handles, reading the caller's arguments, mapping a
//! core failure onto a status code, and catching a panic before it reaches C#.
//!
//! No `extern "C"` function lives here. csbindgen reads `src/lib.rs` alone, so the exports
//! stay there and the plumbing they share stays here.

use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};

use storyarc_core::formats::ComicArchiveError;
use storyarc_core::image::PageDecodeError;
use storyarc_core::library::LibraryError;
use storyarc_core::sources::IndexError;

use crate::{
    STORYARC_ERROR_CANCELLED, STORYARC_ERROR_INTERNAL, STORYARC_ERROR_INVALID_ARGUMENT,
    STORYARC_ERROR_NOT_FOUND, STORYARC_ERROR_STORAGE, STORYARC_ERROR_UNREADABLE,
    STORYARC_ERROR_UNSUPPORTED, STORYARC_OK, fail,
};

/// The tags a handle carries in its first four bytes, so a folder handle passed where a
/// publication handle belongs is refused instead of read as the wrong type.
pub(crate) const FOLDER: u32 = u32::from_be_bytes(*b"SAfs");
pub(crate) const PUBLICATION: u32 = u32::from_be_bytes(*b"SApb");
pub(crate) const STORE: u32 = u32::from_be_bytes(*b"SAst");

/// What an opaque handle points at: the tag first, at offset zero for every `T`.
#[repr(C)]
struct Handle<T> {
    kind: u32,
    value: T,
}

/// A handle the caller owns until it hands it to the matching `_free`.
pub(crate) fn into_handle<T>(kind: u32, value: T) -> *mut c_void {
    Box::into_raw(Box::new(Handle { kind, value })).cast()
}

/// The value behind a handle, or `INVALID_ARGUMENT` naming what was wrong with it.
///
/// # Safety
///
/// `handle` must be null or a live handle this library returned.
pub(crate) unsafe fn borrow<'a, T>(
    handle: *const c_void,
    kind: u32,
    name: &str,
) -> Result<&'a T, i32> {
    if handle.is_null() {
        return Err(fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("the {name} handle is null"),
        ));
    }
    // SAFETY: every handle this library returns is a `Handle<_>`, `repr(C)` with its `u32`
    // tag first, so the first four bytes are readable and aligned whatever its kind.
    if unsafe { handle.cast::<u32>().read() } != kind {
        return Err(fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("the handle is not a {name} handle"),
        ));
    }
    // SAFETY: the tag says this handle was made by `into_handle::<T>` with this `kind`.
    Ok(unsafe { &(*handle.cast::<Handle<T>>()).value })
}

/// Releases a handle. Null, and a handle of another kind, are ignored.
///
/// # Safety
///
/// `handle` must be null or a live handle this library returned, released once.
pub(crate) unsafe fn release<T>(handle: *mut c_void, kind: u32) {
    if handle.is_null() {
        return;
    }
    // SAFETY: as in `borrow`, the tag is the first field of every handle.
    if unsafe { handle.cast::<u32>().read() } != kind {
        return;
    }
    // SAFETY: made by `into_handle::<T>` with this kind, and released once.
    drop(unsafe { Box::from_raw(handle.cast::<Handle<T>>()) });
}

/// `len` bytes at `data` as UTF-8, or `INVALID_ARGUMENT` naming `what`.
///
/// # Safety
///
/// `data` must point to `len` readable bytes, or be null when `len` is zero.
pub(crate) unsafe fn utf8<'a>(data: *const u8, len: usize, what: &str) -> Result<&'a str, i32> {
    if len == 0 {
        return Ok("");
    }
    if data.is_null() {
        return Err(fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("{what} is null but its length is not zero"),
        ));
    }
    // SAFETY: the caller promises `len` readable bytes at the non-null `data`.
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    std::str::from_utf8(bytes).map_err(|_| {
        fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("{what} is not UTF-8"),
        )
    })
}

/// Writes `value` to `out`, or refuses a null `out` naming `what`.
///
/// # Safety
///
/// `out` must be null or point to writable storage for one `T`.
pub(crate) unsafe fn write<T>(out: *mut T, value: T, what: &str) -> Result<(), i32> {
    if out.is_null() {
        return Err(fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            &format!("{what} is null"),
        ));
    }
    // SAFETY: non-null, and the caller promises it is writable.
    unsafe { out.write(value) };
    Ok(())
}

/// Runs an export's body: its status code, and a caught panic as `INTERNAL` rather than an
/// unwind across the C boundary, which would abort the Windows app.
pub(crate) fn guard(body: impl FnOnce() -> Result<(), i32>) -> i32 {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(())) => STORYARC_OK,
        Ok(Err(code)) => code,
        Err(_) => fail(
            STORYARC_ERROR_INTERNAL,
            "the core stopped on an internal error",
        ),
    }
}

/// A core failure as a status code, with its message recorded for `storyarc_last_error`.
pub(crate) fn library_failure(error: &LibraryError) -> i32 {
    fail(status(error), &error.to_string())
}

fn status(error: &LibraryError) -> i32 {
    match error {
        LibraryError::NotFound(_) => STORYARC_ERROR_NOT_FOUND,
        LibraryError::Index(error) => match error {
            IndexError::NotThere => STORYARC_ERROR_NOT_FOUND,
            IndexError::Cancelled => STORYARC_ERROR_CANCELLED,
            IndexError::Unsupported(_)
            | IndexError::FormatNotRecognised
            | IndexError::ContentProtected => STORYARC_ERROR_UNSUPPORTED,
            IndexError::ArchivePasswordProtected | IndexError::ArchiveUnreadable => {
                STORYARC_ERROR_UNREADABLE
            }
        },
        LibraryError::Archive(error) => match error {
            ComicArchiveError::Cancelled => STORYARC_ERROR_CANCELLED,
            ComicArchiveError::UnsupportedContainer(_)
            | ComicArchiveError::UnrecognisedContainer => STORYARC_ERROR_UNSUPPORTED,
            _ => STORYARC_ERROR_UNREADABLE,
        },
        LibraryError::NotPaged(_) => STORYARC_ERROR_UNSUPPORTED,
        LibraryError::PageOutOfRange { .. } => STORYARC_ERROR_INVALID_ARGUMENT,
        LibraryError::Decode(error) => match error {
            PageDecodeError::Unrecognised | PageDecodeError::Unsupported(_) => {
                STORYARC_ERROR_UNSUPPORTED
            }
            PageDecodeError::Failed { .. } | PageDecodeError::TooLarge { .. } => {
                STORYARC_ERROR_UNREADABLE
            }
        },
        LibraryError::Store(_) => STORYARC_ERROR_STORAGE,
    }
}
