//! Library portability and sync (task 3.8 of `desktop-clients`).
//!
//! A document written on iOS and one written on Android, from `packages/test-fixtures/library`,
//! decode here to the same library; a document written here re-reads to that library and
//! carries the same keys the phones' decoders read; the sealed-secrets vector opens and
//! seals to the same bytes; and two devices syncing through one folder keep each other's work.

use std::cell::Cell;
use std::collections::BTreeMap;
use std::path::Path;

use serde_json::Value;
use storyarc_core::domain::{ReadingPosition, ReadingProgress, Timestamp};
use storyarc_core::portability::document::{DocumentTombstone, LibrarySecrets};
use storyarc_core::portability::sealing::{self, SealingFailure};
use storyarc_core::portability::sync::{SyncFile, Unreachable};
use storyarc_core::portability::{
    DocumentFailure, FolderPlace, LibraryDocument, LibrarySnapshot, LibrarySync, SyncOutcome,
    SyncPlace, decode, encode, merging,
};
use storyarc_core::secrets::Secret;
use storyarc_core::shelves::{PublicationCollection, ShelfPin, Shelves};

fn fixture_bytes(name: &str) -> Vec<u8> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../packages/test-fixtures/library")
        .join(name);
    std::fs::read(path).unwrap()
}

fn fixture(name: &str) -> LibraryDocument {
    decode(&fixture_bytes(name)).unwrap()
}

// ---- the phones' documents decode here ----------------------------------------------------

#[test]
fn the_ios_and_the_android_documents_decode_to_the_same_library() {
    let ios = fixture("written-by-ios.json");
    let android = fixture("written-by-android.json");
    assert_eq!(ios.written_by, "ios");
    assert_eq!(android.written_by, "android");
    assert_eq!(ios.format_version, 1);
    assert_eq!(
        ios.written_at,
        Timestamp::parse_rfc3339("2026-01-01T00:04:05Z").unwrap()
    );
    let (a, b) = (&ios.library, &android.library);
    assert_eq!(a.sources, b.sources);
    assert_eq!(a.certificate_pins, b.certificate_pins);
    assert_eq!(a.collections, b.collections);
    assert_eq!(a.reading_lists, b.reading_lists);
    assert_eq!(a.pinned_shelves, b.pinned_shelves);
    assert_eq!(a.progress, b.progress);
    assert_eq!(a.covers, b.covers);
    for (key, value) in &a.settings {
        assert_eq!(b.settings.get(key), Some(value), "setting {key}");
    }
}

#[test]
fn the_five_reconciled_records_read_as_the_document_writes_them() {
    let body = fixture("written-by-android.json").library;
    // A source's timestamp is an ISO string, and its kind lower camel case.
    let nas = &body.sources[0];
    assert_eq!(nas.kind, "networkShare");
    assert_eq!(
        nas.last_successful_sync,
        Timestamp::parse_rfc3339("2025-12-31T00:04:05Z")
    );
    assert_eq!(body.sources[1].last_successful_sync, None);
    // A shelf's cover key.
    assert_eq!(
        body.collections[0].cover_member_id.as_deref(),
        Some("path:/b.cbz")
    );
    // The named position fields, Android's nulls and all.
    assert_eq!(body.progress[0].position, ReadingPosition::page(12, 40));
    assert!(matches!(
        body.progress[2].position,
        ReadingPosition::Listening {
            part: 2,
            part_count: 9,
            offset_millis: 61_500,
            of_millis: Some(600_000)
        }
    ));
    // Pinned shelves as a list of tokens.
    assert_eq!(
        body.pinned_shelves,
        [
            "collection:33333333-3333-3333-3333-333333333333",
            "list:44444444-4444-4444-4444-444444444444"
        ]
    );
}

#[test]
fn neither_document_nor_one_written_here_carries_the_fake_secret() {
    for name in ["written-by-ios.json", "written-by-android.json"] {
        let bytes = fixture_bytes(name);
        assert!(!String::from_utf8_lossy(&bytes).contains("hunter2"));
        let again = encode(&decode(&bytes).unwrap());
        assert!(!String::from_utf8_lossy(&again).contains("hunter2"));
    }
}

// ---- a document written here decodes on the phones -----------------------------------------

/// Every object key path in `value`, with array items folded together.
fn paths(value: &Value, prefix: &str, out: &mut std::collections::BTreeSet<String>) {
    match value {
        Value::Object(map) => {
            for (key, child) in map {
                if child.is_null() {
                    continue;
                }
                let path = format!("{prefix}/{key}");
                out.insert(path.clone());
                paths(child, &path, out);
            }
        }
        Value::Array(items) => items
            .iter()
            .for_each(|i| paths(i, &format!("{prefix}[]"), out)),
        _ => {}
    }
}

#[test]
fn a_document_written_here_keeps_every_key_the_phones_read_and_reads_back_the_same() {
    for name in ["written-by-ios.json", "written-by-android.json"] {
        let original: Value = serde_json::from_slice(&fixture_bytes(name)).unwrap();
        let document = fixture(name);
        let written = encode(&document);
        let reread: Value = serde_json::from_slice(&written).unwrap();
        let (mut theirs, mut ours) = (Default::default(), Default::default());
        paths(&original, "", &mut theirs);
        paths(&reread, "", &mut ours);
        let missing: Vec<&String> = theirs.difference(&ours).collect();
        assert!(
            missing.is_empty(),
            "{name}: written here without {missing:?}"
        );
        assert_eq!(decode(&written).unwrap(), document);
    }
}

#[test]
fn a_document_written_from_this_device_strips_addresses_and_names_its_platform() {
    let mut snapshot = merging(
        &fixture("written-by-ios.json"),
        &LibrarySnapshot::default(),
        "d",
    )
    .snapshot;
    snapshot.sources[0].locator = Some("smb://reader:hunter2@nas.local/comics".into());
    let document = snapshot.document("1.0.0", Timestamp(1_800_000_000), "linux", false);
    assert_eq!(document.written_by, "linux");
    let text = String::from_utf8(encode(&document)).unwrap();
    assert!(!text.contains("hunter2"));
    assert!(text.contains("smb://reader@nas.local/comics"));
    let back = decode(text.as_bytes()).unwrap();
    assert_eq!(back.library.collections.len(), 1);
    assert_eq!(back.library.progress.len(), 3);
}

// ---- the version rules -----------------------------------------------------------------------

#[test]
fn an_unknown_field_is_ignored_and_an_unreadable_record_is_dropped_alone() {
    let mut value: Value = serde_json::from_slice(&fixture_bytes("written-by-ios.json")).unwrap();
    value["library"]["somethingNew"] = Value::from(true);
    value["library"]["progress"][1]["position"]["kind"] = Value::from("hologram");
    value["library"]["progress"][2]["position"]
        .as_object_mut()
        .unwrap()
        .remove("partCount");
    let document = decode(&serde_json::to_vec(&value).unwrap()).unwrap();
    assert_eq!(document.library.progress.len(), 1);
    assert_eq!(document.library.collections.len(), 1);

    value["formatVersion"] = Value::from(7);
    assert_eq!(
        decode(&serde_json::to_vec(&value).unwrap()),
        Err(DocumentFailure::NewerThanThisApp {
            found: 7,
            understood: 1
        })
    );
}

// ---- sealed secrets: the vector neither app made ------------------------------------------

#[test]
fn the_sealed_secrets_vector_opens_and_seals_to_the_same_bytes() {
    let vector: Value = serde_json::from_slice(&fixture_bytes("sealed-secrets.json")).unwrap();
    let passphrase = Secret::from(vector["passphrase"].as_str().unwrap());
    let sealed: LibrarySecrets = serde_json::from_value(vector["secrets"].clone()).unwrap();
    let plaintexts: BTreeMap<String, String> =
        serde_json::from_value(vector["plaintexts"].clone()).unwrap();

    let opened = sealing::open(&sealed, &passphrase).unwrap();
    assert_eq!(opened.len(), 2);
    for (id, text) in &plaintexts {
        assert_eq!(opened[id].expose(), text);
    }

    let secrets: BTreeMap<String, Secret> = plaintexts
        .iter()
        .map(|(id, text)| (id.clone(), Secret::from(text.as_str())))
        .collect();
    let nonces: BTreeMap<String, Vec<u8>> = [
        ("11111111-1111-1111-1111-111111111111", 0x20u8),
        ("55555555-5555-5555-5555-555555555555", 0x30u8),
    ]
    .into_iter()
    .map(|(id, from)| (id.to_owned(), (from..from + 12).collect()))
    .collect();
    let salt: Vec<u8> = (0..16).collect();
    let resealed = sealing::seal_with(&secrets, &passphrase, &salt, &nonces).unwrap();
    assert_eq!(resealed, sealed);

    assert_eq!(
        sealing::open(&sealed, &Secret::from("wrong")),
        Err(SealingFailure::WrongPassphraseOrDamaged)
    );
    let mut greedy = sealed.clone();
    greedy.iterations = u32::MAX;
    assert_eq!(
        sealing::open(&greedy, &passphrase),
        Err(SealingFailure::Unsupported)
    );
}

// ---- an import merges -----------------------------------------------------------------------

#[test]
fn an_import_merges_members_and_keeps_the_furthest_position() {
    let document = fixture("written-by-ios.json");
    let collection = "33333333-3333-3333-3333-333333333333";
    let mut local = LibrarySnapshot {
        shelves: Shelves::default()
            .adding_collection(PublicationCollection {
                id: collection.into(),
                ..PublicationCollection::local("Image Comics")
            })
            .adding_members(["path:/c.cbz"], collection),
        ..LibrarySnapshot::default()
    };
    // Further along than the document on this device, never synced.
    let mut ahead = document.library.progress[0].clone();
    ahead.position = ReadingPosition::page(30, 40);
    local.progress.push(ahead);

    let merged = merging(&document, &local, "linux");
    let members = &merged
        .snapshot
        .shelves
        .collection(collection)
        .unwrap()
        .members;
    assert_eq!(members.len(), 3);
    assert_eq!(merged.members_added, 2);
    assert_eq!(merged.snapshot.progress.len(), 3);
    let kept = merged
        .snapshot
        .progress
        .iter()
        .find(|p| p.identity.content_digest.as_deref() == Some("d1"))
        .unwrap();
    assert_eq!(kept.position, ReadingPosition::page(30, 40));
    assert!(
        merged.conflicts.is_empty(),
        "an absent watermark is not a local move"
    );
    assert_eq!(merged.pins_added, ["nas.local"]);
    assert_eq!(merged.snapshot.sources.len(), 3);
    assert_eq!(merged.sources_needing_sign_in.len(), 2);
    assert!(merged.snapshot.pinned_shelves.contains(&ShelfPin::List(
        "44444444-4444-4444-4444-444444444444".into()
    )));
    assert_eq!(merged.snapshot.covers.len(), 1);
    assert_eq!(merged.snapshot.settings["appearance"], "oledDark");
}

// ---- two devices through one folder ------------------------------------------------------

fn record(digest: &str, page: i64, at: i64) -> ReadingProgress {
    ReadingProgress::new(
        storyarc_core::domain::PublicationIdentity::digest(digest),
        ReadingPosition::page(page, 100),
        Timestamp(at),
    )
}

#[test]
fn two_devices_keep_each_others_shelves_positions_and_deletions() {
    let dir = tempfile::tempdir().unwrap();
    let laptop = LibrarySync::new(FolderPlace::new(dir.path()), "laptop", "1.0.0");
    let desktop = LibrarySync::new(FolderPlace::new(dir.path()), "desktop", "1.0.0");
    let x = "aaaaaaaa-0000-0000-0000-000000000001";
    let y = "aaaaaaaa-0000-0000-0000-000000000002";

    let mine = LibrarySnapshot {
        shelves: Shelves::default().adding_collection(PublicationCollection {
            id: x.into(),
            changed_at: Timestamp(100),
            ..PublicationCollection::local("X")
        }),
        progress: vec![record("d1", 10, 100)],
        ..LibrarySnapshot::default()
    };
    let SyncOutcome::Synced { merged, .. } = laptop.sync(&mine, Timestamp(110)).unwrap() else {
        panic!("the first sync writes");
    };
    let laptop_state = merged.snapshot;

    let theirs = LibrarySnapshot {
        shelves: Shelves::default().adding_collection(PublicationCollection {
            id: y.into(),
            changed_at: Timestamp(120),
            ..PublicationCollection::local("Y")
        }),
        progress: vec![record("d1", 50, 120)],
        ..LibrarySnapshot::default()
    };
    let SyncOutcome::Synced { merged, .. } = desktop.sync(&theirs, Timestamp(130)).unwrap() else {
        panic!("the second device syncs");
    };
    let desktop_state = merged.snapshot;
    assert!(desktop_state.shelves.collection(x).is_some());
    assert!(desktop_state.shelves.collection(y).is_some());
    assert_eq!(
        desktop_state.progress[0].position,
        ReadingPosition::page(50, 100)
    );

    // The laptop deletes X; the deletion travels and X does not come back.
    let mut deleted = laptop_state.clone();
    deleted.shelves = deleted.shelves.deleting_collection(x);
    deleted.removed_shelves.push(DocumentTombstone {
        id: x.into(),
        removed_at: Timestamp(200),
        removed_by: Some("laptop".into()),
    });
    let SyncOutcome::Synced { merged, .. } = laptop.sync(&deleted, Timestamp(210)).unwrap() else {
        panic!("the laptop syncs");
    };
    assert!(merged.snapshot.shelves.collection(x).is_none());
    assert!(merged.snapshot.shelves.collection(y).is_some());
    assert_eq!(
        merged.snapshot.progress[0].position,
        ReadingPosition::page(50, 100)
    );

    let SyncOutcome::Synced { merged, .. } = desktop.sync(&desktop_state, Timestamp(220)).unwrap()
    else {
        panic!("the desktop syncs");
    };
    assert!(merged.snapshot.shelves.collection(x).is_none());
}

/// A place where another device writes between this device's read and its write, once.
struct Racing {
    inner: FolderPlace,
    raced: Cell<bool>,
    other: Vec<u8>,
}

impl SyncPlace for Racing {
    fn names(&self) -> Result<Vec<String>, Unreachable> {
        self.inner.names()
    }
    fn read(&self, name: &str) -> Result<Option<SyncFile>, Unreachable> {
        self.inner.read(name)
    }
    fn write(&self, name: &str, data: &[u8], replacing: Option<&str>) -> Result<bool, Unreachable> {
        if !self.raced.replace(true) {
            assert!(self.inner.write(name, &self.other, replacing)?);
        }
        self.inner.write(name, data, replacing)
    }
    fn delete(&self, name: &str) -> Result<bool, Unreachable> {
        self.inner.delete(name)
    }
}

#[test]
fn a_device_that_loses_the_race_merges_again_rather_than_overwriting() {
    let dir = tempfile::tempdir().unwrap();
    let other = LibrarySnapshot {
        progress: vec![record("other", 5, 50)],
        ..LibrarySnapshot::default()
    }
    .document("1.0.0", Timestamp(60), "phone", true);
    let place = Racing {
        inner: FolderPlace::new(dir.path()),
        raced: Cell::new(false),
        other: encode(&other),
    };
    let sync = LibrarySync::new(place, "linux", "1.0.0");
    let mine = LibrarySnapshot {
        progress: vec![record("mine", 7, 70)],
        ..LibrarySnapshot::default()
    };
    let SyncOutcome::Synced { merged, .. } = sync.sync(&mine, Timestamp(80)).unwrap() else {
        panic!("the second attempt writes");
    };
    assert_eq!(merged.snapshot.progress.len(), 2);
    let on_disk =
        decode(&std::fs::read(dir.path().join("StoryArc Library.json")).unwrap()).unwrap();
    assert_eq!(on_disk.library.progress.len(), 2);
}

#[test]
fn a_conflicted_copy_is_merged_and_removed_and_a_missing_folder_is_grey() {
    let dir = tempfile::tempdir().unwrap();
    let copy = LibrarySnapshot {
        progress: vec![record("copy", 3, 30)],
        ..LibrarySnapshot::default()
    }
    .document("1.0.0", Timestamp(40), "phone", true);
    std::fs::write(dir.path().join("StoryArc Library 2.json"), encode(&copy)).unwrap();
    let sync = LibrarySync::new(FolderPlace::new(dir.path()), "linux", "1.0.0");
    let SyncOutcome::Synced { merged, copies } = sync
        .sync(&LibrarySnapshot::default(), Timestamp(50))
        .unwrap()
    else {
        panic!("syncs");
    };
    assert_eq!(copies, ["StoryArc Library 2.json"]);
    assert_eq!(merged.snapshot.progress.len(), 1);
    assert!(!dir.path().join("StoryArc Library 2.json").exists());

    let gone = LibrarySync::new(
        FolderPlace::new(dir.path().join("unplugged")),
        "linux",
        "1.0.0",
    );
    assert!(
        gone.sync(&LibrarySnapshot::default(), Timestamp(60))
            .is_err()
    );
}
