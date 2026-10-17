//! A publication a reader window holds: the core's record and the open container its
//! pages come from (`storyarc_core::library::OpenPublication`). The window decodes pages
//! on a worker, so the container sits behind a mutex the worker locks.

use std::collections::HashSet;
use std::path::Path;
use std::sync::{Arc, Mutex};

use storyarc_core::domain::{self, ImageAdjustments, PublicationFormat};
use storyarc_core::formats::ComicArchive;
use storyarc_core::image::{self, DecodedPage, PageSize};
use storyarc_core::library::{LibraryError, OpenPublication};

use crate::reading::chapters::{self, Marker};

/// A decode never asks for more than this on a page's longest edge: sharp at the zoom
/// a reader uses, and about 36 MB for the tallest page.
pub const MAX_DECODE_EDGE: u32 = 3072;

#[derive(Clone)]
pub struct Publication {
    /// The identity the window model keys on: the path it was opened from.
    pub id: String,
    pub title: String,
    pub page_count: u32,
    /// The core's record, for the progress store and the detail page.
    pub record: domain::Publication,
    /// The pages the container declares as double spreads.
    pub declared_spreads: HashSet<usize>,
    /// Where the container declares each chapter starts, with its name when it has one.
    pub markers: Vec<Marker>,
    open: Arc<Mutex<OpenPublication>>,
}

impl std::fmt::Debug for Publication {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Publication")
            .field("id", &self.id)
            .field("pages", &self.page_count)
            .finish()
    }
}

/// The words the reader sees for a file the core refused: the file's name, then the reason.
pub fn refusal(path: &Path, error: &LibraryError) -> String {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string());
    match error {
        LibraryError::NotFound(_) => format!("{name}: the file cannot be reached"),
        other => format!("{name}: {other}"),
    }
}

impl Publication {
    /// Opens a comic through the core. A file the core refuses (a CB7, an EPUB the
    /// reader cannot page yet, a damaged archive) is refused by name, with its reason,
    /// as `publication-formats` requires; the caller shows it in grey.
    pub fn open(path: &Path) -> Result<Self, String> {
        let open = OpenPublication::open(path).map_err(|error| refusal(path, &error))?;
        if open.page_count() == 0 {
            return Err(format!("{}: the archive holds no page", file_name(path)));
        }
        let record = open.publication().clone();
        Ok(Self {
            id: path.to_string_lossy().into_owned(),
            title: record.display_title.clone(),
            page_count: u32::try_from(open.page_count()).unwrap_or(u32::MAX),
            declared_spreads: open.declared_spreads().into_iter().collect(),
            markers: chapter_markers(path, record.format),
            record,
            open: Arc::new(Mutex::new(open)),
        })
    }

    /// Decodes one page to RGBA, at most `edge` on its longest edge, with the reader's
    /// adjustments applied. Blocks: call it from a worker. The reason names the codec when
    /// the bytes say which.
    pub fn decode_adjusted(
        &self,
        index: usize,
        edge: u32,
        adjustments: &ImageAdjustments,
    ) -> Result<DecodedPage, String> {
        let open = self
            .open
            .lock()
            .map_err(|_| "the publication is no longer readable".to_owned())?;
        let page = open
            .decode_page(index, Some(edge))
            .map_err(|error| error.to_string())?;
        Ok(if adjustments.is_neutral() {
            page
        } else {
            image::adjusted(&page, adjustments)
        })
    }

    /// Decodes one page to RGBA, at most [`MAX_DECODE_EDGE`] on its longest edge.
    pub fn decode(&self, index: usize) -> Result<DecodedPage, String> {
        self.decode_adjusted(index, MAX_DECODE_EDGE, &ImageAdjustments::default())
    }

    /// Every page's shape from its header, without decoding: what continuous scroll
    /// lays the strip out with. A page whose header cannot be read takes a portrait shape.
    pub fn page_sizes(&self) -> Vec<(i32, i32)> {
        let Ok(open) = self.open.lock() else {
            return Vec::new();
        };
        (0..open.page_count())
            .map(|index| {
                open.page_size(index).map_or((2, 3), |size| {
                    (
                        i32::try_from(size.width).unwrap_or(2),
                        i32::try_from(size.height).unwrap_or(3),
                    )
                })
            })
            .collect()
    }

    /// Whether the publication can be reopened now, for restoration.
    pub fn is_reachable(id: &str) -> bool {
        Path::new(id).exists()
    }
}

/// The chapters a comic archive declares (ComicInfo's bookmarks). A folder of images and
/// an archive that declares none have no markers.
fn chapter_markers(path: &Path, format: PublicationFormat) -> Vec<Marker> {
    if !matches!(
        format,
        PublicationFormat::Cbz | PublicationFormat::Cbr | PublicationFormat::Cbt
    ) {
        return Vec::new();
    }
    ComicArchive::open_file(path).map_or_else(
        |_| Vec::new(),
        |archive| chapters::markers(&archive.chapter_start_indices(), &archive.chapter_titles()),
    )
}

/// Whether a decoded page is a landscape spread that stands alone (`PageDecoder.isSpread`).
pub fn is_wide(width: u32, height: u32) -> bool {
    image::is_spread(PageSize { width, height })
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
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
pub(crate) mod tests {
    use std::path::PathBuf;

    use super::*;

    pub fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/comics")
            .join(name)
    }

    #[test]
    fn a_publication_that_disappears_is_named_in_grey_and_one_that_returns_is_not() {
        assert_eq!(Availability::of("/a.cbz", |_| true).note(), None);
        let gone = Availability::of("/a.cbz", |_| false);
        assert_eq!(gone, Availability::Gone);
        assert_eq!(
            gone.note(),
            Some("The rest of this publication is unavailable")
        );
    }

    #[test]
    fn a_path_that_is_not_there_is_refused_by_name() {
        let error = Publication::open(Path::new("/nonexistent/x.cbz")).unwrap_err();
        assert_eq!(error, "x.cbz: the file cannot be reached");
        assert!(!Publication::is_reachable("/nonexistent/x.cbz"));
    }

    #[test]
    fn a_cb7_archive_is_refused_by_name_with_its_reason() {
        let error = Publication::open(&fixture("refused.cb7")).unwrap_err();
        assert!(error.starts_with("refused.cb7: "), "{error}");
        assert!(error.len() > "refused.cb7: ".len());
    }

    #[test]
    fn a_comic_opens_through_the_core_and_its_pages_decode() {
        let publication = Publication::open(&fixture("natural-sort.cbz")).expect("opens");
        assert!(publication.page_count > 1);
        assert!(!publication.title.is_empty());
        let page = publication.decode(0).expect("the first page decodes");
        assert_eq!(page.rgba.len(), (page.width * page.height * 4) as usize);
        assert!(page.width.max(page.height) <= MAX_DECODE_EDGE);
    }

    #[test]
    fn a_page_decodes_with_the_reader_s_adjustments_and_every_page_has_a_shape() {
        let publication = Publication::open(&fixture("natural-sort.cbz")).expect("opens");
        let grey = ImageAdjustments {
            is_greyscale: true,
            ..ImageAdjustments::default()
        };
        let page = publication.decode_adjusted(0, 256, &grey).expect("decodes");
        assert!(page.width.max(page.height) <= 256);
        assert!(
            page.rgba
                .chunks(4)
                .all(|pixel| pixel[0] == pixel[1] && pixel[1] == pixel[2]),
            "greyscale reached every pixel"
        );
        let sizes = publication.page_sizes();
        assert_eq!(sizes.len(), publication.page_count as usize);
        assert!(sizes.iter().all(|(width, height)| *width > 0 && *height > 0));
        assert!(publication.markers.is_empty(), "the fixture declares no chapters");
    }

    #[test]
    fn a_page_the_core_cannot_decode_names_a_reason() {
        let publication = Publication::open(&fixture("unsupported-codec.cbz")).expect("opens");
        let reasons: Vec<String> = (0..publication.page_count as usize)
            .filter_map(|index| publication.decode(index).err())
            .collect();
        assert!(!reasons.is_empty());
        assert!(reasons.iter().all(|reason| !reason.is_empty()));
    }

    #[test]
    fn a_landscape_page_is_wide_and_a_portrait_one_is_not() {
        assert!(is_wide(2000, 1000));
        assert!(!is_wide(1000, 1500));
    }

    #[test]
    fn the_open_container_moves_to_a_worker() {
        fn send<T: Send + Sync>() {}
        send::<Publication>();
    }
}
