//! What a comic fixture must parse to. Grows with each reader of wave 1, lane C.

use std::sync::Arc;

use storyarc_core::formats::{TarReader, ZipError, ZipReader};
use storyarc_core::io::{FileSource, RandomAccessSource};

use super::manifest::{self, Comic};

pub const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Every assertion the manifest records for one comic archive.
///
/// Returns the first failure as text rather than panicking, so the per-fixture test names
/// the fixture and the pin together.
pub fn check(fixture: &Comic) -> Result<(), String> {
    match container(fixture) {
        "zip" => check_zip(fixture),
        "tar" => check_tar(fixture),
        other => Err(format!(
            "no {other} reader opens {} yet ({})",
            fixture.file, fixture.pins
        )),
    }
}

/// The container the manifest says a fixture really is, falling back to the extension
/// for the ZIP fixtures that record none.
fn container(fixture: &Comic) -> &str {
    match fixture.actual_container.as_deref() {
        Some(named) => named,
        None if fixture.file.ends_with(".cbz") => "zip",
        None => "unknown",
    }
}

fn source(fixture: &Comic) -> Result<Arc<dyn RandomAccessSource>, String> {
    let source = FileSource::open(manifest::path(&fixture.file)).map_err(|e| e.to_string())?;
    Ok(Arc::new(source))
}

fn expect<T: PartialEq + std::fmt::Debug>(what: &str, got: T, want: T) -> Result<(), String> {
    if got == want {
        Ok(())
    } else {
        Err(format!("{what}: got {got:?}, want {want:?}"))
    }
}

/// The container level (task 1.2): the index parses, and every entry's bytes come back the
/// size the central directory recorded, decoding to the PNG that was packed.
fn check_zip(fixture: &Comic) -> Result<(), String> {
    let source = source(fixture)?;

    if fixture.is_recoverable == Some(true) {
        return check_recovered_zip(source);
    }

    let zip = ZipReader::open(source).map_err(|e| format!("open: {e}"))?;
    expect("recovered", zip.is_recovered(), false)?;

    if fixture.expected_refusal.as_deref() == Some("passwordProtected") {
        // `publication-formats`: the archive states that it is protected and nothing is
        // prompted for. The fixture is real ZipCrypto, so a decoder that never checked the
        // flag would hand back ciphertext rather than refuse.
        for entry in zip.entries() {
            expect(
                &format!("{} encrypted", entry.path),
                entry.is_encrypted,
                true,
            )?;
            expect(
                &format!("{} refused", entry.path),
                zip.data(entry).err(),
                Some(ZipError::Encrypted),
            )?;
        }
        return Ok(());
    }

    let paths: Vec<&str> = zip.entries().iter().map(|e| e.path.as_str()).collect();
    for page in fixture.expected_page_order.iter().flatten() {
        if !paths.contains(&page.as_str()) {
            return Err(format!("page {page} is not an entry of the archive"));
        }
    }

    for entry in zip.entries() {
        let data = zip
            .data(entry)
            .map_err(|e| format!("{}: {e}", entry.path))?;
        expect(
            &format!("{} byte count", entry.path),
            data.len() as u64,
            entry.uncompressed_size,
        )?;
        if is_fixture_page(&entry.path) && !data.is_empty() {
            expect(
                &format!("{} starts as a PNG", entry.path),
                data.starts_with(&PNG_SIGNATURE),
                true,
            )?;
        }
    }
    Ok(())
}

/// A page the generator wrote: every fixture page is a PNG, and a resource fork
/// mirroring one is not.
fn is_fixture_page(path: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or(path);
    path.ends_with(".png") && !name.starts_with("._") && !path.starts_with("__MACOSX")
}

/// `truncated.cbz`: the central directory is gone, so the index is rebuilt by scanning and
/// every page it claims really decodes.
fn check_recovered_zip(source: Arc<dyn RandomAccessSource>) -> Result<(), String> {
    expect(
        "an intact open fails",
        ZipReader::open(Arc::clone(&source)).err(),
        Some(ZipError::NoCentralDirectory),
    )?;
    let zip = ZipReader::recovering(source).map_err(|e| format!("recover: {e}"))?;
    expect("recovered", zip.is_recovered(), true)?;
    // The fixture is 60% of a 12-page archive, so some pages survived and some did not.
    // A bound rather than an exact count: the split depends on DEFLATE output, which
    // differs between zlib builds.
    if zip.entries().is_empty() || zip.entries().len() >= 12 {
        return Err(format!("recovered {} entries", zip.entries().len()));
    }
    for entry in zip.entries() {
        let data = zip
            .data(entry)
            .map_err(|e| format!("{}: {e}", entry.path))?;
        expect(
            &format!("{} decodes to a PNG", entry.path),
            data.starts_with(&PNG_SIGNATURE),
            true,
        )?;
    }
    Ok(())
}

/// The container level (task 1.3): a CBT's regular files, in archive order, read verbatim.
fn check_tar(fixture: &Comic) -> Result<(), String> {
    let tar = TarReader::open(source(fixture)?).map_err(|e| format!("open: {e}"))?;
    let paths: Vec<&str> = tar.entries().iter().map(|e| e.path.as_str()).collect();
    let order: Vec<&str> = fixture
        .expected_page_order
        .iter()
        .flatten()
        .map(String::as_str)
        .collect();
    // TAR fixtures hold pages and chapter directories only, and directory blocks are not
    // entries, so the entry list *is* the page order the manifest records.
    expect("entries in archive order", paths, order)?;
    for entry in tar.entries() {
        let data = tar
            .data(entry)
            .map_err(|e| format!("{}: {e}", entry.path))?;
        expect(
            &format!("{} byte count", entry.path),
            data.len() as u64,
            entry.size,
        )?;
        expect(
            &format!("{} starts as a PNG", entry.path),
            data.starts_with(&PNG_SIGNATURE),
            true,
        )?;
    }
    Ok(())
}
