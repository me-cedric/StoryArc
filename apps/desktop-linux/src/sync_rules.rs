//! When the library syncs and how long the app waits for it (task 3.19; `desktop-experience`,
//! *Sync when the app runs*). Start and quit are what the phones call foreground and
//! background: at start the sync document merges on a worker and the window never waits
//! for it; at quit the document is written once more, only if a position changed, within
//! five seconds, and the app quits whatever the result.

use std::sync::mpsc;
use std::time::Duration;

/// The most the quit waits for the sync location.
pub const QUIT_BUDGET: Duration = Duration::from_secs(5);

/// Runs `work` on a thread of its own and waits at most `limit` for the answer. `None`
/// when it did not finish in time: the thread is left to end by itself and its answer is
/// dropped, so a slow share or a sleeping drive holds nothing up.
pub fn within<T: Send + 'static>(
    limit: Duration,
    work: impl FnOnce() -> T + Send + 'static,
) -> Option<T> {
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = sender.send(work());
    });
    receiver.recv_timeout(limit).ok()
}

/// Whether quit writes the document: only when a reading position changed since the last
/// time it was written, and only where a place is configured.
pub fn writes_at_quit(position_changed: bool, place_configured: bool) -> bool {
    position_changed && place_configured
}

/// How a sync ended, for the Sync row's grey line. Never red.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SyncResult {
    Synced,
    /// The place cannot be reached: read normally, sync when it returns.
    Unreachable,
    /// Not finished in the time given.
    TimedOut,
}

pub fn quit_result(answer: Option<bool>) -> SyncResult {
    match answer {
        Some(true) => SyncResult::Synced,
        Some(false) => SyncResult::Unreachable,
        None => SyncResult::TimedOut,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    #[test]
    fn a_slow_sync_location_never_holds_the_quit_past_its_budget() {
        let begun = Instant::now();
        let answer = within(Duration::from_millis(100), || {
            std::thread::sleep(Duration::from_secs(5));
            true
        });
        assert_eq!(answer, None);
        assert!(begun.elapsed() < Duration::from_secs(2));
        assert_eq!(quit_result(answer), SyncResult::TimedOut);
    }

    #[test]
    fn a_quick_sync_answers_and_an_unreachable_place_is_grey_not_an_error() {
        assert_eq!(within(Duration::from_secs(2), || true), Some(true));
        assert_eq!(quit_result(Some(true)), SyncResult::Synced);
        assert_eq!(quit_result(Some(false)), SyncResult::Unreachable);
    }

    #[test]
    fn quit_writes_the_document_only_when_a_position_changed_and_a_place_exists() {
        assert!(writes_at_quit(true, true));
        assert!(!writes_at_quit(false, true));
        assert!(!writes_at_quit(true, false));
    }

    #[test]
    fn the_budget_is_five_seconds() {
        assert_eq!(QUIT_BUDGET, Duration::from_secs(5));
    }
}
