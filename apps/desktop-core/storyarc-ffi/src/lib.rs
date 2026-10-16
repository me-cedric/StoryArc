//! C ABI over `storyarc-core`. The header is `include/storyarc_ffi.h` and the C# side is
//! `generated/NativeMethods.g.cs`, written by `build.rs`. Keep the three in step.
//!
//! The seam's rules (design.md, Decision 5): opaque handles, byte buffers that Rust owns and
//! `storyarc_buffer_free` releases, integer status codes with `storyarc_last_error` for the
//! message, and `storyarc_cancel` on a token for cancellation. Task 1.8a exports the four
//! calls the interop tests exercise; later waves add publication handles under the same
//! rules.

use std::cell::RefCell;
use std::ffi::{CString, c_char, c_void};
use std::sync::OnceLock;

use storyarc_core::io::CancelToken;

/// The call succeeded.
pub const STORYARC_OK: i32 = 0;
/// A pointer or length the call cannot work with. The message names which.
pub const STORYARC_ERROR_INVALID_ARGUMENT: i32 = 1;
/// The call was abandoned because its cancel token fired.
pub const STORYARC_ERROR_CANCELLED: i32 = 2;

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

    /// The committed C# file is what `build.rs` wrote for *this* source: every export has a
    /// `DllImport`, under the library name the Windows app loads.
    #[test]
    fn the_generated_csharp_declares_every_export() {
        let generated = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("generated/NativeMethods.g.cs"),
        )
        .expect("build.rs wrote generated/NativeMethods.g.cs");
        for export in [
            "storyarc_core_version",
            "storyarc_buffer_roundtrip",
            "storyarc_buffer_free",
            "storyarc_last_error",
            "storyarc_cancel_token_new",
            "storyarc_cancel",
            "storyarc_cancel_token_is_cancelled",
            "storyarc_cancel_token_free",
        ] {
            assert!(
                generated.contains(&format!("EntryPoint = \"{export}\"")),
                "{export} has no DllImport in the generated file"
            );
        }
        assert!(generated.contains("__DllName = \"storyarc_ffi\""));
        assert!(generated.contains("namespace StoryArc.Interop"));
        assert!(generated.contains("struct StoryArcBuffer"));
    }

    /// The hand-written header and the generated C# name the same exports.
    #[test]
    fn the_c_header_declares_every_export() {
        let header = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("include/storyarc_ffi.h"),
        )
        .expect("include/storyarc_ffi.h");
        for export in [
            "storyarc_core_version",
            "storyarc_buffer_roundtrip",
            "storyarc_buffer_free",
            "storyarc_last_error",
            "storyarc_cancel_token_new",
            "storyarc_cancel(",
            "storyarc_cancel_token_is_cancelled",
            "storyarc_cancel_token_free",
        ] {
            assert!(
                header.contains(export),
                "{export} is missing from the header"
            );
        }
    }
}
