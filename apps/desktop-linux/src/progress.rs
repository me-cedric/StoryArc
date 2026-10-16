//! When the reading position is written: as the reader reads, before a window closes
//! and before the app quits (`desktop-experience`, Closing a window and quitting the app).
//!
//! The cadence is the Linux reading of lane M's task 2.17. A turn is written no later
//! than five seconds after it and never once per frame: the first unsaved turn starts
//! the clock, later turns ride on it, and one write covers them all. A write that
//! fails never holds a window or the app: the position stays in memory for the next
//! attempt, and the failure is kept for the diagnostic.
//!
//! Pure over an injected store, so the failing case tests on any host.

use std::time::{Duration, Instant};

/// A write is due this long after the first unsaved turn.
pub const WRITE_DELAY: Duration = Duration::from_secs(5);

/// Where positions go. Today a file; the core's progress store when lane C lands it.
pub trait ProgressStore {
    fn write(&mut self, publication: &str, page: u32) -> Result<(), String>;
}

/// One reader window's position and when it is written.
#[derive(Debug)]
pub struct ProgressWriter<S> {
    store: S,
    publication: String,
    /// The position not yet written, if any.
    pending: Option<u32>,
    due: Option<Instant>,
    failures: Vec<String>,
}

impl<S: ProgressStore> ProgressWriter<S> {
    pub fn new(store: S, publication: impl Into<String>) -> Self {
        Self {
            store,
            publication: publication.into(),
            pending: None,
            due: None,
            failures: Vec::new(),
        }
    }

    /// A page turned. Starts the clock when nothing is pending; otherwise the turn
    /// joins the write already scheduled, so holding a key never queues writes.
    pub fn turned(&mut self, page: u32, now: Instant) {
        self.pending = Some(page);
        if self.due.is_none() {
            self.due = Some(now + WRITE_DELAY);
        }
    }

    /// When the next write is due, for the caller's timer.
    pub fn due(&self) -> Option<Instant> {
        self.due
    }

    /// The position held in memory and not yet written.
    pub fn pending(&self) -> Option<u32> {
        self.pending
    }

    /// Writes if the clock has run out. Returns whether a write was attempted; a
    /// failure is already recorded in [`failures`](Self::failures), so the timer that
    /// calls this has nothing to handle.
    pub fn tick(&mut self, now: Instant) -> bool {
        match self.due {
            Some(due) if now >= due => {
                let _ = self.flush();
                true
            }
            _ => false,
        }
    }

    /// Writes the pending position now, before a window closes or the app quits.
    /// A failure is recorded and the position kept; the caller carries on regardless.
    pub fn flush(&mut self) -> Result<(), String> {
        self.due = None;
        let Some(page) = self.pending else {
            return Ok(());
        };
        match self.store.write(&self.publication, page) {
            Ok(()) => {
                self.pending = None;
                Ok(())
            }
            Err(reason) => {
                let named = format!(
                    "{}: page {} not written: {reason}",
                    self.publication,
                    page + 1
                );
                self.failures.push(named.clone());
                Err(named)
            }
        }
    }

    /// Every write that failed, for the diagnostic.
    pub fn failures(&self) -> &[String] {
        &self.failures
    }

    pub fn into_store(self) -> S {
        self.store
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct FakeStore {
        written: Vec<(String, u32)>,
        fail: bool,
    }

    impl ProgressStore for FakeStore {
        fn write(&mut self, publication: &str, page: u32) -> Result<(), String> {
            if self.fail {
                return Err("disk full".into());
            }
            self.written.push((publication.to_owned(), page));
            Ok(())
        }
    }

    fn writer() -> ProgressWriter<FakeStore> {
        ProgressWriter::new(FakeStore::default(), "/comics/a.cbz")
    }

    #[test]
    fn a_turn_is_written_no_later_than_five_seconds_after_it() {
        let start = Instant::now();
        let mut writer = writer();
        writer.turned(3, start);
        assert_eq!(writer.due(), Some(start + WRITE_DELAY));
        assert!(!writer.tick(start + Duration::from_secs(4)));
        assert!(writer.into_store().written.is_empty());

        let mut writer = self::writer();
        writer.turned(3, start);
        assert!(writer.tick(start + WRITE_DELAY));
        assert_eq!(writer.pending(), None);
        assert_eq!(
            writer.into_store().written,
            vec![("/comics/a.cbz".to_owned(), 3)]
        );
    }

    #[test]
    fn many_turns_inside_the_window_are_one_write_of_the_last_page() {
        let start = Instant::now();
        let mut writer = writer();
        for page in 0..200 {
            writer.turned(page, start + Duration::from_millis(page as u64 * 16));
        }
        assert_eq!(
            writer.due(),
            Some(start + WRITE_DELAY),
            "later turns do not push the clock"
        );
        writer.tick(start + WRITE_DELAY);
        assert_eq!(
            writer.into_store().written,
            vec![("/comics/a.cbz".to_owned(), 199)]
        );
    }

    #[test]
    fn closing_writes_the_position_before_the_clock_runs_out() {
        let start = Instant::now();
        let mut writer = writer();
        writer.turned(7, start);
        assert_eq!(writer.flush(), Ok(()));
        assert_eq!(writer.due(), None);
        assert_eq!(
            writer.into_store().written,
            vec![("/comics/a.cbz".to_owned(), 7)]
        );
    }

    #[test]
    fn nothing_pending_means_nothing_written() {
        let mut writer = writer();
        assert_eq!(writer.flush(), Ok(()));
        assert!(!writer.tick(Instant::now()));
        assert!(writer.into_store().written.is_empty());
    }

    #[test]
    fn a_write_that_fails_keeps_the_position_and_names_the_failure() {
        let start = Instant::now();
        let mut writer = ProgressWriter::new(
            FakeStore {
                fail: true,
                ..FakeStore::default()
            },
            "/comics/a.cbz",
        );
        writer.turned(11, start);
        let failed = writer.flush();
        assert!(failed.is_err(), "the caller still closes the window");
        assert_eq!(writer.pending(), Some(11), "the position stays in memory");
        assert_eq!(writer.failures().len(), 1);
        assert!(writer.failures()[0].contains("page 12"));
        assert!(writer.failures()[0].contains("disk full"));
    }

    #[test]
    fn the_next_attempt_after_a_failure_writes_the_held_position() {
        let start = Instant::now();
        let mut writer = ProgressWriter::new(
            FakeStore {
                fail: true,
                ..FakeStore::default()
            },
            "/comics/a.cbz",
        );
        writer.turned(11, start);
        assert!(writer.flush().is_err());
        assert!(
            !writer.tick(start + Duration::from_secs(60)),
            "no clock runs after a failed flush"
        );
        writer.turned(12, start + Duration::from_secs(61));
        // The disk has room again.
        let store = writer.into_store();
        let mut writer = ProgressWriter::new(
            FakeStore {
                fail: false,
                written: store.written,
            },
            "/comics/a.cbz",
        );
        writer.turned(12, start + Duration::from_secs(61));
        assert_eq!(writer.flush(), Ok(()));
        assert_eq!(
            writer.into_store().written,
            vec![("/comics/a.cbz".to_owned(), 12)]
        );
    }
}
