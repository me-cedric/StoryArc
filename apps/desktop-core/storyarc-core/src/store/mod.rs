//! The local store: reading positions, the publications each source holds, and the
//! sources themselves, in one SQLite file (task 2.1 of `desktop-clients`).
//!
//! ADR-0006: progress is written locally first, always, for every publication, and remote
//! sync is a projection of this store outward. The schema's *semantics* are the ones the
//! ADR fixes so the three implementations agree — three identity columns a record is
//! found by any of, a position kept whole, a finished flag with its own stamp, and a sync
//! watermark — while SQLite through rusqlite is this core's own choice, as SwiftData and
//! Room are the phones'.
//!
//! One connection behind a mutex: the reader writes a position every few seconds while
//! the library reads records to draw, and SQLite serialises writers anyway. Every call
//! below takes the lock for the length of one statement or one transaction.

mod library;
mod progress;

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::Connection;

pub use library::StoredSource;

/// A store that could not do what it was asked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StoreError {
    /// SQLite refused. Carries its message, which names the file and the cause.
    Database(String),
    /// A stored record could not be read back as the type it was written as.
    Corrupt(String),
    /// The disk is full. Named apart from every other failure because
    /// `desktop-experience` asks the app to say so in grey and offer to clear a cache.
    DiskFull,
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Database(message) => write!(f, "store: {message}"),
            Self::Corrupt(message) => write!(f, "store record unreadable: {message}"),
            Self::DiskFull => f.write_str("the disk is full"),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> Self {
        if let rusqlite::Error::SqliteFailure(code, _) = &error
            && code.code == rusqlite::ErrorCode::DiskFull
        {
            return Self::DiskFull;
        }
        Self::Database(error.to_string())
    }
}

impl From<serde_json::Error> for StoreError {
    fn from(error: serde_json::Error) -> Self {
        Self::Corrupt(error.to_string())
    }
}

/// The current schema. Bumped when a migration below is added.
const SCHEMA_VERSION: i64 = 1;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS progress (
    id INTEGER PRIMARY KEY,
    server_key TEXT,
    content_digest TEXT,
    normalized_path TEXT,
    position TEXT NOT NULL,
    is_finished INTEGER NOT NULL DEFAULT 0,
    finished_at INTEGER,
    updated_at INTEGER NOT NULL,
    synced_position TEXT
);
CREATE INDEX IF NOT EXISTS progress_server_key ON progress(server_key);
CREATE INDEX IF NOT EXISTS progress_content_digest ON progress(content_digest);
CREATE INDEX IF NOT EXISTS progress_normalized_path ON progress(normalized_path);
CREATE INDEX IF NOT EXISTS progress_updated_at ON progress(updated_at);

CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    kind TEXT NOT NULL,
    locator TEXT NOT NULL,
    position INTEGER NOT NULL,
    is_portal_granted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS publications (
    stable_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    normalized_path TEXT,
    file_size INTEGER,
    modified_at INTEGER,
    record TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS publications_source ON publications(source_id);
CREATE INDEX IF NOT EXISTS publications_path ON publications(normalized_path);
";

/// Reading positions, publications and sources, stored locally and authoritative.
pub struct Store {
    connection: Mutex<Connection>,
    path: Option<PathBuf>,
}

impl Store {
    /// Opens the store on disk, creating the file and its schema when absent. Costs one
    /// file open and a schema check; the parent directory must exist.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        let path = path.as_ref();
        let connection = Connection::open(path)?;
        Self::prepare(connection, Some(path.to_path_buf()))
    }

    /// An in-memory store, for tests and previews. Gone when dropped.
    pub fn in_memory() -> Result<Self, StoreError> {
        Self::prepare(Connection::open_in_memory()?, None)
    }

    fn prepare(connection: Connection, path: Option<PathBuf>) -> Result<Self, StoreError> {
        // WAL keeps a reader drawing the library from waiting behind the writer that is
        // recording a page turn; it is a no-op for the in-memory store.
        if path.is_some() {
            connection.pragma_update(None, "journal_mode", "WAL")?;
        }
        connection.pragma_update(None, "foreign_keys", "ON")?;
        connection.execute_batch(SCHEMA)?;
        let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
        if version < SCHEMA_VERSION {
            connection.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        }
        Ok(Self {
            connection: Mutex::new(connection),
            path,
        })
    }

    /// Bytes the store holds on disk, its journal included, or zero for an in-memory one.
    /// `desktop-experience` asks the preferences to show what the library's records use.
    pub fn size_on_disk(&self) -> u64 {
        let Some(path) = &self.path else {
            return 0;
        };
        let Some(directory) = path.parent() else {
            return 0;
        };
        let stem = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        std::fs::read_dir(directory)
            .map(|entries| {
                entries
                    .flatten()
                    .filter(|entry| entry.file_name().to_string_lossy().starts_with(&stem))
                    .filter_map(|entry| entry.metadata().ok())
                    .map(|metadata| metadata.len())
                    .sum()
            })
            .unwrap_or(0)
    }

    /// The file this store lives in, or `None` for the in-memory store.
    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    fn with<T>(
        &self,
        work: impl FnOnce(&Connection) -> Result<T, StoreError>,
    ) -> Result<T, StoreError> {
        let connection = self
            .connection
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        work(&connection)
    }
}
