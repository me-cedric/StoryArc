//! The one place this crate meets C: about ten `extern "C"` declarations over the vendored
//! libarchive, and the thinnest safe handle that owns a reader.
//!
//! `unsafe` is allowed in this module and nowhere else in `storyarc-core`. The workspace
//! forbids unsafe code; this crate lowers that to `deny` in its `Cargo.toml` so that this
//! one file can opt back in, and the reason is that calling a C library is impossible
//! without it. Everything above — `RarDecoder`, the archives, the library — is safe Rust
//! that cannot name a raw pointer. Keep it that way: a new binding goes here, behind a safe
//! method, with its invariants written down.
//!
//! Only the two RAR readers and the null filter are ever registered. Registering
//! `format_all` would pull every parser libarchive has into reach of a crafted file.
#![allow(unsafe_code)]

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::path::Path;

/// `la_ssize_t`: `ssize_t` on every target this crate compiles libarchive for.
type LaSsize = isize;
/// `la_int64_t`.
type LaInt64 = i64;

#[repr(C)]
struct archive {
    _opaque: [u8; 0],
}

#[repr(C)]
struct archive_entry {
    _opaque: [u8; 0],
}

type ReadCallback = unsafe extern "C" fn(*mut archive, *mut c_void, *mut *const c_void) -> LaSsize;

const ARCHIVE_EOF: c_int = 1;
const ARCHIVE_OK: c_int = 0;
const ARCHIVE_WARN: c_int = -20;

unsafe extern "C" {
    fn archive_read_new() -> *mut archive;
    fn archive_read_support_format_rar(a: *mut archive) -> c_int;
    fn archive_read_support_format_rar5(a: *mut archive) -> c_int;
    fn archive_read_support_filter_none(a: *mut archive) -> c_int;
    fn archive_read_open_filename(a: *mut archive, filename: *const c_char, block: usize) -> c_int;
    fn archive_read_open(
        a: *mut archive,
        client_data: *mut c_void,
        opener: Option<unsafe extern "C" fn(*mut archive, *mut c_void) -> c_int>,
        reader: Option<ReadCallback>,
        closer: Option<unsafe extern "C" fn(*mut archive, *mut c_void) -> c_int>,
    ) -> c_int;
    fn archive_read_next_header(a: *mut archive, entry: *mut *mut archive_entry) -> c_int;
    fn archive_read_data(a: *mut archive, buffer: *mut c_void, len: usize) -> LaSsize;
    fn archive_read_free(a: *mut archive) -> c_int;
    fn archive_error_string(a: *mut archive) -> *const c_char;
    fn archive_entry_pathname(entry: *mut archive_entry) -> *const c_char;
    fn archive_entry_size(entry: *mut archive_entry) -> LaInt64;
}

/// Reading in 64 KB blocks. Large enough that a comic page is a handful of reads.
const BLOCK_SIZE: usize = 64 * 1024;

/// What libarchive said when it refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct LibarchiveError(pub String);

/// The header libarchive just positioned on.
pub(crate) struct Header {
    pub path: String,
    pub size: i64,
}

/// A buffer handed to libarchive as one block, through its read callback.
///
/// `archive_read_open_memory` lives in a libarchive source this project does not vendor,
/// and `archive_read_open` with this callback is the same thing in four lines. The first
/// call gives the whole buffer, and every later call says it ended.
struct MemoryBlock {
    bytes: Vec<u8>,
    given: bool,
}

unsafe extern "C" fn memory_read(
    _a: *mut archive,
    context: *mut c_void,
    out: *mut *const c_void,
) -> LaSsize {
    // SAFETY: `context` is the `Box<MemoryBlock>` pointer `Archive::open_memory` registered,
    // kept alive in the `Archive` for as long as libarchive can call back, and libarchive
    // calls this from the thread that owns the handle, so no other reference exists.
    let block = unsafe { &mut *context.cast::<MemoryBlock>() };
    if block.given {
        return 0;
    }
    block.given = true;
    // SAFETY: `out` is the non-null output slot libarchive passes to a read callback.
    unsafe { *out = block.bytes.as_ptr().cast() };
    block.bytes.len() as LaSsize
}

/// A read handle with only the RAR readers registered. Freed on drop.
pub(crate) struct Archive {
    raw: *mut archive,
    /// The in-memory block the handle reads from, when it reads from memory. Owned here so
    /// the pointer libarchive holds outlives every callback.
    memory: Option<Box<MemoryBlock>>,
}

// SAFETY: a handle is used from one thread at a time, which `&mut self` on every method
// enforces, and libarchive keeps no thread-affine state in a reader. Moving it between
// threads is what lets a decode run on a worker and return to the caller.
unsafe impl Send for Archive {}

impl Archive {
    fn new() -> Result<Self, LibarchiveError> {
        // SAFETY: plain allocation; a null return is the only failure and is checked.
        let raw = unsafe { archive_read_new() };
        if raw.is_null() {
            return Err(LibarchiveError(
                "could not allocate an archive reader".to_owned(),
            ));
        }
        // SAFETY: `raw` is a live reader from `archive_read_new`.
        unsafe {
            archive_read_support_format_rar(raw);
            archive_read_support_format_rar5(raw);
            archive_read_support_filter_none(raw);
        }
        Ok(Self { raw, memory: None })
    }

    /// Opens the archive at `path`.
    pub fn open_path(path: &Path) -> Result<Self, LibarchiveError> {
        let text = path
            .to_str()
            .ok_or_else(|| LibarchiveError(format!("path is not UTF-8: {}", path.display())))?;
        let c_path =
            CString::new(text).map_err(|_| LibarchiveError("path holds a NUL byte".to_owned()))?;
        let archive = Self::new()?;
        // SAFETY: `raw` is live, `c_path` outlives the call, and libarchive copies the
        // name rather than keeping the pointer.
        let status =
            unsafe { archive_read_open_filename(archive.raw, c_path.as_ptr(), BLOCK_SIZE) };
        archive.opened(status)
    }

    /// Opens an archive held in memory, which the callback hands over as one block.
    pub fn open_memory(bytes: Vec<u8>) -> Result<Self, LibarchiveError> {
        let mut archive = Self::new()?;
        let mut block = Box::new(MemoryBlock {
            bytes,
            given: false,
        });
        let context: *mut MemoryBlock = &mut *block;
        archive.memory = Some(block);
        // SAFETY: `raw` is live; `context` points into the boxed block `archive.memory`
        // owns, which is freed only after `archive_read_free` in `Drop`, so every callback
        // libarchive makes sees a live block.
        let status = unsafe {
            archive_read_open(archive.raw, context.cast(), None, Some(memory_read), None)
        };
        archive.opened(status)
    }

    fn opened(self, status: c_int) -> Result<Self, LibarchiveError> {
        if status == ARCHIVE_OK {
            Ok(self)
        } else {
            Err(LibarchiveError(self.message()))
        }
    }

    /// The next entry's header, or `None` at the end of the archive.
    pub fn next_header(&mut self) -> Result<Option<Header>, LibarchiveError> {
        let mut entry: *mut archive_entry = std::ptr::null_mut();
        // SAFETY: `raw` is live and `entry` is a valid out-slot for the call.
        let status = unsafe { archive_read_next_header(self.raw, &mut entry) };
        if status == ARCHIVE_EOF {
            return Ok(None);
        }
        if status != ARCHIVE_OK && status != ARCHIVE_WARN {
            return Err(LibarchiveError(self.message()));
        }
        if entry.is_null() {
            return Err(LibarchiveError("libarchive returned no entry".to_owned()));
        }
        // SAFETY: `entry` is the live header libarchive just positioned on; it stays valid
        // until the next `archive_read_next_header`, and both strings are copied out
        // before then.
        let (name, size) = unsafe { (archive_entry_pathname(entry), archive_entry_size(entry)) };
        let path = if name.is_null() {
            String::new()
        } else {
            // SAFETY: a non-null pathname is a NUL-terminated string libarchive owns.
            unsafe { CStr::from_ptr(name) }
                .to_string_lossy()
                .into_owned()
        };
        Ok(Some(Header { path, size }))
    }

    /// Reads the current entry's data into `buffer`. Zero means the entry is drained.
    pub fn read_data(&mut self, buffer: &mut [u8]) -> Result<usize, LibarchiveError> {
        // SAFETY: `raw` is live, and `buffer` is a writable slice whose length is passed
        // alongside it, so libarchive writes within bounds.
        let got = unsafe { archive_read_data(self.raw, buffer.as_mut_ptr().cast(), buffer.len()) };
        usize::try_from(got).map_err(|_| LibarchiveError(self.message()))
    }

    /// libarchive's own message, kept verbatim so a bug report can carry it.
    fn message(&self) -> String {
        // SAFETY: `raw` is live; the string, when non-null, is NUL-terminated and owned by
        // the handle, and is copied before any further call could replace it.
        let raw = unsafe { archive_error_string(self.raw) };
        if raw.is_null() {
            return "unknown libarchive error".to_owned();
        }
        // SAFETY: see above.
        unsafe { CStr::from_ptr(raw) }
            .to_string_lossy()
            .into_owned()
    }
}

impl Drop for Archive {
    fn drop(&mut self) {
        // SAFETY: `raw` came from `archive_read_new` and is freed exactly once, here. The
        // memory block, if any, is dropped after this returns, so no callback can run on a
        // freed block.
        unsafe { archive_read_free(self.raw) };
    }
}
