//! One resumable transfer into a partial file (`offline-downloads`, *Resuming after
//! interruption*: it "resumes from where it stopped if the server supports range requests,
//! and restarts otherwise, stating which happened").
//!
//! The partial file is the record of what arrived: bytes are appended as they come, so after
//! a quit, a crash or a kill its length is exactly what the next attempt continues from. A
//! sidecar beside it keeps the server's validator (`ETag`) and the total, and a resumed
//! request carries `If-Range` with that validator, so a publication that changed on the
//! server is sent whole rather than spliced onto the old bytes. A `206` is only appended when
//! its `Content-Range` starts where the file ends and names the total the first response did.

use std::cell::RefCell;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::io::CancelToken;
use crate::net::{HttpClient, HttpError, Request, Response};

/// How a transfer started, which the queue states to the reader.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Resumption {
    /// From the first byte, with nothing kept from before.
    Fresh,
    /// From the byte the partial file ended at.
    Resumed { from: u64 },
    /// From the first byte again, because the server would not continue: no range support,
    /// a changed file, or an answer that did not fit the bytes already kept.
    Restarted,
}

/// What a finished transfer produced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transferred {
    pub resumption: Resumption,
    /// The bytes in the partial file, all of them, now.
    pub length: u64,
}

/// Why a transfer stopped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransferError {
    /// The network failed: worth retrying.
    Network(HttpError),
    /// A status that is not the publication: a 404, a 401, a 500.
    Http(u16),
    /// The body stopped short of the total the server named.
    Short { received: u64, expected: u64 },
    /// The disk refused a write; carries the OS message (a full disk says so).
    Disk(String),
    Cancelled,
}

impl TransferError {
    /// Whether an automatic retry may succeed.
    pub fn is_transient(&self) -> bool {
        match self {
            Self::Network(_) | Self::Short { .. } => true,
            Self::Http(status) => *status >= 500 || *status == 408 || *status == 429,
            Self::Disk(_) | Self::Cancelled => false,
        }
    }
}

impl std::fmt::Display for TransferError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Network(error) => write!(f, "{error}"),
            Self::Http(status) => write!(f, "the server answered {status}"),
            Self::Short { received, expected } => {
                write!(f, "the transfer stopped at {received} of {expected} bytes")
            }
            Self::Disk(detail) => write!(f, "the download could not be written: {detail}"),
            Self::Cancelled => f.write_str("cancelled"),
        }
    }
}

impl std::error::Error for TransferError {}

/// What the sidecar remembers between attempts.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct Validator {
    etag: Option<String>,
    total: Option<u64>,
}

fn sidecar(part: &Path) -> PathBuf {
    let mut name = part.as_os_str().to_owned();
    name.push(".json");
    PathBuf::from(name)
}

fn read_validator(part: &Path) -> Validator {
    std::fs::read(sidecar(part))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn write_validator(part: &Path, validator: &Validator) -> Result<(), String> {
    let bytes = serde_json::to_vec(validator).map_err(|e| e.to_string())?;
    std::fs::write(sidecar(part), bytes).map_err(|e| e.to_string())
}

/// Removes a partial file and its sidecar: a cancel, or a finished download moved away.
pub fn discard(part: &Path) {
    let _ = std::fs::remove_file(part);
    let _ = std::fs::remove_file(sidecar(part));
}

/// The bytes kept so far.
pub fn kept(part: &Path) -> u64 {
    std::fs::metadata(part).map(|m| m.len()).unwrap_or(0)
}

/// How the head of a response fits the bytes kept.
enum Fit {
    Append,
    StartOver,
    AlreadyWhole,
}

fn fit(response: &Response, kept: u64, remembered: &Validator) -> Result<Fit, String> {
    match response.status {
        206 => {
            let starts_at_end = response.range_start() == Some(kept);
            let same_total = match (remembered.total, response.range_total()) {
                (Some(before), Some(now)) => before == now,
                _ => true,
            };
            Ok(if kept > 0 && starts_at_end && same_total {
                Fit::Append
            } else {
                Fit::StartOver
            })
        }
        200..=299 => Ok(Fit::StartOver),
        416 if kept > 0 && remembered.total == Some(kept) => Ok(Fit::AlreadyWhole),
        status => Err(format!("status {status}")),
    }
}

/// Fetches `request` into `part`, continuing what is already there when the server allows,
/// and calling `progress(received, total)` as bytes land.
pub fn transfer(
    http: &HttpClient,
    request: Request,
    part: &Path,
    cancel: &CancelToken,
    mut progress: impl FnMut(u64, Option<u64>),
) -> Result<Transferred, TransferError> {
    if let Some(parent) = part.parent() {
        std::fs::create_dir_all(parent).map_err(|e| TransferError::Disk(e.to_string()))?;
    }
    let remembered = read_validator(part);
    let had = kept(part);
    let mut attempt = request.clone();
    if had > 0 {
        attempt = attempt.range(had, None);
        attempt.if_range = remembered.etag.clone();
    }

    // Shared by the head and the body callbacks: the file opened for the chosen mode, how the
    // transfer started, what arrived, and the total the head named.
    let state: RefCell<Option<(File, Resumption, u64, Option<u64>)>> = RefCell::new(None);
    let status: RefCell<Option<u16>> = RefCell::new(None);
    let outcome = http.stream(
        attempt,
        cancel,
        |head| {
            *status.borrow_mut() = Some(head.status);
            let fitted = fit(head, had, &remembered)?;
            let (file, resumption, base, total) = match fitted {
                Fit::AlreadyWhole => return Ok(()),
                Fit::Append => {
                    let file = OpenOptions::new()
                        .append(true)
                        .open(part)
                        .map_err(|e| e.to_string())?;
                    (file, Resumption::Resumed { from: had }, had, head.range_total())
                }
                Fit::StartOver => {
                    let file = File::create(part).map_err(|e| e.to_string())?;
                    let resumption = if had > 0 {
                        Resumption::Restarted
                    } else {
                        Resumption::Fresh
                    };
                    let total = head.range_total().or(head.content_length);
                    (file, resumption, 0, total)
                }
            };
            write_validator(
                part,
                &Validator {
                    etag: head.etag.clone(),
                    total,
                },
            )?;
            *state.borrow_mut() = Some((file, resumption, base, total));
            Ok(())
        },
        |chunk| {
            let mut slot = state.borrow_mut();
            let Some((file, _, received, total)) = slot.as_mut() else {
                return Ok(());
            };
            file.write_all(chunk).map_err(|e| e.to_string())?;
            *received += chunk.len() as u64;
            progress(*received, *total);
            Ok(())
        },
    );

    let finished_status = *status.borrow();
    match outcome {
        Ok(_) => {}
        Err(HttpError::Cancelled) => return Err(TransferError::Cancelled),
        Err(HttpError::Sink(reason)) => {
            return Err(match finished_status {
                Some(code) if !(200..300).contains(&code) && code != 416 => {
                    TransferError::Http(code)
                }
                _ => TransferError::Disk(reason),
            });
        }
        Err(error) => return Err(TransferError::Network(error)),
    }
    let Some((file, resumption, received, total)) = state.into_inner() else {
        // A 416 for a file already whole.
        return Ok(Transferred {
            resumption: Resumption::Resumed { from: had },
            length: had,
        });
    };
    file.sync_all().map_err(|e| TransferError::Disk(e.to_string()))?;
    if let Some(expected) = total
        && received != expected
    {
        return Err(TransferError::Short { received, expected });
    }
    Ok(Transferred {
        resumption,
        length: received,
    })
}
