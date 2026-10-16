//! A page's bytes turned into pixels, and the reader's adjustments applied to them (tasks
//! 2.5 and 2.6 of `desktop-clients`). Mirrored from StoryArcKit's `PageDecoder` and the
//! readers' `PageAdjustments`.
//!
//! The phones decode with the system (ImageIO, `ImageDecoder`, ADR-0005). Windows and Linux
//! share no system decoder that covers HEIC and AVIF the same way, so the core carries its
//! own and every desktop decodes a page identically: `desktop-experience`, *An image the
//! system cannot decode*, asks that no page in a supported archive decode on one desktop and
//! not on another.

pub mod decode;

pub use decode::{
    DecodedPage, MAX_PAGE_PIXELS, PageDecodeError, PageSize, SPREAD_THRESHOLD, can_decode, decode,
    dimensions, is_spread, is_spread_at,
};
