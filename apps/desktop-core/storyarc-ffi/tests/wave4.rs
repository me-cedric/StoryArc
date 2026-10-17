//! The wave 4 seam, called the way the Windows app calls it: raw pointers, status codes
//! and Rust-owned buffers. The EPUB half is the manifest and positions the desktop EPUB
//! bundle takes (task 4.3); the PDF half is the engine on its one thread (task 4.4).

use std::ffi::{CStr, c_void};
use std::path::{Path, PathBuf};
use std::ptr;

use serde_json::Value;
use storyarc_ffi::*;

fn fixture(relative: &str) -> PathBuf {
    let mut dir = Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf();
    loop {
        let candidate = dir.join("packages/test-fixtures");
        if candidate.join("manifest.json").is_file() {
            return candidate.join(relative);
        }
        assert!(dir.pop(), "the shared corpus is above this crate");
    }
}

fn empty() -> StoryArcBuffer {
    StoryArcBuffer {
        data: ptr::null_mut(),
        len: 0,
        capacity: 0,
    }
}

fn take(buffer: StoryArcBuffer) -> Vec<u8> {
    let bytes = if buffer.len == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) }.to_vec()
    };
    unsafe { storyarc_buffer_free(buffer) };
    bytes
}

fn take_json(buffer: StoryArcBuffer) -> Value {
    serde_json::from_slice(&take(buffer)).expect("a JSON answer")
}

fn last_error() -> String {
    let raw = storyarc_last_error();
    assert!(!raw.is_null());
    unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned()
}

const SELF_URL: &[u8] = b"storyarc://publication/manifest.json";

fn open_epub(relative: &str) -> (i32, *mut c_void) {
    let path = fixture(relative);
    let bytes = path.to_str().unwrap().as_bytes();
    let mut handle = ptr::null_mut();
    let status = unsafe {
        storyarc_epub_open(
            bytes.as_ptr(),
            bytes.len(),
            SELF_URL.as_ptr(),
            SELF_URL.len(),
            &mut handle,
        )
    };
    (status, handle)
}

#[test]
fn an_epub_hands_the_bundle_its_manifest_positions_and_resources() {
    let (status, epub) = open_epub("ebooks/fixture.epub");
    assert_eq!(status, STORYARC_OK, "{}", last_error());

    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_epub_manifest(epub, &mut out) },
        STORYARC_OK
    );
    let manifest = take_json(out);
    assert_eq!(manifest["metadata"]["title"], "Fixture Publication");
    assert_eq!(manifest["metadata"]["layout"], "reflowable");
    assert_eq!(
        manifest["links"][0]["href"],
        "storyarc://publication/manifest.json"
    );
    assert_eq!(manifest["readingOrder"][0]["href"], "OEBPS/ch1.xhtml");

    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_epub_positions(epub, &mut out) },
        STORYARC_OK
    );
    let positions = take_json(out);
    let positions = positions.as_array().unwrap();
    assert_eq!(positions.len(), 2);
    assert_eq!(positions[1]["locations"]["position"], 2);
    assert_eq!(positions[1]["locations"]["totalProgression"], 0.5);

    let href = b"OEBPS/cover.png";
    let mut bytes = empty();
    let mut media_type = empty();
    assert_eq!(
        unsafe {
            storyarc_epub_resource(epub, href.as_ptr(), href.len(), &mut bytes, &mut media_type)
        },
        STORYARC_OK
    );
    assert_eq!(&take(bytes)[..4], b"\x89PNG");
    assert_eq!(take(media_type), b"image/png");

    let missing = b"OEBPS/missing.png";
    let mut bytes = empty();
    let mut media_type = empty();
    assert_eq!(
        unsafe {
            storyarc_epub_resource(
                epub,
                missing.as_ptr(),
                missing.len(),
                &mut bytes,
                &mut media_type,
            )
        },
        STORYARC_ERROR_NOT_FOUND
    );
    assert!(last_error().contains("OEBPS/missing.png"));
    assert_eq!(bytes.len, 0);
    assert_eq!(media_type.len, 0);
    unsafe { storyarc_epub_free(epub) };
}

#[test]
fn a_file_that_is_not_an_epub_is_refused_by_name() {
    let (status, handle) = open_epub("comics/natural-sort.cbz");
    assert_eq!(status, STORYARC_ERROR_UNSUPPORTED);
    assert!(handle.is_null());
    assert_eq!(last_error(), "not an EPUB");

    let (status, handle) = open_epub("ebooks/no-package.epub");
    assert_eq!(status, STORYARC_ERROR_UNREADABLE);
    assert!(handle.is_null());
    assert_eq!(last_error(), "no package document");

    let (status, handle) = open_epub("ebooks/not-there.epub");
    assert_eq!(status, STORYARC_ERROR_NOT_FOUND);
    assert!(handle.is_null());
}

#[test]
fn an_epub_handle_of_the_wrong_kind_is_refused() {
    let token = storyarc_cancel_token_new();
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_epub_manifest(token, &mut out) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    assert_eq!(
        unsafe { storyarc_epub_manifest(ptr::null(), &mut out) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    unsafe { storyarc_cancel_token_free(token) };
    unsafe { storyarc_epub_free(ptr::null_mut()) };
}

// ── PDF (task 4.4) ───────────────────────────────────────────────────────────

/// The pinned library, where `pnpm pdfium:fetch` puts it, or wherever `STORYARC_PDFIUM_DIR`
/// says; the PDF cases skip with a line on stderr when neither holds it.
fn pdf_library_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("STORYARC_PDFIUM_DIR") {
        return Some(PathBuf::from(dir));
    }
    let os = match std::env::consts::OS {
        "macos" => "mac",
        "linux" => "linux",
        "windows" => "win",
        _ => return None,
    };
    let arch = match std::env::consts::ARCH {
        "aarch64" => "arm64",
        "x86_64" => "x64",
        _ => return None,
    };
    let folder = if os == "win" { "bin" } else { "lib" };
    let dir = fixture("")
        .parent()?
        .parent()?
        .join(".build/pdfium")
        .join(format!("{os}-{arch}"))
        .join(folder);
    dir.is_dir().then_some(dir)
}

/// Starts the engine, or says why the case is skipped.
fn pdf_engine() -> bool {
    let dir = pdf_library_dir();
    let bytes = dir
        .as_ref()
        .map(|d| d.to_str().unwrap().as_bytes().to_vec())
        .unwrap_or_default();
    let status = unsafe { storyarc_pdf_engine_start(bytes.as_ptr(), bytes.len()) };
    if status == STORYARC_OK {
        return true;
    }
    assert!(
        dir.is_none(),
        "the PDF engine did not start: {}",
        last_error()
    );
    eprintln!("skipped: no PDFium library on this machine, run pnpm pdfium:fetch");
    false
}

fn open_pdf(relative: &str) -> (i32, *mut c_void) {
    let path = fixture(relative);
    let bytes = path.to_str().unwrap().as_bytes();
    let mut handle = ptr::null_mut();
    let status = unsafe { storyarc_pdf_open(bytes.as_ptr(), bytes.len(), &mut handle) };
    (status, handle)
}

#[test]
fn a_pdf_renders_reads_searches_and_lists_its_outline_across_the_seam() {
    if !pdf_engine() {
        return;
    }
    let (status, pdf) = open_pdf("comics/text-pages.pdf");
    assert_eq!(status, STORYARC_OK, "{}", last_error());

    let mut count = 0u32;
    assert_eq!(
        unsafe { storyarc_pdf_page_count(pdf, &mut count) },
        STORYARC_OK
    );
    assert_eq!(count, 3);

    let (mut width, mut height) = (0f32, 0f32);
    assert_eq!(
        unsafe { storyarc_pdf_page_size(pdf, 0, &mut width, &mut height) },
        STORYARC_OK
    );
    assert_eq!((width as u32, height as u32), (612, 792));
    assert_eq!(
        unsafe { storyarc_pdf_page_size(pdf, 3, &mut width, &mut height) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    assert_eq!((width, height), (0.0, 0.0));

    let mut pixels = empty();
    let (mut w, mut h) = (0u32, 0u32);
    assert_eq!(
        unsafe { storyarc_pdf_render_page(pdf, 0, 306, &mut pixels, &mut w, &mut h) },
        STORYARC_OK
    );
    assert_eq!((w, h), (236, 306));
    assert_eq!(take(pixels).len(), 236 * 306 * 4);

    // Two device pixels a point for a high-density window; the edge cap wins over the scale.
    let mut pixels = empty();
    assert_eq!(
        unsafe { storyarc_pdf_render_page_scaled(pdf, 0, 2.0, 0, &mut pixels, &mut w, &mut h) },
        STORYARC_OK
    );
    assert_eq!((w, h), (1224, 1584));
    assert_eq!(take(pixels).len(), 1224 * 1584 * 4);
    let mut pixels = empty();
    assert_eq!(
        unsafe { storyarc_pdf_render_page_scaled(pdf, 0, 4.0, 1000, &mut pixels, &mut w, &mut h) },
        STORYARC_OK
    );
    assert_eq!((w, h), (773, 1000));
    take(pixels);

    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_pdf_page_text(pdf, 1, &mut out) },
        STORYARC_OK
    );
    assert_eq!(String::from_utf8(take(out)).unwrap().trim(), "Chapter Two");

    let mut flag = 0i32;
    assert_eq!(
        unsafe { storyarc_pdf_has_text_layer(pdf, &mut flag) },
        STORYARC_OK
    );
    assert_eq!(flag, 1);

    let query = b"chapter three";
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_pdf_search(pdf, query.as_ptr(), query.len(), &mut out) },
        STORYARC_OK
    );
    let hits = take_json(out);
    assert_eq!(hits[0]["page"], 2);
    assert!(hits[0]["rects"][0]["left"].as_f64().unwrap() > 70.0);

    let mut out = empty();
    assert_eq!(unsafe { storyarc_pdf_outline(pdf, &mut out) }, STORYARC_OK);
    let outline = take_json(out);
    assert_eq!(outline[1]["title"], "Chapter Two");
    assert_eq!(outline[1]["page"], 1);
    assert_eq!(outline[1]["children"], serde_json::json!([]));

    unsafe { storyarc_pdf_free(pdf) };
}

#[test]
fn a_pdf_that_is_not_one_is_unreadable_and_a_missing_file_not_found() {
    if !pdf_engine() {
        return;
    }
    let (status, handle) = open_pdf("comics/natural-sort.cbz");
    assert_eq!(status, STORYARC_ERROR_UNREADABLE, "{}", last_error());
    assert!(handle.is_null());
    let (status, handle) = open_pdf("comics/not-there.pdf");
    assert_eq!(status, STORYARC_ERROR_NOT_FOUND);
    assert!(handle.is_null());

    let mut count = 0u32;
    assert_eq!(
        unsafe { storyarc_pdf_page_count(ptr::null(), &mut count) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    unsafe { storyarc_pdf_free(ptr::null_mut()) };
}
