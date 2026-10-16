//! What an EPUB fixture must parse to (task 1.6). The twin of iOS's `EpubReaderTests` and
//! `EpubSpineCoverTests`.

use std::sync::Arc;

use storyarc_core::formats::{EpubError, EpubReader};
use storyarc_core::io::FileSource;

use super::comics::{PNG_SIGNATURE, expect};
use super::manifest::{self, Ebook};

pub fn check(fixture: &Ebook) -> Result<(), String> {
    let source = FileSource::open(manifest::path(&fixture.file)).map_err(|e| e.to_string())?;
    let reader = match (
        EpubReader::open(Arc::new(source)),
        &fixture.expected_refusal,
    ) {
        (Ok(reader), None) => reader,
        (Ok(_), Some(refusal)) => return Err(format!("opened, but should be refused: {refusal}")),
        (Err(error), Some(refusal)) => {
            // An EPUB with no container document is named, not opened empty: returning an
            // empty publication would put a book in the library that cannot be opened.
            return match (refusal.as_str(), &error) {
                ("no package document", EpubError::NoPackageDocument) => Ok(()),
                _ => Err(format!("refused as {error:?}, want {refusal}")),
            };
        }
        (Err(error), None) => return Err(format!("open: {error} ({})", fixture.pins)),
    };

    expect("version", reader.version, fixture.epub_version)?;
    expect(
        "spine count",
        reader.spine.len(),
        fixture.expected_spine_count,
    )?;
    expect(
        "title",
        reader.metadata.title.clone(),
        fixture.expected_title.clone(),
    )?;
    expect(
        "author",
        reader.metadata.author.clone(),
        fixture.expected_author.clone(),
    )?;
    expect(
        "language",
        reader.metadata.language.clone(),
        fixture.expected_language.clone(),
    )?;
    expect(
        "identifier",
        reader.metadata.identifier.clone(),
        fixture.expected_identifier.clone(),
    )?;
    // A publication that declares none of these says so, rather than inventing them.
    expect(
        "publisher",
        reader.metadata.publisher.clone(),
        fixture.expected_publisher.clone(),
    )?;
    expect(
        "description",
        reader.metadata.description.clone(),
        fixture.expected_description.clone(),
    )?;
    expect(
        "series",
        reader.metadata.series.clone(),
        fixture.expected_series.clone(),
    )?;
    expect(
        "series index",
        reader.metadata.series_index.clone(),
        fixture.expected_series_index.clone(),
    )?;

    if let Some(hrefs) = &fixture.expected_spine_hrefs {
        // Resolved against the package document's directory, not left relative.
        let got: Vec<&str> = reader.spine.iter().map(|i| i.href.as_str()).collect();
        let want: Vec<&str> = hrefs.iter().map(String::as_str).collect();
        expect("spine hrefs", got, want)?;
    }
    if let Some(titles) = &fixture.expected_toc_titles {
        let got: Vec<&str> = reader.toc.iter().map(|e| e.title.as_str()).collect();
        let want: Vec<&str> = titles.iter().map(String::as_str).collect();
        expect("table of contents", got, want)?;
    }
    for entry in &reader.toc {
        // Hrefs are resolved against their document and drop their fragments. Whether the
        // target exists is the publication's business: `series.epub` lists a chapter its
        // spine does not carry, and the manifest records its titles regardless.
        expect(
            &format!("toc entry {} is resolved", entry.href),
            entry.href.contains('#') || entry.href.contains("../") || entry.href.starts_with("./"),
            false,
        )?;
    }
    expect(
        "nav document",
        reader.has_nav_document,
        fixture.has_nav_document,
    )?;
    expect(
        "fixed layout",
        reader.is_fixed_layout,
        fixture.is_fixed_layout,
    )?;
    expect(
        "page progression direction",
        reader.page_progression_direction.clone(),
        fixture.expected_page_progression_direction.clone(),
    )?;

    // The cover under either convention, and the spine fallback when none is declared.
    expect(
        "cover href",
        reader.cover_href.clone(),
        fixture.expected_cover_href.clone(),
    )?;
    expect(
        "has cover image",
        reader.cover_href.is_some(),
        fixture.has_cover_image,
    )?;
    expect(
        "spine cover href",
        reader.cover_or_spine_href(),
        fixture.expected_spine_cover_href.clone(),
    )?;
    if let Some(href) = reader.cover_or_spine_href() {
        let data = reader.data_at(&href).map_err(|e| e.to_string())?;
        expect("cover is a PNG", data.starts_with(&PNG_SIGNATURE), true)?;
        if reader.cover_href.is_some() {
            expect("cover_data", reader.cover_data(), Some(data))?;
        }
    }

    // A spine item's bytes come back.
    if let Some(first) = reader.spine.first() {
        let data = reader.data_at(&first.href).map_err(|e| e.to_string())?;
        expect(
            "first spine item is XHTML",
            first.media_type.as_str(),
            "application/xhtml+xml",
        )?;
        expect("first spine item has bytes", data.is_empty(), false)?;
    }
    Ok(())
}
