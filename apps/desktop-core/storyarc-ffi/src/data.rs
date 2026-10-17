//! Wave 3 exports for the reader's data: the secret vault, the download queue's rules, the
//! shelves and their offline edits, the library document and its sync, sealed secrets, the
//! diagnostic's text and what a folder weighs. The pure rules take a value and an operation
//! as JSON and give the new value back, so C# keeps the state and the core keeps the rules.

use std::collections::BTreeMap;
use std::ffi::c_void;

use serde::Deserialize;
use serde_json::{Value, json};
use storyarc_core::diagnostics::DiagnosticReport;
use storyarc_core::domain::Timestamp;
use storyarc_core::downloads::policy::{DownloadPolicy, NetworkState};
use storyarc_core::downloads::queue::{Download, DownloadQueue, FailureReason};
use storyarc_core::portability::document::LibrarySecrets;
use storyarc_core::portability::{
    FolderPlace, LibrarySnapshot, LibrarySync, Merged, SyncOutcome, decode, encode, merging,
    sealing,
};
use storyarc_core::runtime::Runtime;
use storyarc_core::secrets::Secret;
use storyarc_core::secure_store::{SaveOutcome, SecretKey, Vault, system_store};
use storyarc_core::shelves::{
    PublicationCollection, ReadingList, ShelfEditQueue, ShelfPull, ShelfSnapshot, Shelves,
};

use crate::records::{
    RUNTIME, VAULT, bytes_arg, clear, document_failure, invalid, json_arg, sealing_failure,
    write_bytes, write_json,
};
use crate::seam::{borrow, guard, into_handle, release, utf8, write};
use crate::{
    STORYARC_ERROR_NOT_FOUND, STORYARC_ERROR_STORAGE, STORYARC_ERROR_UNREACHABLE, StoryArcBuffer,
    fail,
};

/// Opens the vault over the system's store (Credential Manager on Windows), or over the
/// session alone when none runs. Free it with `storyarc_vault_free`.
///
/// # Safety
///
/// `runtime` must be a live runtime handle; `out_vault` must point to storage for a pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_vault_open(
    runtime: *const c_void,
    out_vault: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_vault, std::ptr::null_mut(), "out_vault")? };
        let runtime: &Runtime = unsafe { borrow(runtime, RUNTIME, "runtime")? };
        let vault = Vault::new(system_store(runtime));
        unsafe { out_vault.write(into_handle(VAULT, vault)) };
        Ok(())
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct KeyRequest {
    source_id: String,
    field: String,
}

fn vault_failure(error: &impl std::fmt::Display) -> i32 {
    fail(STORYARC_ERROR_STORAGE, &error.to_string())
}

/// Saves the secret (`secret_len` UTF-8 bytes) under `{"sourceId", "field"}`. Writes
/// `{"stored": true}`, or `{"stored": false, "notice": "..."}` when it is held for the
/// session only, the notice present the first time only.
///
/// # Safety
///
/// `vault` must be a live vault handle; `key` and `secret` must point to their lengths in
/// readable bytes; `out` must point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_vault_save(
    vault: *const c_void,
    key: *const u8,
    key_len: usize,
    secret: *const u8,
    secret_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let vault: &Vault = unsafe { borrow(vault, VAULT, "vault")? };
        let key: KeyRequest = unsafe { json_arg(key, key_len, "key")? };
        let secret = Secret::from(unsafe { utf8(secret, secret_len, "secret")? });
        let outcome = vault
            .save(&SecretKey::for_source(&key.source_id, &key.field), secret)
            .map_err(|e| vault_failure(&e))?;
        let value = match outcome {
            SaveOutcome::Stored => json!({ "stored": true }),
            SaveOutcome::SessionOnly { notice } => {
                json!({ "stored": false, "notice": notice.map(|n| n.remedy) })
            }
        };
        unsafe { write_json(out, &value) }
    })
}

/// Writes the secret under `{"sourceId", "field"}` to `out` as UTF-8, or returns
/// `STORYARC_ERROR_NOT_FOUND`. Free `out` as soon as the secret has been used.
///
/// # Safety
///
/// As `storyarc_vault_save`, without the secret.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_vault_load(
    vault: *const c_void,
    key: *const u8,
    key_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let vault: &Vault = unsafe { borrow(vault, VAULT, "vault")? };
        let key: KeyRequest = unsafe { json_arg(key, key_len, "key")? };
        let secret = vault
            .load(&SecretKey::for_source(&key.source_id, &key.field))
            .map_err(|e| vault_failure(&e))?
            .ok_or_else(|| {
                fail(
                    STORYARC_ERROR_NOT_FOUND,
                    "no secret is held for that source",
                )
            })?;
        unsafe { write_bytes(out, secret.expose().as_bytes().to_vec()) }
    })
}

/// Removes the secret under `{"sourceId", "field"}` from the store and the session.
///
/// # Safety
///
/// `vault` must be a live vault handle; `key` must point to `key_len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_vault_delete(
    vault: *const c_void,
    key: *const u8,
    key_len: usize,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let vault: &Vault = unsafe { borrow(vault, VAULT, "vault")? };
        let key: KeyRequest = unsafe { json_arg(key, key_len, "key")? };
        vault
            .delete(&SecretKey::for_source(&key.source_id, &key.field))
            .map_err(|e| vault_failure(&e))
    })
}

/// Releases the vault; session-only secrets go with it. Null is ignored.
///
/// # Safety
///
/// `vault` must be null or a live vault handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_vault_free(vault: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<Vault>(vault, VAULT) };
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", tag = "op")]
enum QueueOp {
    Queue {
        download: Download,
    },
    Pause {
        id: String,
    },
    Resume {
        id: String,
    },
    PauseAll,
    ResumeAll,
    Remove {
        id: String,
    },
    Move {
        id: String,
        to: usize,
    },
    Advance {
        id: String,
        downloaded: u64,
        expected: Option<u64>,
    },
    Fail {
        id: String,
        reason: FailureReason,
        retryable: bool,
    },
    FailVerification {
        id: String,
        reason: FailureReason,
    },
    Finish {
        id: String,
        bytes: u64,
        at: i64,
    },
    Hold {
        network: NetworkState,
        policy: DownloadPolicy,
        used: u64,
    },
    Reclaim,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct QueueRequest {
    #[serde(default)]
    queue: DownloadQueue,
    #[serde(default)]
    ops: Vec<QueueOp>,
    /// When present, the rows that may start now are named in the answer.
    startable: Option<(NetworkState, DownloadPolicy)>,
}

/// Applies the reader's and the network's changes to the download queue, in order:
/// `{"queue", "ops": [{"op": "queue" | "pause" | "resume" | "pauseAll" | "resumeAll" |
/// "remove" | "move" | "advance" | "fail" | "failVerification" | "finish" | "hold" |
/// "reclaim", ...}], "startable"?: [network, policy]}`. Writes `{"queue", "startable",
/// "retry": [[id, backoffSeconds]]}`.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_queue_apply(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: QueueRequest = unsafe { json_arg(request, request_len, "request")? };
        let queue = request
            .ops
            .into_iter()
            .fold(request.queue, |q, op| match op {
                QueueOp::Queue { download } => q.queueing(download),
                QueueOp::Pause { id } => q.pausing(&id),
                QueueOp::Resume { id } => q.resuming(&id),
                QueueOp::PauseAll => q.pausing_all(),
                QueueOp::ResumeAll => q.resuming_all(),
                QueueOp::Remove { id } => q.removing(&id),
                QueueOp::Move { id, to } => q.moving(&id, to),
                QueueOp::Advance {
                    id,
                    downloaded,
                    expected,
                } => q.advancing(&id, downloaded, expected),
                QueueOp::Fail {
                    id,
                    reason,
                    retryable,
                } => q.failing(&id, reason, retryable),
                QueueOp::FailVerification { id, reason } => q.failing_verification(&id, reason),
                QueueOp::Finish { id, bytes, at } => q.finishing(&id, bytes, at),
                QueueOp::Hold {
                    network,
                    policy,
                    used,
                } => q.holding(network, &policy, used),
                QueueOp::Reclaim => q.reclaiming(),
            });
        let startable = request
            .startable
            .map(|(network, policy)| queue.startable(network, &policy));
        let retry: Vec<(String, u64)> = queue
            .downloads()
            .iter()
            .filter(|d| DownloadQueue::should_retry(d))
            .map(|d| match d.state {
                storyarc_core::downloads::queue::DownloadState::Failed { attempts, .. } => {
                    (d.id.clone(), DownloadQueue::backoff(attempts).as_secs())
                }
                _ => (d.id.clone(), 0),
            })
            .collect();
        unsafe {
            write_json(
                out,
                &json!({ "queue": queue, "startable": startable, "retry": retry }),
            )
        }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", tag = "op")]
enum ShelfOp {
    CreateCollection {
        name: String,
        id: Option<String>,
    },
    RenameCollection {
        id: String,
        name: String,
    },
    AddMembers {
        id: String,
        members: Vec<String>,
    },
    RemoveMembers {
        id: String,
        members: Vec<String>,
    },
    SetCollectionCover {
        id: String,
        member: Option<String>,
    },
    DeleteCollection {
        id: String,
    },
    CreateList {
        name: String,
        id: Option<String>,
    },
    RenameList {
        id: String,
        name: String,
    },
    Append {
        id: String,
        entries: Vec<String>,
    },
    RemoveEntry {
        id: String,
        entry: String,
    },
    MoveEntry {
        id: String,
        entry: String,
        to: usize,
    },
    SetListCover {
        id: String,
        member: Option<String>,
    },
    DeleteList {
        id: String,
    },
    RemoveSource {
        source_id: String,
    },
}

#[derive(Deserialize)]
struct ShelvesRequest {
    #[serde(default)]
    shelves: Shelves,
    #[serde(default)]
    ops: Vec<ShelfOp>,
}

/// Applies shelf operations in order: `{"shelves", "ops": [{"op": "createCollection" |
/// "renameCollection" | "addMembers" | "removeMembers" | "setCollectionCover" |
/// "deleteCollection" | "createList" | "renameList" | "append" | "removeEntry" | "moveEntry" |
/// "setListCover" | "deleteList" | "removeSource", ...}]}`. Writes the shelves.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_shelves_apply(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: ShelvesRequest = unsafe { json_arg(request, request_len, "request")? };
        fn refs(items: &[String]) -> Vec<&str> {
            items.iter().map(String::as_str).collect()
        }
        let shelves = request
            .ops
            .into_iter()
            .fold(request.shelves, |s, op| match op {
                ShelfOp::CreateCollection { name, id } => {
                    let mut made = PublicationCollection::local(name);
                    if let Some(id) = id.as_deref().and_then(storyarc_core::shelves::shelf_id) {
                        made.id = id;
                    }
                    s.adding_collection(made)
                }
                ShelfOp::RenameCollection { id, name } => s.renaming_collection(&id, &name),
                ShelfOp::AddMembers { id, members } => s.adding_members(refs(&members), &id),
                ShelfOp::RemoveMembers { id, members } => s.removing_members(refs(&members), &id),
                ShelfOp::SetCollectionCover { id, member } => {
                    s.setting_collection_cover(member.as_deref(), &id)
                }
                ShelfOp::DeleteCollection { id } => s.deleting_collection(&id),
                ShelfOp::CreateList { name, id } => {
                    let mut made = ReadingList::local(name);
                    if let Some(id) = id.as_deref().and_then(storyarc_core::shelves::shelf_id) {
                        made.id = id;
                    }
                    s.adding_list(made)
                }
                ShelfOp::RenameList { id, name } => s.renaming_list(&id, &name),
                ShelfOp::Append { id, entries } => s.appending(refs(&entries), &id),
                ShelfOp::RemoveEntry { id, entry } => s.removing_entry(&entry, &id),
                ShelfOp::MoveEntry { id, entry, to } => s.moving_entry(&entry, to, &id),
                ShelfOp::SetListCover { id, member } => {
                    s.setting_list_cover(member.as_deref(), &id)
                }
                ShelfOp::DeleteList { id } => s.deleting_list(&id),
                ShelfOp::RemoveSource { source_id } => s.removing_all_from(&source_id),
            });
        unsafe { write_json(out, &shelves) }
    })
}

#[derive(Deserialize)]
struct PullRequest {
    queue: ShelfEditQueue,
    /// What each server shelf that answered holds now.
    remote: Vec<ShelfSnapshot>,
}

/// Reconciles the offline edits with the shelves that answered: `{"queue", "remote"}`.
/// Writes `{"toPush", "toDrop", "conflicts": [{"shelf", "discarded"}]}`; the caller pushes,
/// then records the baselines and the notices in its queue.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_shelf_pull(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: PullRequest = unsafe { json_arg(request, request_len, "request")? };
        let pull = ShelfPull::merging(&request.remote, &request.queue);
        let conflicts: Vec<Value> = pull
            .conflicts
            .iter()
            .map(|(shelf, discarded)| json!({ "shelf": shelf, "discarded": discarded }))
            .collect();
        unsafe {
            write_json(
                out,
                &json!({ "toPush": pull.to_push, "toDrop": pull.to_drop, "conflicts": conflicts }),
            )
        }
    })
}

fn merged_json(merged: &Merged) -> Value {
    json!({
        "snapshot": merged.snapshot,
        "conflicts": merged.conflicts.iter().map(|c| json!({
            "resolved": c.resolved, "discarded": c.discarded,
        })).collect::<Vec<_>>(),
        "pinsAdded": merged.pins_added,
        "sourcesNeedingSignIn": merged.sources_needing_sign_in,
        "membersAdded": merged.members_added,
    })
}

/// Imports a library document (`document_len` bytes) into the snapshot JSON this device holds,
/// merging record by record, and writes `{"snapshot", "conflicts", "pinsAdded",
/// "sourcesNeedingSignIn", "membersAdded"}`. A newer format is `STORYARC_ERROR_UNSUPPORTED`
/// naming both versions; over 64 MiB is refused before parsing.
///
/// # Safety
///
/// Each input must point to its length in readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_library_import(
    document: *const u8,
    document_len: usize,
    snapshot: *const u8,
    snapshot_len: usize,
    device: *const u8,
    device_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let bytes = unsafe { bytes_arg(document, document_len, "document")? };
        let local: LibrarySnapshot = unsafe { json_arg(snapshot, snapshot_len, "snapshot")? };
        let device = unsafe { utf8(device, device_len, "device")? };
        let document = decode(&bytes).map_err(|e| document_failure(&e))?;
        unsafe { write_json(out, &merged_json(&merging(&document, &local, device))) }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExportRequest {
    snapshot: LibrarySnapshot,
    app_version: String,
    device: String,
    /// Unix seconds.
    now: i64,
    #[serde(default)]
    for_sync: bool,
    /// When present, the secrets to carry sealed under it: `{"passphrase", "secrets": {id: text}}`.
    sealed: Option<SealRequest>,
}

/// Writes the library document for `{"snapshot", "appVersion", "device", "now", "forSync"?,
/// "sealed"?}`: secrets out of every address, and sealed under the passphrase only when asked.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_library_export(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: ExportRequest = unsafe { json_arg(request, request_len, "request")? };
        let mut document = request.snapshot.document(
            &request.app_version,
            Timestamp(request.now),
            &request.device,
            request.for_sync,
        );
        if let Some(sealed) = request.sealed {
            document.secrets = Some(seal(sealed)?);
        }
        unsafe { write_bytes(out, encode(&document)) }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncRequest {
    folder: String,
    device: String,
    app_version: String,
    now: i64,
    snapshot: LibrarySnapshot,
}

/// Synchronises with the document in the folder the reader chose: `{"folder", "device",
/// "appVersion", "now", "snapshot"}`. Writes the merge as `storyarc_library_import` does, with
/// `"copies"` merged and removed. An unreachable folder is `STORYARC_ERROR_UNREACHABLE`
/// (grey); a document from a newer app is `STORYARC_ERROR_UNSUPPORTED`; losing every attempt
/// to another device is `STORYARC_ERROR_UNREACHABLE` with "busy" in the message.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_library_sync(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: SyncRequest = unsafe { json_arg(request, request_len, "request")? };
        let sync = LibrarySync::new(
            FolderPlace::new(&request.folder),
            request.device,
            request.app_version,
        );
        let outcome = sync
            .sync(&request.snapshot, Timestamp(request.now))
            .map_err(|e| fail(STORYARC_ERROR_UNREACHABLE, &e.0))?;
        let value = match outcome {
            SyncOutcome::Synced { merged, copies } => {
                let mut value = merged_json(&merged);
                value["copies"] = json!(copies);
                value
            }
            SyncOutcome::Refused(failure) => return Err(document_failure(&failure)),
            SyncOutcome::Busy => {
                return Err(fail(
                    STORYARC_ERROR_UNREACHABLE,
                    "busy: another device kept writing",
                ));
            }
        };
        unsafe { write_json(out, &value) }
    })
}

#[derive(Deserialize)]
struct SealRequest {
    passphrase: String,
    secrets: BTreeMap<String, String>,
}

fn seal(request: SealRequest) -> Result<LibrarySecrets, i32> {
    let secrets = request
        .secrets
        .into_iter()
        .map(|(id, text)| (id, Secret::from(text)))
        .collect();
    sealing::seal(&secrets, &Secret::from(request.passphrase)).map_err(|e| sealing_failure(&e))
}

#[derive(Deserialize)]
struct OpenRequest {
    passphrase: String,
    secrets: LibrarySecrets,
}

/// Opens a document's sealed secrets: `{"passphrase", "secrets"}`. Writes `{id: secret}` for
/// the caller to hand straight to the vault. A wrong passphrase is
/// `STORYARC_ERROR_UNAUTHORIZED`, and nothing opens.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_secrets_open(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: OpenRequest = unsafe { json_arg(request, request_len, "request")? };
        let opened = sealing::open(&request.secrets, &Secret::from(request.passphrase))
            .map_err(|e| sealing_failure(&e))?;
        let plain: BTreeMap<&String, &str> =
            opened.iter().map(|(id, s)| (id, s.expose())).collect();
        unsafe { write_json(out, &plain) }
    })
}

#[derive(Deserialize)]
struct DiagnosticSection {
    name: String,
    lines: Vec<(String, String)>,
}

#[derive(Deserialize)]
struct DiagnosticRequest {
    title: String,
    sections: Vec<DiagnosticSection>,
    /// Every secret the app holds, removed from the text in every encoding.
    #[serde(default)]
    secrets: Vec<String>,
}

/// The diagnostic's text for `{"title", "sections": [{"name", "lines": [[key, value]]}],
/// "secrets": [...]}`: every held secret and every hostname removed, then the phones' rules.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_diagnostic_render(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: DiagnosticRequest = unsafe { json_arg(request, request_len, "request")? };
        let mut report = DiagnosticReport::new(request.title);
        for section in &request.sections {
            report.section(
                &section.name,
                section.lines.iter().map(|(k, v)| (k.as_str(), v.as_str())),
            );
        }
        let held: Vec<Secret> = request.secrets.into_iter().map(Secret::from).collect();
        let refs: Vec<&Secret> = held.iter().collect();
        unsafe { write_bytes(out, report.render(&refs).into_bytes()) }
    })
}

/// Writes what every file under the UTF-8 `path` weighs to `out_bytes`, for the storage view;
/// a missing folder weighs nothing.
///
/// # Safety
///
/// `path` must point to `path_len` readable bytes; `out_bytes` to one writable `uint64_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_storage_bytes(
    path: *const u8,
    path_len: usize,
    out_bytes: *mut u64,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_bytes, 0, "out_bytes")? };
        let path = unsafe { utf8(path, path_len, "path")? };
        if path.is_empty() {
            return Err(invalid("the path is empty"));
        }
        let bytes = storyarc_core::downloads::DownloadFolder::new(path).bytes_on_disk();
        unsafe { write(out_bytes, bytes, "out_bytes") }
    })
}

/// Seals secrets for an export on their own: `{"passphrase", "secrets": {id: text}}`. Writes
/// the `secrets` object a document carries.
///
/// # Safety
///
/// `request` must point to `request_len` readable bytes; `out` to one writable buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_secrets_seal(
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let request: SealRequest = unsafe { json_arg(request, request_len, "request")? };
        let sealed = seal(request)?;
        unsafe { write_json(out, &sealed) }
    })
}
