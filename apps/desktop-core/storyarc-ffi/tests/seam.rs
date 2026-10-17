//! The wave 2 seam, called the way the Windows app calls it: through the `extern "C"`
//! functions, with raw pointers, status codes and Rust-owned buffers (design.md, Decision 5).
//! The fixtures are the shared corpus, so a page decoded here is the page the Rust API and
//! the phones decode.

use std::ffi::{CStr, c_void};
use std::path::{Path, PathBuf};
use std::ptr;

use storyarc_ffi::*;

fn corpus(relative: &str) -> PathBuf {
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

/// The buffer's bytes as UTF-8, then the buffer freed, as C# does it.
fn take_string(buffer: StoryArcBuffer) -> String {
    let text = if buffer.len == 0 {
        String::new()
    } else {
        let bytes = unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) };
        String::from_utf8(bytes.to_vec()).expect("records are UTF-8")
    };
    unsafe { storyarc_buffer_free(buffer) };
    text
}

fn last_error() -> String {
    let raw = storyarc_last_error();
    assert!(!raw.is_null(), "a failing call leaves a message");
    unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned()
}

fn open_publication(relative: &str) -> *mut c_void {
    let path = corpus(relative);
    let bytes = path.to_str().unwrap().as_bytes();
    let mut handle = ptr::null_mut();
    let status = unsafe { storyarc_publication_open(bytes.as_ptr(), bytes.len(), &mut handle) };
    assert_eq!(status, STORYARC_OK, "{relative}: {}", last_error());
    assert!(!handle.is_null());
    handle
}

#[test]
fn a_folder_source_lists_its_records_as_utf8_json() {
    let folder = tempfile::tempdir().unwrap();
    for name in ["large-page.cbz", "natural-sort.cbz"] {
        std::fs::copy(corpus(&format!("comics/{name}")), folder.path().join(name)).unwrap();
    }
    let path = folder.path().to_str().unwrap().as_bytes();
    let mut handle = ptr::null_mut();
    let status =
        unsafe { storyarc_folder_open(path.as_ptr(), path.len(), ptr::null(), &mut handle) };
    assert_eq!(status, STORYARC_OK);
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_folder_records(handle, &mut out) },
        STORYARC_OK
    );
    let records: serde_json::Value = serde_json::from_str(&take_string(out)).unwrap();
    let records = records.as_array().unwrap();
    assert_eq!(records.len(), 2);
    assert!(records.iter().all(|record| record["format"] == "cbz"));
    unsafe { storyarc_folder_free(handle) };
}

#[test]
fn a_cancelled_folder_open_says_so_and_hands_back_nothing() {
    let path = corpus("comics");
    let bytes = path.to_str().unwrap().as_bytes();
    let token = storyarc_cancel_token_new();
    unsafe { storyarc_cancel(token) };
    let mut handle = ptr::null_mut();
    let status = unsafe { storyarc_folder_open(bytes.as_ptr(), bytes.len(), token, &mut handle) };
    assert_eq!(status, STORYARC_ERROR_CANCELLED);
    assert!(handle.is_null());
    unsafe { storyarc_cancel_token_free(token) };
}

#[test]
fn a_folder_that_is_not_there_is_not_found() {
    let bytes = b"/no/such/storyarc/folder";
    let mut handle = ptr::null_mut();
    let status =
        unsafe { storyarc_folder_open(bytes.as_ptr(), bytes.len(), ptr::null(), &mut handle) };
    assert_eq!(status, STORYARC_ERROR_NOT_FOUND);
    assert!(last_error().contains("/no/such/storyarc/folder"));
    assert!(handle.is_null());
}

#[test]
fn a_publication_reports_its_page_count_and_metadata() {
    let handle = open_publication("comics/manga-metadata.cbz");
    let mut count = 0u32;
    assert_eq!(
        unsafe { storyarc_publication_page_count(handle, &mut count) },
        STORYARC_OK
    );
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_publication_metadata(handle, &mut out) },
        STORYARC_OK
    );
    let metadata: serde_json::Value = serde_json::from_str(&take_string(out)).unwrap();
    assert_eq!(metadata["pageCount"], u64::from(count));
    assert!(count > 0);
    assert!(metadata["series"].is_string());
    unsafe { storyarc_publication_free(handle) };
}

#[test]
fn a_page_decodes_to_an_rgba_buffer_with_its_width_and_height() {
    let handle = open_publication("comics/large-page.cbz");
    let (mut pixels, mut width, mut height) = (empty(), 0u32, 0u32);
    let status = unsafe {
        storyarc_publication_decode_page(handle, 0, 600, &mut pixels, &mut width, &mut height)
    };
    assert_eq!(status, STORYARC_OK);
    assert_eq!((width, height), (400, 600));
    assert_eq!(pixels.len, 400 * 600 * 4);
    let centre =
        unsafe { std::slice::from_raw_parts(pixels.data.add((300 * 400 + 200) * 4), 4).to_vec() };
    assert!(
        centre
            .iter()
            .zip([185u8, 199, 243, 255])
            .all(|(a, b)| a.abs_diff(b) <= 1),
        "{centre:?}"
    );
    unsafe { storyarc_buffer_free(pixels) };
    // Zero asks for the page at its own size.
    let mut full = empty();
    let status = unsafe {
        storyarc_publication_decode_page(handle, 0, 0, &mut full, &mut width, &mut height)
    };
    assert_eq!(status, STORYARC_OK);
    assert_eq!((width, height), (2000, 3000));
    unsafe { storyarc_buffer_free(full) };
    unsafe { storyarc_publication_free(handle) };
}

#[test]
fn a_page_that_cannot_be_decoded_names_why() {
    let handle = open_publication("comics/unsupported-codec.cbz");
    let (mut pixels, mut width, mut height) = (empty(), 7u32, 7u32);
    let status = unsafe {
        storyarc_publication_decode_page(handle, 1, 0, &mut pixels, &mut width, &mut height)
    };
    assert_eq!(status, STORYARC_ERROR_UNSUPPORTED);
    assert!(last_error().contains("JPEG XL"), "{}", last_error());
    assert!(pixels.data.is_null());
    assert_eq!((width, height), (0, 0));
    let status = unsafe {
        storyarc_publication_decode_page(handle, 9, 0, &mut pixels, &mut width, &mut height)
    };
    assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
    unsafe { storyarc_publication_free(handle) };
}

#[test]
fn a_format_that_is_refused_is_unsupported() {
    let path = corpus("comics/refused.cb7");
    let bytes = path.to_str().unwrap().as_bytes();
    let mut handle = ptr::null_mut();
    let status = unsafe { storyarc_publication_open(bytes.as_ptr(), bytes.len(), &mut handle) };
    assert_eq!(status, STORYARC_ERROR_UNSUPPORTED);
    assert!(last_error().contains("CB7"), "{}", last_error());
    assert!(handle.is_null());
}

#[test]
fn a_progress_record_is_written_and_read_back_as_json() {
    let folder = tempfile::tempdir().unwrap();
    let path = folder.path().join("library.sqlite");
    let path = path.to_str().unwrap().as_bytes();
    let mut store = ptr::null_mut();
    assert_eq!(
        unsafe { storyarc_store_open(path.as_ptr(), path.len(), &mut store) },
        STORYARC_OK
    );

    let identity = br#"{"contentDigest":"d1","normalizedPath":"/a.cbz"}"#;
    let mut out = empty();
    let status =
        unsafe { storyarc_progress_read(store, identity.as_ptr(), identity.len(), &mut out) };
    assert_eq!(status, STORYARC_OK);
    assert_eq!(take_string(out), "null", "nothing recorded yet");

    // The record exactly as the iOS library document writes it.
    let record = br#"{"identity":{"contentDigest":"d1","normalizedPath":"/a.cbz"},"isFinished":false,"position":{"index":12,"kind":"page","of":40},"updatedAt":"2025-12-30T13:06:40Z"}"#;
    assert_eq!(
        unsafe { storyarc_progress_write(store, record.as_ptr(), record.len()) },
        STORYARC_OK
    );
    // Found again by the digest alone.
    let by_digest = br#"{"contentDigest":"d1"}"#;
    let mut out = empty();
    let status =
        unsafe { storyarc_progress_read(store, by_digest.as_ptr(), by_digest.len(), &mut out) };
    assert_eq!(status, STORYARC_OK);
    let back: serde_json::Value = serde_json::from_str(&take_string(out)).unwrap();
    assert_eq!(back["position"]["index"], 12);
    assert_eq!(back["updatedAt"], "2025-12-30T13:06:40Z");

    let junk = b"{not json";
    assert_eq!(
        unsafe { storyarc_progress_write(store, junk.as_ptr(), junk.len()) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    unsafe { storyarc_store_free(store) };
}

#[test]
fn a_handle_of_the_wrong_kind_is_refused_rather_than_misread() {
    let publication = open_publication("comics/single-page.cbz");
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_folder_records(publication, &mut out) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    assert!(last_error().contains("folder"), "{}", last_error());
    let mut count = 0;
    assert_eq!(
        unsafe { storyarc_publication_page_count(ptr::null(), &mut count) },
        STORYARC_ERROR_INVALID_ARGUMENT
    );
    unsafe { storyarc_publication_free(publication) };
    // Null frees are ignored, so a SafeHandle released twice cannot crash the app.
    unsafe {
        storyarc_folder_free(ptr::null_mut());
        storyarc_publication_free(ptr::null_mut());
        storyarc_store_free(ptr::null_mut());
    }
}

#[test]
fn a_path_that_is_not_utf8_is_an_invalid_argument() {
    let bytes = [0xFFu8, 0xFE, 0x00];
    let mut handle = ptr::null_mut();
    let status = unsafe { storyarc_publication_open(bytes.as_ptr(), bytes.len(), &mut handle) };
    assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
    assert!(last_error().contains("UTF-8"), "{}", last_error());
}
