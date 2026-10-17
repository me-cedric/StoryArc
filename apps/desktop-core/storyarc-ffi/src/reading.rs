//! Wave 4 exports for reading: the EPUB manifest and positions the desktop EPUB bundle
//! takes, with the container's resources for the host's scheme handler (task 4.3), and the
//! PDF engine on its one thread (task 4.4). Both open a file by path through
//! `RandomAccessSource`, so the same calls serve a share once the host hands one over.

use std::ffi::c_void;
use std::sync::Arc;

use storyarc_core::epub::WebPublication;
use storyarc_core::formats::EpubError;
use storyarc_core::io::{FileSource, RandomAccessSource};
use storyarc_core::pdf::{PdfDocument, PdfEngine, PdfError};

use crate::records::{clear, write_bytes, write_json};
use crate::seam::{borrow, guard, into_handle, release, utf8, write};
use crate::{
    STORYARC_ERROR_INTERNAL, STORYARC_ERROR_INVALID_ARGUMENT, STORYARC_ERROR_NOT_FOUND,
    STORYARC_ERROR_UNREADABLE, STORYARC_ERROR_UNSUPPORTED, StoryArcBuffer, fail,
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

// ── PDF (task 4.4) ───────────────────────────────────────────────────────────

pub(crate) const PDF: u32 = u32::from_be_bytes(*b"SApd");

fn pdf_failure(error: &PdfError) -> i32 {
    let code = match error {
        PdfError::EngineUnavailable(_) => STORYARC_ERROR_UNSUPPORTED,
        PdfError::Unreadable(_) => STORYARC_ERROR_UNREADABLE,
        PdfError::PageOutOfRange { .. } => STORYARC_ERROR_INVALID_ARGUMENT,
        PdfError::Closed => STORYARC_ERROR_INTERNAL,
    };
    fail(code, &error.to_string())
}

/// The engine, started on first use with the folder the app named, or found by the core.
fn engine(library_dir: Option<&std::path::Path>) -> Result<&'static PdfEngine, i32> {
    PdfEngine::start(library_dir).map_err(|e| pdf_failure(&e))
}

/// Starts the PDF engine on its one thread, binding to the PDFium library in the folder at
/// the UTF-8 path `library_dir` (`library_dir_len` bytes; zero to let the core look in
/// `STORYARC_PDFIUM_DIR`, beside the executable, then the system). The first call decides
/// the library for the process. A library that cannot be loaded is
/// `STORYARC_ERROR_UNSUPPORTED`, with every folder tried in the message. Optional: the
/// first `storyarc_pdf_open` starts the engine the same way with no folder.
///
/// # Safety
///
/// `library_dir` must point to `library_dir_len` readable bytes, or be null when the
/// length is zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_engine_start(
    library_dir: *const u8,
    library_dir_len: usize,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promise, passed on.
        let dir = unsafe { utf8(library_dir, library_dir_len, "library_dir")? };
        let dir = (!dir.is_empty()).then(|| std::path::Path::new(dir));
        engine(dir).map(|_| ())
    })
}

/// Opens the PDF at the UTF-8 path `path` (`path_len` bytes) through ranged reads and
/// writes a PDF handle to `out_pdf`, freed with `storyarc_pdf_free`. A file PDFium cannot
/// open is `STORYARC_ERROR_UNREADABLE`.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes. `out_pdf` must point to writable
/// storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_open(
    path: *const u8,
    path_len: usize,
    out_pdf: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_pdf, std::ptr::null_mut(), "out_pdf")? };
        let source = unsafe { file_source(path, path_len)? };
        let document = engine(None)?.open(source).map_err(|e| pdf_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_pdf.write(into_handle(PDF, document)) };
        Ok(())
    })
}

/// Writes the page count to `out_count`.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out_count` must point to one writable
/// `uint32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_page_count(pdf: *const c_void, out_count: *mut u32) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        unsafe { write(out_count, document.page_count(), "out_count") }
    })
}

/// Writes page `index`'s size in PDF points to `out_width` and `out_height`. An index past
/// the end is `STORYARC_ERROR_INVALID_ARGUMENT`.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out_width` and `out_height` must each point
/// to one writable `float`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_page_size(
    pdf: *const c_void,
    index: u32,
    out_width: *mut f32,
    out_height: *mut f32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe {
            write(out_width, 0.0, "out_width")?;
            write(out_height, 0.0, "out_height")?;
        }
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let (width, height) = document.page_size(index).map_err(|e| pdf_failure(&e))?;
        // SAFETY: both checked writable above.
        unsafe {
            out_width.write(width);
            out_height.write(height);
        }
        Ok(())
    })
}

/// Renders page `index` to 8-bit RGBA, not premultiplied, rows top to bottom with no
/// padding, at most `max_pixel_size` on its longest edge (zero for one pixel per point).
/// Writes the pixels to `out_pixels` (`width * height * 4` bytes, freed with
/// `storyarc_buffer_free`) and the size to `out_width` and `out_height`; on failure the
/// three are zeroed.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out_pixels` must point to one writable
/// `StoryArcBuffer`, `out_width` and `out_height` to one writable `uint32_t` each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_render_page(
    pdf: *const c_void,
    index: u32,
    max_pixel_size: u32,
    out_pixels: *mut StoryArcBuffer,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on; every output is zeroed before any work.
        unsafe {
            clear(out_pixels)?;
            write(out_width, 0, "out_width")?;
            write(out_height, 0, "out_height")?;
        }
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let limit = (max_pixel_size > 0).then_some(max_pixel_size);
        let page = document
            .render_page(index, limit)
            .map_err(|e| pdf_failure(&e))?;
        // SAFETY: all three checked writable above.
        unsafe {
            out_width.write(page.width);
            out_height.write(page.height);
            write_bytes(out_pixels, page.rgba)
        }
    })
}

/// Renders page `index` as `storyarc_pdf_render_page` does, at `scale` device pixels per
/// point (2.0 on a high-density window; at or under zero renders one pixel a point), then
/// shrunk to at most `max_edge` pixels on its longest edge (zero for no cap). The page view
/// asks for its own density so a 612 by 792 point page is sharp on a large or dense window.
///
/// # Safety
///
/// As `storyarc_pdf_render_page`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_render_page_scaled(
    pdf: *const c_void,
    index: u32,
    scale: f32,
    max_edge: u32,
    out_pixels: *mut StoryArcBuffer,
    out_width: *mut u32,
    out_height: *mut u32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on; every output is zeroed before any work.
        unsafe {
            clear(out_pixels)?;
            write(out_width, 0, "out_width")?;
            write(out_height, 0, "out_height")?;
        }
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let cap = (max_edge > 0).then_some(max_edge);
        let page = document
            .render_page_scaled(index, scale, cap)
            .map_err(|e| pdf_failure(&e))?;
        // SAFETY: all three checked writable above.
        unsafe {
            out_width.write(page.width);
            out_height.write(page.height);
            write_bytes(out_pixels, page.rgba)
        }
    })
}

/// Writes page `index`'s text, in content order, to `out` as UTF-8; empty for a page with
/// no text layer. Free `out` with `storyarc_buffer_free`.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out` must point to one writable
/// `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_page_text(
    pdf: *const c_void,
    index: u32,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let text = document.page_text(index).map_err(|e| pdf_failure(&e))?;
        unsafe { write_bytes(out, text.into_bytes()) }
    })
}

/// Writes 1 to `out_flag` when any page carries text, else 0, so the app hides selection
/// and search for an image-only file.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out_flag` must point to one writable `int32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_has_text_layer(
    pdf: *const c_void,
    out_flag: *mut i32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_flag, 0, "out_flag")? };
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let has = document.has_text_layer().map_err(|e| pdf_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_flag.write(i32::from(has)) };
        Ok(())
    })
}

/// Searches every page for `query` (`query_len` UTF-8 bytes), case folded, and writes the
/// hits to `out` as a UTF-8 JSON array of `{"page", "rects": [{"left", "bottom", "right",
/// "top"}]}` in PDF points with the origin at the page's bottom left. Free `out` with
/// `storyarc_buffer_free`.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `query` must point to `query_len` readable
/// bytes. `out` must point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_search(
    pdf: *const c_void,
    query: *const u8,
    query_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let query = unsafe { utf8(query, query_len, "query")? };
        let hits = document.search(query).map_err(|e| pdf_failure(&e))?;
        unsafe { write_json(out, &hits) }
    })
}

/// Writes the outline to `out` as a UTF-8 JSON array of `{"title", "page"?, "children"}`,
/// nested as the file nests it and empty when it has none. Free `out` with
/// `storyarc_buffer_free`.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle. `out` must point to one writable
/// `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_outline(pdf: *const c_void, out: *mut StoryArcBuffer) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let document: &PdfDocument = unsafe { borrow(pdf, PDF, "pdf")? };
        let outline = document.outline().map_err(|e| pdf_failure(&e))?;
        unsafe { write_json(out, &outline) }
    })
}

/// Releases a PDF handle and closes the document. Null is ignored.
///
/// # Safety
///
/// `pdf` must be null or a live PDF handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_pdf_free(pdf: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<PdfDocument>(pdf, PDF) };
}
