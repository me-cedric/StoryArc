//! The format layer: turns a file into an ordered list of pages, and a page into bytes a
//! decoder can use. Mirrored from StoryArcKit's `Formats` target and asserted against the
//! shared corpus in `packages/test-fixtures` (`docs/architecture/format-layer.md`).

mod byte_reader;
pub mod comic_archive;
pub mod comic_info;
pub mod epub;
pub mod filename_metadata;
#[cfg(storyarc_libarchive)]
mod libarchive_sys;
pub mod page_codec;
pub mod page_ordering;
pub mod rar;
pub mod rar_decoder;
pub mod sniff;
pub mod tar;
mod xml;
pub mod zip;
mod zip_central_directory;
mod zip_recovery;

pub use comic_archive::{
    ComicArchive, ComicArchiveError, RarComicArchive, TarComicArchive, ZipComicArchive,
};
pub use comic_info::ComicInfo;
pub use epub::{EpubError, EpubMetadata, EpubReader, EpubSpineItem, EpubTocEntry};
pub use filename_metadata::FilenameMetadata;
pub use page_codec::PageCodec;
pub use page_ordering::{CoverSelection, PageDeclarations, PageEntry, PageOrdering};
pub use rar::{RarEntry, RarError, RarGeneration, RarReader};
pub use rar_decoder::{DecodeError, DecoderEntry, RarDecoder};
pub use sniff::{Container, FormatSniffer};
pub use tar::{TarEntry, TarError, TarReader};
pub use zip::{ZipEntry, ZipError, ZipReader};
