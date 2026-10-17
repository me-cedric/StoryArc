//! The Readium Web Publication Manifest and the positions list for one EPUB, which the
//! desktop EPUB bundle takes in place of a container parser (design.md, Decision 6; task
//! 4.3 of `desktop-clients`). Windows and Linux build them here; macOS builds the same two
//! documents in Swift (Open Question 6), and `tests/epub_positions.rs` holds them to the
//! same numbers.
//!
//! **Positions.** Readium's `EPUBPositionsService`, which both phones run, gives a
//! reflowable reading-order entry `ceil(compressed entry size / 1024)` positions and at
//! least one, and a fixed-layout entry exactly one. The number a reader sees in the
//! progress line is therefore the same on every platform for the same file.

mod manifest;

use std::sync::Arc;

use serde::Serialize;

use crate::formats::{EpubError, EpubReader};
use crate::io::RandomAccessSource;

pub use manifest::{Link, Locations, Locator, Manifest, Metadata};

/// One EPUB, as the bundle sees it: a manifest, a positions list, and its resources by
/// container path.
pub struct WebPublication {
    reader: EpubReader,
    manifest: Manifest,
    positions: Vec<Locator>,
}

/// The bytes of one position in a reading-order entry: Readium's `EPUBPositionsService`.
const BYTES_PER_POSITION: u64 = 1024;

impl WebPublication {
    /// Opens the container and builds both documents. `self_url` is where the host serves
    /// the manifest; every other href is a container path the host resolves against it.
    pub fn open(source: Arc<dyn RandomAccessSource>, self_url: &str) -> Result<Self, EpubError> {
        let reader = EpubReader::open(source)?;
        let manifest = manifest::build(&reader, self_url);
        let positions = positions(&reader, &manifest);
        Ok(Self {
            reader,
            manifest,
            positions,
        })
    }

    pub fn manifest(&self) -> &Manifest {
        &self.manifest
    }

    pub fn positions(&self) -> &[Locator] {
        &self.positions
    }

    /// The manifest as the JSON the bundle's `open` takes.
    pub fn manifest_json(&self) -> String {
        to_json(&self.manifest)
    }

    /// The positions as the JSON array the bundle's `open` takes.
    pub fn positions_json(&self) -> String {
        to_json(&self.positions)
    }

    /// One resource's bytes, by its container path, for the host's scheme handler.
    pub fn resource(&self, href: &str) -> Result<Vec<u8>, EpubError> {
        self.reader.data_at(href)
    }

    /// The media type the package declares for a resource, for the scheme handler's answer.
    pub fn media_type(&self, href: &str) -> Option<&str> {
        self.reader
            .resources
            .iter()
            .find(|r| r.href == href)
            .map(|r| r.media_type.as_str())
    }
}

fn to_json(value: &impl Serialize) -> String {
    // Every type here is plain data with string keys, which serde_json always serialises.
    serde_json::to_string(value).unwrap_or_default()
}

/// The positions list over the manifest's reading order.
fn positions(reader: &EpubReader, manifest: &Manifest) -> Vec<Locator> {
    let fixed = reader.is_fixed_layout;
    let counts: Vec<u64> = manifest
        .reading_order
        .iter()
        .map(|link| {
            if fixed {
                return 1;
            }
            reader.entry(&link.href).map_or(1, |entry| {
                entry.compressed_size.div_ceil(BYTES_PER_POSITION).max(1)
            })
        })
        .collect();
    let total: u64 = counts.iter().sum();
    let mut position = 0u64;
    let mut locators = Vec::with_capacity(total as usize);
    for (link, count) in manifest.reading_order.iter().zip(counts) {
        for page in 0..count {
            position += 1;
            locators.push(Locator {
                href: link.href.clone(),
                media_type: link.media_type.clone(),
                title: link.title.clone(),
                locations: Locations {
                    position,
                    progression: page as f64 / count as f64,
                    total_progression: (position - 1) as f64 / total as f64,
                },
            });
        }
    }
    locators
}
