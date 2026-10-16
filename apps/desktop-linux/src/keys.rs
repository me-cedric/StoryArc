//! Keys and clicks that turn pages, and the chrome that hides while the pointer rests.
//!
//! The Linux reading of the mapper lane M and lane W share (tasks 2.11 and 2.12). Pure:
//! the reader window translates a `gdk::Key` into [`Key`] and a click's x into a zone,
//! then asks this module what to do. The horizontal keys follow the reading direction;
//! Space, Page Down and Page Up do not (`desktop-experience`, Keys that turn pages).

use std::time::{Duration, Instant};

use storyarc_core::domain::ReadingDirection;

/// How long the pointer rests before the chrome and the pointer hide.
pub const CHROME_IDLE: Duration = Duration::from_secs(3);

/// The keys the reader cares about. Everything else is `Other`, which never turns a page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Left,
    Right,
    Up,
    Down,
    Space,
    PageUp,
    PageDown,
    Home,
    End,
    Escape,
    Other,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Modifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
}

impl Modifiers {
    pub const NONE: Self = Self {
        shift: false,
        control: false,
        alt: false,
    };
    pub const SHIFT: Self = Self {
        shift: true,
        control: false,
        alt: false,
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PageAction {
    Next,
    Previous,
    First,
    Last,
}

/// What a key does in a reader, or `None` when it does nothing to the page.
///
/// A text field in focus keeps every key: a letter or an arrow edits the text. Control
/// and Alt chords are left alone too, since those are application accelerators.
pub fn page_action(
    key: Key,
    modifiers: Modifiers,
    direction: ReadingDirection,
    text_field_focused: bool,
) -> Option<PageAction> {
    if text_field_focused || modifiers.control || modifiers.alt {
        return None;
    }
    let mirrored = direction == ReadingDirection::RightToLeft;
    match key {
        Key::Right if mirrored => Some(PageAction::Previous),
        Key::Right => Some(PageAction::Next),
        Key::Left if mirrored => Some(PageAction::Next),
        Key::Left => Some(PageAction::Previous),
        Key::Space if modifiers.shift => Some(PageAction::Previous),
        Key::Space | Key::PageDown | Key::Down => Some(PageAction::Next),
        Key::PageUp | Key::Up => Some(PageAction::Previous),
        Key::Home => Some(PageAction::First),
        Key::End => Some(PageAction::Last),
        Key::Escape | Key::Other => None,
    }
}

/// Where on the page a click landed, in reading-independent terms.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Zone {
    LeftEdge,
    Middle,
    RightEdge,
}

/// The outer thirds are the edge zones.
pub fn zone(x: f64, width: f64) -> Zone {
    if width <= 0.0 {
        return Zone::Middle;
    }
    let third = width / 3.0;
    if x < third {
        Zone::LeftEdge
    } else if x >= width - third {
        Zone::RightEdge
    } else {
        Zone::Middle
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClickAction {
    Turn(PageAction),
    ToggleChrome,
}

/// What a primary click does. With the zones on (the default), the leading edge goes
/// back, the trailing edge goes forward and the middle toggles the chrome. With the
/// zones off every click toggles the chrome. The edges mirror in right-to-left.
pub fn click_action(zone: Zone, direction: ReadingDirection, zones_on: bool) -> ClickAction {
    if !zones_on {
        return ClickAction::ToggleChrome;
    }
    let mirrored = direction == ReadingDirection::RightToLeft;
    match zone {
        Zone::Middle => ClickAction::ToggleChrome,
        Zone::LeftEdge if mirrored => ClickAction::Turn(PageAction::Next),
        Zone::LeftEdge => ClickAction::Turn(PageAction::Previous),
        Zone::RightEdge if mirrored => ClickAction::Turn(PageAction::Previous),
        Zone::RightEdge => ClickAction::Turn(PageAction::Next),
    }
}

/// The wheel in a paged reader: ticks accumulate so a trackpad does not skip pages.
/// Returns the action once a whole notch has gathered, and keeps the remainder.
#[derive(Debug, Default)]
pub struct WheelAccumulator {
    gathered: f64,
}

impl WheelAccumulator {
    /// One scroll notch, or the fraction of one a trackpad reports.
    pub const NOTCH: f64 = 1.0;

    pub fn scrolled(&mut self, delta_y: f64) -> Option<PageAction> {
        self.gathered += delta_y;
        if self.gathered >= Self::NOTCH {
            self.gathered = 0.0;
            Some(PageAction::Next)
        } else if self.gathered <= -Self::NOTCH {
            self.gathered = 0.0;
            Some(PageAction::Previous)
        } else {
            None
        }
    }
}

/// The reader's place in a publication. Pages are counted from zero inside; the
/// label the reader shows is one-based.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PageModel {
    pub page: u32,
    pub count: u32,
}

impl PageModel {
    pub fn new(page: u32, count: u32) -> Self {
        Self {
            page: page.min(count.saturating_sub(1)),
            count,
        }
    }

    /// The page after `action`, or `None` when the page does not move: the next-page
    /// key on the last page moves nothing and announces nothing.
    pub fn apply(self, action: PageAction) -> Option<Self> {
        let last = self.count.saturating_sub(1);
        let target = match action {
            PageAction::Next => self.page.checked_add(1).filter(|page| *page <= last)?,
            PageAction::Previous => self.page.checked_sub(1)?,
            PageAction::First => 0,
            PageAction::Last => last,
        };
        (target != self.page).then_some(Self {
            page: target,
            ..self
        })
    }

    /// Jump to a one-based page number, clamped to the publication.
    pub fn go_to(self, number: u32) -> Self {
        Self {
            page: number.saturating_sub(1).min(self.count.saturating_sub(1)),
            ..self
        }
    }

    pub fn label_number(self) -> u32 {
        self.page + 1
    }
}

/// The reader chrome while the pointer rests: shown on motion, hidden three seconds
/// later unless something holds it (an open popover, the pointer over the bars).
#[derive(Debug)]
pub struct ChromeIdle {
    visible: bool,
    hide_at: Option<Instant>,
    held: bool,
}

impl Default for ChromeIdle {
    fn default() -> Self {
        Self {
            visible: true,
            hide_at: None,
            held: false,
        }
    }
}

impl ChromeIdle {
    pub fn is_visible(&self) -> bool {
        self.visible
    }

    /// The pointer moved: the chrome shows and the clock restarts.
    pub fn pointer_moved(&mut self, now: Instant) {
        self.visible = true;
        self.hide_at = Some(now + CHROME_IDLE);
    }

    /// A popover opened or the pointer is over the bars: nothing hides until released.
    pub fn hold(&mut self, held: bool) {
        self.held = held;
    }

    /// The reader asked for the chrome by key or click.
    pub fn toggle(&mut self, now: Instant) {
        if self.visible {
            self.visible = false;
            self.hide_at = None;
        } else {
            self.pointer_moved(now);
        }
    }

    /// Whether the chrome should hide now. True once, when the deadline passes.
    pub fn should_hide(&mut self, now: Instant) -> bool {
        match self.hide_at {
            Some(deadline) if now >= deadline && !self.held => {
                self.visible = false;
                self.hide_at = None;
                true
            }
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ReadingDirection::{LeftToRight as LTR, RightToLeft as RTL};

    #[test]
    fn right_arrow_page_down_and_space_show_the_next_page_left_to_right() {
        for key in [Key::Right, Key::PageDown, Key::Space, Key::Down] {
            assert_eq!(
                page_action(key, Modifiers::NONE, LTR, false),
                Some(PageAction::Next)
            );
        }
        for key in [Key::Left, Key::PageUp, Key::Up] {
            assert_eq!(
                page_action(key, Modifiers::NONE, LTR, false),
                Some(PageAction::Previous)
            );
        }
        assert_eq!(
            page_action(Key::Space, Modifiers::SHIFT, LTR, false),
            Some(PageAction::Previous)
        );
    }

    #[test]
    fn the_arrows_mirror_right_to_left_but_space_and_page_down_do_not() {
        assert_eq!(
            page_action(Key::Right, Modifiers::NONE, RTL, false),
            Some(PageAction::Previous)
        );
        assert_eq!(
            page_action(Key::Left, Modifiers::NONE, RTL, false),
            Some(PageAction::Next)
        );
        assert_eq!(
            page_action(Key::Space, Modifiers::NONE, RTL, false),
            Some(PageAction::Next)
        );
        assert_eq!(
            page_action(Key::PageDown, Modifiers::NONE, RTL, false),
            Some(PageAction::Next)
        );
        assert_eq!(
            page_action(Key::PageUp, Modifiers::NONE, RTL, false),
            Some(PageAction::Previous)
        );
    }

    #[test]
    fn home_and_end_jump_to_the_first_and_last_page() {
        assert_eq!(
            page_action(Key::Home, Modifiers::NONE, RTL, false),
            Some(PageAction::First)
        );
        assert_eq!(
            page_action(Key::End, Modifiers::NONE, LTR, false),
            Some(PageAction::Last)
        );
    }

    #[test]
    fn a_text_field_in_focus_keeps_every_key() {
        for key in [Key::Right, Key::Left, Key::Space, Key::Home, Key::PageDown] {
            assert_eq!(page_action(key, Modifiers::NONE, LTR, true), None);
        }
    }

    #[test]
    fn a_chord_with_control_or_alt_is_left_to_the_accelerators() {
        let control = Modifiers {
            control: true,
            ..Modifiers::NONE
        };
        let alt = Modifiers {
            alt: true,
            ..Modifiers::NONE
        };
        assert_eq!(page_action(Key::Right, control, LTR, false), None);
        assert_eq!(page_action(Key::Left, alt, LTR, false), None);
        assert_eq!(page_action(Key::Other, Modifiers::NONE, LTR, false), None);
        assert_eq!(page_action(Key::Escape, Modifiers::NONE, LTR, false), None);
    }

    #[test]
    fn a_key_at_the_end_moves_nothing() {
        let last = PageModel::new(31, 32);
        assert_eq!(last.apply(PageAction::Next), None);
        assert_eq!(last.apply(PageAction::Last), None);
        let first = PageModel::new(0, 32);
        assert_eq!(first.apply(PageAction::Previous), None);
        assert_eq!(first.apply(PageAction::First), None);
        assert_eq!(first.apply(PageAction::Next), Some(PageModel::new(1, 32)));
        assert_eq!(first.apply(PageAction::Last), Some(last));
        assert_eq!(PageModel::new(0, 0).apply(PageAction::Next), None);
    }

    #[test]
    fn go_to_page_is_one_based_and_clamped() {
        let model = PageModel::new(0, 32);
        assert_eq!(model.go_to(12).page, 11);
        assert_eq!(model.go_to(12).label_number(), 12);
        assert_eq!(model.go_to(0).page, 0);
        assert_eq!(model.go_to(500).page, 31);
        assert_eq!(PageModel::new(99, 32).page, 31);
    }

    #[test]
    fn the_click_zones_are_the_outer_thirds_and_follow_the_direction() {
        assert_eq!(zone(10.0, 900.0), Zone::LeftEdge);
        assert_eq!(zone(450.0, 900.0), Zone::Middle);
        assert_eq!(zone(890.0, 900.0), Zone::RightEdge);
        assert_eq!(zone(10.0, 0.0), Zone::Middle);
        assert_eq!(
            click_action(Zone::LeftEdge, LTR, true),
            ClickAction::Turn(PageAction::Previous)
        );
        assert_eq!(
            click_action(Zone::RightEdge, LTR, true),
            ClickAction::Turn(PageAction::Next)
        );
        assert_eq!(
            click_action(Zone::LeftEdge, RTL, true),
            ClickAction::Turn(PageAction::Next)
        );
        assert_eq!(
            click_action(Zone::RightEdge, RTL, true),
            ClickAction::Turn(PageAction::Previous)
        );
        assert_eq!(
            click_action(Zone::Middle, LTR, true),
            ClickAction::ToggleChrome
        );
    }

    #[test]
    fn with_the_zones_off_every_click_toggles_the_chrome() {
        for zone in [Zone::LeftEdge, Zone::Middle, Zone::RightEdge] {
            assert_eq!(click_action(zone, LTR, false), ClickAction::ToggleChrome);
        }
    }

    #[test]
    fn the_wheel_turns_once_per_notch_and_a_trackpad_gathers_fractions() {
        let mut wheel = WheelAccumulator::default();
        assert_eq!(wheel.scrolled(1.0), Some(PageAction::Next));
        assert_eq!(wheel.scrolled(0.4), None);
        assert_eq!(wheel.scrolled(0.4), None);
        assert_eq!(wheel.scrolled(0.4), Some(PageAction::Next));
        assert_eq!(wheel.scrolled(-1.0), Some(PageAction::Previous));
    }

    #[test]
    fn the_chrome_hides_three_seconds_after_the_pointer_rests() {
        let start = Instant::now();
        let mut chrome = ChromeIdle::default();
        chrome.pointer_moved(start);
        assert!(chrome.is_visible());
        assert!(!chrome.should_hide(start + Duration::from_secs(2)));
        assert!(chrome.is_visible());
        assert!(chrome.should_hide(start + CHROME_IDLE));
        assert!(!chrome.is_visible());
        assert!(
            !chrome.should_hide(start + Duration::from_secs(10)),
            "it hides once"
        );
    }

    #[test]
    fn a_later_move_restarts_the_clock_and_a_hold_keeps_the_chrome() {
        let start = Instant::now();
        let mut chrome = ChromeIdle::default();
        chrome.pointer_moved(start);
        chrome.pointer_moved(start + Duration::from_secs(2));
        assert!(!chrome.should_hide(start + Duration::from_secs(4)));
        assert!(chrome.should_hide(start + Duration::from_secs(5)));

        chrome.pointer_moved(start + Duration::from_secs(6));
        chrome.hold(true);
        assert!(!chrome.should_hide(start + Duration::from_secs(20)));
        chrome.hold(false);
        assert!(chrome.should_hide(start + Duration::from_secs(20)));
    }

    #[test]
    fn toggling_hides_at_once_and_shows_again_with_a_fresh_clock() {
        let start = Instant::now();
        let mut chrome = ChromeIdle::default();
        chrome.toggle(start);
        assert!(!chrome.is_visible());
        chrome.toggle(start);
        assert!(chrome.is_visible());
        assert!(chrome.should_hide(start + CHROME_IDLE));
    }
}
