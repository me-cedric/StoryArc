//! Reading and writing the document, mirrored from StoryArcKit's `LibraryDocumentCoder` and
//! `ExportableAddress` (`library-portability`, *One versioned document*).
//!
//! A document over 64 MiB is refused before a byte is parsed. A newer format version is
//! refused by name, with nothing read from it. An older one goes through each transform in
//! order; version 1 is the first, so the chain is empty and has somewhere to grow.

use serde_json::Value;

use super::document::LibraryDocument;

/// Why a document was refused. Cases, not sentences: the apps word them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DocumentFailure {
    NotALibraryDocument,
    NewerThanThisApp { found: u32, understood: u32 },
    NoMigrationPath { from: u32 },
    Malformed(String),
    TooLarge { found: usize, limit: usize },
}

impl std::fmt::Display for DocumentFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotALibraryDocument => f.write_str("the file is not a StoryArc library"),
            Self::NewerThanThisApp { found, understood } => write!(
                f,
                "the library is format {found}; this app reads up to format {understood}"
            ),
            Self::NoMigrationPath { from } => write!(f, "format {from} cannot be brought forward"),
            Self::Malformed(detail) => write!(f, "the library could not be read: {detail}"),
            Self::TooLarge { found, limit } => {
                write!(f, "the library is {found} bytes; the limit is {limit}")
            }
        }
    }
}

impl std::error::Error for DocumentFailure {}

/// 64 MiB.
pub const MAXIMUM_BYTES: usize = 64 * 1024 * 1024;

/// One step of the chain: a document of version `from` becomes `from + 1`.
pub struct Transform {
    pub from: u32,
    pub apply: fn(Value) -> Value,
}

/// Every transform this build knows, in order.
pub const TRANSFORMS: &[Transform] = &[];

/// Writes a document: indented, keys in declaration order, covers sorted by key.
pub fn encode(document: &LibraryDocument) -> Vec<u8> {
    let mut document = document.clone();
    document.library.covers.sort_by(|a, b| a.key.cmp(&b.key));
    // A value of plain records cannot fail to serialise.
    serde_json::to_vec_pretty(&document).unwrap_or_default()
}

pub fn decode(bytes: &[u8]) -> Result<LibraryDocument, DocumentFailure> {
    decode_with(bytes, MAXIMUM_BYTES, TRANSFORMS)
}

pub fn decode_with(
    bytes: &[u8],
    limit: usize,
    transforms: &[Transform],
) -> Result<LibraryDocument, DocumentFailure> {
    if bytes.len() > limit {
        return Err(DocumentFailure::TooLarge {
            found: bytes.len(),
            limit,
        });
    }
    let mut value: Value =
        serde_json::from_slice(bytes).map_err(|_| DocumentFailure::NotALibraryDocument)?;
    let declared = value
        .get("formatVersion")
        .and_then(Value::as_u64)
        .and_then(|v| u32::try_from(v).ok())
        .ok_or(DocumentFailure::NotALibraryDocument)?;
    let current = LibraryDocument::CURRENT_FORMAT_VERSION;
    if declared > current {
        return Err(DocumentFailure::NewerThanThisApp {
            found: declared,
            understood: current,
        });
    }
    let mut version = declared;
    while version < current {
        let step = transforms
            .iter()
            .find(|t| t.from == version)
            .ok_or(DocumentFailure::NoMigrationPath { from: version })?;
        value = (step.apply)(value);
        version += 1;
        if let Some(object) = value.as_object_mut() {
            object.insert("formatVersion".into(), Value::from(version));
        }
    }
    serde_json::from_value(value).map_err(|e| DocumentFailure::Malformed(e.to_string()))
}

/// Query and fragment names that carry a secret, dropped from an exported address.
const SECRET_NAMES: &[&str] = &[
    "token",
    "password",
    "passwd",
    "pwd",
    "secret",
    "key",
    "apikey",
    "api_key",
    "api-key",
    "x-api-key",
    "auth",
    "authorization",
    "bearer",
    "accesstoken",
    "access_token",
    "refresh_token",
    "refreshtoken",
    "session",
    "sessionid",
    "session_id",
    "sid",
    "credential",
    "credentials",
    "signature",
    "sig",
];

/// A source's address with every secret removed: the password in the user part, and any
/// query or fragment item named like a secret. The username stays.
pub fn exportable_address(locator: &str) -> String {
    let without_password = match locator.find("://") {
        Some(scheme_end) if is_scheme(&locator[..scheme_end]) => {
            let rest = &locator[scheme_end + 3..];
            let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
            match rest[..authority_end].rfind('@') {
                Some(at) => {
                    let user = rest[..at].split(':').next().unwrap_or_default();
                    format!("{}://{user}@{}", &locator[..scheme_end], &rest[at + 1..])
                }
                None => locator.to_owned(),
            }
        }
        _ => locator.to_owned(),
    };
    let (before_hash, fragment) = match without_password.split_once('#') {
        Some((before, fragment)) => (before.to_owned(), kept_items(fragment)),
        None => (without_password.clone(), None),
    };
    let (address, query) = match before_hash.split_once('?') {
        Some((address, query)) => (address.to_owned(), kept_items(query)),
        None => (before_hash, None),
    };
    let mut out = address;
    if let Some(query) = query {
        out.push('?');
        out.push_str(&query);
    }
    if let Some(fragment) = fragment {
        out.push('#');
        out.push_str(&fragment);
    }
    out
}

fn is_scheme(text: &str) -> bool {
    let mut chars = text.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '.' | '-'))
}

fn kept_items(items: &str) -> Option<String> {
    let kept: Vec<&str> = items
        .split('&')
        .filter(|item| {
            let name = item
                .split('=')
                .next()
                .unwrap_or_default()
                .to_ascii_lowercase();
            !SECRET_NAMES.contains(&name.as_str())
        })
        .collect();
    (!kept.is_empty()).then(|| kept.join("&"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_address_keeps_its_user_and_loses_every_secret() {
        assert_eq!(
            exportable_address("smb://reader:hunter2@nas.local/comics"),
            "smb://reader@nas.local/comics"
        );
        assert_eq!(
            exportable_address("https://kavita.example/api?apiKey=hunter2&library=3"),
            "https://kavita.example/api?library=3"
        );
        assert_eq!(
            exportable_address("https://host/feed?x=1#token=abc"),
            "https://host/feed?x=1"
        );
        assert_eq!(exportable_address("/Books/Shelf"), "/Books/Shelf");
        assert_eq!(
            exportable_address("https://host/a@b?key=1"),
            "https://host/a@b"
        );
    }

    #[test]
    fn a_newer_document_is_refused_by_name_and_a_large_one_before_parsing() {
        let newer = br#"{"formatVersion": 2, "library": {}}"#;
        assert_eq!(
            decode(newer),
            Err(DocumentFailure::NewerThanThisApp {
                found: 2,
                understood: 1
            })
        );
        assert_eq!(
            decode_with(b"{ not json at all", 4, TRANSFORMS),
            Err(DocumentFailure::TooLarge {
                found: 17,
                limit: 4
            })
        );
        assert_eq!(decode(b"[1, 2]"), Err(DocumentFailure::NotALibraryDocument));
    }

    #[test]
    fn an_older_document_runs_the_chain_and_a_gap_in_it_is_named() {
        let old = br#"{"formatVersion": 0, "appVersion": "1", "writtenBy": "ios",
            "writtenAt": "2026-01-01T00:00:00Z", "library": {}}"#;
        assert_eq!(
            decode(old),
            Err(DocumentFailure::NoMigrationPath { from: 0 })
        );
        fn rename(mut v: Value) -> Value {
            v["appVersion"] = Value::from("migrated");
            v
        }
        let chain = [Transform {
            from: 0,
            apply: rename,
        }];
        let document = decode_with(old, MAXIMUM_BYTES, &chain).unwrap();
        assert_eq!(document.format_version, 1);
        assert_eq!(document.app_version, "migrated");
    }
}
