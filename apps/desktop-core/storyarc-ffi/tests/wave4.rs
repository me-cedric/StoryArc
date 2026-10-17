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
