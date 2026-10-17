//! One file on a share, read at an offset (ADR-0008's third source).

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use smb::{Client, ReadAt};

use super::error::{SmbError, Step};
use super::health::{ReadHealth, ReadStatus};
use super::share::{Target, named};
use crate::io::{RandomAccessSource, SourceError};
use crate::runtime::{InRuntime, Runtime};

/// A read past this got an answer or never will. iOS and Android bound a read at 20 s.
const READ_DEADLINE: Duration = Duration::from_secs(20);
/// A reopen past this never will. iOS and Android bound it at 10 s.
const REOPEN_DEADLINE: Duration = Duration::from_secs(10);
/// One READ asks for at most this much; a page larger than it takes several.
const CHUNK: usize = 1 << 20;

/// An open handle and the client whose session it rides on. The client travels with the
/// handle because dropping it is what ends a session that went silent.
pub(crate) struct OpenFile {
    _client: Client,
    file: smb::File,
    length: u64,
}

impl OpenFile {
    pub(crate) fn new(client: Client, file: smb::File, length: u64) -> Self {
        Self {
            _client: client,
            file,
            length,
        }
    }
}

/// A file on a share. Reads open a new session once if the old one has gone, so a laptop that
/// slept, a server that restarted and a changed network all read on without a prompt.
pub struct SmbFile {
    runtime: Runtime,
    target: Arc<Target>,
    path: String,
    length: u64,
    open: Mutex<Option<InRuntime<OpenFile>>>,
    health: Arc<ReadHealth>,
    opens: AtomicUsize,
}

impl SmbFile {
    pub(crate) fn new(runtime: Runtime, target: Arc<Target>, path: String, file: OpenFile) -> Self {
        Self {
            length: file.length,
            open: Mutex::new(Some(InRuntime::new(&runtime, file))),
            runtime,
            target,
            path,
            health: Arc::new(ReadHealth::new()),
            opens: AtomicUsize::new(1),
        }
    }

    /// The path on the share, under the address's folder.
    pub fn path(&self) -> &str {
        &self.path
    }

    /// What the reader window shows now: the two-second indicator, the sixty-second offer.
    pub fn status(&self) -> ReadStatus {
        self.health.at(Instant::now())
    }

    /// The record behind [`SmbFile::status`], for a window that keeps its own clock.
    pub fn health(&self) -> Arc<ReadHealth> {
        Arc::clone(&self.health)
    }

    /// How many sessions this file has opened, the first included. A test reads it to see
    /// that a reconnect happened.
    pub fn opens(&self) -> usize {
        self.opens.load(Ordering::SeqCst)
    }

    /// Forgets the session without asking it anything. The app calls it when the machine
    /// wakes or the network changes; the next read opens a new one.
    pub fn drop_session(&self) {
        *self.slot() = None;
    }

    fn slot(&self) -> MutexGuard<'_, Option<InRuntime<OpenFile>>> {
        self.open
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// One read on the current session, opening one first if there is none.
    fn read_once(
        &self,
        slot: &mut Option<InRuntime<OpenFile>>,
        offset: u64,
        count: usize,
    ) -> Result<Vec<u8>, SmbError> {
        if slot.is_none() {
            let opened = self
                .runtime
                .block_on_within(REOPEN_DEADLINE, self.target.open_file(&self.path))
                .ok_or(SmbError::HostUnreachable)??;
            self.opens.fetch_add(1, Ordering::SeqCst);
            *slot = Some(InRuntime::new(&self.runtime, opened));
        }
        let file = &slot.as_ref().expect("opened just above").file;
        self.runtime
            .block_on_within(READ_DEADLINE, read_fully(file, offset, count, &self.path))
            .ok_or(SmbError::HostUnreachable)?
    }
}

impl RandomAccessSource for SmbFile {
    fn length(&self) -> u64 {
        self.length
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        if offset > self.length {
            return Err(SourceError::OutOfBounds {
                offset,
                count,
                length: self.length,
            });
        }
        let count = count.min((self.length - offset).min(usize::MAX as u64) as usize);
        if count == 0 {
            return Ok(Vec::new());
        }
        self.health.began(Instant::now());
        let mut slot = self.slot();
        let result = self.read_once(&mut slot, offset, count).or_else(|_| {
            // Stale, dropped or asleep: let it go and ask once more on a new session. Once,
            // not in a loop — a share that is really gone says so rather than hang.
            *slot = None;
            self.read_once(&mut slot, offset, count)
        });
        if result.is_err() {
            *slot = None;
        }
        drop(slot);
        self.health.ended(Instant::now(), result.is_ok());
        result.map_err(|error| SourceError::Unreadable(error.to_string()))
    }
}

impl std::fmt::Debug for SmbFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SmbFile")
            .field("path", &self.path)
            .field("length", &self.length)
            .finish()
    }
}

/// Reads `count` bytes at `offset`, in chunks, stopping early only at the end of the file.
async fn read_fully(
    file: &smb::File,
    offset: u64,
    count: usize,
    path: &str,
) -> Result<Vec<u8>, SmbError> {
    let mut buffer = vec![0; count];
    let mut filled = 0;
    while filled < count {
        let end = (filled + CHUNK).min(count);
        let got = file
            .read_at(&mut buffer[filled..end], offset + filled as u64)
            .await
            .map_err(|error| named(&error, Step::Read, path))?;
        if got == 0 {
            break;
        }
        filled += got;
    }
    buffer.truncate(filled);
    Ok(buffer)
}
