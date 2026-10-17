//! Notices when a watched folder's contents change (task 2.3 of `desktop-clients`).
//!
//! `desktop-experience`, *Live folder watching*: a file copied into a watched folder
//! appears in the library within 10 seconds; when the system's limit on watched folders is
//! reached, or a folder is on a share that reports no changes, or it was granted through a
//! portal that passes no change events, the app rescans at a fixed interval of 10 seconds
//! or less and says once, in grey, that the folder is not watched live.
//!
//! Three paths behind one type. The native watchers (inotify, `ReadDirectoryChangesW`,
//! FSEvents) through `notify`, with a burst coalesced into one notice as the phones do; a
//! polled path that lists the folder and compares snapshots, for a folder the native
//! watcher cannot cover; and the same polled path for a portal-granted folder, which Linux
//! only ever hands over without events. The walk is `FolderScan::entries`, so the poll
//! opens no archive.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use notify::{RecursiveMode, Watcher};

use super::local::{FolderScan, WATCH_DIRECTORY_LIMIT};
use super::snapshot::FolderSnapshot;

/// A folder to watch, and whether it came through the document portal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WatchedFolder {
    pub path: PathBuf,
    /// Granted through the Linux document portal, which passes no change events: the
    /// folder takes the polled path without trying a native watcher.
    pub is_portal_granted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WatchOptions {
    /// How many directories one root may need before it is polled rather than watched
    /// live: `WATCH_DIRECTORY_LIMIT`, the phones' ceiling. Tests force it to zero.
    pub directory_limit: usize,
    /// How often a polled folder is listed. Ten seconds or less, as the spec states.
    pub poll_interval: Duration,
    /// How long a burst of native events is left to settle before one notice is sent.
    /// Copying forty comics in produces forty events, and a second's wait is invisible
    /// against the ten the requirement allows.
    pub coalesce: Duration,
}

impl Default for WatchOptions {
    fn default() -> Self {
        Self {
            directory_limit: WATCH_DIRECTORY_LIMIT,
            poll_interval: Duration::from_secs(5),
            coalesce: Duration::from_secs(1),
        }
    }
}

/// Why a folder is not watched live. The name the app shows once, in grey.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotLiveReason {
    /// More directories under the root than the ceiling covers.
    DirectoryLimit { limit: usize, directories: usize },
    /// The system refused the watch: inotify's `max_user_watches`, a share that reports
    /// no changes, a filesystem with no notifier. Carries the system's own message.
    SystemLimit(String),
    /// Granted through a portal that passes no change events.
    PortalGranted,
}

impl std::fmt::Display for NotLiveReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DirectoryLimit { limit, directories } => write!(
                f,
                "not watched live: {directories} directories exceed the limit of {limit}"
            ),
            Self::SystemLimit(message) => write!(f, "not watched live: {message}"),
            Self::PortalGranted => {
                f.write_str("not watched live: the folder was granted through a portal")
            }
        }
    }
}

impl std::error::Error for NotLiveReason {}

/// How one folder is covered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Coverage {
    /// The native watcher delivers changes.
    Live,
    /// The folder is listed every `interval` and compared against the last listing.
    Polled {
        interval: Duration,
        reason: NotLiveReason,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FolderCoverage {
    pub path: PathBuf,
    pub coverage: Coverage,
}

/// The callback a change reaches: the root that changed. Called off the caller's thread.
pub type OnChange = Arc<dyn Fn(&Path) + Send + Sync>;

/// Watches folders and reports the roots whose contents changed.
pub struct FolderWatcher {
    coverage: Vec<FolderCoverage>,
    stop: Arc<AtomicBool>,
    stop_senders: Vec<mpsc::Sender<()>>,
    threads: Vec<JoinHandle<()>>,
    /// Kept alive for as long as the watch lasts; dropped on stop.
    native: Option<notify::RecommendedWatcher>,
}

impl FolderWatcher {
    /// Watches these folders. Returns at once; `on_change` is called from a background
    /// thread with the root that changed, at most once per settled burst for a live
    /// folder and once per changed poll for a polled one. Costs one directory walk per
    /// root up front (to count directories against the limit, and to take the first
    /// snapshot of a polled folder).
    pub fn watch(
        folders: Vec<WatchedFolder>,
        options: WatchOptions,
        on_change: impl Fn(&Path) + Send + Sync + 'static,
    ) -> Self {
        let on_change: OnChange = Arc::new(on_change);
        let stop = Arc::new(AtomicBool::new(false));
        let mut coverage = Vec::with_capacity(folders.len());
        let mut live: Vec<PathBuf> = Vec::new();
        let mut polled: Vec<(PathBuf, NotLiveReason)> = Vec::new();

        for folder in folders {
            if folder.is_portal_granted {
                polled.push((folder.path, NotLiveReason::PortalGranted));
                continue;
            }
            let (directories, truncated) = directories_under(&folder.path, options.directory_limit);
            if truncated {
                polled.push((
                    folder.path,
                    NotLiveReason::DirectoryLimit {
                        limit: options.directory_limit,
                        directories,
                    },
                ));
                continue;
            }
            live.push(folder.path);
        }

        let (native, events) = Self::start_native(&mut live, &mut polled);
        let mut threads = Vec::new();
        let mut stop_senders = Vec::new();

        if let Some(events) = events {
            let roots = live.clone();
            let notify = Arc::clone(&on_change);
            let flag = Arc::clone(&stop);
            let coalesce = options.coalesce;
            threads.push(std::thread::spawn(move || {
                coalescing_loop(&events, &roots, coalesce, &flag, &notify);
            }));
        }
        for path in live {
            coverage.push(FolderCoverage {
                path,
                coverage: Coverage::Live,
            });
        }
        for (path, reason) in polled {
            coverage.push(FolderCoverage {
                path: path.clone(),
                coverage: Coverage::Polled {
                    interval: options.poll_interval,
                    reason,
                },
            });
            let (stop_sender, stop_receiver) = mpsc::channel();
            stop_senders.push(stop_sender);
            let notify = Arc::clone(&on_change);
            let interval = options.poll_interval;
            // The first listing is taken here, before this returns, so a file that arrives
            // the moment the watch starts is a change rather than part of the baseline.
            let scan = FolderScan::new(&path);
            let snapshot = FolderSnapshot::new(scan.entries());
            threads.push(std::thread::spawn(move || {
                polling_loop(&scan, &path, snapshot, interval, &stop_receiver, &notify);
            }));
        }

        Self {
            coverage,
            stop,
            stop_senders,
            threads,
            native,
        }
    }

    /// Tries the native watcher on every live root. A root the system refuses moves to the
    /// polled list with the system's own message.
    fn start_native(
        live: &mut Vec<PathBuf>,
        polled: &mut Vec<(PathBuf, NotLiveReason)>,
    ) -> (
        Option<notify::RecommendedWatcher>,
        Option<mpsc::Receiver<notify::Result<notify::Event>>>,
    ) {
        if live.is_empty() {
            return (None, None);
        }
        let (sender, receiver) = mpsc::channel();
        let mut watcher = match notify::recommended_watcher(move |event| {
            let _ = sender.send(event);
        }) {
            Ok(watcher) => watcher,
            Err(error) => {
                for path in live.drain(..) {
                    polled.push((path, NotLiveReason::SystemLimit(error.to_string())));
                }
                return (None, None);
            }
        };
        let mut watched = Vec::new();
        for path in live.drain(..) {
            match watcher.watch(&path, RecursiveMode::Recursive) {
                Ok(()) => watched.push(path),
                Err(error) => polled.push((path, NotLiveReason::SystemLimit(error.to_string()))),
            }
        }
        *live = watched;
        if live.is_empty() {
            return (None, None);
        }
        (Some(watcher), Some(receiver))
    }

    /// How each folder is covered, in the order given. The polled ones carry the reason the
    /// app states once.
    pub fn coverage(&self) -> &[FolderCoverage] {
        &self.coverage
    }

    pub fn is_watched_live(&self, path: &Path) -> bool {
        self.coverage
            .iter()
            .any(|folder| folder.path == path && folder.coverage == Coverage::Live)
    }

    /// Stops watching and joins the threads. Dropping the watcher does the same.
    pub fn stop(mut self) {
        self.shut_down();
    }

    fn shut_down(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        self.native.take();
        for sender in self.stop_senders.drain(..) {
            let _ = sender.send(());
        }
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

impl Drop for FolderWatcher {
    fn drop(&mut self) {
        self.shut_down();
    }
}

/// Every directory under `root`, nearest first, counted up to `limit`: the number seen
/// (at least the number past the limit, when there is one) and whether the limit bit.
/// Breadth-first on purpose: when the limit bites, the folders it keeps are the ones a
/// reader drops a file into. Hidden directories are skipped as the walk skips them.
pub fn directories_under(root: &Path, limit: usize) -> (usize, bool) {
    let mut queue = vec![root.to_path_buf()];
    let mut found = 0;
    while let Some(directory) = (found < limit).then(|| queue.pop()).flatten() {
        found += 1;
        let Ok(entries) = std::fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let hidden = path
                .file_name()
                .is_some_and(|name| name.to_string_lossy().starts_with('.'));
            if hidden {
                continue;
            }
            if std::fs::symlink_metadata(&path).is_ok_and(|m| m.is_dir()) {
                queue.push(path);
            }
        }
    }
    (found + queue.len(), !queue.is_empty())
}

/// Turns a burst of native events into one notice per root once the burst settles.
fn coalescing_loop(
    events: &mpsc::Receiver<notify::Result<notify::Event>>,
    roots: &[PathBuf],
    coalesce: Duration,
    stop: &AtomicBool,
    notify: &OnChange,
) {
    // FSEvents and inotify report paths as the kernel spells them, which on macOS means
    // `/private/var/…` for a root the reader chose as `/var/…`; matching on the resolved
    // form is what lets an event find its root.
    let resolved: Vec<(PathBuf, PathBuf)> = roots
        .iter()
        .map(|root| {
            (
                root.clone(),
                std::fs::canonicalize(root).unwrap_or_else(|_| root.clone()),
            )
        })
        .collect();
    let mut pending: HashMap<PathBuf, Instant> = HashMap::new();
    while !stop.load(Ordering::SeqCst) {
        let wait = pending
            .values()
            .map(|due| due.saturating_duration_since(Instant::now()))
            .min()
            .unwrap_or(Duration::from_millis(500));
        match events.recv_timeout(wait) {
            Ok(Ok(event)) => {
                let due = Instant::now() + coalesce;
                let mut matched = false;
                for path in &event.paths {
                    for (root, canonical) in &resolved {
                        if path.starts_with(root) || path.starts_with(canonical) {
                            pending.insert(root.clone(), due);
                            matched = true;
                        }
                    }
                }
                // An event that names no root — a rename out of the tree, a rescan request
                // from the watcher — is attributed to every root rather than lost.
                if !matched {
                    for (root, _) in &resolved {
                        pending.insert(root.clone(), due);
                    }
                }
            }
            Ok(Err(_)) => {
                for (root, _) in &resolved {
                    pending.insert(root.clone(), Instant::now() + coalesce);
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
        let now = Instant::now();
        let settled: Vec<PathBuf> = pending
            .iter()
            .filter(|(_, due)| **due <= now)
            .map(|(root, _)| root.clone())
            .collect();
        for root in settled {
            pending.remove(&root);
            notify(&root);
        }
    }
}

/// Lists the folder every `interval` and reports when the listing moved.
fn polling_loop(
    scan: &FolderScan,
    root: &Path,
    mut snapshot: FolderSnapshot,
    interval: Duration,
    stop: &mpsc::Receiver<()>,
    notify: &OnChange,
) {
    loop {
        match stop.recv_timeout(interval) {
            Ok(()) | Err(RecvTimeoutError::Disconnected) => return,
            Err(RecvTimeoutError::Timeout) => {}
        }
        let walked = scan.entries();
        if let Some(change) = snapshot.change(&walked)
            && !change.is_empty()
        {
            snapshot = snapshot.updated(walked);
            notify(root);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directories_are_counted_breadth_first_up_to_the_limit() {
        let dir = tempfile::tempdir().unwrap();
        let mut deep = dir.path().to_path_buf();
        for level in 1..5 {
            deep = deep.join(format!("level-{level}"));
            std::fs::create_dir(&deep).unwrap();
        }
        std::fs::create_dir(dir.path().join(".hidden")).unwrap();
        assert_eq!(directories_under(dir.path(), 96), (5, false));
        assert_eq!(directories_under(dir.path(), 3), (4, true));
        assert_eq!(directories_under(dir.path(), 0), (1, true));
    }

    #[test]
    fn a_reason_names_itself_as_not_watched_live() {
        assert!(
            NotLiveReason::PortalGranted
                .to_string()
                .starts_with("not watched live")
        );
        assert!(
            NotLiveReason::SystemLimit("inotify".into())
                .to_string()
                .contains("inotify")
        );
    }
}
