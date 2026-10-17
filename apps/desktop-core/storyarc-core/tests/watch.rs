//! The watcher abstraction (task 2.3 of `desktop-clients`): a file added to a watched
//! folder is noticed inside 10 seconds, a folder past the system limit falls back to a
//! rescan and says it is not watched live, and a folder granted through a portal is polled.

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::Duration;

use storyarc_core::sources::watch::{
    Coverage, FolderWatcher, NotLiveReason, WatchOptions, WatchedFolder,
};

const TEN_SECONDS: Duration = Duration::from_secs(10);

fn folder(dir: &tempfile::TempDir, is_portal_granted: bool) -> WatchedFolder {
    WatchedFolder {
        path: dir.path().to_path_buf(),
        is_portal_granted,
    }
}

/// Starts a watcher over `dir` and returns it with the channel its changes arrive on.
fn watching(
    folder: WatchedFolder,
    options: WatchOptions,
) -> (FolderWatcher, mpsc::Receiver<PathBuf>) {
    let (sender, receiver) = mpsc::channel();
    let watcher = FolderWatcher::watch(vec![folder], options, move |root: &Path| {
        let _ = sender.send(root.to_path_buf());
    });
    (watcher, receiver)
}

#[test]
fn a_file_added_to_a_watched_folder_is_seen_inside_ten_seconds() {
    let dir = tempfile::tempdir().unwrap();
    let (watcher, changes) = watching(folder(&dir, false), WatchOptions::default());
    assert!(matches!(watcher.coverage()[0].coverage, Coverage::Live));

    std::fs::write(dir.path().join("New.cbz"), b"PK\x03\x04").unwrap();

    let changed = changes
        .recv_timeout(TEN_SECONDS)
        .expect("a change inside ten seconds");
    assert_eq!(changed, dir.path());
    watcher.stop();
}

#[test]
fn a_folder_past_the_limit_falls_back_to_a_rescan_and_says_so() {
    let dir = tempfile::tempdir().unwrap();
    let options = WatchOptions {
        directory_limit: 0,
        poll_interval: Duration::from_secs(1),
        ..WatchOptions::default()
    };
    let (watcher, changes) = watching(folder(&dir, false), options);

    let coverage = &watcher.coverage()[0];
    let Coverage::Polled { interval, reason } = &coverage.coverage else {
        panic!("the folder should be polled, not watched live: {coverage:?}");
    };
    assert_eq!(*interval, Duration::from_secs(1));
    assert_eq!(
        *reason,
        NotLiveReason::DirectoryLimit {
            limit: 0,
            directories: 1
        }
    );
    assert!(reason.to_string().contains("not watched live"), "{reason}");
    assert!(!watcher.is_watched_live(dir.path()));

    std::fs::write(dir.path().join("New.cbz"), b"PK\x03\x04").unwrap();
    let changed = changes
        .recv_timeout(TEN_SECONDS)
        .expect("the rescan sees the file");
    assert_eq!(changed, dir.path());
    watcher.stop();
}

#[test]
fn a_portal_granted_folder_is_polled_and_sees_a_file_inside_ten_seconds() {
    let dir = tempfile::tempdir().unwrap();
    let options = WatchOptions {
        poll_interval: Duration::from_secs(1),
        ..WatchOptions::default()
    };
    let (watcher, changes) = watching(folder(&dir, true), options);
    assert!(matches!(
        &watcher.coverage()[0].coverage,
        Coverage::Polled {
            reason: NotLiveReason::PortalGranted,
            ..
        }
    ));

    std::fs::write(dir.path().join("New.cbz"), b"PK\x03\x04").unwrap();
    let changed = changes
        .recv_timeout(TEN_SECONDS)
        .expect("the poll sees the file");
    assert_eq!(changed, dir.path());
    watcher.stop();
}

#[test]
fn the_default_poll_interval_is_ten_seconds_or_less() {
    assert!(WatchOptions::default().poll_interval <= TEN_SECONDS);
    assert_eq!(
        WatchOptions::default().directory_limit,
        storyarc_core::sources::WATCH_DIRECTORY_LIMIT
    );
}
