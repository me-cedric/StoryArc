//! Secrets never leave the secure store (task 3.3 of `desktop-clients`, written before the
//! store it tests).
//!
//! `desktop-experience`, *Secrets in the system's own store*: a secret goes to the system's
//! secure store and the source's record holds only a reference; with no store running the
//! secret is held for the session and the app says so once; a store that refuses keeps no copy;
//! and the app's data directory, its logs and an exported diagnostic are searched for a known
//! secret and none of them holds it, **in any encoding**. That last clause is what this file is
//! for: every check below looks for the secret as UTF-8, UTF-16 in both byte orders, Base64
//! (standard and URL-safe, alone and as an HTTP Basic pair), percent-encoding, hex in both
//! cases and JSON's ASCII escapes.
//!
//! The store here is the in-memory one. The Windows Credential Manager and Secret Service
//! backends run only on their own systems; their behaviour behind the same trait is what the
//! `Vault` cases pin.

use std::path::Path;
use std::sync::{Mutex, OnceLock};

use storyarc_core::diagnostics::{DiagnosticReport, redact};
use storyarc_core::runtime::Runtime;
use storyarc_core::secrets::{
    MemorySecretStore, SaveOutcome, Secret, SecretKey, SecretStore, SecretStoreError,
    UnavailableStore, Vault, WINDOWS_BLOB_LIMIT,
};
use storyarc_core::sources::smb::{SmbAddress, SmbLogin, SmbShare};
use storyarc_core::store::{Store, StoredSource};

/// Non-ASCII on purpose, so that UTF-8, UTF-16 and the escapes all differ from each other.
const SECRET: &str = "Hunter2-s\u{e9}cret-\u{20ac}-\u{1d11e}-tok";
const USER: &str = "ada";
const HOST: &str = "nas.example.lan";

// ---- every encoding the secret could hide in ---------------------------------------------

fn base64(bytes: &[u8], url_safe: bool) -> String {
    let alphabet: &[u8] = if url_safe {
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    } else {
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    };
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |acc, (i, b)| acc | u32::from(*b) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(alphabet[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}

/// Every form the secret could take on its way to a file, a log or a diagnostic.
fn encodings(secret: &str) -> Vec<(&'static str, Vec<u8>)> {
    let utf8 = secret.as_bytes().to_vec();
    let utf16le: Vec<u8> = secret.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let utf16be: Vec<u8> = secret.encode_utf16().flat_map(u16::to_be_bytes).collect();
    let percent: String = utf8
        .iter()
        .map(|b| {
            if b.is_ascii_alphanumeric() {
                (*b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    let hex_lower: String = utf8.iter().map(|b| format!("{b:02x}")).collect();
    let json_ascii: String = secret
        .encode_utf16()
        .map(|unit| match char::from_u32(u32::from(unit)) {
            Some(c) if c.is_ascii() => c.to_string(),
            _ => format!("\\u{unit:04x}"),
        })
        .collect();
    // Base64 is position-dependent, so a secret embedded in a longer value would encode
    // differently; the bare value and the Basic pair are the two shapes a client sends.
    vec![
        ("UTF-8", utf8.clone()),
        ("UTF-16LE", utf16le),
        ("UTF-16BE", utf16be),
        ("Base64", base64(&utf8, false).trim_end_matches('=').into()),
        ("Base64 URL", base64(&utf8, true).into()),
        (
            "Base64 Basic pair",
            base64(format!("{USER}:{secret}").as_bytes(), false).into(),
        ),
        ("percent", percent.into()),
        ("hex", hex_lower.clone().into()),
        ("HEX", hex_lower.to_uppercase().into()),
        ("JSON escapes", json_ascii.into()),
    ]
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

/// Fails naming the place and the encoding the secret was found in.
fn assert_absent(place: &str, haystack: &[u8]) {
    for (encoding, needle) in encodings(SECRET) {
        assert!(
            !contains(haystack, &needle),
            "the secret is in {place}, as {encoding}"
        );
    }
}

/// Every file under `dir`, read whole.
fn every_file(dir: &Path) -> Vec<(String, Vec<u8>)> {
    let mut found = Vec::new();
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            found.extend(every_file(&path));
        } else {
            found.push((path.display().to_string(), std::fs::read(&path).unwrap()));
        }
    }
    found
}

// ---- a logger that keeps everything -----------------------------------------------------

struct Capture(Mutex<Vec<String>>);

impl log::Log for Capture {
    fn enabled(&self, _: &log::Metadata<'_>) -> bool {
        true
    }

    fn log(&self, record: &log::Record<'_>) {
        let line = format!("{} {} {}", record.level(), record.target(), record.args());
        self.0.lock().unwrap().push(line);
    }

    fn flush(&self) {}
}

fn capture() -> &'static Capture {
    static LOGGER: OnceLock<&'static Capture> = OnceLock::new();
    LOGGER.get_or_init(|| {
        let logger: &'static Capture = Box::leak(Box::new(Capture(Mutex::new(Vec::new()))));
        log::set_logger(logger).expect("one logger per test binary");
        log::set_max_level(log::LevelFilter::Trace);
        logger
    })
}

fn logged() -> Vec<u8> {
    capture().0.lock().unwrap().join("\n").into_bytes()
}

// ---- the encodings check can fail -------------------------------------------------------

#[test]
fn the_search_finds_the_secret_in_each_encoding_it_looks_for() {
    // A check that always passes looks exactly like a clean store (AGENTS.md, section 5).
    for (encoding, needle) in encodings(SECRET) {
        let mut planted = b"before ".to_vec();
        planted.extend_from_slice(&needle);
        planted.extend_from_slice(b" after");
        let found = std::panic::catch_unwind(|| assert_absent("a planted buffer", &planted));
        assert!(
            found.is_err(),
            "the {encoding} search found nothing it was given"
        );
    }
}

// ---- the store and the record -----------------------------------------------------------

#[test]
fn a_saved_secret_goes_to_the_store_and_the_record_holds_only_a_reference() {
    capture();
    let data = tempfile::tempdir().unwrap();
    let vault = Vault::new(Box::new(MemorySecretStore::new()));
    let source = StoredSource {
        id: "8c1d6c0e-6f3e-4a51-9a3b-2b8e7c1d0f42".into(),
        display_name: "Comics".into(),
        kind: "networkShare".into(),
        locator: format!("smb://{HOST}/Comics"),
        position: 0,
        is_portal_granted: false,
    };
    let key = SecretKey::for_source(&source.id, "password");
    assert_eq!(
        vault.save(&key, Secret::new(SECRET)).unwrap(),
        SaveOutcome::Stored
    );

    let store = Store::open(data.path().join("library.sqlite")).unwrap();
    store.save_source(&source).unwrap();
    drop(store);

    // The record names the secret only through the source's id.
    assert!(key.account().contains(&source.id));
    assert_eq!(vault.load(&key).unwrap().unwrap().expose(), SECRET);
    for (path, bytes) in every_file(data.path()) {
        assert_absent(&path, &bytes);
    }
    assert_absent("the log", &logged());
}

#[test]
fn a_secret_prints_as_a_mask_wherever_it_travels() {
    let key = SecretKey::for_source("a-source", "token");
    let secret = Secret::new(SECRET);
    let login = SmbLogin::account(USER, SECRET);
    let printed = format!("{secret:?} {login:?} {key:?} {:#?}", login);
    assert_absent("a Debug print", printed.as_bytes());
    // A pasted address carrying credentials keeps none of them.
    let pasted = SmbAddress::parse(&format!("smb://{USER}:{SECRET}@{HOST}/Comics")).unwrap();
    assert_absent("a parsed address", format!("{pasted:?}").as_bytes());
}

// ---- the session-only fallback and a refusing store -------------------------------------

#[test]
fn with_no_store_running_the_secret_lives_for_the_session_and_the_app_says_so_once() {
    capture();
    let vault = Vault::new(Box::new(UnavailableStore::new()));
    let key = SecretKey::for_source("share", "password");
    let first = vault.save(&key, Secret::new(SECRET)).unwrap();
    let SaveOutcome::SessionOnly { notice } = first else {
        panic!("a missing store is not an error: {first:?}");
    };
    let notice = notice.expect("the first save says so");
    // Each OS names its own store.
    let store_name = if cfg!(windows) {
        "Credential Manager"
    } else {
        "Secret Service"
    };
    assert!(notice.remedy.contains(store_name));
    assert_eq!(
        vault.save(&key, Secret::new(SECRET)).unwrap(),
        SaveOutcome::SessionOnly { notice: None },
        "once, not on every save"
    );
    assert_eq!(vault.load(&key).unwrap().unwrap().expose(), SECRET);

    // The next launch is a new vault, and asks again.
    let next_launch = Vault::new(Box::new(UnavailableStore::new()));
    assert!(next_launch.load(&key).unwrap().is_none());
    assert_absent("the log", &logged());
}

#[test]
fn a_store_that_refuses_is_named_and_no_copy_is_kept() {
    let vault = Vault::new(Box::new(MemorySecretStore::refusing()));
    let key = SecretKey::for_source("share", "password");
    let error = vault.save(&key, Secret::new(SECRET)).unwrap_err();
    assert!(matches!(error, SecretStoreError::Refused(_)));
    assert_absent("the error", format!("{error} {error:?}").as_bytes());
    assert!(
        vault.load(&key).unwrap().is_none(),
        "no copy: the source asks to sign in"
    );
}

#[test]
fn a_secret_over_the_windows_blob_limit_is_refused_before_the_store_sees_it() {
    let store = MemorySecretStore::with_limit(WINDOWS_BLOB_LIMIT);
    let key = SecretKey::for_source("kavita", "apiKey");
    let long = "k".repeat(WINDOWS_BLOB_LIMIT + 1);
    assert_eq!(
        store.save(&key, &Secret::new(long)).unwrap_err(),
        SecretStoreError::TooLarge {
            limit: WINDOWS_BLOB_LIMIT
        }
    );
    let fits = "k".repeat(WINDOWS_BLOB_LIMIT);
    store.save(&key, &Secret::new(fits.clone())).unwrap();
    assert_eq!(store.load(&key).unwrap().unwrap().expose(), fits);
}

#[test]
fn deleting_a_source_removes_its_secret() {
    let vault = Vault::new(Box::new(MemorySecretStore::new()));
    let key = SecretKey::for_source("share", "password");
    vault.save(&key, Secret::new(SECRET)).unwrap();
    vault.delete(&key).unwrap();
    assert!(vault.load(&key).unwrap().is_none());
    vault.delete(&key).unwrap();
}

// ---- the network path and the diagnostic ------------------------------------------------

#[test]
fn signing_in_to_a_share_logs_no_secret() {
    capture();
    let runtime = Runtime::new().unwrap();
    // Nothing listens on 4999 (AGENTS.md, the fixture table); the attempt still runs the
    // client's connect path and every log line it writes. With the Samba fixture running,
    // `STORYARC_SMB_PORT` sends the attempt through a full NTLM exchange as well.
    let port = std::env::var("STORYARC_SMB_PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(4999);
    let address = SmbAddress::new("127.0.0.1", "Comics").with_port(port);
    let _ = SmbShare::check(&runtime, address, SmbLogin::account(USER, SECRET));
    let log = logged();
    assert!(
        String::from_utf8_lossy(&log).contains("smb"),
        "the client wrote no log line, so the search below would prove nothing"
    );
    assert_absent("the log", &log);
}

#[test]
fn an_exported_diagnostic_holds_no_secret_and_no_host() {
    let secret = Secret::new(SECRET);
    let mut report = DiagnosticReport::new("StoryArc diagnostic");
    report.section("App", [("version", "0.1.0")]);
    report.section("Sources", [("count", "1")]);
    // Free text that an error message carried into the report: the worst case.
    report.section(
        "Last error",
        [
            (
                "message",
                format!("smb://{USER}:{SECRET}@{HOST}:445/Comics refused").as_str(),
            ),
            ("detail", format!("password={SECRET}").as_str()),
            ("raw", SECRET),
        ],
    );
    let text = report.render(&[&secret]);
    assert_absent("the diagnostic", text.as_bytes());
    assert!(!text.contains(HOST), "a hostname is redacted as on a phone");
    assert!(text.contains("[App]") && text.contains("count = 1"));
}

#[test]
fn the_redaction_rules_match_the_phones() {
    assert_eq!(
        redact("smb://reader:hunter2@nas.local:445/comics"),
        "smb://[host]/comics"
    );
    assert_eq!(redact("at 192.168.1.20 now"), "at [host] now");
    assert_eq!(redact("token: abc123"), "token=[redacted]");
    assert_eq!(
        redact("key AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"),
        "key=[redacted]"
    );
    assert_eq!(
        redact("run AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 ok"),
        "run [token] ok"
    );
    assert_eq!(redact("/Users/ada/Comics"), "~/Comics");
    assert_eq!(redact("/home/ada/Comics"), "~/Comics");
}
