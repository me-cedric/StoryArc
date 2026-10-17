//! Full screen as a request the compositor may refuse (task 2.29).
//!
//! GTK asks for full screen and the compositor answers by changing the window's state,
//! or not: some tiling layouts never grant it. This module decides, from what the window
//! reports and how long ago it was asked, whether the window is full, asking, or refused.
//! A refused window stays as it is and reads normally; the menu entry says in grey that
//! full screen is not available (`desktop-experience`, A system that refuses). Pure.

use std::time::{Duration, Instant};

/// How long the compositor has to answer before the request counts as refused.
pub const ANSWER_WITHIN: Duration = Duration::from_millis(1500);

/// The English note beside the menu entry when full screen is refused.
pub const REFUSED_NOTE: &str = "Full screen is not available";

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FullScreen {
    #[default]
    Windowed,
    /// Asked at this instant, no answer yet.
    Asking(Instant),
    Full,
    /// The compositor did not grant it. The entry stays grey until a later grant
    /// (the user's own compositor shortcut) clears it.
    Refused,
}

impl FullScreen {
    /// The key or the menu entry was used. In full screen it leaves; a refused window
    /// ignores the request, so a refusal never turns into a loop of asks.
    pub fn toggle(self, now: Instant) -> Self {
        match self {
            Self::Windowed => Self::Asking(now),
            Self::Asking(_) | Self::Full => Self::Windowed,
            Self::Refused => Self::Refused,
        }
    }

    /// What the window reports now: whether it is full screen. Called on every state
    /// change and from a timer while a request is open.
    pub fn observed(self, is_full: bool, now: Instant) -> Self {
        match (self, is_full) {
            (_, true) => Self::Full,
            (Self::Asking(at), false) if now.duration_since(at) >= ANSWER_WITHIN => Self::Refused,
            (Self::Full, false) => Self::Windowed,
            (state, false) => state,
        }
    }

    /// Whether the menu entry and the key act.
    pub fn is_available(self) -> bool {
        self != Self::Refused
    }

    /// Escape leaves full screen, and does nothing otherwise.
    pub fn leaves_on_escape(self) -> bool {
        matches!(self, Self::Full | Self::Asking(_))
    }

    pub fn note(self) -> Option<&'static str> {
        (self == Self::Refused).then_some(REFUSED_NOTE)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn later(ms: u64, from: Instant) -> Instant {
        from + Duration::from_millis(ms)
    }

    #[test]
    fn a_granted_request_becomes_full_screen_and_leaves_with_the_same_key() {
        let start = Instant::now();
        let state = FullScreen::Windowed.toggle(start);
        assert!(matches!(state, FullScreen::Asking(_)));
        let state = state.observed(true, later(100, start));
        assert_eq!(state, FullScreen::Full);
        assert!(state.leaves_on_escape());
        assert_eq!(state.toggle(later(200, start)), FullScreen::Windowed);
    }

    #[test]
    fn escape_does_nothing_in_a_window() {
        assert!(!FullScreen::Windowed.leaves_on_escape());
    }

    #[test]
    fn no_answer_in_time_means_refused_and_the_entry_says_so() {
        let start = Instant::now();
        let state = FullScreen::Windowed.toggle(start);
        assert_eq!(
            state.observed(false, later(500, start)),
            state,
            "still waiting"
        );
        let refused = state.observed(false, later(2000, start));
        assert_eq!(refused, FullScreen::Refused);
        assert!(!refused.is_available());
        assert_eq!(refused.note(), Some("Full screen is not available"));
        assert_eq!(refused.toggle(later(3000, start)), FullScreen::Refused);
    }

    #[test]
    fn a_late_grant_still_wins_over_a_refusal() {
        let start = Instant::now();
        let refused = FullScreen::Windowed
            .toggle(start)
            .observed(false, later(2000, start));
        assert_eq!(refused.observed(true, later(2500, start)), FullScreen::Full);
    }

    #[test]
    fn the_compositor_leaving_full_screen_returns_to_a_window() {
        let start = Instant::now();
        assert_eq!(
            FullScreen::Full.observed(false, start),
            FullScreen::Windowed
        );
    }
}
