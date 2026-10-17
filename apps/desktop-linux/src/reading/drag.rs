//! Whether a drag across a page commits a turn, and which way (`desktop-experience`,
//! Dragging to turn a page). Past the threshold the page turns the way the drag went,
//! mirrored right-to-left; short of it the page settles back and no turn is counted. The
//! curl is wave 5, so in wave 2 the page slides with the pointer.

use crate::keys::PageAction;

pub struct DragTurn;

impl DragTurn {
    /// The least a drag travels before it commits: the iOS swipe's 48 on a narrow page,
    /// and a sixth of the page on a wide one.
    pub const MINIMUM_TRAVEL: f64 = 48.0;
    pub const TRAVEL_FRACTION: f64 = 1.0 / 6.0;

    pub fn threshold(width: f64) -> f64 {
        Self::MINIMUM_TRAVEL.max(width * Self::TRAVEL_FRACTION)
    }

    /// The reading-order step a finished drag asks for: 1, -1, or 0 for none.
    ///
    /// A drag to the left reveals what sits to the right: the next page left-to-right and
    /// the previous page right-to-left, as the trailing click zone does.
    pub fn step(translation: f64, width: f64, right_to_left: bool) -> i32 {
        let limit = Self::threshold(width);
        let display = if translation <= -limit {
            1
        } else if translation >= limit {
            -1
        } else {
            return 0;
        };
        if right_to_left { -display } else { display }
    }

    /// The page action a finished drag asks for, if any.
    pub fn action(translation: f64, width: f64, right_to_left: bool) -> Option<PageAction> {
        match Self::step(translation, width, right_to_left) {
            1 => Some(PageAction::Next),
            -1 => Some(PageAction::Previous),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn past_the_threshold_the_page_turns_the_way_the_drag_went() {
        assert_eq!(DragTurn::step(-200.0, 900.0, false), 1);
        assert_eq!(DragTurn::step(200.0, 900.0, false), -1);
        assert_eq!(
            DragTurn::action(-200.0, 900.0, false),
            Some(PageAction::Next)
        );
    }

    #[test]
    fn short_of_the_threshold_no_turn_is_counted() {
        assert_eq!(DragTurn::step(-100.0, 900.0, false), 0);
        assert_eq!(DragTurn::step(30.0, 200.0, false), 0);
        assert_eq!(DragTurn::step(0.0, 900.0, true), 0);
        assert_eq!(DragTurn::action(30.0, 200.0, false), None);
    }

    #[test]
    fn mirrored_in_a_right_to_left_publication() {
        assert_eq!(DragTurn::step(-200.0, 900.0, true), -1);
        assert_eq!(DragTurn::step(200.0, 900.0, true), 1);
    }

    #[test]
    fn the_threshold_is_48_on_a_narrow_page_and_a_sixth_of_a_wide_one() {
        assert_eq!(DragTurn::threshold(200.0), 48.0);
        assert_eq!(DragTurn::threshold(1200.0), 200.0);
        assert_eq!(DragTurn::threshold(0.0), 48.0);
    }
}
