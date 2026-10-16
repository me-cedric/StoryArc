//! Decompresses RAR entries, and nothing else. Mirrored from StoryArcKit's
//! `RarDecoder.swift`; Android's `rar_decoder.c` is the same three checks in the same order.
//!
//! This is the whole of libarchive's job in StoryArc. [`RarReader`](super::RarReader)
//! already answers every question the library asks — entry names, sizes, the cover, solid,
//! encrypted — from headers alone, and reads stored entries directly. What it cannot do is
//! undo RAR's LZ and PPMd coding, which is a real codec and the one thing worth a C
//! dependency (ADR-0005).
//!
//! So the seam is deliberately narrow: a path or a buffer in, entry bytes out. Nothing above
//! this type knows libarchive exists, which is what makes the dependency replaceable and
//! keeps the untrusted-input surface to a single call. The bindings themselves are in
//! `libarchive_sys.rs`, the only module of this crate allowed to spell `unsafe`.

use std::collections::{HashMap, HashSet};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeError {
    /// libarchive refused to open the archive at all.
    CannotOpen(String),
    /// The archive opened but the entry was never reached.
    EntryNotFound(String),
    /// libarchive stopped part-way through the entry's data.
    Truncated {
        path: String,
        expected: usize,
        got: usize,
    },
    /// The entry claims — or delivers — more than [`RarDecoder::MAX_ENTRY_BYTES`].
    TooLarge {
        path: String,
        declared: i64,
        cap: usize,
    },
    /// libarchive's own message, kept verbatim so a bug report can carry it.
    Libarchive(String),
    /// This build carries no decoder: Windows until task 1.7 lands.
    Unavailable,
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CannotOpen(message) => write!(f, "cannot open archive: {message}"),
            Self::EntryNotFound(path) => write!(f, "entry not found: {path}"),
            Self::Truncated {
                path,
                expected,
                got,
            } => write!(f, "{path}: expected {expected} bytes, got {got}"),
            Self::TooLarge {
                path,
                declared,
                cap,
            } => write!(f, "{path}: declares {declared} bytes, cap is {cap}"),
            Self::Libarchive(message) => write!(f, "libarchive: {message}"),
            Self::Unavailable => f.write_str("no RAR decoder in this build"),
        }
    }
}

impl std::error::Error for DecodeError {}

/// An entry as libarchive names and sizes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecoderEntry {
    pub path: String,
    pub size: i64,
}

pub struct RarDecoder;

impl RarDecoder {
    /// A ceiling on one entry's unpacked size.
    ///
    /// The size in a RAR header is untrusted: without a cap, a crafted archive claiming a
    /// petabyte drives the loop until the process dies. 512 MB is far past any real comic
    /// page, and the same number as iOS's `maxEntryBytes` and Android's `MAX_ENTRY_BYTES`.
    pub const MAX_ENTRY_BYTES: usize = 512 * 1024 * 1024;

    /// Zero bytes after an isolated entry's packed bytes.
    ///
    /// libarchive's RAR5 reader asks for 4 bytes past each compressed block, because its bit
    /// reader loads a word at a time. In a whole file those bytes are the next header. It
    /// sizes its own merge buffer 8 bytes past the block for the same reason.
    pub const ISOLATED_PADDING: usize = 8;
}

#[cfg(storyarc_libarchive)]
mod backed {
    use super::*;
    use crate::formats::libarchive_sys::{Archive, LibarchiveError};

    const BLOCK_SIZE: usize = 64 * 1024;

    impl From<LibarchiveError> for DecodeError {
        fn from(error: LibarchiveError) -> Self {
            Self::Libarchive(error.0)
        }
    }

    impl RarDecoder {
        /// Unpacked bytes for one entry, found by its path inside the archive.
        ///
        /// Walks headers until the path matches. That is linear, which is correct for RAR: a
        /// solid archive *must* be read in order, and for a non-solid one libarchive skips
        /// entry data without decompressing it.
        pub fn data_for_entry(path: &str, archive_path: &Path) -> Result<Vec<u8>, DecodeError> {
            let mut archive = open(archive_path)?;
            while let Some(header) = archive.next_header()? {
                if header.path == path {
                    return read_current_entry(&mut archive, path, header.size);
                }
            }
            Err(DecodeError::EntryNotFound(path.to_owned()))
        }

        /// Every entry's unpacked bytes in archive order, for the paths given.
        ///
        /// One pass rather than one open per page. A solid archive makes this the only
        /// affordable shape — reading page 30 there means decompressing 1 to 29, so asking
        /// for pages one at a time would be quadratic.
        pub fn data_for_entries(
            paths: &HashSet<String>,
            archive_path: &Path,
        ) -> Result<HashMap<String, Vec<u8>>, DecodeError> {
            let mut found = HashMap::new();
            if paths.is_empty() {
                return Ok(found);
            }
            let mut archive = open(archive_path)?;
            while found.len() < paths.len() {
                let Some(header) = archive.next_header()? else {
                    break;
                };
                if !paths.contains(&header.path) || found.contains_key(&header.path) {
                    continue;
                }
                let data = read_current_entry(&mut archive, &header.path, header.size)?;
                found.insert(header.path, data);
            }
            Ok(found)
        }

        /// Unpacked bytes of the one entry in `archive`, which `RarReader::isolated` built.
        ///
        /// The buffer holds the main header and a single entry, so the first header is the
        /// entry: no name match is needed, and none can miss on a name libarchive spells
        /// differently. `path` only names the entry in an error.
        pub fn data_of_isolated(path: &str, mut archive: Vec<u8>) -> Result<Vec<u8>, DecodeError> {
            if archive.is_empty() {
                return Err(DecodeError::CannotOpen("empty archive buffer".to_owned()));
            }
            archive.resize(archive.len() + RarDecoder::ISOLATED_PADDING, 0);
            let mut archive =
                Archive::open_memory(archive).map_err(|error| DecodeError::CannotOpen(error.0))?;
            let Some(header) = archive.next_header()? else {
                return Err(DecodeError::EntryNotFound(path.to_owned()));
            };
            read_current_entry(&mut archive, path, header.size)
        }

        /// Entry names and sizes as *libarchive* sees them.
        ///
        /// Not used for indexing — `RarReader` does that without a C library. This exists so
        /// a test can assert the two agree, which is the only way to know our header parser
        /// and the decoder are looking at the same archive.
        pub fn entry_names(archive_path: &Path) -> Result<Vec<DecoderEntry>, DecodeError> {
            let mut archive = open(archive_path)?;
            let mut names = Vec::new();
            while let Some(header) = archive.next_header()? {
                names.push(DecoderEntry {
                    path: header.path,
                    size: header.size,
                });
            }
            Ok(names)
        }
    }

    fn open(path: &Path) -> Result<Archive, DecodeError> {
        Archive::open_path(path).map_err(|error| DecodeError::CannotOpen(error.0))
    }

    /// Drains the current entry's data, up to `MAX_ENTRY_BYTES`.
    ///
    /// `declared` is a header field, so it is untrusted twice over. It is refused outright
    /// when it exceeds the cap — before a byte is read, which is the whole point: an archive
    /// that means to exhaust the device says so in its header and never gets to prove it.
    /// And it seeds the buffer's capacity but does not bound the loop, so the loop carries
    /// the same ceiling for the case where the header declares nothing at all.
    ///
    /// A mismatch at the end is reported rather than papered over, which is also what turns
    /// a run that hit the ceiling into a failure.
    fn read_current_entry(
        archive: &mut Archive,
        path: &str,
        declared: i64,
    ) -> Result<Vec<u8>, DecodeError> {
        let cap = RarDecoder::MAX_ENTRY_BYTES;
        let declared_size = match usize::try_from(declared) {
            Ok(size) if size <= cap => size,
            _ => {
                return Err(DecodeError::TooLarge {
                    path: path.to_owned(),
                    declared,
                    cap,
                });
            }
        };
        let mut out = Vec::with_capacity(declared_size);
        let mut block = vec![0u8; BLOCK_SIZE];
        while out.len() < cap {
            let read = archive.read_data(&mut block)?;
            if read == 0 {
                break;
            }
            let room = read.min(cap - out.len());
            out.extend_from_slice(&block[..room]);
        }
        // A short read means the archive claimed more than it delivered. Saying so beats
        // handing a truncated page to the decoder and reporting a corrupt image.
        if declared_size > 0 && out.len() != declared_size {
            return Err(DecodeError::Truncated {
                path: path.to_owned(),
                expected: declared_size,
                got: out.len(),
            });
        }
        Ok(out)
    }
}

#[cfg(not(storyarc_libarchive))]
mod unbacked {
    use super::*;

    impl RarDecoder {
        pub fn data_for_entry(_path: &str, _archive_path: &Path) -> Result<Vec<u8>, DecodeError> {
            Err(DecodeError::Unavailable)
        }

        pub fn data_for_entries(
            _paths: &HashSet<String>,
            _archive_path: &Path,
        ) -> Result<HashMap<String, Vec<u8>>, DecodeError> {
            Err(DecodeError::Unavailable)
        }

        pub fn data_of_isolated(_path: &str, _archive: Vec<u8>) -> Result<Vec<u8>, DecodeError> {
            Err(DecodeError::Unavailable)
        }

        pub fn entry_names(_archive_path: &Path) -> Result<Vec<DecoderEntry>, DecodeError> {
            Err(DecodeError::Unavailable)
        }
    }
}
