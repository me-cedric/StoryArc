//! What a comic fixture must parse to. Grows with each reader of wave 1, lane C.

use std::sync::Arc;

use std::collections::HashSet;

use storyarc_core::formats::{
    RarDecoder, RarGeneration, RarReader, TarReader, ZipError, ZipReader,
};
use storyarc_core::io::{FileSource, RandomAccessSource};

use super::manifest::{self, Comic};

pub const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Every assertion the manifest records for one comic archive.
///
/// Returns the first failure as text rather than panicking, so the per-fixture test names
/// the fixture and the pin together.
pub fn check(fixture: &Comic) -> Result<(), String> {
    // The container level first (tasks 1.2, 1.3 and 1.5), then the archive level (1.6).
    // 7-Zip has no container reader on purpose: it is refused by name, and that refusal
    // is the whole of what the archive level asserts for it.
    match container(fixture) {
        "zip" => check_zip(fixture)?,
        "tar" => check_tar(fixture)?,
        "rar4" | "rar5" => check_rar(fixture)?,
        "7z" => {}
        other => {
            return Err(format!(
                "no {other} reader opens {} ({})",
                fixture.file, fixture.pins
            ));
        }
    }
    super::archives::check(fixture)
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

pub fn expect<T: PartialEq + std::fmt::Debug>(what: &str, got: T, want: T) -> Result<(), String> {
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

/// The container level (task 1.5): our header reader and libarchive see the same archive,
/// stored entries read by range, and compressed ones decode to the bytes libarchive's own
/// suite documents.
fn check_rar(fixture: &Comic) -> Result<(), String> {
    let path = manifest::path(&fixture.file);
    let reader = RarReader::open(source(fixture)?).map_err(|e| format!("open: {e}"))?;
    let generation = match container(fixture) {
        "rar4" => RarGeneration::Rar4,
        _ => RarGeneration::Rar5,
    };
    expect("generation", reader.generation(), generation)?;
    expect(
        "solid",
        reader.is_solid(),
        fixture.is_solid.unwrap_or(false),
    )?;
    expect("encrypted", reader.is_encrypted(), false)?;
    // Measured, not assumed: libarchive reads a solid RAR5 completely and refuses a solid
    // RAR4 outright, so the two generations get different answers to the same flag.
    let readable = !(reader.is_solid() && generation == RarGeneration::Rar4);
    expect(
        "readable when local",
        reader.is_readable_when_local(),
        readable,
    )?;

    if !readable {
        // The finding this pins: libarchive lists the first entry and *then* fails, because
        // the first entry of a solid archive is not itself solid. Detection has to look at
        // every entry, not just the first.
        expect("first entry solid", reader.entries()[0].is_solid, false)?;
        expect(
            "a later entry solid",
            reader.entries()[1..].iter().any(|e| e.is_solid),
            true,
        )?;
        if RarDecoder::entry_names(&path).is_ok() {
            return Err("libarchive listed a solid RAR4 it cannot read".to_owned());
        }
        return Ok(());
    }

    let theirs = RarDecoder::entry_names(&path).map_err(|e| format!("libarchive: {e}"))?;
    let their_paths: Vec<&str> = theirs.iter().map(|e| e.path.as_str()).collect();
    // A vendored fixture is one whose contents libarchive's own suite documents, so it
    // always records the names to hold the decoder to.
    if fixture.is_vendored == Some(true) && fixture.expected_entry_names.is_none() {
        return Err("a vendored fixture records no expected entry names".to_owned());
    }
    if let Some(names) = &fixture.expected_entry_names {
        let names: Vec<&str> = names.iter().map(String::as_str).collect();
        expect("libarchive's entry names", their_paths.clone(), names)?;
    }
    // Our reader lists files only, so libarchive's directories are absent from it; what it
    // does list must match libarchive by name and size, in order, or the library would show a
    // page count the reader cannot deliver.
    let mut their_files = theirs
        .iter()
        .filter(|e| reader.entries().iter().any(|ours| ours.path == e.path));
    for ours in reader.entries() {
        let Some(theirs) = their_files.next() else {
            return Err(format!("{}: not listed by libarchive", ours.path));
        };
        expect(
            &format!("{} name", ours.path),
            ours.path.as_str(),
            theirs.path.as_str(),
        )?;
        // libarchive sizes a symbolic link at zero and carries its target elsewhere; our
        // header reader reports the header's own unpacked size, which for `testlink` in
        // the vendored RAR4 fixture is the target's eight bytes. A link is never a page,
        // so the two are compared only where libarchive reports data.
        if theirs.size > 0 {
            expect(
                &format!("{} size", ours.path),
                ours.size,
                theirs.size as u64,
            )?;
        }
    }

    if let Some(order) = &fixture.expected_page_order {
        let pages: Vec<&str> = reader
            .entries()
            .iter()
            .map(|e| e.path.as_str())
            .filter(|p| p.ends_with(".png"))
            .collect();
        let order: Vec<&str> = order.iter().map(String::as_str).collect();
        expect("pages in archive order", pages, order)?;
    }

    for entry in reader.entries() {
        // A link carries no data for libarchive (see above), so it is read by range only.
        let has_data = theirs.iter().any(|e| e.path == entry.path && e.size > 0);
        let data = if entry.is_stored {
            let by_range = reader
                .data(entry)
                .map_err(|e| format!("{}: {e}", entry.path))?;
            if has_data {
                // The same bytes through libarchive's memory path: the main header and this
                // one entry, handed over as a buffer, which is how a remote non-solid entry
                // decodes.
                let isolated = reader
                    .isolated(entry)
                    .map_err(|e| format!("{}: {e}", entry.path))?;
                let through_libarchive = RarDecoder::data_of_isolated(&entry.path, isolated)
                    .map_err(|e| format!("{} isolated: {e}", entry.path))?;
                expect(
                    &format!("{} isolated agrees", entry.path),
                    through_libarchive == by_range,
                    true,
                )?;
            }
            by_range
        } else {
            RarDecoder::data_for_entry(&entry.path, &path)
                .map_err(|e| format!("{}: {e}", entry.path))?
        };
        expect(
            &format!("{} byte count", entry.path),
            data.len() as u64,
            entry.size,
        )?;
        if entry.path.ends_with(".png") {
            expect(
                &format!("{} starts as a PNG", entry.path),
                data.starts_with(&PNG_SIGNATURE),
                true,
            )?;
        }
    }

    check_known_contents(fixture, &path)
}

/// The vendored fixtures decode to bytes libarchive's own assertions document, so the
/// decoder is checked against something other than itself.
fn check_known_contents(fixture: &Comic, path: &std::path::Path) -> Result<(), String> {
    match fixture.file.as_str() {
        "comics/rar4-compressed.cbr" => {
            let text = RarDecoder::data_for_entry("test.txt", path).map_err(|e| e.to_string())?;
            expect(
                "test.txt",
                text.as_slice(),
                b"test text document\r\n".as_slice(),
            )?;
            let nested =
                RarDecoder::data_for_entry("testdir/test.txt", path).map_err(|e| e.to_string())?;
            expect("testdir/test.txt", nested, text)
        }
        "comics/rar5-compressed.cbr" => {
            let data = RarDecoder::data_for_entry("test.bin", path).map_err(|e| e.to_string())?;
            expect("test.bin", data, libarchive_test_bin(1200))
        }
        "comics/rar5-solid.cbr" => {
            // Reading the last entry means decompressing all the ones before it.
            let last = RarDecoder::data_for_entry("test6.bin", path).map_err(|e| e.to_string())?;
            expect("test6.bin length", last.len(), 4096)?;
            let wanted: HashSet<String> = ["test.bin", "test3.bin", "test6.bin"]
                .iter()
                .map(|s| (*s).to_owned())
                .collect();
            let found = RarDecoder::data_for_entries(&wanted, path).map_err(|e| e.to_string())?;
            expect("one pass finds all three", found.len(), 3)?;
            expect(
                "test.bin",
                found["test.bin"].clone(),
                libarchive_test_bin(1200),
            )?;
            expect("test6.bin", found["test6.bin"].len(), 4096)
        }
        _ => Ok(()),
    }
}

/// libarchive's own generator for `test.bin`: each little-endian 32-bit word at index `i` is
/// `max(0, k*k - 3*k + 1)` for `k = i + 1`. Reproduced here so the assertion is independent
/// of the decoder under test.
fn libarchive_test_bin(byte_count: usize) -> Vec<u8> {
    (0..byte_count / 4)
        .flat_map(|index| {
            let step = index as i64 + 1;
            let value = (step * step - 3 * step + 1).max(0) as u32;
            value.to_le_bytes()
        })
        .collect()
}
