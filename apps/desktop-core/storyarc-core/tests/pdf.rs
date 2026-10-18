//! Task 4.4 of `desktop-clients`: PDF through PDFium on one thread, read through a
//! `RandomAccessSource`. The corpus PDFs pin the text and the outline the phones read;
//! a file built here, with a large image on its last page, proves the first page shows
//! after a few ranged reads and not after the whole file.
//!
//! The PDFium library is bound at run time. The tests look for it in `STORYARC_PDFIUM_DIR`
//! or under `.build/pdfium/<platform>/lib`, where `pnpm pdfium:fetch` puts the pinned one,
//! and each case skips with a line on stderr when neither holds it.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use storyarc_core::io::{FileSource, MemorySource, RandomAccessSource, SourceError};
use storyarc_core::pdf::{PdfEngine, PdfError};

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

/// The folder the pinned library sits in on this machine, if it was fetched.
fn library_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("STORYARC_PDFIUM_DIR") {
        return Some(PathBuf::from(dir));
    }
    let os = match std::env::consts::OS {
        "macos" => "mac",
        "linux" => "linux",
        "windows" => "win",
        _ => return None,
    };
    let arch = match std::env::consts::ARCH {
        "aarch64" => "arm64",
        "x86_64" => "x64",
        _ => return None,
    };
    let folder = if os == "win" { "bin" } else { "lib" };
    let dir = corpus::manifest::root()
        .parent()?
        .parent()?
        .join(".build/pdfium")
        .join(format!("{os}-{arch}"))
        .join(folder);
    dir.is_dir().then_some(dir)
}

fn engine() -> Option<&'static PdfEngine> {
    let dir = library_dir();
    match PdfEngine::start(dir.as_deref()) {
        Ok(engine) => Some(engine),
        Err(PdfError::EngineUnavailable(why)) if dir.is_none() => {
            eprintln!("skipped: no PDFium library on this machine, run pnpm pdfium:fetch ({why})");
            None
        }
        Err(error) => panic!("the PDF engine did not start: {error}"),
    }
}

fn open(file: &str) -> Option<storyarc_core::pdf::PdfDocument> {
    let engine = engine()?;
    let source = FileSource::open(corpus::manifest::path(file)).unwrap();
    Some(
        engine
            .open(Arc::new(source))
            .unwrap_or_else(|e| panic!("{file}: {e}")),
    )
}

#[test]
fn the_text_pdf_reads_as_the_phones_read_it() {
    let Some(document) = open("comics/text-pages.pdf") else {
        return;
    };
    let fixture = corpus::manifest::pdf("comics/text-pages.pdf");
    assert_eq!(document.page_count(), fixture.expected_page_count as u32);
    let (width, height) = document.page_size(0).unwrap();
    assert_eq!(
        (width as u32, height as u32),
        (
            fixture.expected_page_size_points[0],
            fixture.expected_page_size_points[1]
        )
    );
    assert_eq!(document.has_text_layer().unwrap(), fixture.has_text_layer);
    let texts: Vec<String> = (0..document.page_count())
        .map(|i| document.page_text(i).unwrap().trim().to_owned())
        .collect();
    assert_eq!(texts, fixture.expected_page_text.clone().unwrap());

    let outline = document.outline().unwrap();
    let titles: Vec<&str> = outline.iter().map(|e| e.title.as_str()).collect();
    let want: Vec<&str> = fixture
        .expected_outline_titles
        .as_ref()
        .unwrap()
        .iter()
        .map(String::as_str)
        .collect();
    assert_eq!(titles, want);
    assert_eq!(
        outline.iter().map(|e| e.page).collect::<Vec<_>>(),
        [Some(0), Some(1), Some(2)]
    );
    assert!(outline.iter().all(|e| e.children.is_empty()));
}

#[test]
fn search_finds_a_phrase_on_its_page_with_its_rectangles() {
    let Some(document) = open("comics/text-pages.pdf") else {
        return;
    };
    let hits = document.search("chapter two").unwrap();
    assert_eq!(hits.len(), 1, "{hits:?}");
    assert_eq!(hits[0].page, 1);
    let rect = hits[0].rects[0];
    assert!(rect.right > rect.left && rect.top > rect.bottom, "{rect:?}");
    // The text sits at 72, 700 in a 612 by 792 page.
    assert!(rect.left >= 70.0 && rect.left < 80.0, "{rect:?}");
    assert!(rect.bottom > 690.0 && rect.top < 730.0, "{rect:?}");

    let every = document.search("Chapter").unwrap();
    assert_eq!(
        every.iter().map(|hit| hit.page).collect::<Vec<_>>(),
        [0, 1, 2]
    );
    assert!(document.search("  ").unwrap().is_empty());
    assert!(document.search("nowhere").unwrap().is_empty());
}

#[test]
fn the_image_pdf_reads_as_a_comic_with_no_text_layer() {
    let Some(document) = open("comics/image-pages.pdf") else {
        return;
    };
    let fixture = corpus::manifest::pdf("comics/image-pages.pdf");
    assert_eq!(document.page_count(), fixture.expected_page_count as u32);
    let (width, height) = document.page_size(0).unwrap();
    assert_eq!((width as u32, height as u32), (200, 300));
    assert!(!document.has_text_layer().unwrap());
    assert_eq!(document.page_text(0).unwrap().trim(), "");
    assert!(document.outline().unwrap().is_empty());

    let page = document.render_page(0, Some(150)).unwrap();
    assert_eq!((page.width, page.height), (100, 150));
    assert_eq!(page.rgba.len(), 100 * 150 * 4);
    let full = document.render_page(0, None).unwrap();
    assert_eq!((full.width, full.height), (200, 300));
    assert!(full.rgba.chunks(4).all(|px| px[3] == 255), "opaque pixels");
}

#[test]
fn a_page_renders_at_device_scale_and_the_edge_cap_holds() {
    let Some(document) = open("comics/text-pages.pdf") else {
        return;
    };
    let one = document.render_page_scaled(0, 1.0, None).unwrap();
    assert_eq!((one.width, one.height), (612, 792));
    let two = document.render_page_scaled(0, 2.0, None).unwrap();
    assert_eq!((two.width, two.height), (one.width * 2, one.height * 2));
    assert_eq!(two.rgba.len(), 1224 * 1584 * 4);
    assert_eq!(
        two.width as f32 / two.height as f32,
        one.width as f32 / one.height as f32
    );

    // The cap wins over the scale: 792 * 4 would be 3168 on the long edge.
    let capped = document.render_page_scaled(0, 4.0, Some(1000)).unwrap();
    assert_eq!((capped.width, capped.height), (773, 1000));
    // A scale that fits under the cap is left alone.
    let under = document.render_page_scaled(0, 1.5, Some(4000)).unwrap();
    assert_eq!((under.width, under.height), (918, 1188));
    // The old call is the one-pixel-a-point case.
    let plain = document.render_page(0, None).unwrap();
    assert_eq!((plain.width, plain.height), (one.width, one.height));
}

#[test]
fn a_page_past_the_end_is_named_rather_than_rendered() {
    let Some(document) = open("comics/text-pages.pdf") else {
        return;
    };
    assert_eq!(
        document.render_page(3, None).err(),
        Some(PdfError::PageOutOfRange { index: 3, count: 3 })
    );
    assert_eq!(
        document.page_text(9).err(),
        Some(PdfError::PageOutOfRange { index: 9, count: 3 })
    );
}

#[test]
fn bytes_that_are_not_a_pdf_are_refused() {
    let Some(engine) = engine() else {
        return;
    };
    let source = MemorySource::new(vec![b'A'; 2048]);
    assert!(matches!(
        engine.open(Arc::new(source)).err(),
        Some(PdfError::Unreadable(_))
    ));
}

/// A source that counts what is read of it.
struct Counting {
    inner: MemorySource,
    bytes: AtomicU64,
}

impl RandomAccessSource for Counting {
    fn length(&self) -> u64 {
        self.inner.length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        let bytes = self.inner.read(offset, count)?;
        self.bytes.fetch_add(bytes.len() as u64, Ordering::Relaxed);
        Ok(bytes)
    }
}

/// A PDF in the corpus generator's own shape: three pages, the first two with a line of
/// text and the last with an image whose raw stream is `image_bytes` long.
fn large_pdf(image_bytes: usize) -> Vec<u8> {
    let (width, height) = (4096usize, image_bytes / 4096);
    let mut objects: Vec<Vec<u8>> = Vec::new();
    objects.push(b"<< /Type /Catalog /Pages 2 0 R >>".to_vec());
    objects.push(b"<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>".to_vec());
    let font = b"/Resources << /Font << /F1 10 0 R >> >>";
    for (page_object, content_object, text) in [(3, 4, "Page One"), (5, 6, "Page Two")] {
        let _ = page_object;
        let content = format!("BT /F1 24 Tf 72 700 Td ({text}) Tj ET");
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {content_object} 0 R {} >>",
                String::from_utf8_lossy(font)
            )
            .into_bytes(),
        );
        objects.push(
            format!(
                "<< /Length {} >>\nstream\n{content}\nendstream",
                content.len()
            )
            .into_bytes(),
        );
    }
    objects.push(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 8 0 R /Resources << /XObject << /Im1 9 0 R >> >> >>".to_vec(),
    );
    let draw = "q 612 0 0 792 0 0 cm /Im1 Do Q";
    objects.push(format!("<< /Length {} >>\nstream\n{draw}\nendstream", draw.len()).into_bytes());
    let mut image = format!(
        "<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceGray /BitsPerComponent 8 /Length {} >>\nstream\n",
        width * height
    )
    .into_bytes();
    image.resize(image.len() + width * height, 0x80);
    image.extend_from_slice(b"\nendstream");
    objects.push(image);
    objects.push(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_vec());

    let mut out = b"%PDF-1.7\n".to_vec();
    let mut offsets = Vec::new();
    for (index, object) in objects.iter().enumerate() {
        offsets.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n", index + 1).as_bytes());
        out.extend_from_slice(object);
        out.extend_from_slice(b"\nendobj\n");
    }
    let xref = out.len();
    out.extend_from_slice(
        format!("xref\n0 {}\n0000000000 65535 f \n", objects.len() + 1).as_bytes(),
    );
    for offset in offsets {
        out.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }
    out.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
            objects.len() + 1
        )
        .as_bytes(),
    );
    out
}

#[test]
fn the_first_page_of_a_large_file_shows_without_the_whole_file() {
    let Some(engine) = engine() else {
        return;
    };
    let bytes = large_pdf(48 * 1024 * 1024);
    let length = bytes.len() as u64;
    let source = Arc::new(Counting {
        inner: MemorySource::new(bytes),
        bytes: AtomicU64::new(0),
    });
    let document = engine.open(source.clone()).unwrap();
    assert_eq!(document.page_count(), 3);
    let page = document.render_page(0, Some(300)).unwrap();
    assert_eq!(page.width, 232);
    assert_eq!(document.page_text(0).unwrap().trim(), "Page One");

    let read = source.bytes.load(Ordering::Relaxed);
    eprintln!("first page: read {read} of {length} bytes");
    assert!(
        read < length / 10,
        "read {read} of {length} bytes for the first page"
    );

    // The last page needs the image, and reads it.
    let last = document.render_page(2, Some(64)).unwrap();
    assert_eq!(last.rgba[0], 0x80);
    assert!(source.bytes.load(Ordering::Relaxed) > length / 2);
}
