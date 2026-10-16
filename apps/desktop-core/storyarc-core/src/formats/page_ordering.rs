//! Which archive entries are pages, in what order, and which one is the cover. Mirrored
//! from `PageEntry.swift` and `PageSelection.swift`.
//!
//! This is the part of the format layer most likely to disagree between implementations,
//! so it is pure, dependency-free, and asserted against the shared fixture corpus.

use crate::domain::NaturalOrder;

/// One page inside a publication, before it is decoded.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageEntry {
    /// The entry's path inside the archive. Unique, so it is the identity.
    pub path: String,
    /// Uncompressed size in bytes, where the container reports one.
    pub byte_count: Option<u64>,
}

impl PageEntry {
    pub fn new(path: impl Into<String>, byte_count: Option<u64>) -> Self {
        Self {
            path: path.into(),
            byte_count,
        }
    }
}

pub struct PageOrdering;

impl PageOrdering {
    /// Image extensions StoryArc will attempt to decode. A file outside this set is never a
    /// page — `publication-formats` requires `ComicInfo.xml`, `Thumbs.db` and resource
    /// forks to be excluded rather than shown blank.
    ///
    /// `jxl` is in the list although no platform's decoder reads it, and that is
    /// deliberate: `publication-formats` requires an unsupported codec to show "a
    /// placeholder naming the codec" without breaking pagination, and a page excluded from
    /// the list is a page nobody can be told about. It is listed so it can be refused by
    /// name — see `PageCodec`.
    pub const IMAGE_EXTENSIONS: [&'static str; 12] = [
        "jpg", "jpeg", "png", "webp", "avif", "gif", "heic", "heif", "bmp", "tif", "tiff", "jxl",
    ];

    /// True when an entry could be part of a publication at all.
    ///
    /// Everything `is_page` rejects before it looks at the extension, split out so a folder
    /// classifier can apply the same exclusions to audio without restating them.
    pub fn is_candidate_entry(path: &str) -> bool {
        // Directory markers are not entries.
        if path.ends_with('/') {
            return false;
        }
        let mut components = path.split('/').filter(|c| !c.is_empty());
        let Some(name) = components.clone().next_back() else {
            return false;
        };
        // macOS resource forks travel inside archives made on a Mac and mirror every real
        // page, so an archive would report double its page count.
        if components.any(|c| c == "__MACOSX") {
            return false;
        }
        // `._page1.png` is a fork; `.DS_Store` and friends are dotfiles.
        !name.starts_with('.')
    }

    /// True when an entry is a page candidate.
    pub fn is_page(path: &str) -> bool {
        Self::is_candidate_entry(path)
            && Self::extension(path)
                .is_some_and(|ext| Self::IMAGE_EXTENSIONS.contains(&ext.as_str()))
    }

    /// The lower-cased extension of the last path component, if it has one.
    pub fn extension(path: &str) -> Option<String> {
        let name = path.rsplit('/').next().unwrap_or(path);
        let dot = name.rfind('.')?;
        if dot == 0 {
            return None;
        }
        Some(name[dot + 1..].to_lowercase())
    }

    /// Sorts entries the way a human would: `page10` after `page9`, and chapter directories
    /// in order, by comparing the full path.
    pub fn sorted(mut entries: Vec<PageEntry>) -> Vec<PageEntry> {
        entries.sort_by(|a, b| NaturalOrder::compare(&a.path, &b.path));
        entries
    }

    /// Filters to pages, then sorts. The whole job in one call.
    pub fn pages(paths: &[&str]) -> Vec<PageEntry> {
        Self::sorted(
            paths
                .iter()
                .filter(|p| Self::is_page(p))
                .map(|p| PageEntry::new(*p, None))
                .collect(),
        )
    }

    pub fn natural_compare(lhs: &str, rhs: &str) -> bool {
        NaturalOrder::precedes(lhs, rhs)
    }
}

/// Resolves which page is the cover.
pub struct CoverSelection;

impl CoverSelection {
    /// The designated cover, when one is designated and exists; otherwise the first page
    /// in reading order.
    ///
    /// A designated index that falls outside the page list is ignored rather than clamped.
    /// `ComicInfo`'s indices count *archive* entries, and an archive whose non-page entries
    /// were filtered out can leave a stale index behind — showing an arbitrary middle page
    /// would look like a bug in the reader rather than in the file.
    pub fn cover(pages: &[PageEntry], designated: Option<usize>) -> Option<&PageEntry> {
        match designated {
            Some(index) if index < pages.len() => pages.get(index),
            _ => pages.first(),
        }
    }
}

/// Resolves what `ComicInfo.xml` says about individual pages.
pub struct PageDeclarations;

impl PageDeclarations {
    /// The declared spreads that actually name a page in this list. Same caveat as the
    /// cover: an index outside the page list is dropped rather than clamped.
    pub fn spreads(pages: &[PageEntry], declared: &[usize]) -> Vec<usize> {
        declared
            .iter()
            .copied()
            .filter(|&i| i < pages.len())
            .collect()
    }

    /// The declared chapter starts that actually name a page in this list.
    pub fn chapter_starts(pages: &[PageEntry], declared: &[usize]) -> Vec<usize> {
        Self::spreads(pages, declared)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(entries: &[PageEntry]) -> Vec<&str> {
        entries.iter().map(|e| e.path.as_str()).collect()
    }

    #[test]
    fn chapter_directories_order_naturally_by_full_path() {
        let ordered = PageOrdering::pages(&[
            "ch10/p1.png",
            "ch2/p1.png",
            "ch1/p10.png",
            "ch1/p2.png",
            "ch1/p1.png",
        ]);
        assert_eq!(
            paths(&ordered),
            [
                "ch1/p1.png",
                "ch1/p2.png",
                "ch1/p10.png",
                "ch2/p1.png",
                "ch10/p1.png"
            ]
        );
    }

    #[test]
    fn comic_info_resource_forks_and_cruft_are_never_pages() {
        for path in [
            "ComicInfo.xml",
            "comicinfo.xml",
            "__MACOSX/._page1.png",
            "._page1.png",
            "Thumbs.db",
            ".DS_Store",
            "notes.txt",
            "chapter1/",
        ] {
            assert!(!PageOrdering::is_page(path), "{path} was taken for a page");
        }
    }

    #[test]
    fn every_supported_image_codec_is_accepted_in_any_case() {
        for ext in [
            "jpg", "JPEG", "png", "WebP", "avif", "gif", "heic", "heif", "bmp", "tiff", "jxl",
        ] {
            assert!(
                PageOrdering::is_page(&format!("page.{ext}")),
                "rejected .{ext}"
            );
        }
    }

    #[test]
    fn a_designated_index_outside_the_page_list_is_ignored_not_clamped() {
        let pages = vec![
            PageEntry::new("a.png", Some(1)),
            PageEntry::new("b.png", Some(1)),
        ];
        assert_eq!(
            CoverSelection::cover(&pages, Some(9)).unwrap().path,
            "a.png"
        );
        assert_eq!(
            CoverSelection::cover(&pages, Some(1)).unwrap().path,
            "b.png"
        );
        assert_eq!(CoverSelection::cover(&pages, None).unwrap().path, "a.png");
        assert!(CoverSelection::cover(&[], None).is_none());
        assert_eq!(PageDeclarations::spreads(&pages, &[1, 5]), [1]);
    }
}
