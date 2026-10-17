//! Downloads (task 3.6 of `desktop-clients`, `offline-downloads`).
//!
//! Every case brings its own HTTP server on an ephemeral port: one that serves a fixed body,
//! answers `Range` and `If-Range` as a file server does, and can be slowed down so a transfer
//! is still running when the test acts on it. The kill case runs the transfer in a child
//! process (this same test binary, re-entered through an environment variable), kills it
//! while bytes are arriving, and resumes in this process byte for byte.

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use storyarc_core::downloads::queue::{DownloadState, FailureReason, Pause};
use storyarc_core::downloads::transfer::{self, Resumption, TransferError};
use storyarc_core::downloads::{DownloadFolder, Landed, LandingError};
use storyarc_core::io::CancelToken;
use storyarc_core::net::{HttpClient, Request, TrustStore, Url};
use storyarc_core::runtime::Runtime;

/// How the test server behaves.
#[derive(Clone)]
struct Serving {
    body: Arc<Mutex<Vec<u8>>>,
    etag: Arc<Mutex<Option<String>>>,
    ranges: bool,
    /// Requests whose number is below this are sent slowly, a few kilobytes at a time.
    slow_requests: usize,
    /// Cuts every answer after this many bytes, with the full length still declared.
    cut_at: Option<usize>,
    status: u16,
}

impl Serving {
    fn of(body: Vec<u8>) -> Self {
        Self {
            body: Arc::new(Mutex::new(body)),
            etag: Arc::new(Mutex::new(Some("\"v1\"".into()))),
            ranges: true,
            slow_requests: 0,
            cut_at: None,
            status: 200,
        }
    }
}

/// What the server saw: each request's `Range` and `If-Range`.
type Seen = Arc<Mutex<Vec<(Option<String>, Option<String>)>>>;

fn serve(serving: Serving) -> (Url, Seen) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen: Seen = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::clone(&seen);
    let count = Arc::new(AtomicUsize::new(0));
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let serving = serving.clone();
            let log = Arc::clone(&log);
            let number = count.fetch_add(1, Ordering::SeqCst);
            std::thread::spawn(move || answer(stream, &serving, &log, number));
        }
    });
    (
        Url::parse(&format!("http://127.0.0.1:{port}/book.cbz")).unwrap(),
        seen,
    )
}

fn answer(stream: TcpStream, serving: &Serving, log: &Seen, number: usize) {
    let (range, if_range) = read_headers(&stream);
    log.lock().unwrap().push((range.clone(), if_range.clone()));
    let body = serving.body.lock().unwrap().clone();
    let etag = serving.etag.lock().unwrap().clone();
    let total = body.len();
    let mut head = String::new();
    let mut from = 0;
    let status = if serving.status != 200 {
        serving.status
    } else {
        let start = range
            .as_deref()
            .and_then(|r| r.strip_prefix("bytes="))
            .and_then(|r| r.split('-').next())
            .and_then(|s| s.parse::<usize>().ok());
        let validator_holds = match (&if_range, &etag) {
            (None, _) => true,
            (Some(asked), Some(now)) => asked == now,
            (Some(_), None) => false,
        };
        match start {
            Some(start) if serving.ranges && validator_holds && start >= total => {
                head.push_str(&format!("Content-Range: bytes */{total}\r\n"));
                from = total;
                416
            }
            Some(start) if serving.ranges && validator_holds => {
                head.push_str(&format!(
                    "Content-Range: bytes {start}-{}/{total}\r\n",
                    total - 1
                ));
                from = start;
                206
            }
            _ => 200,
        }
    };
    if serving.ranges {
        head.push_str("Accept-Ranges: bytes\r\n");
    }
    if let Some(tag) = etag {
        head.push_str(&format!("ETag: {tag}\r\n"));
    }
    let payload: &[u8] = if (200..300).contains(&status) {
        &body[from..]
    } else {
        &[]
    };
    let mut stream = stream;
    if write!(
        stream,
        "HTTP/1.1 {status} X\r\n{head}Content-Length: {}\r\nConnection: close\r\n\r\n",
        payload.len()
    )
    .is_err()
    {
        return;
    }
    let sent = serving
        .cut_at
        .map_or(payload.len(), |cut| cut.min(payload.len()));
    for chunk in payload[..sent].chunks(8 * 1024) {
        if stream.write_all(chunk).is_err() {
            return;
        }
        if number < serving.slow_requests {
            std::thread::sleep(Duration::from_millis(25));
        }
    }
}

fn read_headers(stream: &TcpStream) -> (Option<String>, Option<String>) {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    let (mut range, mut if_range) = (None, None);
    loop {
        let mut header = String::new();
        if reader.read_line(&mut header).unwrap_or(0) == 0 || header == "\r\n" {
            break;
        }
        if let Some((name, value)) = header.split_once(':') {
            let value = Some(value.trim().to_owned());
            if name.eq_ignore_ascii_case("range") {
                range = value;
            } else if name.eq_ignore_ascii_case("if-range") {
                if_range = value;
            }
        }
    }
    (range, if_range)
}

fn http() -> HttpClient {
    HttpClient::new(&Runtime::new().unwrap(), TrustStore::new()).unwrap()
}

/// A megabyte that is not a run of one value, so a misplaced splice shows.
fn megabyte() -> Vec<u8> {
    (0..1024 * 1024u32)
        .map(|i| (i.wrapping_mul(2_654_435_761) >> 24) as u8)
        .collect()
}

fn fixture(name: &str) -> Vec<u8> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../packages/test-fixtures/comics")
        .join(name);
    std::fs::read(path).unwrap()
}

// ---- one transfer ---------------------------------------------------------------------------

#[test]
fn a_fresh_transfer_writes_every_byte_and_says_it_started_fresh() {
    let body = megabyte();
    let (url, seen) = serve(Serving::of(body.clone()));
    let dir = tempfile::tempdir().unwrap();
    let part = dir.path().join("one.part");
    let mut last = (0, None);
    let done = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |received, total| last = (received, total),
    )
    .unwrap();
    assert_eq!(done.resumption, Resumption::Fresh);
    assert_eq!(done.length, body.len() as u64);
    assert_eq!(std::fs::read(&part).unwrap(), body);
    assert_eq!(last, (body.len() as u64, Some(body.len() as u64)));
    assert_eq!(seen.lock().unwrap()[0], (None, None));
}

#[test]
fn a_cancelled_transfer_keeps_what_arrived_and_the_next_one_resumes_from_there() {
    let body = megabyte();
    let mut serving = Serving::of(body.clone());
    serving.slow_requests = 1;
    let (url, seen) = serve(serving);
    let dir = tempfile::tempdir().unwrap();
    let part = dir.path().join("one.part");
    let cancel = CancelToken::new();
    let stopped = transfer::transfer(
        &http(),
        Request::get(url.clone()),
        &part,
        &cancel,
        |r, _| {
            if r >= 64 * 1024 {
                cancel.cancel();
            }
        },
    );
    assert_eq!(stopped, Err(TransferError::Cancelled));
    let kept = transfer::kept(&part);
    assert!(kept >= 64 * 1024 && kept < body.len() as u64, "kept {kept}");

    let done = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    assert_eq!(done.resumption, Resumption::Resumed { from: kept });
    assert_eq!(std::fs::read(&part).unwrap(), body);
    let second = seen.lock().unwrap()[1].clone();
    assert_eq!(second.0, Some(format!("bytes={kept}-")));
    assert_eq!(second.1.as_deref(), Some("\"v1\""));
}

#[test]
fn a_server_without_ranges_restarts_and_says_so() {
    let body = megabyte();
    let mut serving = Serving::of(body.clone());
    serving.ranges = false;
    let (url, _) = serve(serving);
    let dir = tempfile::tempdir().unwrap();
    let part = dir.path().join("one.part");
    std::fs::write(&part, &body[..1000]).unwrap();
    let done = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    assert_eq!(done.resumption, Resumption::Restarted);
    assert_eq!(std::fs::read(&part).unwrap(), body);
}

#[test]
fn a_publication_changed_on_the_server_is_fetched_whole_rather_than_spliced() {
    let old = megabyte();
    let serving = Serving::of(old.clone());
    let (url, _) = serve(serving.clone());
    let dir = tempfile::tempdir().unwrap();
    let part = dir.path().join("one.part");
    let cancel = CancelToken::new();
    let _ = transfer::transfer(
        &http(),
        Request::get(url.clone()),
        &part,
        &cancel,
        |r, _| {
            if r >= 8 * 1024 {
                cancel.cancel();
            }
        },
    );
    assert!(transfer::kept(&part) > 0);

    let new: Vec<u8> = old.iter().map(|b| b.wrapping_add(1)).collect();
    *serving.body.lock().unwrap() = new.clone();
    *serving.etag.lock().unwrap() = Some("\"v2\"".into());
    let done = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    assert_eq!(done.resumption, Resumption::Restarted);
    assert_eq!(std::fs::read(&part).unwrap(), new);
}

#[test]
fn a_file_already_whole_is_not_fetched_again() {
    let body = megabyte();
    let (url, _) = serve(Serving::of(body.clone()));
    let dir = tempfile::tempdir().unwrap();
    let part = dir.path().join("one.part");
    transfer::transfer(
        &http(),
        Request::get(url.clone()),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    let again = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    assert_eq!(again.length, body.len() as u64);
    assert_eq!(std::fs::read(&part).unwrap(), body);
}

#[test]
fn a_missing_publication_is_its_status_and_a_short_body_is_retried() {
    let mut missing = Serving::of(Vec::new());
    missing.status = 404;
    let (url, _) = serve(missing);
    let dir = tempfile::tempdir().unwrap();
    let error = transfer::transfer(
        &http(),
        Request::get(url),
        &dir.path().join("a.part"),
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap_err();
    assert_eq!(error, TransferError::Http(404));
    assert!(!error.is_transient());

    let mut short = Serving::of(megabyte());
    short.cut_at = Some(100_000);
    let (url, _) = serve(short);
    let error = transfer::transfer(
        &http(),
        Request::get(url),
        &dir.path().join("b.part"),
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap_err();
    assert!(error.is_transient(), "{error:?}");
    assert_eq!(FailureReason::of(&error), FailureReason::Network);
}

// ---- a killed process resumes byte for byte ---------------------------------------------

const CHILD_URL: &str = "STORYARC_DOWNLOAD_CHILD_URL";
const CHILD_PART: &str = "STORYARC_DOWNLOAD_CHILD_PART";

/// The child side of the kill case. Does nothing unless the parent set the variables.
#[test]
fn the_child_side_of_a_killed_download() {
    let (Ok(url), Ok(part)) = (std::env::var(CHILD_URL), std::env::var(CHILD_PART)) else {
        return;
    };
    let _ = transfer::transfer(
        &http(),
        Request::get(Url::parse(&url).unwrap()),
        Path::new(&part),
        &CancelToken::new(),
        |_, _| {},
    );
    // Reaching here means the kill came too late; the parent fails on it.
    std::process::exit(3);
}

#[test]
fn a_download_killed_mid_transfer_resumes_byte_for_byte() {
    let body = megabyte();
    let mut serving = Serving::of(body.clone());
    serving.slow_requests = 1;
    let (url, seen) = serve(serving);
    let dir = tempfile::tempdir().unwrap();
    let part: PathBuf = dir.path().join("killed.part");

    let mut child = Command::new(std::env::current_exe().unwrap())
        .args([
            "the_child_side_of_a_killed_download",
            "--exact",
            "--nocapture",
        ])
        .env(CHILD_URL, url.as_str())
        .env(CHILD_PART, &part)
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(20);
    while transfer::kept(&part) < 128 * 1024 {
        assert!(Instant::now() < deadline, "the child never wrote");
        assert!(child.try_wait().unwrap().is_none(), "the child ended early");
        std::thread::sleep(Duration::from_millis(10));
    }
    child.kill().unwrap();
    child.wait().unwrap();
    let kept = transfer::kept(&part);
    assert!(kept < body.len() as u64, "the kill came after the end");

    let done = transfer::transfer(
        &http(),
        Request::get(url),
        &part,
        &CancelToken::new(),
        |_, _| {},
    )
    .unwrap();
    assert_eq!(done.resumption, Resumption::Resumed { from: kept });
    assert_eq!(std::fs::read(&part).unwrap(), body);
    assert_eq!(
        seen.lock().unwrap().last().unwrap().0,
        Some(format!("bytes={kept}-"))
    );
}

// ---- landing: integrity before available offline -----------------------------------------

#[test]
fn a_finished_download_is_verified_moved_into_its_folder_and_the_partial_is_gone() {
    let body = fixture("natural-sort.cbz");
    let (url, _) = serve(Serving::of(body.clone()));
    let dir = tempfile::tempdir().unwrap();
    let folder = DownloadFolder::new(dir.path());
    let landed: Landed = folder
        .fetch(
            &http(),
            "opds:1",
            "Natural Sort",
            Request::get(url),
            None,
            &CancelToken::new(),
            |_, _| {},
        )
        .unwrap();
    assert_eq!(std::fs::read(&landed.path).unwrap(), body);
    assert_eq!(landed.path.extension().unwrap(), "cbz");
    assert_eq!(landed.resumption, Resumption::Fresh);
    assert!(landed.publication.page_count.unwrap_or(0) > 0);
    assert!(!folder.partial("opds:1").exists());
    assert_eq!(folder.located("opds:1"), Some(landed.path.clone()));
    assert_eq!(folder.bytes_on_disk(), body.len() as u64);

    folder.remove("opds:1");
    assert_eq!(folder.located("opds:1"), None);
    assert_eq!(folder.bytes_on_disk(), 0);
}

#[test]
fn bytes_that_are_not_a_publication_fail_verification_and_leave_nothing_behind() {
    // An error page served as the file: the likeliest bytes that are not a publication.
    let body = b"<html><body>Service temporarily unavailable</body></html>".repeat(40);
    let (url, _) = serve(Serving::of(body));
    let dir = tempfile::tempdir().unwrap();
    let folder = DownloadFolder::new(dir.path());
    let error = folder
        .fetch(
            &http(),
            "opds:2",
            "Half",
            Request::get(url),
            None,
            &CancelToken::new(),
            |_, _| {},
        )
        .unwrap_err();
    assert_eq!(error, LandingError::Unreadable);
    assert_eq!(FailureReason::from(&error), FailureReason::Unreadable);
    assert!(!folder.partial("opds:2").exists());
    assert_eq!(folder.located("opds:2"), None);
}

#[test]
fn a_known_container_the_app_does_not_read_is_unsupported_not_unreadable() {
    let mut seven = vec![0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4];
    seven.resize(4096, 0);
    let (url, _) = serve(Serving::of(seven));
    let dir = tempfile::tempdir().unwrap();
    let folder = DownloadFolder::new(dir.path());
    let error = folder
        .fetch(
            &http(),
            "opds:3",
            "Seven",
            Request::get(url),
            None,
            &CancelToken::new(),
            |_, _| {},
        )
        .unwrap_err();
    assert!(matches!(error, LandingError::Unsupported(_)), "{error:?}");
}

#[test]
fn a_queue_saved_mid_download_comes_back_with_the_running_item_queued() {
    use storyarc_core::downloads::queue::{Download, DownloadQueue};
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("queue.json");
    let queue = DownloadQueue::default()
        .queueing(Download::new("a", "A", "http://x/a"))
        .queueing(Download::new("b", "B", "http://x/b"))
        .marking("a", DownloadState::Running)
        .advancing("a", 500, Some(1000))
        .marking("b", DownloadState::Paused(Pause::ByReader));
    queue.save(&file).unwrap();
    let back = DownloadQueue::load(&file).unwrap();
    assert_eq!(back.get("a").unwrap().state, DownloadState::Queued);
    assert_eq!(back.get("a").unwrap().downloaded_bytes, 500);
    assert_eq!(
        back.get("b").unwrap().state,
        DownloadState::Paused(Pause::ByReader)
    );
}
