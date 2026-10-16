//! Keeping the display awake while a reader is in front (task 2.34).
//!
//! The application's own inhibit call asks the session, through the portal under
//! Flatpak, not to dim or blank the screen. A refusal is silent: the call returns a
//! zero cookie, the window reads as before and nothing is shown. Pure over the two
//! calls, so the refusal tests on any host.

/// The inhibit cookie a window holds, if the session granted one.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct IdleHold {
    cookie: Option<u32>,
}

impl IdleHold {
    /// Holds the display awake. `inhibit` is the application's call; zero is a refusal.
    /// Holding twice keeps the first cookie, so a window never stacks inhibits.
    pub fn hold(&mut self, inhibit: impl FnOnce() -> u32) {
        if self.cookie.is_some() {
            return;
        }
        self.cookie = Some(inhibit()).filter(|cookie| *cookie != 0);
    }

    /// Lets the display sleep again, when it was held.
    pub fn release(&mut self, uninhibit: impl FnOnce(u32)) {
        if let Some(cookie) = self.cookie.take() {
            uninhibit(cookie);
        }
    }

    #[cfg(test)]
    pub fn is_held(&self) -> bool {
        self.cookie.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_granted_inhibit_is_held_and_released_once() {
        let mut hold = IdleHold::default();
        hold.hold(|| 7);
        assert!(hold.is_held());
        let mut released = Vec::new();
        hold.release(|cookie| released.push(cookie));
        hold.release(|cookie| released.push(cookie));
        assert_eq!(released, vec![7]);
        assert!(!hold.is_held());
    }

    #[test]
    fn a_refusal_is_silent_and_there_is_nothing_to_release() {
        let mut hold = IdleHold::default();
        hold.hold(|| 0);
        assert!(!hold.is_held());
        hold.release(|_| panic!("nothing was granted"));
    }

    #[test]
    fn holding_twice_asks_once() {
        let mut hold = IdleHold::default();
        let mut asked = 0;
        hold.hold(|| {
            asked += 1;
            3
        });
        hold.hold(|| {
            asked += 1;
            4
        });
        assert_eq!(asked, 1);
        let mut released = None;
        hold.release(|cookie| released = Some(cookie));
        assert_eq!(released, Some(3));
    }
}
