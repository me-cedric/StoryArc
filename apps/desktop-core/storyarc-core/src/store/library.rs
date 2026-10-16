//! The library half of the store: the sources a reader configured and the publications
//! each one holds, kept so the library opens from disk before any folder is walked and so
//! a returning app can reconcile by size and modification time (task 2.2).

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};

use super::{Store, StoreError};
use crate::domain::{Publication, Timestamp};

/// One configured source, as the store keeps it. The desktop registry of
/// `SourceRegistry.swift`'s order and identifiers; connection state is never stored,
/// because a state read back from disk is a claim about the past.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredSource {
    /// A UUID string, as the mobile registries spell theirs.
    pub id: String,
    pub display_name: String,
    /// `localFolder`, `networkShare`, `opdsCatalogue` or `kavitaServer`.
    pub kind: String,
    /// A path for a folder, a URL otherwise.
    pub locator: String,
    /// Where the reader put it. Order carries meaning: a higher source wins a duplicate.
    pub position: i64,
    /// A folder granted through the Linux document portal, which passes no change events:
    /// the watcher polls it (task 2.3).
    #[serde(default)]
    pub is_portal_granted: bool,
}

impl Store {
    /// Every source, in the reader's order.
    pub fn sources(&self) -> Result<Vec<StoredSource>, StoreError> {
        self.with(|connection| {
            let mut statement = connection.prepare(
                "SELECT id, display_name, kind, locator, position, is_portal_granted FROM sources ORDER BY position, id",
            )?;
            let rows = statement.query_map([], |row| {
                Ok(StoredSource {
                    id: row.get(0)?,
                    display_name: row.get(1)?,
                    kind: row.get(2)?,
                    locator: row.get(3)?,
                    position: row.get(4)?,
                    is_portal_granted: row.get(5)?,
                })
            })?;
            rows.map(|row| row.map_err(StoreError::from)).collect()
        })
    }

    /// Adds a source at the end, or replaces the one with the same id in place. One write.
    pub fn save_source(&self, source: &StoredSource) -> Result<(), StoreError> {
        self.with(|connection| {
            let position: i64 = connection
                .query_row(
                    "SELECT position FROM sources WHERE id = ?1",
                    params![source.id],
                    |row| row.get(0),
                )
                .optional()?
                .unwrap_or_else(|| {
                    connection
                        .query_row("SELECT COALESCE(MAX(position), -1) + 1 FROM sources", [], |row| {
                            row.get(0)
                        })
                        .unwrap_or(0)
                });
            connection.execute(
                "INSERT OR REPLACE INTO sources (id, display_name, kind, locator, position, is_portal_granted)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    source.id,
                    source.display_name,
                    source.kind,
                    source.locator,
                    position,
                    source.is_portal_granted
                ],
            )?;
            Ok(())
        })
    }

    /// Removes a source and the publications it held. Progress stays: ADR-0006 keeps a
    /// position for thirty days after its source goes, and nothing here forgets one.
    pub fn remove_source(&self, id: &str) -> Result<(), StoreError> {
        self.with(|connection| {
            connection.execute("DELETE FROM publications WHERE source_id = ?1", params![id])?;
            connection.execute("DELETE FROM sources WHERE id = ?1", params![id])?;
            Ok(())
        })
    }

    /// The publications a source holds, in the order they were recorded.
    pub fn publications(&self, source_id: &str) -> Result<Vec<Publication>, StoreError> {
        self.with(|connection| {
            let mut statement = connection
                .prepare("SELECT record FROM publications WHERE source_id = ?1 ORDER BY rowid")?;
            let rows = statement.query_map(params![source_id], |row| row.get::<_, String>(0))?;
            rows.map(|row| {
                row.map_err(StoreError::from)
                    .and_then(|record| serde_json::from_str(&record).map_err(StoreError::from))
            })
            .collect()
        })
    }

    /// Every publication of every source.
    pub fn all_publications(&self) -> Result<Vec<Publication>, StoreError> {
        self.with(|connection| {
            let mut statement =
                connection.prepare("SELECT record FROM publications ORDER BY rowid")?;
            let rows = statement.query_map([], |row| row.get::<_, String>(0))?;
            rows.map(|row| {
                row.map_err(StoreError::from)
                    .and_then(|record| serde_json::from_str(&record).map_err(StoreError::from))
            })
            .collect()
        })
    }

    /// The publication recorded at a path, whichever source holds it.
    pub fn publication_at(&self, normalized_path: &str) -> Result<Option<Publication>, StoreError> {
        self.with(|connection| {
            connection
                .query_row(
                    "SELECT record FROM publications WHERE normalized_path = ?1 LIMIT 1",
                    params![normalized_path],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
                .map(|record| serde_json::from_str(&record).map_err(StoreError::from))
                .transpose()
        })
    }

    /// Replaces what a source holds with `publications`, in one transaction, so a reader
    /// never sees half a scan. Costs one write per publication.
    pub fn replace_publications(
        &self,
        source_id: &str,
        publications: &[Publication],
    ) -> Result<(), StoreError> {
        self.with(|connection| {
            let transaction = connection.unchecked_transaction()?;
            transaction.execute(
                "DELETE FROM publications WHERE source_id = ?1",
                params![source_id],
            )?;
            for publication in publications {
                insert(&transaction, source_id, publication)?;
            }
            transaction.commit()?;
            Ok(())
        })
    }

    /// Records or replaces one publication of a source.
    pub fn save_publication(
        &self,
        source_id: &str,
        publication: &Publication,
    ) -> Result<(), StoreError> {
        self.with(|connection| insert(connection, source_id, publication))
    }

    /// Drops the publications at these paths.
    pub fn remove_publications_at(&self, paths: &[String]) -> Result<(), StoreError> {
        self.with(|connection| {
            let transaction = connection.unchecked_transaction()?;
            for path in paths {
                transaction.execute(
                    "DELETE FROM publications WHERE normalized_path = ?1",
                    params![path],
                )?;
            }
            transaction.commit()?;
            Ok(())
        })
    }
}

fn insert(
    connection: &rusqlite::Connection,
    source_id: &str,
    publication: &Publication,
) -> Result<(), StoreError> {
    connection.execute(
        "INSERT OR REPLACE INTO publications (stable_id, source_id, normalized_path, file_size, modified_at, record)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            publication.id(),
            source_id,
            publication.identity.normalized_path,
            publication.file_size,
            publication.modified_at.map(|moment: Timestamp| moment.0),
            serde_json::to_string(publication)?,
        ],
    )?;
    Ok(())
}
