//! The format layer: turns a file into an ordered list of pages, and a page into bytes a
//! decoder can use. Mirrored from StoryArcKit's `Formats` target and asserted against the
//! shared corpus in `packages/test-fixtures` (`docs/architecture/format-layer.md`).

mod byte_reader;
pub mod zip;
mod zip_central_directory;
mod zip_recovery;

pub use zip::{ZipEntry, ZipError, ZipReader};
