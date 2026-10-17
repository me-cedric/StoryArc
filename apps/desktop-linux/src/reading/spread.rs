//! Whether a reader window shows two pages, and which page lands on which side
//! (`desktop-experience`, Two-page spreads by window shape). The pairing is the core's
//! `SpreadLayout::paired`; this adds the window-shape rule and the screen order.

use std::collections::HashSet;

use storyarc_core::domain::{Spread, SpreadLayout};

use super::zoom::Size;
use crate::keys::PageAction;
use crate::settings::Layout;

pub struct SpreadDecision;

impl SpreadDecision {
    /// Two portrait pages side by side are about 4:3. A window at or past this aspect
    /// pairs; a narrower one shows one page.
    pub const PAIRING_ASPECT: f64 = 1.25;

    pub fn pairs(viewport: Size) -> bool {
        viewport.height > 0.0 && viewport.width / viewport.height >= Self::PAIRING_ASPECT
    }

    /// Whether this window pairs under the reader's layout choice: Auto follows the
    /// window's shape, Two Pages pairs whenever the window is not a narrow column.
    pub fn pairs_for(layout: Layout, viewport: Size) -> bool {
        match layout {
            Layout::Auto => Self::pairs(viewport),
            Layout::TwoPages => viewport.height > 0.0 && viewport.width >= viewport.height,
            Layout::Single | Layout::Scroll => false,
        }
    }

    /// The layout for a window of this shape. `cover_alone` is the desktop default.
    pub fn layout(
        page_count: usize,
        wide: &HashSet<usize>,
        pairs: bool,
        cover_alone: bool,
    ) -> SpreadLayout {
        if pairs {
            SpreadLayout::paired(page_count, wide, cover_alone)
        } else {
            SpreadLayout::single(page_count)
        }
    }

    /// The page a turn lands on: the first page of the slot after `action`, or `None` when
    /// nothing moves. A turn moves one screen, so a pair turns two pages and a lone page one.
    pub fn turned(layout: &SpreadLayout, page: usize, action: PageAction) -> Option<usize> {
        let count = layout.count();
        if count == 0 {
            return None;
        }
        let current = layout.slot_containing(page);
        let target = match action {
            PageAction::Next => current.checked_add(1).filter(|slot| *slot < count)?,
            PageAction::Previous => current.checked_sub(1)?,
            PageAction::First => 0,
            PageAction::Last => count - 1,
        };
        let landing = layout.slot(target)?.leading;
        (landing != page).then_some(landing)
    }

    /// The pages of a slot from the left of the screen to the right: right-to-left puts
    /// the page read first on the right. A lone page is centred and no blank is drawn.
    pub fn screen_order(spread: &Spread, right_to_left: bool) -> Vec<usize> {
        let pages = spread.pages();
        if right_to_left {
            pages.into_iter().rev().collect()
        } else {
            pages
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pages(layout: &SpreadLayout) -> Vec<Vec<usize>> {
        layout.slots.iter().map(Spread::pages).collect()
    }

    #[test]
    fn a_wide_window_pairs_and_a_narrow_one_shows_one_page() {
        assert!(SpreadDecision::pairs(Size::new(1400.0, 800.0)));
        assert!(!SpreadDecision::pairs(Size::new(700.0, 900.0)));
        assert!(!SpreadDecision::pairs(Size::new(800.0, 0.0)));
        let wide = Size::new(1400.0, 800.0);
        assert!(!SpreadDecision::pairs_for(Layout::Single, wide));
        assert!(SpreadDecision::pairs_for(Layout::Auto, wide));
        let square = Size::new(900.0, 800.0);
        assert!(SpreadDecision::pairs_for(Layout::TwoPages, square));
        assert!(!SpreadDecision::pairs_for(Layout::Auto, square));
    }

    #[test]
    fn the_cover_is_alone_then_pairs_and_the_last_of_an_odd_count_is_alone() {
        let layout = SpreadDecision::layout(7, &HashSet::new(), true, true);
        assert_eq!(
            pages(&layout),
            [vec![0], vec![1, 2], vec![3, 4], vec![5, 6]]
        );
        let even = SpreadDecision::layout(8, &HashSet::new(), true, true);
        assert_eq!(
            pages(&even),
            [vec![0], vec![1, 2], vec![3, 4], vec![5, 6], vec![7]]
        );
        assert!(even.slots.last().is_some_and(|slot| !slot.is_pair()));
    }

    #[test]
    fn a_page_that_is_already_a_spread_shows_alone_and_full_width() {
        let layout = SpreadDecision::layout(6, &HashSet::from([3]), true, true);
        assert_eq!(pages(&layout), [vec![0], vec![1, 2], vec![3], vec![4, 5]]);
    }

    #[test]
    fn a_narrow_window_keeps_the_reader_on_the_same_page_one_per_slot() {
        let layout = SpreadDecision::layout(5, &HashSet::new(), false, true);
        assert_eq!(
            pages(&layout),
            [vec![0], vec![1], vec![2], vec![3], vec![4]]
        );
        assert_eq!(layout.slot_containing(3), 3);
        let paired = SpreadDecision::layout(5, &HashSet::new(), true, true);
        assert_eq!(paired.slot_containing(3), 2);
    }

    #[test]
    fn right_to_left_puts_the_page_read_first_on_the_right() {
        let pair = Spread {
            leading: 4,
            trailing: Some(5),
        };
        assert_eq!(SpreadDecision::screen_order(&pair, false), [4, 5]);
        assert_eq!(SpreadDecision::screen_order(&pair, true), [5, 4]);
        let alone = Spread {
            leading: 9,
            trailing: None,
        };
        assert_eq!(SpreadDecision::screen_order(&alone, true), [9]);
    }

    #[test]
    fn a_turn_moves_one_screen_and_stops_at_either_end() {
        let paired = SpreadDecision::layout(7, &HashSet::new(), true, true);
        assert_eq!(
            SpreadDecision::turned(&paired, 0, PageAction::Next),
            Some(1)
        );
        assert_eq!(
            SpreadDecision::turned(&paired, 1, PageAction::Next),
            Some(3)
        );
        // A reader on the trailing page of a pair turns back to the pair before it.
        assert_eq!(
            SpreadDecision::turned(&paired, 4, PageAction::Previous),
            Some(1)
        );
        assert_eq!(SpreadDecision::turned(&paired, 5, PageAction::Next), None);
        assert_eq!(
            SpreadDecision::turned(&paired, 0, PageAction::Previous),
            None
        );
        assert_eq!(
            SpreadDecision::turned(&paired, 2, PageAction::Last),
            Some(5)
        );
        assert_eq!(SpreadDecision::turned(&paired, 5, PageAction::Last), None);
        let empty = SpreadDecision::layout(0, &HashSet::new(), true, true);
        assert_eq!(SpreadDecision::turned(&empty, 0, PageAction::Next), None);
    }

    #[test]
    fn the_cover_pairs_with_page_two_when_cover_alone_is_off() {
        let layout = SpreadDecision::layout(4, &HashSet::new(), true, false);
        assert_eq!(pages(&layout), [vec![0, 1], vec![2, 3]]);
    }
}
