//! Wave 4 exports for reading: the EPUB manifest and positions the desktop EPUB bundle
//! takes, with the container's resources for the host's scheme handler (task 4.3), and the
//! PDF engine on its one thread (task 4.4). Both open a file by path through
//! `RandomAccessSource`, so the same calls serve a share once the host hands one over.

use std::ffi::c_void;
use std::sync::Arc;

use storyarc_core::epub::WebPublication;
use storyarc_core::formats::EpubError;
use storyarc_core::io::{FileSource, RandomAccessSource};

use crate::records::{clear, write_bytes};
use crate::seam::{borrow, guard, into_handle, release, utf8, write};
use crate::{
    STORYARC_ERROR_NOT_FOUND, STORYARC_ERROR_UNREADABLE, STORYARC_ERROR_UNSUPPORTED,
    StoryArcBuffer, fail,
};

pub(crate) const EPUB: u32 = u32::from_be_bytes(*b"SAeb");

/// The file at a UTF-8 path as a source, or `NOT_FOUND` naming the path.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes, or be null when `path_len` is zero.
pub(crate) unsafe fn file_source(
    path: *const u8,
    path_len: usize,
) -> Result<Arc<dyn RandomAccessSource>, i32> {
    // SAFETY: the caller's promise, passed on.
    let path = unsafe { utf8(path, path_len, "path")? };
    if !std::path::Path::new(path).is_file() {
        return Err(fail(
            STORYARC_ERROR_NOT_FOUND,
            &format!("nothing to open at {path}"),
        ));
    }
    let source =
        FileSource::open(path).map_err(|e| fail(STORYARC_ERROR_UNREADABLE, &e.to_string()))?;
    Ok(Arc::new(source))
}

fn epub_failure(error: &EpubError) -> i32 {
    let code = match error {
        EpubError::NotEpub => STORYARC_ERROR_UNSUPPORTED,
        EpubError::NoPackageDocument | EpubError::Malformed(_) => STORYARC_ERROR_UNREADABLE,
    };
    fail(code, &error.to_string())
}

/// Opens the EPUB at the UTF-8 path `path` (`path_len` bytes), builds its Readium Web
/// Publication Manifest with `self_url` (`self_url_len` bytes) as the manifest's own
/// address, and writes an EPUB handle to `out_epub`, freed with `storyarc_epub_free`. A
/// file that is not an EPUB is `STORYARC_ERROR_UNSUPPORTED`; one with no package document
/// is `STORYARC_ERROR_UNREADABLE`, named in the message.
///
/// # Safety
///
/// `path` and `self_url` must point to their lengths in readable bytes. `out_epub` must
/// point to writable storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_epub_open(
    path: *const u8,
    path_len: usize,
    self_url: *const u8,
    self_url_len: usize,
    out_epub: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_epub, std::ptr::null_mut(), "out_epub")? };
        let source = unsafe { file_source(path, path_len)? };
        let self_url = unsafe { utf8(self_url, self_url_len, "self_url")? };
        let publication = WebPublication::open(source, self_url).map_err(|e| epub_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_epub.write(into_handle(EPUB, publication)) };
        Ok(())
    })
}

/// Writes the manifest to `out` as UTF-8 JSON: `metadata` with `layout` and
/// `readingProgression`, `readingOrder`, `resources`, `toc` and the self link. Every href
/// but the self link is a container path. Free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// `epub` must be null or a live EPUB handle. `out` must point to one writable
/// `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_epub_manifest(
    epub: *const c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let publication: &WebPublication = unsafe { borrow(epub, EPUB, "epub")? };
        unsafe { write_bytes(out, publication.manifest_json().into_bytes()) }
    })
}

/// Writes the positions list to `out` as a UTF-8 JSON array of locators, the numbers iOS
/// and Android show for the same book. Free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// As `storyarc_epub_manifest`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_epub_positions(
    epub: *const c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let publication: &WebPublication = unsafe { borrow(epub, EPUB, "epub")? };
        unsafe { write_bytes(out, publication.positions_json().into_bytes()) }
    })
}

/// Writes the bytes of the resource at the container path `href` (`href_len` UTF-8 bytes)
/// to `out_bytes` and its declared media type, or nothing when the package declares none,
/// to `out_media_type`, for the host's scheme handler. A path the container does not hold
/// is `STORYARC_ERROR_NOT_FOUND`. Free both with `storyarc_buffer_free`.
///
/// # Safety
///
/// `epub` must be null or a live EPUB handle. `href` must point to `href_len` readable
/// bytes. `out_bytes` and `out_media_type` must each point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_epub_resource(
    epub: *const c_void,
    href: *const u8,
    href_len: usize,
    out_bytes: *mut StoryArcBuffer,
    out_media_type: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on; both outputs are zeroed before any work.
        unsafe {
            clear(out_bytes)?;
            clear(out_media_type)?;
        }
        let publication: &WebPublication = unsafe { borrow(epub, EPUB, "epub")? };
        let href = unsafe { utf8(href, href_len, "href")? };
        let bytes = publication.resource(href).map_err(|e| match e {
            EpubError::Malformed(_) => fail(
                STORYARC_ERROR_NOT_FOUND,
                &format!("the container holds nothing at {href}"),
            ),
            other => epub_failure(&other),
        })?;
        let media_type = publication
            .media_type(href)
            .unwrap_or_default()
            .as_bytes()
            .to_vec();
        // SAFETY: both checked writable above.
        unsafe {
            write_bytes(out_bytes, bytes)?;
            write_bytes(out_media_type, media_type)
        }
    })
}

/// Releases an EPUB handle. Null is ignored.
///
/// # Safety
///
/// `epub` must be null or a live EPUB handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_epub_free(epub: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<WebPublication>(epub, EPUB) };
}
