//! The archive level of a comic fixture (task 1.6): the page list, its order, what was
//! skipped, the named refusals, `ComicInfo.xml` and the cover. The twin of iOS's
//! `ComicArchiveTests`, `ComicInfoTests` and `CoverSelectionTests`.

use storyarc_core::domain::ReadingDirection;
use storyarc_core::formats::{ComicArchive, ComicArchiveError, Container, PageCodec};

use super::comics::{PNG_SIGNATURE, expect};
use super::manifest::{self, Comic, ComicInfoExpectation};

pub fn check(fixture: &Comic) -> Result<(), String> {
    let path = manifest::path(&fixture.file);
    let archive = match (ComicArchive::open_file(&path), &fixture.expected_refusal) {
        (Ok(archive), None) => archive,
        (Ok(_), Some(refusal)) => return Err(format!("opened, but should be refused: {refusal}")),
        (Err(error), Some(refusal)) => return check_refusal(&error, refusal),
        (Err(error), None) => return Err(format!("open: {error}")),
    };

    let paths: Vec<&str> = archive.pages().iter().map(|p| p.path.as_str()).collect();
    if let Some(count) = fixture.expected_page_count {
        expect("page count", paths.len(), count)?;
    }
    if let Some(order) = &fixture.expected_page_order {
        let order: Vec<&str> = order.iter().map(String::as_str).collect();
        expect("page order", paths.clone(), order)?;
    }
    expect(
        "skipped pages",
        archive.skipped_page_count(),
        fixture.expected_skipped_page_count.unwrap_or(0),
    )?;
    if fixture.is_recoverable == Some(true) {
        let ComicArchive::Zip(zip) = &archive else {
            return Err("a truncated CBZ did not open as a ZIP".to_owned());
        };
        expect("recovered", zip.is_recovered, true)?;
        // 60% of a 12-page archive: some pages survived and some did not.
        if archive.pages().is_empty() || archive.pages().len() >= 12 {
            return Err(format!("recovered {} pages", archive.pages().len()));
        }
    } else if let ComicArchive::Zip(zip) = &archive {
        expect("recovered", zip.is_recovered, false)?;
    }

    // Every listed page's bytes come out, and are the PNG that was packed — unless the
    // fixture packed a codec nothing decodes, which stays a page and is named.
    for page in archive.pages() {
        let data = archive
            .data(page)
            .map_err(|e| format!("{}: {e}", page.path))?;
        if page.path.ends_with(".png") {
            expect(
                &format!("{} starts as a PNG", page.path),
                data.starts_with(&PNG_SIGNATURE),
                true,
            )?;
        } else if let Some(codec) = &fixture.expected_undecodable_codec {
            expect(
                &format!("{} is named", page.path),
                PageCodec::name(Some(&data), &page.path),
                Some(codec.as_str()),
            )?;
        }
    }

    check_rar_flags(fixture, &archive)?;
    check_metadata(fixture, &archive)?;
    check_cover(fixture, &archive)
}

/// `publication-formats` forbids a generic failure: each refusal has its own name.
fn check_refusal(error: &ComicArchiveError, refusal: &str) -> Result<(), String> {
    let matches = match refusal {
        "passwordProtected" => *error == ComicArchiveError::PasswordProtected,
        // The manifest's sentence is the generator's note; what the spec requires is a typed
        // refusal that carries the container's name, and iOS asserts exactly that.
        "7z archives are not supported" => {
            *error == ComicArchiveError::UnsupportedContainer(Container::SevenZip)
                && Container::SevenZip.display_name() == "7-Zip"
        }
        "This comic uses solid compression, which cannot be opened" => {
            *error == ComicArchiveError::SolidArchive
        }
        other => {
            return Err(format!(
                "the manifest names a refusal this harness does not know: {other}"
            ));
        }
    };
    if matches {
        Ok(())
    } else {
        Err(format!("refused as {error:?}, want {refusal}"))
    }
}

fn check_rar_flags(fixture: &Comic, archive: &ComicArchive) -> Result<(), String> {
    let ComicArchive::Rar(rar) = archive else {
        return Ok(());
    };
    if let Some(streamable) = fixture.is_streamable {
        expect("streamable", rar.is_streamable, streamable)?;
    }
    // Opened from a local file, so nothing is download-only even when solid.
    expect("download only", rar.is_download_only, false)
}

fn check_metadata(fixture: &Comic, archive: &ComicArchive) -> Result<(), String> {
    let info = archive.comic_info();
    expect(
        "has ComicInfo",
        info.is_some(),
        fixture.has_comic_info == Some(true),
    )?;
    let Some(info) = info else {
        return Ok(());
    };
    expect(
        "series",
        info.series.clone(),
        fixture.expected_series.clone(),
    )?;
    let Some(want) = &fixture.expected_comic_info else {
        return Ok(());
    };
    check_fields(info, want)
}

fn check_fields(
    info: &storyarc_core::formats::ComicInfo,
    want: &ComicInfoExpectation,
) -> Result<(), String> {
    expect("series", info.series.clone(), want.series.clone())?;
    expect("number", info.number.clone(), want.number.clone())?;
    if want.volume.is_some() {
        expect("volume", info.volume, want.volume)?;
    }
    if want.title.is_some() {
        expect("title", info.title.clone(), want.title.clone())?;
    }
    if want.summary.is_some() {
        expect("summary", info.summary.clone(), want.summary.clone())?;
    }
    if let Some(writers) = &want.writers {
        expect("writers", info.writers.clone(), writers.clone())?;
    }
    if let Some(penciller) = &want.penciller {
        expect(
            "pencillers",
            info.pencillers.clone(),
            vec![penciller.clone()],
        )?;
    }
    if want.publisher.is_some() {
        expect("publisher", info.publisher.clone(), want.publisher.clone())?;
    }
    for (name, got, wanted) in [
        ("year", info.year, want.year),
        ("month", info.month, want.month),
        ("day", info.day, want.day),
        ("page count", info.page_count, want.page_count),
    ] {
        if wanted.is_some() {
            expect(name, got, wanted)?;
        }
    }
    if want.language.is_some() {
        expect("language", info.language.clone(), want.language.clone())?;
    }
    if let Some(direction) = &want.reading_direction {
        let got = info.reading_direction();
        expect("reading direction", got.manifest_name(), direction.as_str())?;
        if got == ReadingDirection::RightToLeft && info.declared_direction.is_none() {
            // The second branch of the rule: Japanese with no declaration.
            expect(
                "japanese",
                info.language.as_deref().map(|l| l.starts_with("ja")),
                Some(true),
            )?;
        }
    }
    expect(
        "cover page index",
        info.cover_page_index,
        want.cover_page_index,
    )?;
    if let Some(spreads) = &want.double_page_indices {
        expect(
            "double pages",
            info.double_page_indices.clone(),
            spreads.clone(),
        )?;
    }
    Ok(())
}

/// The cover: the first page in reading order, unless `ComicInfo.xml` designates another,
/// and its bytes are the page's bytes.
fn check_cover(fixture: &Comic, archive: &ComicArchive) -> Result<(), String> {
    let designated = fixture
        .expected_comic_info
        .as_ref()
        .and_then(|info| info.cover_page_index);
    let want = match designated {
        Some(index) => archive.pages().get(index),
        None => archive.pages().first(),
    };
    expect("cover page", archive.cover_page(), want)?;
    let Some(cover) = archive.cover_page() else {
        return Ok(());
    };
    let data = archive.data(cover).map_err(|e| e.to_string())?;
    expect(
        "cover bytes",
        Some(data.len() as u64),
        cover.byte_count.or(Some(data.len() as u64)),
    )?;
    if cover.path.ends_with(".png") {
        expect("cover is a PNG", data.starts_with(&PNG_SIGNATURE), true)?;
    }
    if let Some(spreads) = &fixture.spread_indices {
        // The manifest's spreads are aspect-ratio facts for the decoder of a later task;
        // a ComicInfo-declared spread is a statement, and only the statement is read here.
        let declared = archive.double_page_indices();
        if !declared.is_empty() {
            expect("declared spreads", declared, spreads.clone())?;
        }
    }
    Ok(())
}
