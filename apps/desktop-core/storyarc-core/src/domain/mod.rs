//! Rules the library and the format layer share, mirrored from StoryArcKit's
//! `StoryArcCore` target: the ones that must not drift between the two callers.

pub mod natural_order;
pub mod reading_direction;

pub use natural_order::NaturalOrder;
pub use reading_direction::ReadingDirection;
