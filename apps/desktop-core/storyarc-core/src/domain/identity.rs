//! How StoryArc decides two things are the same publication. Mirrored from
//! `PublicationIdentity.swift`.
//!
//! ADR-0006: a server identifier wins when the publication came from a source that has
//! one; otherwise a content digest, which survives renames, moves and re-downloads; a
//! normalised path only as a last resort. Both a server id and a digest are recorded when
//! both are known — that is what lets a file read from a folder and the same file read
//! from a Kavita server resolve to one progress record.
//!
//! On the wire the identity is the flat shape the library documents in
//! `packages/test-fixtures/library` pin: `serverSourceId`, `serverRemoteId`,
//! `contentDigest`, `normalizedPath`, each absent when unknown.

use serde::{Deserialize, Serialize};

/// A server's own name for a publication, and which configured source the server is.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ServerIdentifier {
    /// The source's id, as the registry spells it (a UUID string on every platform).
    pub source_id: String,
    pub remote_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
pub struct PublicationIdentity {
    pub server_identifier: Option<ServerIdentifier>,
    pub content_digest: Option<String>,
    pub normalized_path: Option<String>,
}

impl PublicationIdentity {
    pub fn path(path: impl Into<String>) -> Self {
        Self {
            normalized_path: Some(path.into()),
            ..Self::default()
        }
    }

    pub fn digest(digest: impl Into<String>) -> Self {
        Self {
            content_digest: Some(digest.into()),
            ..Self::default()
        }
    }

    pub fn server(source_id: impl Into<String>, remote_id: impl Into<String>) -> Self {
        Self {
            server_identifier: Some(ServerIdentifier {
                source_id: source_id.into(),
                remote_id: remote_id.into(),
            }),
            ..Self::default()
        }
    }

    /// A stable key for lists, diffing and anything stored against a publication.
    ///
    /// **The path outranks both the digest and the server here, and only here.** `matches`
    /// keeps ADR-0006's order because that order answers "are these the same
    /// publication?". This answers "what string is this publication filed under?", and
    /// the only requirement of a filing key is that it does not move — the path is the
    /// component the app learns first, so ranking it first is the same rule as "the key
    /// does not move". The three prefixes are the mobile apps' own.
    pub fn stable_id(&self) -> String {
        if let Some(path) = &self.normalized_path {
            return format!("path:{path}");
        }
        if let Some(server) = &self.server_identifier {
            return format!("srv:{}:{}", server.source_id, server.remote_id);
        }
        if let Some(digest) = &self.content_digest {
            return format!("sha:{digest}");
        }
        "path:".to_owned()
    }

    /// The same identity with a content digest recorded against it. One already present is
    /// kept: whoever supplied it knew something this caller does not.
    pub fn recording_digest(&self, digest: Option<&str>) -> Self {
        match (&self.content_digest, digest) {
            (None, Some(digest)) => Self {
                content_digest: Some(digest.to_owned()),
                ..self.clone()
            },
            _ => self.clone(),
        }
    }

    /// The same identity with a server's own identifier recorded against it. One already
    /// present is kept.
    pub fn recording_server(&self, server: Option<ServerIdentifier>) -> Self {
        match (&self.server_identifier, server) {
            (None, Some(server)) => Self {
                server_identifier: Some(server),
                ..self.clone()
            },
            _ => self.clone(),
        }
    }

    /// Two identities match when *any* recorded component matches. A file that gains a
    /// server id later still resolves to the progress recorded against its digest.
    pub fn matches(&self, other: &Self) -> bool {
        let same = |mine: &Option<String>, theirs: &Option<String>| match (mine, theirs) {
            (Some(mine), Some(theirs)) => mine == theirs,
            _ => false,
        };
        matches!(
            (&self.server_identifier, &other.server_identifier),
            (Some(mine), Some(theirs)) if mine == theirs
        ) || same(&self.content_digest, &other.content_digest)
            || same(&self.normalized_path, &other.normalized_path)
    }

    /// This identity, with each component it lacks taken from `other`.
    pub fn filling(&self, other: &Self) -> Self {
        Self {
            server_identifier: self
                .server_identifier
                .clone()
                .or_else(|| other.server_identifier.clone()),
            content_digest: self
                .content_digest
                .clone()
                .or_else(|| other.content_digest.clone()),
            normalized_path: self
                .normalized_path
                .clone()
                .or_else(|| other.normalized_path.clone()),
        }
    }

    /// True when nothing at all was recorded — a bug at the call site rather than a state
    /// the app should tolerate.
    pub fn is_empty(&self) -> bool {
        self.server_identifier.is_none()
            && self.content_digest.is_none()
            && self.normalized_path.is_none()
    }
}

/// The wire shape, flat as the library documents write it.
#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Wire {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    server_source_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    server_remote_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    content_digest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    normalized_path: Option<String>,
}

impl Serialize for PublicationIdentity {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        Wire {
            server_source_id: self.server_identifier.as_ref().map(|s| s.source_id.clone()),
            server_remote_id: self.server_identifier.as_ref().map(|s| s.remote_id.clone()),
            content_digest: self.content_digest.clone(),
            normalized_path: self.normalized_path.clone(),
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for PublicationIdentity {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let wire = Wire::deserialize(deserializer)?;
        // Half a server identifier is no server identifier: a source id with no remote id
        // names nothing, and matching on it would join every chapter of one server.
        let server_identifier = match (wire.server_source_id, wire.server_remote_id) {
            (Some(source_id), Some(remote_id)) => Some(ServerIdentifier {
                source_id,
                remote_id,
            }),
            _ => None,
        };
        Ok(Self {
            server_identifier,
            content_digest: wire.content_digest,
            normalized_path: wire.normalized_path,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_filing_key_prefers_the_path_then_the_server_then_the_digest() {
        let full = PublicationIdentity {
            server_identifier: Some(ServerIdentifier {
                source_id: "s".into(),
                remote_id: "9".into(),
            }),
            content_digest: Some("d".into()),
            normalized_path: Some("/a.cbz".into()),
        };
        assert_eq!(full.stable_id(), "path:/a.cbz");
        assert_eq!(
            PublicationIdentity::server("s", "9")
                .recording_digest(Some("d"))
                .stable_id(),
            "srv:s:9"
        );
        assert_eq!(PublicationIdentity::digest("d").stable_id(), "sha:d");
        assert_eq!(PublicationIdentity::default().stable_id(), "path:");
    }

    #[test]
    fn any_shared_component_matches_and_a_present_component_is_kept() {
        let by_path = PublicationIdentity::path("/a.cbz");
        let by_digest = by_path.recording_digest(Some("d"));
        assert!(by_digest.matches(&PublicationIdentity::digest("d")));
        assert!(!by_path.matches(&PublicationIdentity::digest("d")));
        assert_eq!(by_digest.recording_digest(Some("other")), by_digest);
        assert_eq!(by_path.recording_digest(None), by_path);
        assert!(PublicationIdentity::default().is_empty());
    }

    #[test]
    fn the_wire_shape_is_the_library_documents_flat_one() {
        let json = r#"{"serverRemoteId":"901","serverSourceId":"5555"}"#;
        let identity: PublicationIdentity = serde_json::from_str(json).unwrap();
        assert_eq!(identity, PublicationIdentity::server("5555", "901"));
        assert_eq!(
            serde_json::to_string(&identity).unwrap(),
            r#"{"serverSourceId":"5555","serverRemoteId":"901"}"#
        );
        let half: PublicationIdentity = serde_json::from_str(r#"{"serverSourceId":"x"}"#).unwrap();
        assert!(half.is_empty());
    }
}
