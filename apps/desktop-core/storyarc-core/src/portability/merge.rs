//! What a device holds, and how a document merges into it (`library-portability`, *Import
//! merges*; `library-sync`, *Two devices that both moved*), mirrored from StoryArcKit's
//! `LibrarySyncMerge`, `ShelfStamps` and `ChangeStamps`.
//!
//! Record by record, never a wholesale replace: progress by ADR-0006 (furthest wins, finished
//! stays finished, an absent watermark is not a local move); shelves by membership union, with
//! a deletion travelling as a tombstone; settings by last writer per field; sources, pins and
//! chosen covers added where the device lacks them. A record Kavita holds stays Kavita's.

use std::collections::{BTreeMap, BTreeSet};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Map, Value};

use super::coder::exportable_address;
use super::document::{
    DocumentCollection, DocumentCover, DocumentReadingList, DocumentSource, DocumentStamp,
    DocumentTombstone, LibraryBody, LibraryDocument,
};
use crate::domain::{ProgressPull, PullConflict, ReadingProgress, Timestamp};
use crate::shelves::{
    PinnedShelves, PublicationCollection, ReadingList, ShelfOrigin, Shelves, shelf_id,
};

/// The largest chosen cover an import keeps: 8 MB.
pub const MAXIMUM_COVER_BYTES: usize = 8 * 1024 * 1024;

/// Everything a device holds that a document carries.
#[derive(Debug, Clone, PartialEq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LibrarySnapshot {
    pub sources: Vec<DocumentSource>,
    pub certificate_pins: BTreeMap<String, Vec<String>>,
    pub shelves: Shelves,
    pub removed_shelves: Vec<DocumentTombstone>,
    pub pinned_shelves: PinnedShelves,
    pub settings: Map<String, Value>,
    /// When each setting last changed on this device.
    pub settings_changed_at: BTreeMap<String, Timestamp>,
    pub themes: Value,
    pub progress: Vec<ReadingProgress>,
    pub covers: Vec<DocumentCover>,
}

impl LibrarySnapshot {
    /// Whether Kavita owns this record's position: it names a Kavita source.
    pub fn owned_by_kavita(&self, record: &ReadingProgress) -> bool {
        record.identity.server_identifier.as_ref().is_some_and(|s| {
            self.sources
                .iter()
                .any(|source| source.kind == "kavitaServer" && source.id == s.source_id)
        })
    }

    /// The document this snapshot writes: secrets out of every address, and for a sync
    /// document Kavita's own positions left to Kavita.
    pub fn document(
        &self,
        app_version: &str,
        now: Timestamp,
        device: &str,
        for_sync: bool,
    ) -> LibraryDocument {
        let progress = self
            .progress
            .iter()
            .filter(|p| !(for_sync && self.owned_by_kavita(p)))
            .map(|p| ReadingProgress {
                synced_position: None,
                ..p.clone()
            })
            .collect();
        let mut settings = self.settings.clone();
        if !self.settings_changed_at.is_empty() {
            let stamps: Map<String, Value> = self
                .settings_changed_at
                .iter()
                .map(|(k, at)| {
                    let stamp = DocumentStamp {
                        at: *at,
                        by: Some(device.to_owned()),
                    };
                    (
                        k.clone(),
                        serde_json::to_value(stamp).unwrap_or(Value::Null),
                    )
                })
                .collect();
            settings.insert("changed".into(), Value::Object(stamps));
        }
        let body = LibraryBody {
            sources: self
                .sources
                .iter()
                .map(|s| DocumentSource {
                    locator: s.locator.as_deref().map(exportable_address),
                    ..s.clone()
                })
                .collect(),
            certificate_pins: self.certificate_pins.clone(),
            collections: self
                .shelves
                .collections
                .iter()
                .filter(|c| c.origin == ShelfOrigin::Local)
                .map(|c| DocumentCollection {
                    id: c.id.clone(),
                    name: c.name.clone(),
                    members: c.members.iter().cloned().collect(),
                    cover_member_id: c.cover_member_id.clone(),
                    changed_at: (c.changed_at != Timestamp::default()).then_some(c.changed_at),
                    changed_by: None,
                })
                .collect(),
            reading_lists: self
                .shelves
                .lists
                .iter()
                .filter(|l| l.origin == ShelfOrigin::Local)
                .map(|l| DocumentReadingList {
                    id: l.id.clone(),
                    name: l.name.clone(),
                    entries: l.entries.clone(),
                    cover_member_id: l.cover_member_id.clone(),
                    changed_at: (l.changed_at != Timestamp::default()).then_some(l.changed_at),
                    changed_by: None,
                })
                .collect(),
            pinned_shelves: self.pinned_shelves.tokens(),
            settings,
            reading_themes: self.themes.clone(),
            progress,
            covers: self.covers.clone(),
            removed_shelves: (!self.removed_shelves.is_empty())
                .then(|| self.removed_shelves.clone()),
        };
        LibraryDocument {
            written_by: device.to_owned(),
            ..LibraryDocument::new(app_version, now, body)
        }
    }
}

/// What a merge produced, and what the reader is told.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Merged {
    pub snapshot: LibrarySnapshot,
    /// Positions that diverged on both sides: told once, naming both.
    pub conflicts: Vec<PullConflict>,
    /// Hosts that gained a pinned certificate from the document.
    pub pins_added: Vec<String>,
    /// Sources the document added that need a sign-in.
    pub sources_needing_sign_in: Vec<String>,
    /// Members and entries the document added to shelves this device already had.
    pub members_added: usize,
}

/// The settings defaults the phones share, for the "changed, with no stamp" rule.
fn setting_default(key: &str) -> Value {
    match key {
        "appearance" => Value::from("system"),
        "turnPagesByTappingTheEdges" => Value::from(true),
        "linkReadingThemeToAppearance"
        | "downloadOverWifiOnly"
        | "removeDownloadsAfterFinishing" => Value::from(false),
        "lightReadingTheme" => Value::from("paper"),
        "darkReadingTheme" => Value::from("quiet"),
        _ => Value::Null,
    }
}

/// A value with no stamp counts as changed at the first second when it differs from the
/// default, and as never changed when it is the default.
fn unstamped(key: &str, value: Option<&Value>) -> i64 {
    let value = value.cloned().unwrap_or_else(|| setting_default(key));
    if value == setting_default(key) { 0 } else { 1 }
}

fn merge_settings(
    local: &LibrarySnapshot,
    document: &LibraryBody,
    device: &str,
) -> (Map<String, Value>, BTreeMap<String, Timestamp>) {
    let stamps: BTreeMap<String, DocumentStamp> = document
        .settings
        .get("changed")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    let keys: BTreeSet<&String> = local
        .settings
        .keys()
        .chain(document.settings.keys())
        .filter(|k| *k != "changed")
        .collect();
    let mut value = local.settings.clone();
    let mut changed = BTreeMap::new();
    for key in keys {
        let mine = local
            .settings_changed_at
            .get(key)
            .map(|t| t.0)
            .unwrap_or_else(|| unstamped(key, local.settings.get(key)));
        let theirs = stamps.get(key);
        let theirs_at = theirs
            .map(|s| s.at.0)
            .unwrap_or_else(|| unstamped(key, document.settings.get(key)));
        let differ = local.settings.get(key) != document.settings.get(key);
        let by = theirs.and_then(|s| s.by.clone()).unwrap_or_default();
        let remote_wins = theirs_at > mine
            || (theirs_at == mine && theirs_at > 0 && differ && by.as_str() > device);
        if remote_wins {
            match document.settings.get(key) {
                Some(v) => value.insert(key.clone(), v.clone()),
                None => value.remove(key),
            };
            changed.insert(key.clone(), Timestamp(theirs_at));
        } else if let Some(held) = local.settings_changed_at.get(key) {
            changed.insert(key.clone(), *held);
        }
    }
    (value, changed)
}

fn tombstones(
    local: &[DocumentTombstone],
    arriving: &[DocumentTombstone],
) -> BTreeMap<String, DocumentTombstone> {
    let mut removed: BTreeMap<String, DocumentTombstone> = BTreeMap::new();
    for t in local.iter().chain(arriving) {
        let Some(id) = shelf_id(&t.id) else { continue };
        if removed
            .get(&id)
            .is_none_or(|held| held.removed_at < t.removed_at)
        {
            removed.insert(id.clone(), DocumentTombstone { id, ..t.clone() });
        }
    }
    removed
}

fn merge_shelves(local: &LibrarySnapshot, document: &LibraryBody, merged: &mut Merged) {
    let removed = tombstones(
        &local.removed_shelves,
        document.removed_shelves.as_deref().unwrap_or_default(),
    );
    // A shelf changed after its deletion outlives the deletion; otherwise the deletion wins.
    let survives =
        |id: &str, changed: Timestamp| removed.get(id).is_none_or(|t| changed > t.removed_at);
    let mut shelves = Shelves::default();
    for c in &local.shelves.collections {
        if survives(&c.id, c.changed_at) {
            shelves = shelves.adding_collection(c.clone());
        }
    }
    for l in &local.shelves.lists {
        if survives(&l.id, l.changed_at) {
            shelves = shelves.adding_list(l.clone());
        }
    }
    for c in &document.collections {
        let Some(id) = shelf_id(&c.id) else { continue };
        let changed = c.changed_at.unwrap_or_default();
        match shelves.collection(&id).cloned() {
            Some(held) => {
                let before = held.members.len();
                shelves = shelves.adding_members(c.members.iter().map(String::as_str), &id);
                merged.members_added += shelves
                    .collection(&id)
                    .map_or(0, |n| n.members.len() - before);
                if changed > held.changed_at {
                    shelves = shelves
                        .renaming_collection(&id, &c.name)
                        .setting_collection_cover(c.cover_member_id.as_deref(), &id);
                }
            }
            None if survives(&id, changed) => {
                shelves = shelves
                    .adding_collection(PublicationCollection {
                        id: id.clone(),
                        changed_at: changed,
                        ..PublicationCollection::local(c.name.clone())
                    })
                    .adding_members(c.members.iter().map(String::as_str), &id)
                    .setting_collection_cover(c.cover_member_id.as_deref(), &id);
            }
            None => {}
        }
    }
    for l in &document.reading_lists {
        let Some(id) = shelf_id(&l.id) else { continue };
        let changed = l.changed_at.unwrap_or_default();
        match shelves.list(&id).cloned() {
            Some(held) => {
                let before = held.entries.len();
                shelves = shelves.appending(l.entries.iter().map(String::as_str), &id);
                merged.members_added += shelves.list(&id).map_or(0, |n| n.entries.len() - before);
                if changed > held.changed_at {
                    shelves = shelves
                        .renaming_list(&id, &l.name)
                        .setting_list_cover(l.cover_member_id.as_deref(), &id);
                }
            }
            None if survives(&id, changed) => {
                shelves = shelves
                    .adding_list(ReadingList {
                        id: id.clone(),
                        changed_at: changed,
                        ..ReadingList::local(l.name.clone())
                    })
                    .appending(l.entries.iter().map(String::as_str), &id)
                    .setting_list_cover(l.cover_member_id.as_deref(), &id);
            }
            None => {}
        }
    }
    let present: BTreeSet<&String> = shelves
        .collections
        .iter()
        .map(|c| &c.id)
        .chain(shelves.lists.iter().map(|l| &l.id))
        .collect();
    merged.snapshot.removed_shelves = removed
        .into_values()
        .filter(|t| !present.contains(&t.id))
        .collect();
    merged.snapshot.shelves = shelves;
}

fn merge_progress(local: &LibrarySnapshot, document: &LibraryBody, merged: &mut Merged) {
    let arriving: Vec<ReadingProgress> = one_per_publication(
        document
            .progress
            .iter()
            .filter(|p| !local.owned_by_kavita(p))
            .cloned()
            .collect(),
    );
    let held = one_per_publication(local.progress.clone());
    let pull = ProgressPull::merging(&arriving, |identity| {
        held.iter().find(|h| h.identity.matches(identity)).cloned()
    });
    let mut records = held;
    for record in pull.to_save {
        match records
            .iter()
            .position(|r| r.identity.matches(&record.identity))
        {
            Some(i) => {
                let identity = records[i].identity.filling(&record.identity);
                records[i] = ReadingProgress { identity, ..record };
            }
            None => records.push(record),
        }
    }
    // The watermark: what both sides now hold is what was last synchronised.
    merged.snapshot.progress = records
        .into_iter()
        .map(|r| {
            if local.owned_by_kavita(&r) {
                r
            } else {
                ReadingProgress {
                    synced_position: Some(r.position.clone()),
                    ..r
                }
            }
        })
        .collect();
    merged.conflicts = pull.conflicts;
}

/// The newest record per publication, with the identities of the others folded in.
fn one_per_publication(mut records: Vec<ReadingProgress>) -> Vec<ReadingProgress> {
    records.sort_by_key(|r| std::cmp::Reverse(r.updated_at));
    let mut kept: Vec<ReadingProgress> = Vec::new();
    for record in records {
        match kept
            .iter()
            .position(|k| k.identity.matches(&record.identity))
        {
            Some(i) => kept[i].identity = kept[i].identity.filling(&record.identity),
            None => kept.push(record),
        }
    }
    kept
}

fn cover_is_usable(cover: &DocumentCover) -> bool {
    STANDARD
        .decode(&cover.image)
        .is_ok_and(|bytes| !bytes.is_empty() && bytes.len() <= MAXIMUM_COVER_BYTES)
}

/// Merges `document` into `local`. `device` names this device for the settings tie-break.
pub fn merging(document: &LibraryDocument, local: &LibrarySnapshot, device: &str) -> Merged {
    let body = &document.library;
    let mut merged = Merged {
        snapshot: local.clone(),
        ..Merged::default()
    };
    merge_shelves(local, body, &mut merged);
    merge_progress(local, body, &mut merged);

    let (settings, changed) = merge_settings(local, body, device);
    merged.snapshot.settings = settings;
    merged.snapshot.settings_changed_at = changed;
    let local_themes_empty = local
        .themes
        .get("entries")
        .and_then(Value::as_array)
        .is_none_or(Vec::is_empty)
        && local.themes.get("customPalette").is_none_or(Value::is_null);
    if local_themes_empty {
        merged.snapshot.themes = body.reading_themes.clone();
    }

    for source in &body.sources {
        let Some(id) = shelf_id(&source.id) else {
            continue;
        };
        if merged
            .snapshot
            .sources
            .iter()
            .any(|s| shelf_id(&s.id).as_deref() == Some(&id))
        {
            continue;
        }
        if source.needs_sign_in {
            merged.sources_needing_sign_in.push(id.clone());
        }
        merged.snapshot.sources.push(DocumentSource {
            id,
            ..source.clone()
        });
    }
    for (host, pins) in &body.certificate_pins {
        let held = merged
            .snapshot
            .certificate_pins
            .entry(host.clone())
            .or_default();
        let before = held.len();
        for pin in pins {
            if !held.contains(pin) {
                held.push(pin.clone());
            }
        }
        if held.len() > before {
            merged.pins_added.push(host.clone());
        }
    }
    let tokens: Vec<String> = local
        .pinned_shelves
        .tokens()
        .into_iter()
        .chain(body.pinned_shelves.iter().cloned())
        .collect();
    merged.snapshot.pinned_shelves = PinnedShelves::of_tokens(tokens.iter().map(String::as_str));
    for cover in &body.covers {
        if !merged.snapshot.covers.iter().any(|c| c.key == cover.key) && cover_is_usable(cover) {
            merged.snapshot.covers.push(cover.clone());
        }
    }
    merged
}

#[cfg(test)]
mod tests {
    use super::*;

    fn document_with(settings: Value) -> LibraryDocument {
        LibraryDocument::new(
            "1",
            Timestamp(0),
            LibraryBody {
                settings: settings.as_object().cloned().unwrap_or_default(),
                ..LibraryBody::default()
            },
        )
    }

    #[test]
    fn a_setting_goes_to_its_last_writer_and_a_tie_to_the_greater_device_name() {
        let local = LibrarySnapshot {
            settings: serde_json::json!({"appearance": "dark", "language": "de"})
                .as_object()
                .cloned()
                .unwrap(),
            settings_changed_at: [
                ("appearance".to_owned(), Timestamp(100)),
                ("language".to_owned(), Timestamp(300)),
            ]
            .into_iter()
            .collect(),
            ..LibrarySnapshot::default()
        };
        let remote = document_with(serde_json::json!({
            "appearance": "light",
            "language": "fr",
            "changed": {
                "appearance": {"at": "1970-01-01T00:03:20Z", "by": "phone"},
                "language": {"at": "1970-01-01T00:03:20Z", "by": "phone"}
            }
        }));
        let merged = merging(&remote, &local, "linux").snapshot;
        assert_eq!(merged.settings["appearance"], "light");
        assert_eq!(merged.settings_changed_at["appearance"], Timestamp(200));
        assert_eq!(merged.settings["language"], "de");

        let tie = LibrarySnapshot {
            settings_changed_at: [("appearance".to_owned(), Timestamp(200))]
                .into_iter()
                .collect(),
            ..local
        };
        assert_eq!(
            merging(&remote, &tie, "linux").snapshot.settings["appearance"],
            "light"
        );
        assert_eq!(
            merging(&remote, &tie, "zebra").snapshot.settings["appearance"],
            "dark"
        );
    }
}
