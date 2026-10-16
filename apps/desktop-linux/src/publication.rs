//! A publication a reader window holds: its identity, its title, how many pages it has
//! and which way it reads. A local record until lane C's library records land (task
//! 2.1), opened through the core's format layer, which is on main since wave 1.
//!
//! The core decodes no page yet (task 2.5), so a reader window shows the page's
//! number and name rather than its artwork. The count and the order are real.

use std::path::Path;

use storyarc_core::domain::ReadingDirection;
use storyarc_core::formats::{ComicArchive, FilenameMetadata};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Publication {
    /// The identity the window model and the progress store key on: the path.
    pub id: String,
    pub title: String,
    pub page_count: u32,
    pub direction: ReadingDirection,
    /// The page names in reading order, for the placeholder page.
    pub page_names: Vec<String>,
}

impl Publication {
    /// Opens a local comic archive through the core. A file the core refuses is
    /// refused by name, as `publication-formats` requires: the message names the
    /// reason, and the caller shows it in grey.
    pub fn open(path: &Path) -> Result<Self, String> {
        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        if !path.is_file() {
            return Err(format!("{name}: the file cannot be reached"));
        }
        let archive = ComicArchive::open_file(path).map_err(|error| format!("{name}: {error}"))?;
        let pages = archive.pages();
        if pages.is_empty() {
            return Err(format!("{name}: the archive holds no page"));
        }
        let info = archive.comic_info();
        let stem = path
            .file_stem()
            .map(|stem| stem.to_string_lossy().into_owned())
            .unwrap_or_else(|| name.clone());
        let metadata = FilenameMetadata::new(
            &stem,
            info.and_then(|info| info.series.as_deref()),
            info.and_then(|info| info.title.as_deref()),
        );
        // The embedded title first, then "Series number" from the file name, then the stem.
        let title = info
            .and_then(|info| info.title.clone())
            .filter(|title| !title.trim().is_empty())
            .or_else(|| match (&metadata.series, &metadata.number) {
                (Some(series), Some(number)) => Some(format!("{series} {number}")),
                (Some(series), None) => Some(series.clone()),
                _ => None,
            })
            .unwrap_or(stem);
        Ok(Self {
            id: path.to_string_lossy().into_owned(),
            title,
            page_count: pages.len() as u32,
            direction: info.map_or(ReadingDirection::LeftToRight, |info| {
                info.reading_direction()
            }),
            page_names: pages.iter().map(|page| page.path.clone()).collect(),
        })
    }

    /// Whether the publication can be reopened now, for restoration.
    pub fn is_reachable(id: &str) -> bool {
        Path::new(id).is_file()
    }
}

/// Whether the file behind an open reader window can still be reached. The window keeps
/// the pages it already holds either way and no window closes by itself.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Availability {
    #[default]
    Available,
    Gone,
}

impl Availability {
    pub fn of(id: &str, reachable: impl Fn(&str) -> bool) -> Self {
        if reachable(id) {
            Self::Available
        } else {
            Self::Gone
        }
    }

    /// The grey note the window shows while the rest of the publication is unavailable.
    pub fn note(self) -> Option<&'static str> {
        (self == Self::Gone).then_some("The rest of this publication is unavailable")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_publication_that_disappears_is_named_in_grey_and_one_that_returns_is_not() {
        assert_eq!(Availability::of("/a.cbz", |_| true).note(), None);
        let gone = Availability::of("/a.cbz", |_| false);
        assert_eq!(gone, Availability::Gone);
        assert_eq!(
            gone.note(),
            Some("The rest of this publication is unavailable")
        );
        assert_eq!(
            Availability::of("/a.cbz", |_| true),
            Availability::Available
        );
    }

    #[test]
    fn a_path_that_is_not_a_file_is_refused_by_name() {
        let error = Publication::open(Path::new("/nonexistent/x.cbz")).unwrap_err();
        assert!(error.starts_with("x.cbz:"), "{error}");
        assert!(!Publication::is_reachable("/nonexistent/x.cbz"));
    }
}
