//! Rules the library and the format layer share, mirrored from StoryArcKit's
//! `StoryArcCore` target: the ones that must not drift between the two callers.

pub mod adjustments;
pub mod identity;
pub mod natural_order;
pub mod progress;
pub mod publication;
pub mod reading_direction;
pub mod spread_layout;
pub mod timestamp;

pub use adjustments::ImageAdjustments;
pub use identity::{PublicationIdentity, ServerIdentifier};
pub use natural_order::NaturalOrder;
pub use progress::{ProgressMerge, ProgressMergeOutcome, ReadingPosition, ReadingProgress};
pub use publication::{
    MetadataOrigin, Publication, PublicationFormat, PublicationStatus, StreamingCapability,
};
pub use reading_direction::ReadingDirection;
pub use spread_layout::{Spread, SpreadLayout};
pub use timestamp::Timestamp;
