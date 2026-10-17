//! The two time rules of `network-share`, *Disconnect and reconnect*, as plain arithmetic.
//!
//! - *Connection drops while reading*: an inline, dismissible indicator appears **only** if a
//!   page is actually blocked on the network for more than 2 seconds.
//! - *Reconnection fails repeatedly*: when reconnection has failed for longer than 60 seconds
//!   while the reader is open, the app offers to download the publication and to return to
//!   the library.
//!
//! The source records when a read started and when reads began failing; the reader window
//! asks [`ReadHealth::at`] on its own clock. Instants are passed in, so the tests drive time.

use std::sync::Mutex;
use std::time::{Duration, Instant};

/// How long a read may wait before the reader shows the indicator.
pub const BLOCKED_INDICATOR_AFTER: Duration = Duration::from_secs(2);
/// How long reconnection may keep failing before the reader offers the way out.
pub const OFFER_OFFLINE_AFTER: Duration = Duration::from_secs(60);

/// What the reader window shows now.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ReadStatus {
    /// A read has waited on the network for more than two seconds.
    pub shows_indicator: bool,
    /// Reads have failed, without one success between, for more than sixty seconds.
    pub offers_download: bool,
}

#[derive(Debug, Default)]
struct State {
    /// When the read in flight began, if one is.
    in_flight_since: Option<Instant>,
    /// When the first failure of the current run of failures happened.
    failing_since: Option<Instant>,
}

/// The record a source keeps of its reads. Shared between the reading thread and the window.
#[derive(Debug, Default)]
pub struct ReadHealth {
    state: Mutex<State>,
}

impl ReadHealth {
    pub fn new() -> Self {
        Self::default()
    }

    /// A read starts at `now`.
    pub fn began(&self, now: Instant) {
        self.with(|state| state.in_flight_since = Some(now));
    }

    /// The read in flight ended at `now`, well or not. A success ends the run of failures; a
    /// failure starts one, or continues it.
    pub fn ended(&self, now: Instant, succeeded: bool) {
        self.with(|state| {
            state.in_flight_since = None;
            if succeeded {
                state.failing_since = None;
            } else if state.failing_since.is_none() {
                state.failing_since = Some(now);
            }
        });
    }

    /// What to show at `now`.
    pub fn at(&self, now: Instant) -> ReadStatus {
        self.with(|state| ReadStatus {
            shows_indicator: state.in_flight_since.is_some_and(|since| {
                now.saturating_duration_since(since) > BLOCKED_INDICATOR_AFTER
            }),
            offers_download: state
                .failing_since
                .is_some_and(|since| now.saturating_duration_since(since) > OFFER_OFFLINE_AFTER),
        })
    }

    fn with<T>(&self, body: impl FnOnce(&mut State) -> T) -> T {
        // A poisoned lock means a panic mid-update of two `Option<Instant>`s; the values are
        // still meaningful, so the record is read rather than lost.
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        body(&mut state)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secs(n: u64) -> Duration {
        Duration::from_secs(n)
    }

    #[test]
    fn a_read_shorter_than_two_seconds_never_shows_the_indicator() {
        let start = Instant::now();
        let health = ReadHealth::new();
        health.began(start);
        assert!(
            !health.at(start + secs(2)).shows_indicator,
            "exactly two is not more"
        );
        health.ended(start + Duration::from_millis(2_500), true);
        assert_eq!(health.at(start + secs(10)), ReadStatus::default());
    }

    #[test]
    fn a_read_blocked_past_two_seconds_shows_it_until_it_returns() {
        let start = Instant::now();
        let health = ReadHealth::new();
        health.began(start);
        assert!(
            health
                .at(start + Duration::from_millis(2_001))
                .shows_indicator
        );
        health.ended(start + secs(3), true);
        assert!(!health.at(start + secs(3)).shows_indicator);
    }

    #[test]
    fn failures_for_sixty_seconds_offer_the_download_and_a_success_withdraws_it() {
        let start = Instant::now();
        let health = ReadHealth::new();
        health.began(start);
        health.ended(start + secs(10), false);
        health.began(start + secs(20));
        health.ended(start + secs(40), false);
        assert!(
            !health.at(start + secs(70)).offers_download,
            "sixty from the first failure"
        );
        assert!(health.at(start + secs(71)).offers_download);
        health.began(start + secs(80));
        health.ended(start + secs(81), true);
        assert!(!health.at(start + secs(200)).offers_download);
    }

    #[test]
    fn a_success_between_failures_restarts_the_sixty_seconds() {
        let start = Instant::now();
        let health = ReadHealth::new();
        health.ended(start, false);
        health.ended(start + secs(50), true);
        health.ended(start + secs(55), false);
        assert!(!health.at(start + secs(100)).offers_download);
        assert!(health.at(start + secs(116)).offers_download);
    }
}
