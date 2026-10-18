//! The progress half of the store. Mirrored from `ProgressStore.swift` and
//! `ProgressStore.kt`: the same lookup order, the same sticky finished flag, the same
//! kept watermark.

use rusqlite::{Connection, OptionalExtension, Row, params};

use super::{Store, StoreError};
use crate::domain::{
    PublicationIdentity, ReadingPosition, ReadingProgress, ServerIdentifier, Timestamp,
};

/// One row of `progress`, with the identity flattened so a record is found by any
/// component on its own.
struct StoredProgress {
    id: i64,
    server_key: Option<String>,
    content_digest: Option<String>,
    normalized_path: Option<String>,
    position: String,
    is_finished: bool,
    finished_at: Option<i64>,
    updated_at: i64,
    synced_position: Option<String>,
}

const COLUMNS: &str = "id, server_key, content_digest, normalized_path, position, is_finished, finished_at, updated_at, synced_position";

impl StoredProgress {
    fn from_row(row: &Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            server_key: row.get(1)?,
            content_digest: row.get(2)?,
            normalized_path: row.get(3)?,
            position: row.get(4)?,
            is_finished: row.get(5)?,
            finished_at: row.get(6)?,
            updated_at: row.get(7)?,
            synced_position: row.get(8)?,
        })
    }

    fn domain(&self) -> Result<ReadingProgress, StoreError> {
        Ok(ReadingProgress {
            identity: PublicationIdentity {
                server_identifier: self.server_key.as_deref().and_then(server_identifier),
                content_digest: self.content_digest.clone(),
                normalized_path: self.normalized_path.clone(),
            },
            position: serde_json::from_str(&self.position)?,
            is_finished: self.is_finished,
            finished_at: self.finished_at.map(Timestamp),
            updated_at: Timestamp(self.updated_at),
            synced_position: self
                .synced_position
                .as_deref()
                .map(serde_json::from_str)
                .transpose()?,
        })
    }
}

/// The one column a server identifier is stored as: `<source id>:<remote id>`.
fn server_key(identity: &PublicationIdentity) -> Option<String> {
    identity
        .server_identifier
        .as_ref()
        .map(|server| format!("{}:{}", server.source_id, server.remote_id))
}

fn server_identifier(key: &str) -> Option<ServerIdentifier> {
    let (source_id, remote_id) = key.split_once(':')?;
    Some(ServerIdentifier {
        source_id: source_id.to_owned(),
        remote_id: remote_id.to_owned(),
    })
}

/// The row for an identity, matched on any component in ADR-0006's order of preference.
fn existing(
    connection: &Connection,
    identity: &PublicationIdentity,
) -> Result<Option<StoredProgress>, StoreError> {
    let lookups: [(&str, Option<String>); 3] = [
        ("server_key", server_key(identity)),
        ("content_digest", identity.content_digest.clone()),
        ("normalized_path", identity.normalized_path.clone()),
    ];
    for (column, value) in lookups {
        let Some(value) = value else { continue };
        let found = connection
            .query_row(
                &format!("SELECT {COLUMNS} FROM progress WHERE {column} = ?1 LIMIT 1"),
                params![value],
                StoredProgress::from_row,
            )
            .optional()?;
        if found.is_some() {
            return Ok(found);
        }
    }
    Ok(None)
}

impl Store {
    /// The progress recorded for a publication, if any. Matches on *any* identity
    /// component, in ADR-0006's order of preference. Three indexed lookups at most.
    pub fn progress(
        &self,
        identity: &PublicationIdentity,
    ) -> Result<Option<ReadingProgress>, StoreError> {
        self.with(|connection| {
            existing(connection, identity)?
                .map(|row| row.domain())
                .transpose()
        })
    }

    /// The record for a publication named only by its stable id. A table scan, for the
    /// source-side pull that holds a string and nothing else.
    pub fn progress_for_stable_id(&self, id: &str) -> Result<Option<ReadingProgress>, StoreError> {
        Ok(self
            .recent_progress(usize::MAX)?
            .into_iter()
            .find(|record| record.identity.stable_id() == id))
    }

    /// Records a position, replacing whatever was there. One write.
    ///
    /// Finished is sticky: a routine save never unmarks a publication, and the finished
    /// stamp is set once. A synced position the incoming record lacks is kept, because
    /// only an exchange with a server knows one. Identity components fill in as they
    /// become known, so a record written against a path is later found by its digest. A
    /// `path-` digest, the placeholder the wave 4 Windows app filed EPUB and PDF progress
    /// under, gives way to the real digest on the first save that brings one.
    pub fn save_progress(&self, progress: &ReadingProgress) -> Result<(), StoreError> {
        let position = serde_json::to_string(&progress.position)?;
        let synced = progress
            .synced_position
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;
        self.with(|connection| {
            if let Some(record) = existing(connection, &progress.identity)? {
                let is_finished = record.is_finished || progress.is_finished;
                let finished_at = if is_finished && !record.is_finished {
                    Some(progress.finished_at.unwrap_or(progress.updated_at).0)
                } else {
                    record.finished_at
                };
                connection.execute(
                    "UPDATE progress SET position = ?1, is_finished = ?2, finished_at = ?3, updated_at = ?4,
                        synced_position = COALESCE(?5, synced_position),
                        server_key = COALESCE(server_key, ?6),
                        content_digest = CASE WHEN content_digest LIKE 'path-%'
                            THEN COALESCE(?7, content_digest) ELSE COALESCE(content_digest, ?7) END,
                        normalized_path = COALESCE(normalized_path, ?8)
                     WHERE id = ?9",
                    params![
                        position,
                        is_finished,
                        finished_at,
                        progress.updated_at.0,
                        synced,
                        server_key(&progress.identity),
                        progress.identity.content_digest,
                        progress.identity.normalized_path,
                        record.id,
                    ],
                )?;
            } else {
                let finished_at = progress
                    .is_finished
                    .then(|| progress.finished_at.unwrap_or(progress.updated_at).0);
                connection.execute(
                    "INSERT INTO progress (server_key, content_digest, normalized_path, position, is_finished, finished_at, updated_at, synced_position)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    params![
                        server_key(&progress.identity),
                        progress.identity.content_digest,
                        progress.identity.normalized_path,
                        position,
                        progress.is_finished,
                        finished_at,
                        progress.updated_at.0,
                        synced,
                    ],
                )?;
            }
            Ok(())
        })
    }

    /// Records what else is known about a publication already in the store, changing
    /// nothing about the reading: neither the position nor `updated_at` moves. Returns
    /// whether a record was found and something was new about it.
    pub fn link_identity(&self, identity: &PublicationIdentity) -> Result<bool, StoreError> {
        self.with(|connection| {
            let Some(record) = existing(connection, identity)? else {
                return Ok(false);
            };
            let key = server_key(identity);
            let changed = (record.server_key.is_none() && key.is_some())
                || (record.content_digest.is_none() && identity.content_digest.is_some())
                || (record.normalized_path.is_none() && identity.normalized_path.is_some());
            if !changed {
                return Ok(false);
            }
            connection.execute(
                "UPDATE progress SET server_key = COALESCE(server_key, ?1),
                    content_digest = COALESCE(content_digest, ?2),
                    normalized_path = COALESCE(normalized_path, ?3)
                 WHERE id = ?4",
                params![
                    key,
                    identity.content_digest,
                    identity.normalized_path,
                    record.id
                ],
            )?;
            Ok(true)
        })
    }

    /// Everything recorded, most recently read first. What "Continue reading" is built
    /// from. One indexed scan of at most `limit` rows.
    pub fn recent_progress(&self, limit: usize) -> Result<Vec<ReadingProgress>, StoreError> {
        self.with(|connection| {
            let mut statement = connection.prepare(&format!(
                "SELECT {COLUMNS} FROM progress ORDER BY updated_at DESC, id DESC LIMIT ?1"
            ))?;
            let rows = statement.query_map(
                params![i64::try_from(limit).unwrap_or(i64::MAX)],
                StoredProgress::from_row,
            )?;
            rows.map(|row| row.map_err(StoreError::from).and_then(|row| row.domain()))
                .collect()
        })
    }

    /// Sets the finished flag, in either direction. The deliberate act `reading-progress`
    /// names, as opposed to a page turn implying it.
    pub fn mark_finished(
        &self,
        identity: &PublicationIdentity,
        finished: bool,
        at: Timestamp,
    ) -> Result<(), StoreError> {
        self.with(|connection| {
            if let Some(record) = existing(connection, identity)? {
                let finished_at = finished.then(|| record.finished_at.unwrap_or(at.0));
                connection.execute(
                    "UPDATE progress SET is_finished = ?1, finished_at = ?2, updated_at = ?3 WHERE id = ?4",
                    params![finished, finished_at, at.0, record.id],
                )?;
            } else {
                // Nothing recorded yet, and marking read is still a position: the whole of it.
                let position = serde_json::to_string(&ReadingPosition::page(0, i64::from(finished)))?;
                connection.execute(
                    "INSERT INTO progress (server_key, content_digest, normalized_path, position, is_finished, finished_at, updated_at, synced_position)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)",
                    params![
                        server_key(identity),
                        identity.content_digest,
                        identity.normalized_path,
                        position,
                        finished,
                        finished.then_some(at.0),
                        at.0,
                    ],
                )?;
            }
            Ok(())
        })
    }

    /// Forgets one publication's position. A deliberate act, per ADR-0006.
    pub fn forget_progress(&self, identity: &PublicationIdentity) -> Result<(), StoreError> {
        self.with(|connection| {
            if let Some(record) = existing(connection, identity)? {
                connection.execute("DELETE FROM progress WHERE id = ?1", params![record.id])?;
            }
            Ok(())
        })
    }

    /// Forgets every recorded position. `settings-and-about` requires reading history to be
    /// individually clearable.
    pub fn clear_progress(&self) -> Result<(), StoreError> {
        self.with(|connection| {
            connection.execute("DELETE FROM progress", [])?;
            Ok(())
        })
    }
}
