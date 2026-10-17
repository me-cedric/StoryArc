//! The SMB source against the Samba fixture (task 3.2 of `desktop-clients`).
//!
//! The fixture is `scripts/smb-server.sh` (`pnpm smb`), or the same `smb.conf` in a container
//! (`docs/delivery/desktop-spike-smb.md`). Each case that needs it skips with a line on stderr
//! when nothing answers on its port, as Android's `SmbClientTest.isServerRunning()` does, so a
//! machine without Samba still runs the rest. Ports and the account come from the environment:
//!
//! | Variable | Default | Serves |
//! | --- | --- | --- |
//! | `STORYARC_SMB_PORT` | 4445 | the signed, unencrypted share |
//! | `STORYARC_SMB_ENCRYPTED_PORT` | 4446 | the share with `smb encrypt = required` |
//! | `STORYARC_SMB1_PORT` | none | a server that speaks only SMB 1; skipped when unset |
//! | `STORYARC_SMB_USER` | `$USER` | the account `smb-server.sh` maps onto this machine's |

use std::sync::Arc;
use std::time::Duration;

use storyarc_core::formats::ComicArchive;
use storyarc_core::io::RandomAccessSource;
use storyarc_core::runtime::Runtime;
use storyarc_core::sources::smb::{SmbAddress, SmbError, SmbLogin, SmbShare, probe};

const PASSWORD: &str = "lovelace";
const SHARE: &str = "Comics";
/// Nothing listens here, by design (`AGENTS.md`, the fixture port table).
const REFUSED_PORT: u16 = 4999;

fn port(variable: &str, default: Option<u16>) -> Option<u16> {
    std::env::var(variable)
        .ok()
        .and_then(|value| value.parse().ok())
        .or(default)
}

fn user() -> String {
    std::env::var("STORYARC_SMB_USER")
        .or_else(|_| std::env::var("USER"))
        .unwrap_or_else(|_| "nobody".into())
}

/// The port of a running fixture, or `None` with the reason on stderr. An SMB server must
/// answer a negotiate: an open socket is not enough, because a container's port proxy accepts
/// a connection with nothing working behind it.
fn fixture(variable: &str, default: Option<u16>) -> Option<u16> {
    let Some(port) = port(variable, default) else {
        eprintln!("skipped: {variable} is not set");
        return None;
    };
    if probe::answers_smb("127.0.0.1", port, Duration::from_secs(1)) {
        Some(port)
    } else {
        eprintln!("skipped: no SMB server answers on {port} (pnpm smb)");
        None
    }
}

fn plain() -> Option<u16> {
    fixture("STORYARC_SMB_PORT", Some(4445))
}

fn address(port: u16) -> SmbAddress {
    SmbAddress::new("127.0.0.1", SHARE).with_port(port)
}

fn login() -> SmbLogin {
    SmbLogin::account(user(), PASSWORD)
}

#[test]
fn a_share_reports_its_dialect_and_negotiates_encryption() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let identity = SmbShare::check(&runtime, address(port), login()).unwrap();
    assert_eq!(identity.dialect, "SMB 3.1.1");
    assert!(
        identity.is_encrypted,
        "an SMB 3 server that supports encryption is asked for it (network-share, Encrypted transport)"
    );
}

#[test]
fn a_share_that_requires_encryption_is_read_encrypted() {
    let Some(port) = fixture("STORYARC_SMB_ENCRYPTED_PORT", Some(4446)) else {
        return;
    };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    assert!(share.identity().is_encrypted);
    let file = share.open("Fine Print.cbz").unwrap();
    assert_eq!(file.read(0, 4).unwrap(), b"PK\x03\x04");
}

#[test]
fn a_rejected_password_is_named() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let wrong = SmbLogin::account(user(), "not the password");
    assert_eq!(
        SmbShare::check(&runtime, address(port), wrong).unwrap_err(),
        SmbError::AuthenticationRejected
    );
}

#[test]
fn a_missing_share_is_named() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let nowhere = SmbAddress::new("127.0.0.1", "Nowhere").with_port(port);
    assert_eq!(
        SmbShare::check(&runtime, nowhere, login()).unwrap_err(),
        SmbError::ShareNotFound
    );
}

#[test]
fn nothing_listening_is_an_unreachable_host() {
    let runtime = Runtime::new().unwrap();
    let error = SmbShare::check(&runtime, address(REFUSED_PORT), login()).unwrap_err();
    assert_eq!(error, SmbError::HostUnreachable);
    assert!(error.is_unreachable());
}

#[test]
fn a_missing_file_is_not_a_missing_share() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    assert_eq!(
        share.open("Not Here.cbz").unwrap_err(),
        SmbError::FileNotFound("Not Here.cbz".into())
    );
}

#[test]
fn the_root_lists_folders_first_then_natural_order() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    let entries = share.list("").unwrap();
    let first_file = entries
        .iter()
        .position(|entry| !entry.is_directory)
        .unwrap();
    assert!(entries[..first_file].iter().all(|entry| entry.is_directory));
    assert!(
        entries
            .iter()
            .any(|e| e.name == "Salt and Iron" && e.is_directory)
    );
    let tidal: Vec<_> = entries
        .iter()
        .filter(|e| e.name.starts_with("Tidal Reach"))
        .map(|e| e.name.as_str())
        .collect();
    assert_eq!(
        tidal,
        [
            "Tidal Reach 01.cbz",
            "Tidal Reach 02.cbz",
            "Tidal Reach 03.cbz"
        ]
    );
    let quiet = entries
        .iter()
        .find(|e| e.name == "Quiet Machines.cbz")
        .unwrap();
    assert!(quiet.length > 0);
    let inside = share.list("Salt and Iron").unwrap();
    assert!(!inside.is_empty());
    assert!(inside.iter().all(|e| e.path.starts_with("Salt and Iron/")));
}

#[test]
fn a_comic_on_the_share_opens_through_the_same_archive_reader() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    let file = Arc::new(share.open("Quiet Machines.cbz").unwrap());
    let whole = file.read(0, file.length() as usize).unwrap();
    assert_eq!(whole.len() as u64, file.length());
    let archive = ComicArchive::open(file.clone()).unwrap();
    assert!(!archive.pages().is_empty());
    let first = archive.data(&archive.pages()[0]).unwrap();
    assert!(!first.is_empty());
    // The status a reader window polls stays quiet on a healthy share.
    assert_eq!(file.status(), Default::default());
}

#[test]
fn a_dropped_session_reconnects_on_the_next_read_without_a_prompt() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    let file = share.open("Quiet Machines.cbz").unwrap();
    let before = file.read(100, 64).unwrap();
    assert_eq!(file.opens(), 1);
    // What a wake from sleep or a changed network does to the session.
    file.drop_session();
    let after = file.read(100, 64).unwrap();
    assert_eq!(before, after);
    assert_eq!(file.opens(), 2);
}

#[test]
fn a_read_past_the_end_is_short_and_one_beyond_it_is_refused() {
    let Some(port) = plain() else { return };
    let runtime = Runtime::new().unwrap();
    let share = SmbShare::connect(&runtime, address(port), login()).unwrap();
    let file = share.open("Fine Print.cbz").unwrap();
    let length = file.length();
    assert_eq!(file.read(length - 3, 100).unwrap().len(), 3);
    assert!(file.read(length + 1, 1).is_err());
}

#[test]
fn an_smb1_only_server_is_refused_with_the_setting_to_change() {
    let Some(port) = fixture("STORYARC_SMB1_PORT", None) else {
        return;
    };
    let runtime = Runtime::new().unwrap();
    let error = SmbShare::check(&runtime, address(port), login()).unwrap_err();
    assert_eq!(error, SmbError::ProtocolUnsupported);
    assert!(error.remedy().unwrap().contains("SMB 2"));
}
