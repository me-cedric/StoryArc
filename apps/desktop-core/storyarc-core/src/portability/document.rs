//! The library document's shape, mirrored from StoryArcKit's `LibraryDocument.swift` and
//! pinned by the two documents in `packages/test-fixtures/library`.
//!
//! The document is the agreed shape, and each platform converts at its own boundary. The five
//! records the phones' stores disagree on are written one way here: a source's timestamp is an
//! ISO 8601 string, a source kind is lower camel case, a shelf's cover key is `coverMemberId`,
//! a reading position has named fields under a `kind`, and pinned shelves are a list of tokens.
//!
//! Settings and reading themes are carried as JSON objects: the phones agree on their keys
//! but each platform has a key the other lacks, and a field this build does not know is kept
//! rather than lost on a round trip through a desktop.

use std::collections::BTreeMap;

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Map, Value};

use crate::domain::{ReadingProgress, Timestamp};

/// The platform names a document's `writtenBy` carries. The name decides nothing on import.
pub mod platform {
    pub const IOS: &str = "ios";
    pub const ANDROID: &str = "android";
    pub const WINDOWS: &str = "windows";
    pub const LINUX: &str = "linux";

    /// This build's own name.
    pub fn this() -> &'static str {
        if cfg!(windows) { WINDOWS } else { LINUX }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryDocument {
    pub format_version: u32,
    pub app_version: String,
    pub written_by: String,
    pub written_at: Timestamp,
    pub library: LibraryBody,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub secrets: Option<LibrarySecrets>,
}

impl LibraryDocument {
    pub const CURRENT_FORMAT_VERSION: u32 = 1;

    pub fn new(
        app_version: impl Into<String>,
        written_at: Timestamp,
        library: LibraryBody,
    ) -> Self {
        Self {
            format_version: Self::CURRENT_FORMAT_VERSION,
            app_version: app_version.into(),
            written_by: platform::this().to_owned(),
            written_at,
            library,
            secrets: None,
        }
    }
}

fn empty_themes() -> Value {
    serde_json::json!({ "entries": [] })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryBody {
    #[serde(default)]
    pub sources: Vec<DocumentSource>,
    #[serde(default)]
    pub certificate_pins: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub collections: Vec<DocumentCollection>,
    #[serde(default)]
    pub reading_lists: Vec<DocumentReadingList>,
    #[serde(default)]
    pub pinned_shelves: Vec<String>,
    #[serde(default)]
    pub settings: Map<String, Value>,
    #[serde(default = "empty_themes")]
    pub reading_themes: Value,
    /// Every record this build can read; one it cannot is dropped alone.
    #[serde(default, deserialize_with = "readable_progress")]
    pub progress: Vec<ReadingProgress>,
    #[serde(default)]
    pub covers: Vec<DocumentCover>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub removed_shelves: Option<Vec<DocumentTombstone>>,
}

impl Default for LibraryBody {
    fn default() -> Self {
        Self {
            sources: Vec::new(),
            certificate_pins: BTreeMap::new(),
            collections: Vec::new(),
            reading_lists: Vec::new(),
            pinned_shelves: Vec::new(),
            settings: Map::new(),
            reading_themes: empty_themes(),
            progress: Vec::new(),
            covers: Vec::new(),
            removed_shelves: None,
        }
    }
}

/// `library-portability`, *A record this version cannot read*: a position of a kind this
/// build does not know, or one lacking a field its kind needs, drops that record alone.
fn readable_progress<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<ReadingProgress>, D::Error> {
    let records = Vec::<Value>::deserialize(d)?;
    Ok(records
        .into_iter()
        .filter_map(|record| serde_json::from_value::<ReadingProgress>(record).ok())
        .map(|record| ReadingProgress {
            synced_position: None,
            ..record
        })
        .collect())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentSource {
    pub id: String,
    pub display_name: String,
    /// Lower camel case: `localFolder`, `networkShare`, `opdsCatalog`, `kavitaServer`.
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_successful_sync: Option<Timestamp>,
    /// The address with any secret removed ([`super::exportable_address`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locator: Option<String>,
    #[serde(default)]
    pub needs_sign_in: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentCollection {
    pub id: String,
    pub name: String,
    pub members: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_member_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub changed_at: Option<Timestamp>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub changed_by: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentReadingList {
    pub id: String,
    pub name: String,
    pub entries: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_member_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub changed_at: Option<Timestamp>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub changed_by: Option<String>,
}

/// A cover the reader chose: its override key and the image in base64.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentCover {
    pub key: String,
    pub image: String,
}

/// A shelf deleted on some device, so the deletion travels.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentTombstone {
    pub id: String,
    pub removed_at: Timestamp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub removed_by: Option<String>,
}

/// Who changed a field last, and when.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentStamp {
    pub at: Timestamp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub by: Option<String>,
}

/// Secrets sealed under the reader's passphrase, every parameter written down.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LibrarySecrets {
    pub kdf: String,
    pub iterations: u32,
    pub salt: String,
    pub cipher: String,
    /// By source id, lower case.
    pub sealed: BTreeMap<String, SealedSecret>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SealedSecret {
    pub nonce: String,
    /// The ciphertext with the 16-byte tag after it.
    pub ciphertext: String,
}
