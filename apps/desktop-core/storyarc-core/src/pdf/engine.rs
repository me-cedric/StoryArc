//! The PDF thread and the documents it holds.

use std::collections::HashMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

use pdfium_render::prelude::{
    PdfBookmark, PdfRenderConfig, PdfSearchDirection, PdfSearchOptions, Pdfium, PdfiumError,
    PdfiumLibraryBindings,
};
use serde::Serialize;

use crate::image::DecodedPage;
use crate::io::RandomAccessSource;

use super::reader::SourceReader;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PdfError {
    /// The PDFium library could not be loaded. The message says where it was looked for.
    EngineUnavailable(String),
    /// The file is not a PDF this engine can open: damaged, encrypted, or not a PDF.
    Unreadable(String),
    /// A page index at or past the document's page count.
    PageOutOfRange { index: u32, count: u32 },
    /// The document was closed, or the PDF thread is gone.
    Closed,
}

impl fmt::Display for PdfError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EngineUnavailable(why) => write!(f, "the PDF engine is unavailable: {why}"),
            Self::Unreadable(why) => write!(f, "the PDF cannot be read: {why}"),
            Self::PageOutOfRange { index, count } => {
                write!(f, "page {index} asked of a document of {count} pages")
            }
            Self::Closed => f.write_str("the PDF document is closed"),
        }
    }
}

impl std::error::Error for PdfError {}

/// A rectangle on a page in PDF points, origin at the page's bottom left.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct PdfRect {
    pub left: f32,
    pub bottom: f32,
    pub right: f32,
    pub top: f32,
}

/// One hit of a search: the page and the rectangles of its text.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PdfMatch {
    pub page: u32,
    pub rects: Vec<PdfRect>,
}

/// One outline entry, with its page when the entry names one and its children.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PdfOutlineEntry {
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub page: Option<u32>,
    pub children: Vec<PdfOutlineEntry>,
}

/// Work the PDF thread runs, with the answer sent back on a channel inside the job.
type Job = Box<dyn FnOnce(&mut Worker) + Send>;

/// What the PDF thread owns: the library and every open document, by id.
struct Worker {
    pdfium: &'static Pdfium,
    documents: HashMap<u64, pdfium_render::prelude::PdfDocument<'static>>,
    next_id: u64,
}

/// The engine: one thread, started once per process.
pub struct PdfEngine {
    jobs: Mutex<Sender<Job>>,
}

static ENGINE: OnceLock<Result<PdfEngine, PdfError>> = OnceLock::new();

/// The deepest outline the engine reports, and the most entries, so a cyclic or absurd
/// outline in an untrusted file ends.
const OUTLINE_DEPTH: usize = 16;
const OUTLINE_ENTRIES: usize = 10_000;

impl PdfEngine {
    /// Starts the engine, or hands back the one already running. `library_dir` is the
    /// folder holding `libpdfium.so`, `libpdfium.dylib` or `pdfium.dll`; without one the
    /// engine tries `STORYARC_PDFIUM_DIR`, the running executable's folder, then the system.
    /// The first call decides the library for the process; later calls ignore the folder.
    pub fn start(library_dir: Option<&Path>) -> Result<&'static PdfEngine, PdfError> {
        let dir = library_dir.map(Path::to_path_buf);
        ENGINE
            .get_or_init(|| Self::spawn(dir))
            .as_ref()
            .map_err(Clone::clone)
    }

    fn spawn(library_dir: Option<PathBuf>) -> Result<PdfEngine, PdfError> {
        let (jobs, inbox) = mpsc::channel::<Job>();
        let (started, ready) = mpsc::channel::<Result<(), PdfError>>();
        let spawned = thread::Builder::new()
            .name("storyarc-pdf".to_owned())
            .spawn(move || {
                let bindings = match bind(library_dir.as_deref()) {
                    Ok(bindings) => bindings,
                    Err(error) => {
                        let _ = started.send(Err(error));
                        return;
                    }
                };
                // The library lives as long as the process; a leak is the honest lifetime.
                let pdfium: &'static Pdfium = Box::leak(Box::new(Pdfium::new(bindings)));
                let _ = started.send(Ok(()));
                let mut worker = Worker {
                    pdfium,
                    documents: HashMap::new(),
                    next_id: 1,
                };
                while let Ok(job) = inbox.recv() {
                    job(&mut worker);
                }
            });
        if let Err(error) = spawned {
            return Err(PdfError::EngineUnavailable(error.to_string()));
        }
        ready.recv().map_err(|_| PdfError::Closed)??;
        Ok(PdfEngine {
            jobs: Mutex::new(jobs),
        })
    }

    /// Runs `job` on the PDF thread and waits for its answer.
    fn run<T: Send + 'static>(
        &self,
        job: impl FnOnce(&mut Worker) -> T + Send + 'static,
    ) -> Result<T, PdfError> {
        let (reply, answer) = mpsc::sync_channel(1);
        let boxed: Job = Box::new(move |worker| {
            let _ = reply.send(job(worker));
        });
        self.jobs
            .lock()
            .map_err(|_| PdfError::Closed)?
            .send(boxed)
            .map_err(|_| PdfError::Closed)?;
        answer.recv().map_err(|_| PdfError::Closed)
    }

    /// Opens a document over a source. The source is read as pages are asked for.
    pub fn open(
        &'static self,
        source: Arc<dyn RandomAccessSource>,
    ) -> Result<PdfDocument, PdfError> {
        let (id, page_count) = self.run(move |worker| {
            let document = worker
                .pdfium
                .load_pdf_from_reader(SourceReader::new(source), None)
                .map_err(|e| PdfError::Unreadable(describe(&e)))?;
            let page_count = u32::try_from(document.pages().len()).unwrap_or(0);
            let id = worker.next_id;
            worker.next_id += 1;
            worker.documents.insert(id, document);
            Ok::<_, PdfError>((id, page_count))
        })??;
        Ok(PdfDocument {
            engine: self,
            id,
            page_count,
        })
    }
}

/// The bindings, from the first place a library is found.
fn bind(library_dir: Option<&Path>) -> Result<Box<dyn PdfiumLibraryBindings>, PdfError> {
    let mut tried = Vec::new();
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(dir) = library_dir {
        candidates.push(dir.to_path_buf());
    }
    if let Some(dir) = std::env::var_os("STORYARC_PDFIUM_DIR") {
        candidates.push(PathBuf::from(dir));
    }
    if let Some(dir) = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf))
    {
        candidates.push(dir);
    }
    for dir in candidates {
        let path = Pdfium::pdfium_platform_library_name_at_path(&dir);
        match Pdfium::bind_to_library(&path) {
            Ok(bindings) => return Ok(bindings),
            Err(error) => tried.push(format!("{}: {}", path.display(), describe(&error))),
        }
    }
    Pdfium::bind_to_system_library().map_err(|error| {
        tried.push(format!("system library: {}", describe(&error)));
        PdfError::EngineUnavailable(tried.join("; "))
    })
}

fn describe(error: &PdfiumError) -> String {
    match error {
        PdfiumError::LoadLibraryError(inner) => inner.to_string(),
        other => other.to_string(),
    }
}

/// One open document. Every call runs on the PDF thread; dropping it closes the document.
pub struct PdfDocument {
    engine: &'static PdfEngine,
    id: u64,
    page_count: u32,
}

impl PdfDocument {
    pub fn page_count(&self) -> u32 {
        self.page_count
    }

    fn check(&self, index: u32) -> Result<(), PdfError> {
        if index < self.page_count {
            Ok(())
        } else {
            Err(PdfError::PageOutOfRange {
                index,
                count: self.page_count,
            })
        }
    }

    /// Runs `job` over this document on the PDF thread.
    fn with<T: Send + 'static>(
        &self,
        job: impl FnOnce(&pdfium_render::prelude::PdfDocument<'static>) -> Result<T, PdfError>
        + Send
        + 'static,
    ) -> Result<T, PdfError> {
        let id = self.id;
        self.engine.run(move |worker| {
            let document = worker.documents.get(&id).ok_or(PdfError::Closed)?;
            job(document)
        })?
    }

    /// The page's size in PDF points, width then height.
    pub fn page_size(&self, index: u32) -> Result<(f32, f32), PdfError> {
        self.check(index)?;
        self.with(move |document| {
            let page = page_at(document, index)?;
            Ok((page.width().value, page.height().value))
        })
    }

    /// Renders a page to 8-bit RGBA, not premultiplied, at one pixel per point, shrunk to
    /// at most `max_pixel_size` on its longest edge when one is given. Never upscales.
    pub fn render_page(
        &self,
        index: u32,
        max_pixel_size: Option<u32>,
    ) -> Result<DecodedPage, PdfError> {
        self.render_page_scaled(index, 1.0, max_pixel_size)
    }

    /// Renders a page to 8-bit RGBA, not premultiplied, at `scale` device pixels per point
    /// (2.0 on a high-density window), then shrunk to at most `max_edge` pixels on its
    /// longest edge when one is given. A scale at or under zero renders at one pixel a point.
    pub fn render_page_scaled(
        &self,
        index: u32,
        scale: f32,
        max_edge: Option<u32>,
    ) -> Result<DecodedPage, PdfError> {
        self.check(index)?;
        self.with(move |document| {
            let page = page_at(document, index)?;
            let (width, height) = (page.width().value.max(1.0), page.height().value.max(1.0));
            let longest = width.max(height);
            let scale = if scale.is_finite() && scale > 0.0 {
                scale
            } else {
                1.0
            };
            let scale = max_edge.map_or(scale, |max| scale.min(max.max(1) as f32 / longest));
            let target_width = (width * scale).round().max(1.0) as i32;
            let target_height = (height * scale).round().max(1.0) as i32;
            let config = PdfRenderConfig::new().set_target_size(target_width, target_height);
            let bitmap = page
                .render_with_config(&config)
                .map_err(|e| PdfError::Unreadable(describe(&e)))?;
            let width = u32::try_from(bitmap.width()).unwrap_or(0);
            let height = u32::try_from(bitmap.height()).unwrap_or(0);
            Ok(DecodedPage {
                width,
                height,
                rgba: bitmap.as_rgba_bytes(),
            })
        })
    }

    /// The page's text, in content order. Empty for a page with no text layer.
    pub fn page_text(&self, index: u32) -> Result<String, PdfError> {
        self.check(index)?;
        self.with(move |document| {
            let page = page_at(document, index)?;
            let text = page
                .text()
                .map_err(|e| PdfError::Unreadable(describe(&e)))?;
            Ok(text.all())
        })
    }

    /// Whether any page carries text, so the apps hide selection and search otherwise.
    pub fn has_text_layer(&self) -> Result<bool, PdfError> {
        self.with(|document| {
            for page in document.pages().iter() {
                if page.text().is_ok_and(|text| !text.all().trim().is_empty()) {
                    return Ok(true);
                }
            }
            Ok(false)
        })
    }

    /// Every hit of `query` in the document, case folded, page by page.
    pub fn search(&self, query: &str) -> Result<Vec<PdfMatch>, PdfError> {
        let query = query.trim().to_owned();
        if query.is_empty() {
            return Ok(Vec::new());
        }
        self.with(move |document| {
            let options = PdfSearchOptions::new().match_case(false);
            let mut hits = Vec::new();
            for (page_index, page) in document.pages().iter().enumerate() {
                let Ok(text) = page.text() else { continue };
                let Ok(search) = text.search(&query, &options) else {
                    continue;
                };
                for segments in search.iter(PdfSearchDirection::SearchForward) {
                    let rects = segments
                        .iter()
                        .map(|segment| {
                            let bounds = segment.bounds();
                            PdfRect {
                                left: bounds.left().value,
                                bottom: bounds.bottom().value,
                                right: bounds.right().value,
                                top: bounds.top().value,
                            }
                        })
                        .collect();
                    hits.push(PdfMatch {
                        page: u32::try_from(page_index).unwrap_or(u32::MAX),
                        rects,
                    });
                }
            }
            Ok(hits)
        })
    }

    /// The document's outline, nested as the file nests it. Empty when it has none.
    pub fn outline(&self) -> Result<Vec<PdfOutlineEntry>, PdfError> {
        self.with(|document| {
            let bookmarks = document.bookmarks();
            let mut budget = OUTLINE_ENTRIES;
            Ok(siblings(bookmarks.root(), 0, &mut budget))
        })
    }
}

impl Drop for PdfDocument {
    fn drop(&mut self) {
        let id = self.id;
        let _ = self.engine.run(move |worker| {
            worker.documents.remove(&id);
        });
    }
}

fn page_at<'a>(
    document: &'a pdfium_render::prelude::PdfDocument<'static>,
    index: u32,
) -> Result<pdfium_render::prelude::PdfPage<'a>, PdfError> {
    let index = i32::try_from(index).map_err(|_| PdfError::PageOutOfRange {
        index,
        count: u32::try_from(document.pages().len()).unwrap_or(0),
    })?;
    document
        .pages()
        .get(index)
        .map_err(|e| PdfError::Unreadable(describe(&e)))
}

/// An entry and every sibling after it, each with its children.
fn siblings(
    first: Option<PdfBookmark<'_>>,
    depth: usize,
    budget: &mut usize,
) -> Vec<PdfOutlineEntry> {
    let mut entries = Vec::new();
    let mut next = first;
    while let Some(bookmark) = next {
        if *budget == 0 {
            break;
        }
        *budget -= 1;
        let page = bookmark
            .destination()
            .and_then(|destination| destination.page_index().ok())
            .and_then(|index| u32::try_from(index).ok());
        let children = if depth + 1 < OUTLINE_DEPTH {
            siblings(bookmark.first_child(), depth + 1, budget)
        } else {
            Vec::new()
        };
        entries.push(PdfOutlineEntry {
            title: bookmark.title().unwrap_or_default(),
            page,
            children,
        });
        next = bookmark.next_sibling();
    }
    entries
}
