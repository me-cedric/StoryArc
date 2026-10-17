//! The wave 3 seam, called the way the Windows app calls it: raw pointers, UTF-8 JSON with a
//! length, status codes and Rust-owned buffers. The network cases bring their own servers on
//! ephemeral ports; port 4999 answers nothing, by design (AGENTS.md, the fixture port table).

use std::ffi::{CStr, c_void};
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::ptr;

use serde_json::{Value, json};
use storyarc_ffi::*;

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

/// Calls a `(request, len, out)` export with `request` as JSON.
fn call(
    export: unsafe extern "C" fn(*const u8, usize, *mut StoryArcBuffer) -> i32,
    request: &Value,
) -> (i32, Vec<u8>) {
    let bytes = serde_json::to_vec(request).unwrap();
    let mut out = empty();
    let status = unsafe { export(bytes.as_ptr(), bytes.len(), &mut out) };
    (status, take(out))
}

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

struct Core {
    runtime: *mut c_void,
    http: *mut c_void,
}

impl Core {
    fn new() -> Self {
        let mut runtime = ptr::null_mut();
        assert_eq!(unsafe { storyarc_runtime_new(&mut runtime) }, STORYARC_OK);
        let mut http = ptr::null_mut();
        assert_eq!(
            unsafe { storyarc_http_new(runtime, &mut http) },
            STORYARC_OK
        );
        Self { runtime, http }
    }
}

impl Drop for Core {
    fn drop(&mut self) {
        unsafe {
            storyarc_http_free(self.http);
            storyarc_runtime_free(self.runtime);
        }
    }
}

/// A server that answers every request with `body` and `content_type`.
fn serve(body: Vec<u8>, content_type: &'static str) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut reader = BufReader::new(&stream);
            let mut line = String::new();
            while reader.read_line(&mut line).unwrap_or(0) > 0 && line != "\r\n" {
                line.clear();
            }
            let mut stream = stream;
            let _ = write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            let _ = stream.write_all(&body);
        }
    });
    format!("http://127.0.0.1:{port}/")
}

#[test]
fn a_wrong_handle_and_a_wrong_request_are_named() {
    let core = Core::new();
    let mut out = empty();
    let request = b"{}";
    // A runtime handle where the HTTP client belongs.
    let status = unsafe { storyarc_opds_feed(core.runtime, request.as_ptr(), 2, &mut out) };
    assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
    assert!(last_error().contains("not a http handle"));
    let status = unsafe { storyarc_opds_feed(core.http, b"[".as_ptr(), 1, &mut out) };
    assert_eq!(status, STORYARC_ERROR_INVALID_ARGUMENT);
    assert!(last_error().contains("not the expected JSON"));
    unsafe { storyarc_buffer_free(out) };
}

#[test]
fn a_share_that_does_not_answer_is_unreachable_and_grey() {
    let core = Core::new();
    let request =
        serde_json::to_vec(&json!({"address": "smb://127.0.0.1/comics", "port": 4999})).unwrap();
    let mut share = ptr::null_mut();
    let status =
        unsafe { storyarc_smb_connect(core.runtime, request.as_ptr(), request.len(), &mut share) };
    assert_eq!(status, STORYARC_ERROR_UNREACHABLE, "{}", last_error());
    assert!(share.is_null());
}

#[test]
fn a_catalogue_page_crosses_as_json() {
    let core = Core::new();
    let feed = br#"<feed xmlns="http://www.w3.org/2005/Atom"><title>Tiny</title>
        <entry><title>Shelf</title><id>s</id><link rel="subsection" href="/shelf" type="application/atom+xml;profile=opds-catalog"/></entry></feed>"#;
    let root = serve(feed.to_vec(), "application/atom+xml");
    let request = serde_json::to_vec(&json!({ "root": root })).unwrap();
    let mut out = empty();
    let status =
        unsafe { storyarc_opds_feed(core.http, request.as_ptr(), request.len(), &mut out) };
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let page = take_json(out);
    assert_eq!(page["title"], "Tiny");
    assert_eq!(page["dialect"], "atom");
    assert_eq!(page["navigation"][0]["title"], "Shelf");
}

#[test]
fn a_kavita_server_that_does_not_answer_is_unreachable() {
    let core = Core::new();
    let request = serde_json::to_vec(&json!({
        "address": "http://127.0.0.1:4999", "apiKey": "k", "call": "libraries"
    }))
    .unwrap();
    let mut out = empty();
    let status =
        unsafe { storyarc_kavita_call(core.http, request.as_ptr(), request.len(), &mut out) };
    assert_eq!(status, STORYARC_ERROR_UNREACHABLE, "{}", last_error());
    unsafe { storyarc_buffer_free(out) };
}

#[test]
fn the_network_state_is_one_of_three() {
    let core = Core::new();
    let mut state = -1;
    assert_eq!(
        unsafe { storyarc_network_state(core.runtime, &mut state) },
        STORYARC_OK
    );
    assert!((0..=2).contains(&state));
}

unsafe extern "C" fn count(context: *mut c_void, received: u64, total: i64) {
    let seen = unsafe { &mut *context.cast::<(u64, i64)>() };
    *seen = (received, total);
}

#[test]
fn a_download_lands_verified_and_reports_its_progress() {
    let core = Core::new();
    let body = std::fs::read(fixture("comics/natural-sort.cbz")).unwrap();
    let url = serve(body.clone(), "application/vnd.comicbook+zip");
    let folder = tempfile::tempdir().unwrap();
    let request = serde_json::to_vec(&json!({
        "folder": folder.path(), "id": "opds:1", "title": "Natural Sort", "url": url,
    }))
    .unwrap();
    let mut seen: (u64, i64) = (0, 0);
    let mut out = empty();
    let status = unsafe {
        storyarc_download_fetch(
            core.http,
            request.as_ptr(),
            request.len(),
            ptr::null(),
            Some(count),
            (&mut seen as *mut (u64, i64)).cast(),
            &mut out,
        )
    };
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let landed = take_json(out);
    assert_eq!(landed["resumption"], "fresh");
    assert_eq!(landed["length"], body.len());
    assert_eq!(
        std::fs::read(landed["path"].as_str().unwrap()).unwrap(),
        body
    );
    assert_eq!(seen, (body.len() as u64, body.len() as i64));

    let path = folder.path().to_str().unwrap().as_bytes();
    let mut bytes = 0;
    assert_eq!(
        unsafe { storyarc_storage_bytes(path.as_ptr(), path.len(), &mut bytes) },
        STORYARC_OK
    );
    assert_eq!(bytes, body.len() as u64);
}

#[test]
fn the_queue_rules_run_across_the_seam() {
    let request = json!({
        "ops": [
            {"op": "queue", "download": {"id": "a", "title": "A", "remote": "x", "state": {"state": "queued"}}},
            {"op": "queue", "download": {"id": "b", "title": "B", "remote": "x", "state": {"state": "queued"}}},
            {"op": "fail", "id": "a", "reason": {"kind": "network"}, "retryable": true},
            {"op": "hold", "network": "metered", "policy": {}, "used": 0},
        ],
        "startable": ["metered", {"unmeteredOnly": false}],
    });
    let (status, out) = call(storyarc_queue_apply, &request);
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let answer: Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(answer["queue"]["downloads"][1]["state"]["state"], "paused");
    assert_eq!(answer["retry"], json!([["a", 2]]));
}

#[test]
fn shelves_and_their_offline_edits_run_across_the_seam() {
    let id = "33333333-3333-3333-3333-333333333333";
    let (status, out) = call(
        storyarc_shelves_apply,
        &json!({"ops": [
            {"op": "createCollection", "name": "Image Comics", "id": id},
            {"op": "addMembers", "id": id, "members": ["path:/a.cbz", "path:/b.cbz"]},
            {"op": "setCollectionCover", "id": id, "member": "path:/b.cbz"},
        ]}),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let shelves: Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(shelves["collections"][0]["coverMemberId"], "path:/b.cbz");

    let shelf = json!({"sourceID": "server", "shelfID": 7, "kind": "list"});
    let (status, out) = call(
        storyarc_shelf_pull,
        &json!({
            "queue": {
                "edits": [{"shelf": shelf, "entry": "b", "title": "B", "madeAt": "2026-01-01T00:00:00Z"}],
                "baselines": [{"shelf": shelf, "entries": ["a"]}],
            },
            "remote": [{"shelf": shelf, "entries": ["a"]}],
        }),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let pull: Value = serde_json::from_slice(&out).unwrap();
    assert_eq!(pull["toPush"][0]["entry"], "b");
}

#[test]
fn a_phone_document_imports_exports_and_syncs_across_the_seam() {
    let document = std::fs::read(fixture("library/written-by-ios.json")).unwrap();
    let snapshot = b"{}";
    let device = b"windows";
    let mut out = empty();
    let status = unsafe {
        storyarc_library_import(
            document.as_ptr(),
            document.len(),
            snapshot.as_ptr(),
            snapshot.len(),
            device.as_ptr(),
            device.len(),
            &mut out,
        )
    };
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let merged = take_json(out);
    assert_eq!(merged["snapshot"]["progress"].as_array().unwrap().len(), 3);
    assert_eq!(merged["pinsAdded"], json!(["nas.local"]));

    let (status, written) = call(
        storyarc_library_export,
        &json!({"snapshot": merged["snapshot"], "appVersion": "1.0.0", "device": "windows", "now": 1_800_000_000}),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let written: Value = serde_json::from_slice(&written).unwrap();
    assert_eq!(written["writtenBy"], "windows");
    assert_eq!(written["library"]["collections"][0]["name"], "Image Comics");

    let folder = tempfile::tempdir().unwrap();
    let (status, synced) = call(
        storyarc_library_sync,
        &json!({"folder": folder.path(), "device": "windows", "appVersion": "1.0.0", "now": 1_800_000_000, "snapshot": merged["snapshot"]}),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let synced: Value = serde_json::from_slice(&synced).unwrap();
    assert_eq!(synced["copies"], json!([]));
    assert!(folder.path().join("StoryArc Library.json").is_file());

    let (status, _) = call(
        storyarc_library_sync,
        &json!({"folder": folder.path().join("unplugged"), "device": "windows", "appVersion": "1", "now": 1, "snapshot": {}}),
    );
    assert_eq!(status, STORYARC_ERROR_UNREACHABLE);

    let mut newer: Value = serde_json::from_slice(&document).unwrap();
    newer["formatVersion"] = json!(9);
    let newer = serde_json::to_vec(&newer).unwrap();
    let mut out = empty();
    let status = unsafe {
        storyarc_library_import(
            newer.as_ptr(),
            newer.len(),
            snapshot.as_ptr(),
            2,
            device.as_ptr(),
            7,
            &mut out,
        )
    };
    assert_eq!(status, STORYARC_ERROR_UNSUPPORTED);
    assert!(last_error().contains("format 9"));
    unsafe { storyarc_buffer_free(out) };
}

#[test]
fn secrets_seal_open_and_refuse_a_wrong_passphrase_across_the_seam() {
    let id = "11111111-1111-1111-1111-111111111111";
    let (status, sealed) = call(
        storyarc_secrets_seal,
        &json!({"passphrase": "pässphrase", "secrets": {id: "hunter2"}}),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    assert!(!String::from_utf8_lossy(&sealed).contains("hunter2"));
    let sealed: Value = serde_json::from_slice(&sealed).unwrap();
    let (status, opened) = call(
        storyarc_secrets_open,
        &json!({"passphrase": "pässphrase", "secrets": sealed}),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    assert_eq!(
        serde_json::from_slice::<Value>(&opened).unwrap()[id],
        "hunter2"
    );
    let (status, _) = call(
        storyarc_secrets_open,
        &json!({"passphrase": "wrong", "secrets": sealed}),
    );
    assert_eq!(status, STORYARC_ERROR_UNAUTHORIZED);
}

#[test]
fn the_vault_keeps_a_secret_for_the_session_and_the_diagnostic_never_shows_it() {
    let core = Core::new();
    let mut vault = ptr::null_mut();
    assert_eq!(
        unsafe { storyarc_vault_open(core.runtime, &mut vault) },
        STORYARC_OK
    );
    let key = br#"{"sourceId":"11111111-1111-1111-1111-111111111111","field":"password"}"#;
    let secret = b"hunter2-session";
    let mut out = empty();
    let status = unsafe {
        storyarc_vault_save(
            vault,
            key.as_ptr(),
            key.len(),
            secret.as_ptr(),
            secret.len(),
            &mut out,
        )
    };
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let saved = take_json(out);
    assert!(saved["stored"].is_boolean());
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_vault_load(vault, key.as_ptr(), key.len(), &mut out) },
        STORYARC_OK
    );
    assert_eq!(take(out), secret);
    assert_eq!(
        unsafe { storyarc_vault_delete(vault, key.as_ptr(), key.len()) },
        STORYARC_OK
    );
    let mut out = empty();
    assert_eq!(
        unsafe { storyarc_vault_load(vault, key.as_ptr(), key.len(), &mut out) },
        STORYARC_ERROR_NOT_FOUND
    );
    unsafe { storyarc_buffer_free(out) };
    unsafe { storyarc_vault_free(vault) };

    let (status, text) = call(
        storyarc_diagnostic_render,
        &json!({
            "title": "StoryArc diagnostic",
            "sections": [{"name": "source", "lines": [["address", "smb://reader:hunter2-session@nas.local/comics"]]}],
            "secrets": ["hunter2-session"],
        }),
    );
    assert_eq!(status, STORYARC_OK, "{}", last_error());
    let text = String::from_utf8(text).unwrap();
    assert!(text.contains("[source]"));
    assert!(!text.contains("hunter2-session"));
    assert!(!text.contains("nas.local"));
}
