//! The format layer: turns a file into an ordered list of pages, and a page into bytes a
//! decoder can use. Mirrored from StoryArcKit's `Formats` target and asserted against the
//! shared corpus in `packages/test-fixtures` (`docs/architecture/format-layer.md`).

mod byte_reader;
#[cfg(storyarc_libarchive)]
mod libarchive_sys;
pub mod rar;
pub mod rar_decoder;
pub mod tar;
pub mod zip;
mod zip_central_directory;
mod zip_recovery;

pub use rar::{RarEntry, RarError, RarGeneration, RarReader};
pub use rar_decoder::{DecodeError, DecoderEntry, RarDecoder};
pub use tar::{TarEntry, TarError, TarReader};
pub use zip::{ZipEntry, ZipError, ZipReader};
