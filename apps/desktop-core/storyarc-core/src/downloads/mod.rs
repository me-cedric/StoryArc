//! Downloads (`offline-downloads`): which may run now ([`policy`]), one resumable transfer
//! into a partial file ([`transfer`]), the queue and its rules ([`queue`]), and the folder a
//! finished file lands in after it passes the integrity check ([`DownloadFolder`]).
//!
//! **Indexing is the verification**, as on the phones: with no checksum from the server, the
//! honest check is whether the bytes are a publication this app opens. A truncated archive
//! fails here rather than at the first page turn. A container the app does not read is not a
//! failed verification, because fetching it again yields the same container.

pub mod policy;
pub mod queue;
pub mod transfer;

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::domain::{Publication, PublicationFormat};
use crate::io::CancelToken;
use crate::net::{HttpClient, Request};
use crate::sources::{IndexError, PublicationIndexer};
use transfer::{Resumption, TransferError};

/// A finished, verified download.
#[derive(Debug, Clone)]
pub struct Landed {
    pub path: PathBuf,
    pub publication: Publication,
    pub resumption: Resumption,
    pub length: u64,
}

/// Why a download did not land.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LandingError {
    Transfer(TransferError),
    /// The bytes are not a publication: re-queue once ([`queue::DownloadQueue::failing_verification`]).
    Unreadable,
    /// A container the app recognises and does not read, named: terminal.
    Unsupported(String),
    /// The verified file could not be moved into place.
    Disk(String),
}

impl LandingError {
    /// Whether an automatic retry of the transfer may succeed.
    pub fn is_transient(&self) -> bool {
        match self {
            Self::Transfer(error) => error.is_transient(),
            Self::Unreadable | Self::Unsupported(_) | Self::Disk(_) => false,
        }
    }
}

impl std::fmt::Display for LandingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Transfer(error) => write!(f, "{error}"),
            Self::Unreadable => f.write_str("the downloaded file is not a publication"),
            Self::Unsupported(format) => write!(f, "{format} is not supported"),
            Self::Disk(detail) => write!(f, "the download could not be kept: {detail}"),
        }
    }
}

impl std::error::Error for LandingError {}

/// The downloads folder: one subfolder per publication, named by a digest of its id, which
/// holds the partial file while it arrives and the publication once it is verified.
#[derive(Debug, Clone)]
pub struct DownloadFolder {
    root: PathBuf,
}

const PARTIAL: &str = "download.part";

impl DownloadFolder {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn slot(&self, id: &str) -> PathBuf {
        let digest = Sha256::digest(id.as_bytes());
        let name: String = digest[..12].iter().map(|b| format!("{b:02x}")).collect();
        self.root.join(name)
    }

    /// Where the bytes of `id` arrive.
    pub fn partial(&self, id: &str) -> PathBuf {
        self.slot(id).join(PARTIAL)
    }

    /// The finished publication of `id`, when it is there.
    pub fn located(&self, id: &str) -> Option<PathBuf> {
        std::fs::read_dir(self.slot(id))
            .ok()?
            .flatten()
            .map(|e| e.path())
            .find(|p| p.is_file() && !is_partial(p))
    }

    /// Removes the publication of `id` and anything partial: cancel, or remove download.
    pub fn remove(&self, id: &str) {
        let _ = std::fs::remove_dir_all(self.slot(id));
    }

    /// What every file under the folder weighs, partial ones included: the storage view.
    pub fn bytes_on_disk(&self) -> u64 {
        fn walk(dir: &Path) -> u64 {
            std::fs::read_dir(dir)
                .map(|entries| {
                    entries
                        .flatten()
                        .map(|e| match e.metadata() {
                            Ok(m) if m.is_dir() => walk(&e.path()),
                            Ok(m) => m.len(),
                            Err(_) => 0,
                        })
                        .sum()
                })
                .unwrap_or(0)
        }
        walk(&self.root)
    }

    /// Transfers `request` for publication `id`, resuming what a previous attempt kept,
    /// verifies the bytes, and moves them into place named after `title`. A failed
    /// verification discards the bytes so the re-queue starts from nothing.
    #[allow(clippy::too_many_arguments)]
    pub fn fetch(
        &self,
        http: &HttpClient,
        id: &str,
        title: &str,
        request: Request,
        series_hint: Option<&str>,
        cancel: &CancelToken,
        progress: impl FnMut(u64, Option<u64>),
    ) -> Result<Landed, LandingError> {
        let part = self.partial(id);
        let done = transfer::transfer(http, request, &part, cancel, progress)
            .map_err(LandingError::Transfer)?;
        let format = match PublicationIndexer::index_path(&part, series_hint) {
            Ok(publication) => publication.format,
            Err(error) => {
                transfer::discard(&part);
                return Err(verification(error));
            }
        };
        let target = self
            .slot(id)
            .join(format!("{}.{}", file_stem(title), extension(format)));
        if let Some(old) = self.located(id) {
            let _ = std::fs::remove_file(old);
        }
        std::fs::rename(&part, &target).map_err(|e| LandingError::Disk(e.to_string()))?;
        transfer::discard(&part);
        let publication =
            PublicationIndexer::index_path(&target, series_hint).map_err(|error| {
                let _ = std::fs::remove_file(&target);
                verification(error)
            })?;
        Ok(Landed {
            path: target,
            publication,
            resumption: done.resumption,
            length: done.length,
        })
    }
}

fn is_partial(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| n.starts_with(PARTIAL))
}

fn verification(error: IndexError) -> LandingError {
    match error {
        IndexError::Unsupported(format) => LandingError::Unsupported(format),
        _ => LandingError::Unreadable,
    }
}

/// The title as a file name every system accepts: no separators, no reserved characters,
/// no trailing dot or space, at most 80 characters.
fn file_stem(title: &str) -> String {
    let cleaned: String = title
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .take(80)
        .collect();
    let trimmed = cleaned.trim_matches(|c: char| c == '.' || c.is_whitespace());
    if trimmed.is_empty() {
        "publication".to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn extension(format: PublicationFormat) -> &'static str {
    match format {
        PublicationFormat::Cbz => "cbz",
        PublicationFormat::Cbr => "cbr",
        PublicationFormat::Cb7 => "cb7",
        PublicationFormat::Cbt => "cbt",
        PublicationFormat::Epub => "epub",
        PublicationFormat::Pdf => "pdf",
        PublicationFormat::M4b => "m4b",
        PublicationFormat::Mp3 => "mp3",
        PublicationFormat::Flac => "flac",
        PublicationFormat::Ogg => "ogg",
        PublicationFormat::ImageFolder | PublicationFormat::AudioFolder => "bin",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_title_becomes_a_name_every_system_accepts() {
        assert_eq!(file_stem("Saga: Vol. 1/2?"), "Saga_ Vol. 1_2_");
        assert_eq!(file_stem(" .. "), "publication");
        assert_eq!(file_stem("CON."), "CON");
        assert_eq!(file_stem(&"x".repeat(200)).len(), 80);
    }
}
