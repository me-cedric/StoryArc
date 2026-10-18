//! A publication a reader window holds: the core's record and the open container its
//! pages come from, a comic archive (`storyarc_core::library::OpenPublication`) or a PDF
//! (`storyarc_core::pdf::PdfDocument`, task 4.11). The window decodes pages on a worker,
//! so the container sits behind a mutex the worker locks.

use std::collections::HashSet;
use std::path::Path;
use std::sync::{Arc, Mutex};

use storyarc_core::domain::{self, ImageAdjustments, PublicationFormat};
use storyarc_core::formats::ComicArchive;
use storyarc_core::image::{self, DecodedPage, PageSize};
use storyarc_core::io::source::FileSource;
use storyarc_core::library::{LibraryError, OpenPublication};
use storyarc_core::pdf::{PdfDocument, PdfEngine, PdfMatch, PdfOutlineEntry};
use storyarc_core::sources::PublicationIndexer;

use crate::reading::chapters::{self, Marker};

/// A decode never asks for more than this on a page's longest edge: sharp at the zoom
/// a reader uses, and about 36 MB for the tallest page.
pub const MAX_DECODE_EDGE: u32 = 3072;

/// Device pixels per point a PDF page renders at: the view's scale factor, raised so a
/// page whose longest edge is `page_longest` points fills a view whose longest edge is
/// `view_longest` logical pixels. The decode's edge cap still bounds it. Without this the
/// core's one pixel a point was scaled up and blurred on a large or HiDPI window.
pub fn pdf_scale(page_longest: f32, view_longest: i32, scale_factor: i32) -> f32 {
    let fill = view_longest.max(0) as f32 / page_longest.max(1.0);
    scale_factor.max(1) as f32 * fill.max(1.0)
}

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
    open: Arc<Mutex<Container>>,
}

/// What the pages come from.
enum Container {
    /// Boxed: the archive index is large next to the PDF handle.
    Comic(Box<OpenPublication>),
    Pdf(PdfDocument),
}

/// Whether a path is a PDF, which opens through the core's PDF engine.
pub fn is_pdf(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("pdf"))
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
        if is_pdf(path) {
            return Self::open_pdf(path);
        }
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
            open: Arc::new(Mutex::new(Container::Comic(Box::new(open)))),
        })
    }

    /// Opens a PDF through the core's engine (`ebook-reader`, PDF rendering). The engine
    /// binds the pinned PDFium once per process; without the library the file is refused
    /// by name with where the library was looked for. The outline's entries that name a
    /// page become the reader's chapter markers.
    fn open_pdf(path: &Path) -> Result<Self, String> {
        let name = file_name(path);
        let record = PublicationIndexer::index_path(path, None)
            .map_err(|error| format!("{name}: {error}"))?;
        let engine = PdfEngine::start(None).map_err(|error| format!("{name}: {error}"))?;
        let source = FileSource::open(path).map_err(|error| format!("{name}: {error}"))?;
        let document = engine
            .open(Arc::new(source))
            .map_err(|error| format!("{name}: {error}"))?;
        if document.page_count() == 0 {
            return Err(format!("{name}: the document holds no page"));
        }
        let markers = outline_markers(&document.outline().unwrap_or_default());
        Ok(Self {
            id: path.to_string_lossy().into_owned(),
            title: record.display_title.clone(),
            page_count: document.page_count(),
            declared_spreads: HashSet::new(),
            markers,
            record,
            open: Arc::new(Mutex::new(Container::Pdf(document))),
        })
    }

    /// Whether the pages are a PDF, whose text, search and outline the reader offers.
    pub fn is_pdf(&self) -> bool {
        self.open
            .lock()
            .is_ok_and(|open| matches!(&*open, Container::Pdf(_)))
    }

    /// Whether any page carries text, so selection and search are offered (`ebook-reader`,
    /// A text layer is detected rather than assumed). False for a comic.
    pub fn has_text_layer(&self) -> bool {
        match self.open.lock().as_deref() {
            Ok(Container::Pdf(document)) => document.has_text_layer().unwrap_or(false),
            _ => false,
        }
    }

    /// One page's text, in content order; empty for a page without text. Blocks.
    pub fn page_text(&self, index: usize) -> String {
        match self.open.lock().as_deref() {
            Ok(Container::Pdf(document)) => document
                .page_text(u32::try_from(index).unwrap_or(u32::MAX))
                .unwrap_or_default(),
            _ => String::new(),
        }
    }

    /// Every hit of `query`, page by page, case folded by the engine. Blocks.
    pub fn search(&self, query: &str) -> Vec<PdfMatch> {
        match self.open.lock().as_deref() {
            Ok(Container::Pdf(document)) => document.search(query).unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    /// The outline as the file nests it; empty for a comic or a PDF without one.
    pub fn outline(&self) -> Vec<PdfOutlineEntry> {
        match self.open.lock().as_deref() {
            Ok(Container::Pdf(document)) => document.outline().unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    /// Decodes one page to RGBA, at most `edge` on its longest edge, with the reader's
    /// adjustments applied. `view` is the longest edge of the view in logical pixels and
    /// its scale factor: a PDF page renders to fill it (`pdf_scale`); a comic page is
    /// decoded as stored. Blocks: call it from a worker. The reason names the codec when
    /// the bytes say which.
    pub fn decode_adjusted(
        &self,
        index: usize,
        edge: u32,
        view: (i32, i32),
        adjustments: &ImageAdjustments,
    ) -> Result<DecodedPage, String> {
        let open = self
            .open
            .lock()
            .map_err(|_| "the publication is no longer readable".to_owned())?;
        let page = match &*open {
            Container::Comic(open) => open
                .decode_page(index, Some(edge))
                .map_err(|error| error.to_string())?,
            Container::Pdf(document) => {
                let index = u32::try_from(index).unwrap_or(u32::MAX);
                let (width, height) = document.page_size(index).unwrap_or((1.0, 1.0));
                let scale = pdf_scale(width.max(height), view.0, view.1);
                document
                    .render_page_scaled(index, scale, Some(edge))
                    .map_err(|error| error.to_string())?
            }
        };
        Ok(if adjustments.is_neutral() {
            page
        } else {
            image::adjusted(&page, adjustments)
        })
    }

    /// Decodes one page to RGBA, at most [`MAX_DECODE_EDGE`] on its longest edge.
    #[cfg(test)]
    pub fn decode(&self, index: usize) -> Result<DecodedPage, String> {
        self.decode_adjusted(index, MAX_DECODE_EDGE, (0, 1), &ImageAdjustments::default())
    }

    /// Every page's shape from its header, without decoding: what continuous scroll
    /// lays the strip out with. A page whose header cannot be read takes a portrait shape.
    pub fn page_sizes(&self) -> Vec<(i32, i32)> {
        let Ok(open) = self.open.lock() else {
            return Vec::new();
        };
        match &*open {
            Container::Comic(open) => (0..open.page_count())
                .map(|index| {
                    open.page_size(index).map_or((2, 3), |size| {
                        (
                            i32::try_from(size.width).unwrap_or(2),
                            i32::try_from(size.height).unwrap_or(3),
                        )
                    })
                })
                .collect(),
            Container::Pdf(document) => (0..document.page_count())
                .map(|index| {
                    document.page_size(index).map_or((2, 3), |(width, height)| {
                        (
                            width.round().max(1.0) as i32,
                            height.round().max(1.0) as i32,
                        )
                    })
                })
                .collect(),
        }
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

/// The chapter markers a PDF outline gives: each top-level entry that names a page,
/// deduplicated by page, with the first title for that page.
fn outline_markers(outline: &[PdfOutlineEntry]) -> Vec<Marker> {
    let mut titles = std::collections::HashMap::new();
    let mut starts = Vec::new();
    for entry in outline {
        if let Some(page) = entry.page {
            let page = page as usize;
            starts.push(page);
            titles.entry(page).or_insert_with(|| entry.title.clone());
        }
    }
    chapters::markers(&starts, &titles)
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

    /// The corpus PDF through the window's own publication, or `None` where the pinned
    /// PDFium is not on disk (`pnpm pdfium:fetch`; the container build fetches it).
    fn pdf(name: &str) -> Option<Publication> {
        if PdfEngine::start(None).is_err() {
            eprintln!("skipped: no PDFium library (STORYARC_PDFIUM_DIR); run pnpm pdfium:fetch");
            return None;
        }
        Some(Publication::open(&fixture(name)).expect("the corpus PDF opens"))
    }

    #[test]
    fn a_scale_of_two_asks_the_pdf_for_twice_the_pixels() {
        assert_eq!(pdf_scale(792.0, 0, 1), 1.0);
        assert_eq!(pdf_scale(792.0, 0, 2), 2.0);
        assert_eq!(pdf_scale(792.0, 1584, 1), 2.0, "a large window fills");
        assert_eq!(
            pdf_scale(792.0, 400, 2),
            2.0,
            "never under the scale factor"
        );
        let Some(book) = pdf("text-pages.pdf") else {
            return;
        };
        let neutral = ImageAdjustments::default();
        let at = |edge, view| book.decode_adjusted(0, edge, view, &neutral).unwrap();
        let one = at(MAX_DECODE_EDGE, (0, 1));
        let two = at(MAX_DECODE_EDGE, (0, 2));
        assert_eq!((one.width, one.height), (612, 792));
        assert_eq!((two.width, two.height), (1224, 1584));
        assert_eq!(at(1000, (0, 2)).height, 1000, "the edge cap holds");
    }

    #[test]
    fn the_text_pdf_reads_as_the_phones_read_it_at_the_window() {
        let Some(book) = pdf("text-pages.pdf") else {
            return;
        };
        assert!(book.is_pdf());
        assert_eq!(book.page_count, 3);
        assert_eq!(book.page_sizes(), vec![(612, 792); 3]);
        assert!(book.has_text_layer());
        let texts: Vec<String> = (0..3)
            .map(|i| book.page_text(i).trim().to_owned())
            .collect();
        assert_eq!(texts, ["Chapter One", "Chapter Two", "Chapter Three"]);
        let titles: Vec<Option<String>> = book.markers.iter().map(|m| m.title.clone()).collect();
        assert_eq!(
            titles,
            [
                Some("Chapter One".into()),
                Some("Chapter Two".into()),
                Some("Chapter Three".into())
            ]
        );
        assert_eq!(
            book.markers.iter().map(|m| m.index).collect::<Vec<_>>(),
            [0, 1, 2]
        );
        assert_eq!(book.outline().len(), 3);
        let hits = book.search("chapter two");
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].page, 1);
        assert_eq!(
            book.search("Chapter")
                .iter()
                .map(|h| h.page)
                .collect::<Vec<_>>(),
            [0, 1, 2]
        );
        assert!(book.search("nowhere").is_empty());
        // The core renders one pixel per point and never upscales (`ebook-reader`, A
        // rendered page is bounded by what it is shown at), so the page view scales it.
        let page = book.decode(0).expect("the first page renders");
        assert_eq!((page.width, page.height), (612, 792));
    }

    #[test]
    fn the_image_pdf_reads_as_a_comic_with_no_text_controls() {
        let Some(book) = pdf("image-pages.pdf") else {
            return;
        };
        assert_eq!(book.page_count, 3);
        assert_eq!(book.page_sizes(), vec![(200, 300); 3]);
        assert!(!book.has_text_layer());
        assert!(book.markers.is_empty());
        assert!(book.search("anything").is_empty());
        let page = book.decode(1).expect("an image page renders");
        assert_eq!((page.width, page.height), (200, 300));
    }

    #[test]
    fn bytes_that_are_not_a_pdf_are_refused_by_name() {
        if PdfEngine::start(None).is_err() {
            return;
        }
        let dir = tempfile::tempdir().expect("a folder");
        let path = dir.path().join("not-really.pdf");
        std::fs::write(&path, b"%PDF-1.7 but then nothing of the sort").expect("written");
        let refusal = Publication::open(&path).expect_err("refused");
        assert!(refusal.starts_with("not-really.pdf: "), "{refusal}");
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
        let page = publication
            .decode_adjusted(0, 256, (0, 1), &grey)
            .expect("decodes");
        assert!(page.width.max(page.height) <= 256);
        assert!(
            page.rgba
                .chunks(4)
                .all(|pixel| pixel[0] == pixel[1] && pixel[1] == pixel[2]),
            "greyscale reached every pixel"
        );
        let sizes = publication.page_sizes();
        assert_eq!(sizes.len(), publication.page_count as usize);
        assert!(
            sizes
                .iter()
                .all(|(width, height)| *width > 0 && *height > 0)
        );
        assert!(
            publication.markers.is_empty(),
            "the fixture declares no chapters"
        );
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
