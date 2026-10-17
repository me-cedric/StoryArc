//! The reader's pure rules for task 2.28: zoom and pan, two-page spreads by window shape,
//! and dragging to turn. Rust copies of lane M's `ZoomModel`, `SpreadDecision` and
//! `DragTurn` (tasks 2.13 to 2.15), with the same tests, so the desktops agree. The
//! pairing arithmetic itself is the core's `SpreadLayout`, which iOS and Android share.

pub mod direction;
pub mod drag;
pub mod end;
pub mod spread;
pub mod zoom;

pub use drag::DragTurn;
pub use spread::SpreadDecision;
pub use zoom::{Size, ZoomModel, fitted_size};
