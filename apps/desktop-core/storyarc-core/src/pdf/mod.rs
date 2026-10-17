//! PDF for Windows and Linux through PDFium (design.md, Decision 7; task 4.4 of
//! `desktop-clients`): page rendering, text, search and the outline. macOS keeps PDFKit.
//!
//! **One thread.** PDFium is not thread safe, so the engine owns one thread, started once
//! per process, and every call here is a message to it answered before the call returns.
//! A call from the interface thread would wait on that thread, so the apps make them off
//! it, as with everything else in the core.
//!
//! **Read + Seek over a source.** PDFium reads a file through callbacks, and `reader`
//! turns a `RandomAccessSource` into the `Read + Seek` it asks for. PDFium reads the
//! trailer, the cross-reference table and then only the objects a page needs, so the
//! first page of a large file on a share shows after a few ranged reads rather than a
//! transfer of the whole file; `tests/pdf.rs` counts the bytes to prove it.
//!
//! **The library.** `pdfium-render` binds at run time to the PDFium library the desktop
//! builds bundle (`apps/desktop-core/pdfium/pin.json`). The engine looks in the folder it
//! is given, then `STORYARC_PDFIUM_DIR`, then beside the running executable, then the
//! system's library path; `scripts/pdfium-fetch.mjs` puts the pinned one on a dev machine.

mod engine;
mod reader;

pub use engine::{PdfDocument, PdfEngine, PdfError, PdfMatch, PdfOutlineEntry, PdfRect};
pub use reader::SourceReader;
