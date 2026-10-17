//! C ABI over `storyarc-core`. The header is `include/storyarc_ffi.h` and the C# side is
//! `generated/NativeMethods.g.cs`, written by `build.rs`. Keep the three in step.
//!
//! The seam's rules (design.md, Decision 5): opaque handles, byte buffers that Rust owns and
//! `storyarc_buffer_free` releases, integer status codes with `storyarc_last_error` for the
//! message, and `storyarc_cancel` on a token for cancellation. Task 1.8a exported the four
//! calls the interop tests exercise. Wave 2 adds three tagged handles over
//! `storyarc_core::library` — a folder source, an open publication and the progress store —
//! with records crossing as UTF-8 JSON and pages as RGBA buffers. Wave 3 adds the network
//! (`network.rs`: the runtime, HTTP with pins, SMB, OPDS, Kavita, the metered flag, a
//! download) and the reader's data (`data.rs`: the vault, the download queue's rules, shelves
//! and offline edits, the library document and sync, sealed secrets, the diagnostic, storage),
//! with two more status codes for a grey unreachable source and a refused credential. Wave
//! 4 adds reading (`reading.rs`: the EPUB manifest, positions and resources for the
//! bundle, and the PDF engine).
//!
//! A handle is used by one thread at a time and released once by its own `_free`; releasing
//! null is a no-op. Paths and JSON arrive as UTF-8 bytes with a length, never NUL-terminated.

mod data;
mod network;
mod reading;
mod records;
mod seam;

pub use data::*;
pub use network::*;
pub use reading::*;

use std::cell::RefCell;
use std::ffi::{CString, c_char, c_void};
use std::sync::OnceLock;

use storyarc_core::domain::{PublicationIdentity, ReadingProgress};
use storyarc_core::io::CancelToken;
use storyarc_core::library::{FolderSource, OpenPublication, ProgressStore};

use seam::{FOLDER, PUBLICATION, STORE, borrow, guard, into_handle, library_failure, release};

/// The call succeeded.
pub const STORYARC_OK: i32 = 0;
/// A pointer, length, handle or index the call cannot work with. The message names which.
pub const STORYARC_ERROR_INVALID_ARGUMENT: i32 = 1;
/// The call was abandoned because its cancel token fired.
pub const STORYARC_ERROR_CANCELLED: i32 = 2;
/// Nothing at the path the call was given.
pub const STORYARC_ERROR_NOT_FOUND: i32 = 3;
/// A format or codec this build refuses. The message names it, for the reader.
pub const STORYARC_ERROR_UNSUPPORTED: i32 = 4;
/// A publication or page in a supported format that is damaged, locked or too large.
pub const STORYARC_ERROR_UNREADABLE: i32 = 5;
/// The local store refused, or the disk is full.
pub const STORYARC_ERROR_STORAGE: i32 = 6;
/// The core failed in a way it has no case for. A defect, reported rather than a crash.
pub const STORYARC_ERROR_INTERNAL: i32 = 7;
/// The source, server or sync place did not answer. Grey, never red: try again later.
pub const STORYARC_ERROR_UNREACHABLE: i32 = 8;
/// A credential, key or passphrase was refused, or a certificate is not trusted; the message
/// names the challenge or the fingerprint.
pub const STORYARC_ERROR_UNAUTHORIZED: i32 = 9;

/// Bytes Rust owns. The caller reads `len` bytes at `data` and hands the whole struct back
/// to `storyarc_buffer_free` exactly once. `data` is null when `len` is zero.
#[repr(C)]
pub struct StoryArcBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl StoryArcBuffer {
    fn from_vec(bytes: Vec<u8>) -> Self {
        if bytes.capacity() == 0 {
            return Self {
                data: std::ptr::null_mut(),
                len: 0,
                capacity: 0,
            };
        }
        let mut bytes = std::mem::ManuallyDrop::new(bytes);
        Self {
            data: bytes.as_mut_ptr(),
            len: bytes.len(),
            capacity: bytes.capacity(),
        }
    }
}

thread_local! {
    /// The message of the most recent failing call on this thread.
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// Records `message` for `storyarc_last_error` and returns `code`, so a failing call is
/// one expression.
fn fail(code: i32, message: &str) -> i32 {
    let text = CString::new(message.replace('\0', " ")).unwrap_or_default();
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(text));
    code
}

/// Returns the core version as a static NUL-terminated string. The caller never frees it.
#[unsafe(no_mangle)]
pub extern "C" fn storyarc_core_version() -> *const c_char {
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION
        .get_or_init(|| CString::new(storyarc_core::version()).expect("version has no NUL byte"))
        .as_ptr()
}

/// Copies `len` bytes at `data` into a buffer Rust owns and writes it to `out`.
///
/// The round trip the interop tests use to prove caller-owned bytes cross the seam and
/// Rust-owned bytes come back. Returns `STORYARC_OK`, or `STORYARC_ERROR_INVALID_ARGUMENT`
/// when `out` is null or `data` is null with a non-zero `len`.
///
/// # Safety
///
/// `data` must point to `len` readable bytes, or be null when `len` is zero. `out` must be
/// null or point to writable storage for one `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_buffer_roundtrip(
    data: *const u8,
    len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    if out.is_null() {
        return fail(STORYARC_ERROR_INVALID_ARGUMENT, "out is null");
    }
    let bytes = if len == 0 {
        Vec::new()
    } else if data.is_null() {
        return fail(
            STORYARC_ERROR_INVALID_ARGUMENT,
            "data is null but len is not zero",
        );
    } else {
        // SAFETY: the caller promises `len` readable bytes at the non-null `data`.
        unsafe { std::slice::from_raw_parts(data, len) }.to_vec()
    };
    // SAFETY: `out` is non-null and the caller promises it is writable.
    unsafe { out.write(StoryArcBuffer::from_vec(bytes)) };
    STORYARC_OK
}

/// Releases a buffer a call of this library returned. A buffer with no capacity is a
/// no-op, so a zeroed struct is safe to free.
///
/// # Safety
///
/// `buffer` must be exactly as a call of this library returned it, and freed only once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_buffer_free(buffer: StoryArcBuffer) {
    if buffer.capacity == 0 || buffer.data.is_null() {
        return;
    }
    // SAFETY: the three fields are the ones `StoryArcBuffer::from_vec` took from a `Vec<u8>`
    // this library allocated, and the caller frees the buffer once.
    drop(unsafe { Vec::from_raw_parts(buffer.data, buffer.len, buffer.capacity) });
}

/// The message of the most recent failing call on the calling thread, as a NUL-terminated
/// UTF-8 string, or null when no call on this thread has failed. The pointer stays valid
/// until the next failing call on the same thread; the caller never frees it.
#[unsafe(no_mangle)]
pub extern "C" fn storyarc_last_error() -> *const c_char {
    LAST_ERROR.with(|slot| {
        slot.borrow()
            .as_ref()
            .map_or(std::ptr::null(), |text| text.as_ptr())
    })
}

/// A new cancel token, not yet cancelled. Freed with `storyarc_cancel_token_free`.
#[unsafe(no_mangle)]
pub extern "C" fn storyarc_cancel_token_new() -> *mut c_void {
    Box::into_raw(Box::new(CancelToken::new())).cast()
}

/// Raises the token. Every read behind it stops with `STORYARC_ERROR_CANCELLED`. A null
/// token is ignored; cancelling twice is harmless.
///
/// # Safety
///
/// `token` must be null or a token `storyarc_cancel_token_new` returned that has not been
/// freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_cancel(token: *mut c_void) {
    if token.is_null() {
        return;
    }
    // SAFETY: the caller promises a live token from `storyarc_cancel_token_new`.
    unsafe { &*token.cast::<CancelToken>() }.cancel();
}

/// Whether the token has been raised: 1 when it has, 0 when it has not or is null.
///
/// # Safety
///
/// `token` must be null or a token `storyarc_cancel_token_new` returned that has not been
/// freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_cancel_token_is_cancelled(token: *const c_void) -> i32 {
    if token.is_null() {
        return 0;
    }
    // SAFETY: the caller promises a live token from `storyarc_cancel_token_new`.
    i32::from(unsafe { &*token.cast::<CancelToken>() }.is_cancelled())
}

/// Frees a token. A null token is ignored.
///
/// # Safety
///
/// `token` must be null or a token `storyarc_cancel_token_new` returned, freed only once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_cancel_token_free(token: *mut c_void) {
    if token.is_null() {
        return;
    }
    // SAFETY: the caller promises a token from `storyarc_cancel_token_new`, freed once.
    drop(unsafe { Box::from_raw(token.cast::<CancelToken>()) });
}

/// Scans the folder at the UTF-8 path `path` (`path_len` bytes) and writes a folder handle
/// to `out_folder`, freed with `storyarc_folder_free`. `cancel` may be null; when it fires
/// the call returns `STORYARC_ERROR_CANCELLED` and no handle. A missing folder is
/// `STORYARC_ERROR_NOT_FOUND`.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes. `cancel` must be null or a live token.
/// `out_folder` must point to writable storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_folder_open(
    path: *const u8,
    path_len: usize,
    cancel: *const c_void,
    out_folder: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { seam::write(out_folder, std::ptr::null_mut(), "out_folder")? };
        let path = unsafe { seam::utf8(path, path_len, "path")? };
        let token = if cancel.is_null() {
            CancelToken::new()
        } else {
            // SAFETY: the caller promises a live token from `storyarc_cancel_token_new`.
            unsafe { &*cancel.cast::<CancelToken>() }.clone()
        };
        let source = FolderSource::open(path, &token).map_err(|e| library_failure(&e))?;
        if source.was_cancelled() {
            return Err(fail(
                STORYARC_ERROR_CANCELLED,
                "the folder scan was cancelled",
            ));
        }
        // SAFETY: checked writable above.
        unsafe { out_folder.write(into_handle(FOLDER, source)) };
        Ok(())
    })
}

/// Writes the folder's publications to `out` as a UTF-8 JSON array of publication records,
/// the shape the phones' library documents use. Free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// `folder` must be null or a live folder handle. `out` must point to one writable
/// `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_folder_records(
    folder: *const c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let source: &FolderSource = unsafe { borrow(folder, FOLDER, "folder")? };
        let records = StoryArcBuffer::from_vec(source.records_json().into_bytes());
        unsafe { seam::write(out, records, "out") }
    })
}

/// Releases a folder handle. Null is ignored.
///
/// # Safety
///
/// `folder` must be null or a live folder handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_folder_free(folder: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<FolderSource>(folder, FOLDER) };
}

/// Opens the comic at the UTF-8 path `path` (`path_len` bytes) — a CBZ, CBR, CBT or a
/// folder of images — and writes a publication handle to `out_publication`, freed with
/// `storyarc_publication_free`. A refused format is `STORYARC_ERROR_UNSUPPORTED` with its
/// name in the message.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes. `out_publication` must point to writable
/// storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_publication_open(
    path: *const u8,
    path_len: usize,
    out_publication: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { seam::write(out_publication, std::ptr::null_mut(), "out_publication")? };
        let path = unsafe { seam::utf8(path, path_len, "path")? };
        let opened = OpenPublication::open(path).map_err(|e| library_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_publication.write(into_handle(PUBLICATION, opened)) };
        Ok(())
    })
}

/// Writes the publication's page count to `out_count`.
///
/// # Safety
///
/// `publication` must be null or a live publication handle. `out_count` must point to one
/// writable `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_publication_page_count(
    publication: *const c_void,
    out_count: *mut u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let opened: &OpenPublication = unsafe { borrow(publication, PUBLICATION, "publication")? };
        let count = u32::try_from(opened.page_count()).unwrap_or(u32::MAX);
        unsafe { seam::write(out_count, count, "out_count") }
    })
}

/// Writes the publication's record to `out` as a UTF-8 JSON object: title, series, number,
/// authors, identity, page count and the rest. Free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// `publication` must be null or a live publication handle. `out` must point to one
/// writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_publication_metadata(
    publication: *const c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let opened: &OpenPublication = unsafe { borrow(publication, PUBLICATION, "publication")? };
        let record = StoryArcBuffer::from_vec(opened.metadata_json().into_bytes());
        unsafe { seam::write(out, record, "out") }
    })
}

/// Decodes page `index` to 8-bit RGBA, not premultiplied, rows top to bottom with no
/// padding, at most `max_pixel_size` on its longest edge (zero for the page's own size).
/// Writes the pixels to `out_pixels` (`width * height * 4` bytes, freed with
/// `storyarc_buffer_free`) and the size to `out_width` and `out_height`. On failure the
/// three are zeroed: an index past the end is `STORYARC_ERROR_INVALID_ARGUMENT`, a codec
/// this build refuses `STORYARC_ERROR_UNSUPPORTED`, a damaged page
/// `STORYARC_ERROR_UNREADABLE`, each with the codec named in the message.
///
/// # Safety
///
/// `publication` must be null or a live publication handle. `out_pixels` must point to one
/// writable `StoryArcBuffer`, `out_width` and `out_height` to one writable `uint32_t` each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_publication_decode_page(
    publication: *const c_void,
    index: u32,
    max_pixel_size: u32,
    out_pixels: *mut StoryArcBuffer,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on; every output is zeroed before any work.
        unsafe {
            seam::write(
                out_pixels,
                StoryArcBuffer::from_vec(Vec::new()),
                "out_pixels",
            )?;
            seam::write(out_width, 0, "out_width")?;
            seam::write(out_height, 0, "out_height")?;
        }
        let opened: &OpenPublication = unsafe { borrow(publication, PUBLICATION, "publication")? };
        let limit = (max_pixel_size > 0).then_some(max_pixel_size);
        let page = opened
            .decode_page(index as usize, limit)
            .map_err(|e| library_failure(&e))?;
        // SAFETY: all three checked writable above.
        unsafe {
            out_width.write(page.width);
            out_height.write(page.height);
            out_pixels.write(StoryArcBuffer::from_vec(page.rgba));
        }
        Ok(())
    })
}

/// Releases a publication handle. Null is ignored.
///
/// # Safety
///
/// `publication` must be null or a live publication handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_publication_free(publication: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<OpenPublication>(publication, PUBLICATION) };
}

/// Opens or creates the progress store at the UTF-8 path `path` (`path_len` bytes) and
/// writes a store handle to `out_store`, freed with `storyarc_store_free`.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes. `out_store` must point to writable
/// storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_store_open(
    path: *const u8,
    path_len: usize,
    out_store: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { seam::write(out_store, std::ptr::null_mut(), "out_store")? };
        let path = unsafe { seam::utf8(path, path_len, "path")? };
        let store = ProgressStore::open(path).map_err(|e| library_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_store.write(into_handle(STORE, store)) };
        Ok(())
    })
}

/// Reads the progress record of the publication whose identity is the UTF-8 JSON object at
/// `identity_json` (`serverSourceId`, `serverRemoteId`, `contentDigest`, `normalizedPath`,
/// any of them). Writes the record to `out` as UTF-8 JSON, or `null` when there is none;
/// free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// `store` must be null or a live store handle. `identity_json` must point to
/// `identity_len` readable bytes. `out` must point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_progress_read(
    store: *const c_void,
    identity_json: *const u8,
    identity_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let store: &ProgressStore = unsafe { borrow(store, STORE, "store")? };
        let text = unsafe { seam::utf8(identity_json, identity_len, "identity_json")? };
        let identity: PublicationIdentity = serde_json::from_str(text).map_err(|error| {
            fail(
                STORYARC_ERROR_INVALID_ARGUMENT,
                &format!("identity_json is not an identity: {error}"),
            )
        })?;
        let record = store.read(&identity).map_err(|e| library_failure(&e))?;
        let json = serde_json::to_string(&record)
            .map_err(|error| fail(STORYARC_ERROR_INTERNAL, &error.to_string()))?;
        unsafe { seam::write(out, StoryArcBuffer::from_vec(json.into_bytes()), "out") }
    })
}

/// Records a position: the UTF-8 JSON progress record at `record_json`, in the shape the
/// phones' library documents use. Finished stays finished. A record that is not one is
/// `STORYARC_ERROR_INVALID_ARGUMENT`; a full disk is `STORYARC_ERROR_STORAGE`.
///
/// # Safety
///
/// `store` must be null or a live store handle. `record_json` must point to `record_len`
/// readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_progress_write(
    store: *const c_void,
    record_json: *const u8,
    record_len: usize,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let store: &ProgressStore = unsafe { borrow(store, STORE, "store")? };
        let text = unsafe { seam::utf8(record_json, record_len, "record_json")? };
        let record: ReadingProgress = serde_json::from_str(text).map_err(|error| {
            fail(
                STORYARC_ERROR_INVALID_ARGUMENT,
                &format!("record_json is not a progress record: {error}"),
            )
        })?;
        store.write(&record).map_err(|e| library_failure(&e))
    })
}

/// Releases a store handle. Null is ignored.
///
/// # Safety
///
/// `store` must be null or a live store handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_store_free(store: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<ProgressStore>(store, STORE) };
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    fn last_error() -> Option<String> {
        let raw = storyarc_last_error();
        if raw.is_null() {
            return None;
        }
        Some(unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned())
    }

    #[test]
    fn version_matches_the_core_and_is_stable() {
        let first = storyarc_core_version();
        let text = unsafe { CStr::from_ptr(first) }.to_str().expect("utf-8");
        assert_eq!(text, storyarc_core::version());
        assert_eq!(
            first,
            storyarc_core_version(),
            "the pointer must stay the same"
        );
    }

    #[test]
    fn bytes_round_trip_through_a_rust_owned_buffer_and_are_freed() {
        let sent = [1u8, 2, 3, 250, 0, 7];
        let mut out = StoryArcBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        let status = unsafe { storyarc_buffer_roundtrip(sent.as_ptr(), sent.len(), &mut out) };
        assert_eq!(status, STORYARC_OK);
        assert_eq!(out.len, sent.len());
        assert!(out.capacity >= out.len);
        let received = unsafe { std::slice::from_raw_parts(out.data, out.len) };
        assert_eq!(received, &sent);
        unsafe { storyarc_buffer_free(out) };
    }

    #[test]
    fn an_empty_round_trip_is_a_null_buffer_that_frees_safely() {
        let mut out = StoryArcBuffer {
            data: std::ptr::null_mut(),
            len: 9,
            capacity: 9,
        };
        let status = unsafe { storyarc_buffer_roundtrip(std::ptr::null(), 0, &mut out) };
        assert_eq!(status, STORYARC_OK);
        assert!(out.data.is_null());
        assert_eq!((out.len, out.capacity), (0, 0));
        unsafe { storyarc_buffer_free(out) };
    }

    #[test]
    fn a_failing_call_returns_a_code_and_last_error_names_the_cause() {
        let mut out = StoryArcBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        let status = unsafe { storyarc_buffer_roundtrip(std::ptr::null(), 4, &mut out) };
        assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
        assert_eq!(
            last_error().as_deref(),
            Some("data is null but len is not zero")
        );
        let status =
            unsafe { storyarc_buffer_roundtrip(std::ptr::null(), 0, std::ptr::null_mut()) };
        assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
        assert_eq!(last_error().as_deref(), Some("out is null"));
    }

    #[test]
    fn the_last_error_is_per_thread() {
        let mut out = StoryArcBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        unsafe { storyarc_buffer_roundtrip(std::ptr::null(), 1, &mut out) };
        assert!(last_error().is_some());
        let elsewhere = std::thread::spawn(last_error).join().unwrap();
        assert_eq!(elsewhere, None, "another thread has not failed");
    }

    #[test]
    fn a_cancel_token_is_raised_through_the_seam() {
        let token = storyarc_cancel_token_new();
        assert!(!token.is_null());
        assert_eq!(unsafe { storyarc_cancel_token_is_cancelled(token) }, 0);
        unsafe { storyarc_cancel(token) };
        assert_eq!(unsafe { storyarc_cancel_token_is_cancelled(token) }, 1);
        unsafe { storyarc_cancel(token) };
        unsafe { storyarc_cancel_token_free(token) };
        // Null is ignored everywhere, so a C# wrapper disposed twice cannot crash the app.
        unsafe { storyarc_cancel(std::ptr::null_mut()) };
        assert_eq!(
            unsafe { storyarc_cancel_token_is_cancelled(std::ptr::null()) },
            0
        );
        unsafe { storyarc_cancel_token_free(std::ptr::null_mut()) };
    }

    fn crate_file(relative: &str) -> String {
        std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(relative))
            .unwrap_or_else(|error| panic!("{relative}: {error}"))
    }

    /// Every `extern "C"` function the crate exports, read from the four files that hold
    /// them, so a new export cannot be added without the two checks below seeing it.
    fn exports() -> Vec<String> {
        let source = [
            "src/lib.rs",
            "src/network.rs",
            "src/data.rs",
            "src/reading.rs",
        ]
        .map(crate_file)
        .join("\n");
        let exports: Vec<String> = source
            .lines()
            .filter_map(|line| {
                let rest = line.trim_start().strip_prefix("pub ")?;
                let rest = rest.strip_prefix("unsafe ").unwrap_or(rest);
                let name = rest.strip_prefix("extern \"C\" fn ")?;
                Some(name.split('(').next()?.to_owned())
            })
            .collect();
        assert_eq!(exports.len(), 53, "{exports:?}");
        exports
    }

    /// The status codes, as this file defines them.
    const CODES: [(&str, i32); 10] = [
        ("STORYARC_OK", STORYARC_OK),
        (
            "STORYARC_ERROR_INVALID_ARGUMENT",
            STORYARC_ERROR_INVALID_ARGUMENT,
        ),
        ("STORYARC_ERROR_CANCELLED", STORYARC_ERROR_CANCELLED),
        ("STORYARC_ERROR_NOT_FOUND", STORYARC_ERROR_NOT_FOUND),
        ("STORYARC_ERROR_UNSUPPORTED", STORYARC_ERROR_UNSUPPORTED),
        ("STORYARC_ERROR_UNREADABLE", STORYARC_ERROR_UNREADABLE),
        ("STORYARC_ERROR_STORAGE", STORYARC_ERROR_STORAGE),
        ("STORYARC_ERROR_INTERNAL", STORYARC_ERROR_INTERNAL),
        ("STORYARC_ERROR_UNREACHABLE", STORYARC_ERROR_UNREACHABLE),
        ("STORYARC_ERROR_UNAUTHORIZED", STORYARC_ERROR_UNAUTHORIZED),
    ];

    /// The committed C# file is what `build.rs` wrote for *this* source: every export has a
    /// `DllImport` and every status code a constant, under the library name the Windows app
    /// loads.
    #[test]
    fn the_generated_csharp_declares_every_export_and_code() {
        let generated = crate_file("generated/NativeMethods.g.cs");
        for export in exports() {
            assert!(
                generated.contains(&format!("EntryPoint = \"{export}\"")),
                "{export} has no DllImport in the generated file"
            );
        }
        for (name, value) in CODES {
            assert!(
                generated.contains(&format!("internal const int {name} = {value};")),
                "{name} = {value} is not in the generated file"
            );
        }
        assert!(generated.contains("__DllName = \"storyarc_ffi\""));
        assert!(generated.contains("namespace StoryArc.Interop"));
        assert!(generated.contains("struct StoryArcBuffer"));
    }

    /// The hand-written header declares the same exports and the same codes.
    #[test]
    fn the_c_header_declares_every_export_and_code() {
        let header = crate_file("include/storyarc_ffi.h");
        for export in exports() {
            assert!(
                header.contains(&format!(" {export}(")) || header.contains(&format!("*{export}(")),
                "{export} is missing from the header"
            );
        }
        for (name, value) in CODES {
            assert!(
                header.contains(&format!("#define {name} {value}\n")),
                "{name} {value} is missing from the header"
            );
        }
    }
}
