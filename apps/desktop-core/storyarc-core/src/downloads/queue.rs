//! The download queue as a value (`offline-downloads`, *Queue management*), mirrored from
//! StoryArcKit's `DownloadLibrary`: every change is a pure operation that returns a new
//! queue, the order is the reader's, and the rules the phones keep are kept here by name.
//!
//! The app holds one, drives transfers from [`DownloadQueue::startable`], and saves it after
//! each change. A queue loaded after a quit, a crash or a kill puts every `Running` row back
//! to `Queued`: nothing carries it any more, and its partial file is where it resumes from.

use std::path::Path;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use super::LandingError;
use super::policy::{Admission, DownloadPolicy, NetworkState};
use super::transfer::{Resumption, TransferError};

/// Why the queue paused a row. Each has its own remedy, so each is named.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Pause {
    /// The reader paused it. Nothing resumes it but the reader.
    ByReader,
    /// "Wi-Fi only" on a metered connection: resumes when an unmetered one returns.
    WaitingForUnmetered,
    /// No connection: resumes when one returns.
    WaitingForNetwork,
    /// The reader's storage limit or the disk: resumes when room is made.
    OutOfSpace,
}

impl Pause {
    /// Whether the queue itself lifts this hold when its cause goes away.
    pub fn lifts_by_itself(self) -> bool {
        !matches!(self, Self::ByReader)
    }
}

/// Why a row failed: a case, never a sentence, so the app words it in the reader's language
/// on the day it is drawn (`localization`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "detail")]
pub enum FailureReason {
    /// The connection failed or the transfer stopped short.
    Network,
    /// The server answered with a status that is not the publication.
    Server(u16),
    /// The disk refused a write.
    Disk,
    /// The bytes arrived and are not a publication.
    Unreadable,
    /// The bytes are a container the app does not read, named.
    Unsupported(String),
}

impl FailureReason {
    pub fn of(error: &TransferError) -> Self {
        match error {
            TransferError::Network(_) | TransferError::Short { .. } | TransferError::Cancelled => {
                Self::Network
            }
            TransferError::Http(status) => Self::Server(*status),
            TransferError::Disk(_) => Self::Disk,
        }
    }
}

impl From<&LandingError> for FailureReason {
    fn from(error: &LandingError) -> Self {
        match error {
            LandingError::Transfer(error) => Self::of(error),
            LandingError::Unreadable => Self::Unreadable,
            LandingError::Unsupported(format) => Self::Unsupported(format.clone()),
            LandingError::Disk(_) => Self::Disk,
        }
    }
}

/// Where a row stands.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "state")]
pub enum DownloadState {
    Queued,
    Running,
    Paused(Pause),
    Failed {
        reason: FailureReason,
        attempts: u32,
    },
    Finished,
}

impl DownloadState {
    pub fn is_finished(&self) -> bool {
        *self == Self::Finished
    }
}

/// One publication the reader asked to keep.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Download {
    /// The publication's id in the library: one row per publication.
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_id: Option<String>,
    pub title: String,
    /// Where the bytes come from. Never carries a credential: the source signs the request.
    pub remote: String,
    pub state: DownloadState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_bytes: Option<u64>,
    #[serde(default)]
    pub downloaded_bytes: u64,
    /// Unix milliseconds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<i64>,
    #[serde(default)]
    pub verification_failures: u32,
    /// How the last attempt began, which the row states.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_attempt: Option<Resumption>,
    /// Asked for by hand, which overrides "Wi-Fi only" once (*Overriding once*).
    #[serde(default)]
    pub started_by_hand: bool,
}

impl Download {
    pub fn new(id: impl Into<String>, title: impl Into<String>, remote: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            source_id: None,
            title: title.into(),
            remote: remote.into(),
            state: DownloadState::Queued,
            expected_bytes: None,
            downloaded_bytes: 0,
            completed_at: None,
            verification_failures: 0,
            last_attempt: None,
            started_by_hand: false,
        }
    }

    pub fn by_hand(mut self) -> Self {
        self.started_by_hand = true;
        self
    }

    /// How far along, when the server stated a total.
    pub fn fraction(&self) -> Option<f64> {
        let expected = self.expected_bytes.filter(|e| *e > 0)?;
        Some((self.downloaded_bytes as f64 / expected as f64).min(1.0))
    }
}

/// Why a saved queue could not be read or written.
#[derive(Debug)]
pub enum QueueFileError {
    Io(std::io::Error),
    Format(serde_json::Error),
}

impl std::fmt::Display for QueueFileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(f, "the download queue could not be saved or read: {error}"),
            Self::Format(error) => write!(f, "the saved download queue is damaged: {error}"),
        }
    }
}

impl std::error::Error for QueueFileError {}

/// Every download, in the reader's order.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DownloadQueue {
    downloads: Vec<Download>,
}

impl DownloadQueue {
    /// Three, from `offline-downloads`: "retried automatically up to three times".
    pub const ATTEMPT_LIMIT: u32 = 3;
    /// One, from "a failed verification re-queues it once".
    pub const VERIFICATION_LIMIT: u32 = 1;

    pub fn downloads(&self) -> &[Download] {
        &self.downloads
    }

    pub fn get(&self, id: &str) -> Option<&Download> {
        self.downloads.iter().find(|d| d.id == id)
    }

    /// Those still to do, in the order they will be done.
    pub fn pending(&self) -> impl Iterator<Item = &Download> {
        self.downloads.iter().filter(|d| !d.state.is_finished())
    }

    pub fn finished(&self) -> impl Iterator<Item = &Download> {
        self.downloads.iter().filter(|d| d.state.is_finished())
    }

    /// What the finished downloads weigh.
    pub fn bytes_on_disk(&self) -> u64 {
        self.finished().map(|d| d.downloaded_bytes).sum()
    }

    fn map(&self, id: &str, change: impl Fn(&mut Download)) -> Self {
        Self {
            downloads: self
                .downloads
                .iter()
                .map(|each| {
                    let mut each = each.clone();
                    if each.id == id {
                        change(&mut each);
                    }
                    each
                })
                .collect(),
        }
    }

    /// Queues a download, or does nothing when the publication is already known: "the app
    /// does not re-fetch it".
    pub fn queueing(&self, download: Download) -> Self {
        if self.get(&download.id).is_some() {
            return self.clone();
        }
        let mut downloads = self.downloads.clone();
        downloads.push(download);
        Self { downloads }
    }

    pub fn marking(&self, id: &str, state: DownloadState) -> Self {
        self.map(id, |d| d.state = state.clone())
    }

    pub fn advancing(&self, id: &str, downloaded: u64, expected: Option<u64>) -> Self {
        self.map(id, |d| {
            d.downloaded_bytes = downloaded;
            if expected.is_some() {
                d.expected_bytes = expected;
            }
        })
    }

    pub fn recording_attempt(&self, id: &str, how: Resumption) -> Self {
        self.map(id, |d| d.last_attempt = Some(how))
    }

    /// Moves a row. `to` is an index in the list *before* the move, as a drag reports it.
    pub fn moving(&self, id: &str, to: usize) -> Self {
        let Some(from) = self.downloads.iter().position(|d| d.id == id) else {
            return self.clone();
        };
        let mut downloads = self.downloads.clone();
        let row = downloads.remove(from);
        let to = if to > from { to - 1 } else { to };
        downloads.insert(to.min(downloads.len()), row);
        Self { downloads }
    }

    /// The reader's pause. A finished row has nothing to pause.
    pub fn pausing(&self, id: &str) -> Self {
        self.map(id, |d| {
            if !d.state.is_finished() {
                d.state = DownloadState::Paused(Pause::ByReader);
            }
        })
    }

    /// The reader's resume, or retry: a paused or failed row goes back in the queue with its
    /// attempts spent forgotten.
    pub fn resuming(&self, id: &str) -> Self {
        self.map(id, |d| {
            if matches!(
                d.state,
                DownloadState::Paused(_) | DownloadState::Failed { .. }
            ) {
                d.state = DownloadState::Queued;
                d.verification_failures = 0;
            }
        })
    }

    /// Pauses or resumes every row that is not finished: the global controls.
    pub fn pausing_all(&self) -> Self {
        let ids: Vec<String> = self.pending().map(|d| d.id.clone()).collect();
        ids.iter().fold(self.clone(), |q, id| q.pausing(id))
    }

    pub fn resuming_all(&self) -> Self {
        let ids: Vec<String> = self.pending().map(|d| d.id.clone()).collect();
        ids.iter().fold(self.clone(), |q, id| q.resuming(id))
    }

    /// Cancel or remove: the row goes. The caller discards the partial or the file.
    pub fn removing(&self, id: &str) -> Self {
        Self {
            downloads: self
                .downloads
                .iter()
                .filter(|d| d.id != id)
                .cloned()
                .collect(),
        }
    }

    /// Records a failed attempt. A failure no retry can mend spends every attempt at once.
    pub fn failing(&self, id: &str, reason: FailureReason, retryable: bool) -> Self {
        self.map(id, |d| {
            let before = match d.state {
                DownloadState::Failed { attempts, .. } => attempts,
                _ => 0,
            };
            let attempts = if retryable {
                before + 1
            } else {
                Self::ATTEMPT_LIMIT
            };
            d.state = DownloadState::Failed {
                reason: reason.clone(),
                attempts,
            };
        })
    }

    /// Records bytes that did not verify: back in the queue once, then failed for good.
    pub fn failing_verification(&self, id: &str, reason: FailureReason) -> Self {
        self.map(id, |d| {
            d.verification_failures += 1;
            d.downloaded_bytes = 0;
            d.state = if d.verification_failures <= Self::VERIFICATION_LIMIT {
                DownloadState::Queued
            } else {
                DownloadState::Failed {
                    reason: reason.clone(),
                    attempts: Self::ATTEMPT_LIMIT,
                }
            };
        })
    }

    pub fn finishing(&self, id: &str, bytes: u64, at_millis: i64) -> Self {
        self.map(id, |d| {
            d.state = DownloadState::Finished;
            d.downloaded_bytes = bytes;
            d.expected_bytes = Some(bytes);
            d.completed_at = Some(at_millis);
        })
    }

    /// Whether a failed row has an automatic attempt left.
    pub fn should_retry(download: &Download) -> bool {
        matches!(download.state, DownloadState::Failed { attempts, .. } if attempts < Self::ATTEMPT_LIMIT)
    }

    /// The wait before the next automatic attempt: doubling from two seconds.
    pub fn backoff(attempts: u32) -> Duration {
        Duration::from_secs(2u64 << attempts.saturating_sub(1).min(16))
    }

    /// Applies the network and the policy to every row the queue may hold or release: the
    /// ones the policy holds back are paused with the reason the queue says in grey, running
    /// ones included (*A network that changes mid-download*), and held ones whose cause has
    /// gone go back in the queue. A reader's pause is never touched. The caller stops the
    /// transfers of rows this paused; their partial files keep what arrived.
    pub fn holding(&self, network: NetworkState, policy: &DownloadPolicy, used: u64) -> Self {
        Self {
            downloads: self
                .downloads
                .iter()
                .map(|d| {
                    let mut d = d.clone();
                    let eligible = match &d.state {
                        DownloadState::Queued | DownloadState::Running => true,
                        DownloadState::Paused(pause) => pause.lifts_by_itself(),
                        _ => false,
                    };
                    if !eligible {
                        return d;
                    }
                    let left = d
                        .expected_bytes
                        .map(|e| e.saturating_sub(d.downloaded_bytes));
                    d.state = match policy.admit(network, d.started_by_hand, used, left) {
                        Admission::Run => match d.state {
                            DownloadState::Running => DownloadState::Running,
                            _ => DownloadState::Queued,
                        },
                        Admission::WaitForUnmetered => {
                            DownloadState::Paused(Pause::WaitingForUnmetered)
                        }
                        Admission::WaitForNetwork => {
                            DownloadState::Paused(Pause::WaitingForNetwork)
                        }
                        Admission::StorageLimitReached => DownloadState::Paused(Pause::OutOfSpace),
                    };
                    d
                })
                .collect(),
        }
    }

    /// The rows to start now, in queue order, within the bound for `network`.
    pub fn startable(&self, network: NetworkState, policy: &DownloadPolicy) -> Vec<String> {
        let running = self
            .downloads
            .iter()
            .filter(|d| d.state == DownloadState::Running)
            .count();
        let room = policy.concurrency(network).saturating_sub(running);
        self.downloads
            .iter()
            .filter(|d| d.state == DownloadState::Queued)
            .take(room)
            .map(|d| d.id.clone())
            .collect()
    }

    /// Every running row back in the queue: after a launch, nothing carries them.
    pub fn reclaiming(&self) -> Self {
        Self {
            downloads: self
                .downloads
                .iter()
                .map(|d| {
                    let mut d = d.clone();
                    if d.state == DownloadState::Running {
                        d.state = DownloadState::Queued;
                    }
                    d
                })
                .collect(),
        }
    }

    /// Writes the queue beside itself and renames it into place, so a kill mid-write leaves
    /// the previous queue rather than half of this one.
    pub fn save(&self, path: &Path) -> Result<(), QueueFileError> {
        let bytes = serde_json::to_vec_pretty(self).map_err(QueueFileError::Format)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(QueueFileError::Io)?;
        }
        let mut staging = path.as_os_str().to_owned();
        staging.push(".saving");
        std::fs::write(&staging, bytes).map_err(QueueFileError::Io)?;
        std::fs::rename(&staging, path).map_err(QueueFileError::Io)
    }

    /// Reads a saved queue, reclaimed. No file is an empty queue.
    pub fn load(path: &Path) -> Result<Self, QueueFileError> {
        match std::fs::read(path) {
            Ok(bytes) => serde_json::from_slice::<Self>(&bytes)
                .map(|q| q.reclaiming())
                .map_err(QueueFileError::Format),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(error) => Err(QueueFileError::Io(error)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn three() -> DownloadQueue {
        DownloadQueue::default()
            .queueing(Download::new("a", "A", "http://x/a"))
            .queueing(Download::new("b", "B", "http://x/b"))
            .queueing(Download::new("c", "C", "http://x/c"))
    }

    fn ids(q: &DownloadQueue) -> Vec<&str> {
        q.downloads().iter().map(|d| d.id.as_str()).collect()
    }

    #[test]
    fn a_known_publication_is_not_queued_twice() {
        let q = three().queueing(Download::new("a", "Again", "http://x/again"));
        assert_eq!(ids(&q), ["a", "b", "c"]);
        assert_eq!(q.get("a").unwrap().title, "A");
    }

    #[test]
    fn a_move_takes_the_index_before_the_move_as_a_drag_reports_it() {
        assert_eq!(ids(&three().moving("a", 2)), ["b", "a", "c"]);
        assert_eq!(ids(&three().moving("a", 3)), ["b", "c", "a"]);
        assert_eq!(ids(&three().moving("c", 0)), ["c", "a", "b"]);
    }

    #[test]
    fn three_attempts_with_doubling_backoff_then_failed_with_a_retry_that_resets() {
        let mut q = three();
        for attempt in 1..=3 {
            q = q.failing("a", FailureReason::Network, true);
            let row = q.get("a").unwrap();
            assert_eq!(DownloadQueue::should_retry(row), attempt < 3);
        }
        assert_eq!(DownloadQueue::backoff(1), Duration::from_secs(2));
        assert_eq!(DownloadQueue::backoff(2), Duration::from_secs(4));
        assert_eq!(DownloadQueue::backoff(3), Duration::from_secs(8));
        let q = q.resuming("a");
        assert_eq!(q.get("a").unwrap().state, DownloadState::Queued);
        let q = q.failing("a", FailureReason::Server(404), false);
        assert!(!DownloadQueue::should_retry(q.get("a").unwrap()));
    }

    #[test]
    fn a_failed_verification_requeues_once_then_fails() {
        let q = three().failing_verification("a", FailureReason::Unreadable);
        assert_eq!(q.get("a").unwrap().state, DownloadState::Queued);
        let q = q.failing_verification("a", FailureReason::Unreadable);
        assert_eq!(
            q.get("a").unwrap().state,
            DownloadState::Failed {
                reason: FailureReason::Unreadable,
                attempts: DownloadQueue::ATTEMPT_LIMIT
            }
        );
    }

    #[test]
    fn a_metered_network_pauses_what_the_policy_holds_back_mid_download_and_releases_it_after() {
        let policy = DownloadPolicy::default();
        let q = DownloadQueue::default()
            .queueing(Download::new("a", "A", "x"))
            .queueing(Download::new("b", "B", "x").by_hand())
            .queueing(Download::new("c", "C", "x"))
            .marking("a", DownloadState::Running)
            .pausing("c");
        let held = q.holding(NetworkState::Metered, &policy, 0);
        assert_eq!(
            held.get("a").unwrap().state,
            DownloadState::Paused(Pause::WaitingForUnmetered)
        );
        assert_eq!(held.get("b").unwrap().state, DownloadState::Queued);
        assert_eq!(
            held.get("c").unwrap().state,
            DownloadState::Paused(Pause::ByReader)
        );
        assert_eq!(held.startable(NetworkState::Metered, &policy), ["b"]);

        let back = held.holding(NetworkState::Unmetered, &policy, 0);
        assert_eq!(back.get("a").unwrap().state, DownloadState::Queued);
        assert_eq!(
            back.get("c").unwrap().state,
            DownloadState::Paused(Pause::ByReader)
        );
        assert_eq!(back.startable(NetworkState::Unmetered, &policy), ["a", "b"]);
    }

    #[test]
    fn offline_holds_everything_in_grey_and_the_bound_counts_what_runs() {
        let policy = DownloadPolicy::default();
        let q = three().holding(NetworkState::Offline, &policy, 0);
        assert!(
            q.downloads()
                .iter()
                .all(|d| d.state == DownloadState::Paused(Pause::WaitingForNetwork))
        );
        let q = three().marking("a", DownloadState::Running);
        let policy = DownloadPolicy {
            concurrency: 2,
            ..policy
        };
        assert_eq!(q.startable(NetworkState::Unmetered, &policy), ["b"]);
    }

    #[test]
    fn the_storage_limit_pauses_with_its_own_reason() {
        let policy = DownloadPolicy {
            storage_limit: Some(1_000),
            ..DownloadPolicy::default()
        };
        let q = three().advancing("a", 0, Some(500));
        let held = q.holding(NetworkState::Unmetered, &policy, 800);
        assert_eq!(
            held.get("a").unwrap().state,
            DownloadState::Paused(Pause::OutOfSpace)
        );
        assert_eq!(held.get("b").unwrap().state, DownloadState::Queued);
    }

    #[test]
    fn global_pause_leaves_finished_rows_and_finished_rows_weigh_their_bytes() {
        let q = three().finishing("a", 1234, 1).pausing_all();
        assert!(q.get("a").unwrap().state.is_finished());
        assert_eq!(
            q.get("b").unwrap().state,
            DownloadState::Paused(Pause::ByReader)
        );
        assert_eq!(q.bytes_on_disk(), 1234);
        assert_eq!(
            q.resuming_all().get("c").unwrap().state,
            DownloadState::Queued
        );
    }
}
