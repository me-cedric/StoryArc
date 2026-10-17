//! Collections and reading lists (task 3.7 of `desktop-clients`) against the shared fixtures:
//! the shelves `packages/test-fixtures/library` holds, written once by iOS and once by
//! Android, read into the core's shelves and held to the rules both phones keep.

use std::path::Path;

use serde_json::Value;
use storyarc_core::shelves::{
    EntryReading, PinnedShelves, PublicationCollection, ReadingList, ShelfOrigin, ShelfPin,
    Shelves, cover_members, shelf_id,
};

fn library(name: &str) -> Value {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../packages/test-fixtures/library")
        .join(name);
    serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap()
}

fn strings(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

/// The shelves a document carries, through the core's own operations.
fn shelves_of(document: &Value) -> (Shelves, PinnedShelves) {
    let body = &document["library"];
    let mut shelves = Shelves::default();
    for c in body["collections"].as_array().unwrap() {
        let id = shelf_id(c["id"].as_str().unwrap()).unwrap();
        let members = strings(&c["members"]);
        shelves = shelves
            .adding_collection(PublicationCollection {
                id: id.clone(),
                ..PublicationCollection::local(c["name"].as_str().unwrap())
            })
            .adding_members(members.iter().map(String::as_str), &id)
            .setting_collection_cover(c["coverMemberId"].as_str(), &id);
    }
    for l in body["readingLists"].as_array().unwrap() {
        let id = shelf_id(l["id"].as_str().unwrap()).unwrap();
        let entries = strings(&l["entries"]);
        shelves = shelves
            .adding_list(ReadingList {
                id: id.clone(),
                ..ReadingList::local(l["name"].as_str().unwrap())
            })
            .appending(entries.iter().map(String::as_str), &id)
            .setting_list_cover(l["coverMemberId"].as_str(), &id);
    }
    let pins = strings(&body["pinnedShelves"]);
    (
        shelves,
        PinnedShelves::of_tokens(pins.iter().map(String::as_str)),
    )
}

const COLLECTION: &str = "33333333-3333-3333-3333-333333333333";
const LIST: &str = "44444444-4444-4444-4444-444444444444";

#[test]
fn the_ios_and_android_documents_hold_the_same_shelves() {
    let ios = shelves_of(&library("written-by-ios.json"));
    let android = shelves_of(&library("written-by-android.json"));
    assert_eq!(ios, android);
}

#[test]
fn the_fixture_collection_keeps_its_members_and_its_chosen_cover() {
    let (shelves, _) = shelves_of(&library("written-by-ios.json"));
    let collection = shelves.collection(COLLECTION).unwrap();
    assert_eq!(collection.name, "Image Comics");
    assert_eq!(collection.origin, ShelfOrigin::Local);
    assert_eq!(
        collection.members.iter().collect::<Vec<_>>(),
        ["path:/a.cbz", "path:/b.cbz"]
    );
    assert_eq!(collection.cover_member_id.as_deref(), Some("path:/b.cbz"));
    let ordered = collection.members.iter().map(String::as_str);
    assert_eq!(
        cover_members(collection.cover_member_id.as_deref(), ordered, |_| true),
        ["path:/b.cbz"]
    );
    // The chosen cover cannot be fetched: the composite of what can, never an empty frame.
    let ordered = collection.members.iter().map(String::as_str);
    assert_eq!(
        cover_members(collection.cover_member_id.as_deref(), ordered, |m| m
            != "path:/b.cbz"),
        ["path:/a.cbz"]
    );
    // Removing the cover's member clears the choice.
    let without = shelves.removing_members(["path:/b.cbz"], COLLECTION);
    assert_eq!(
        without.collection(COLLECTION).unwrap().cover_member_id,
        None
    );
}

#[test]
fn the_fixture_list_keeps_its_order_and_offers_the_next_entry_in_it() {
    let (shelves, _) = shelves_of(&library("written-by-android.json"));
    let list = shelves.list(LIST).unwrap();
    assert_eq!(list.entries, ["path:/b.cbz", "path:/a.cbz"]);
    assert_eq!(list.cover_member_id, None);
    assert_eq!(list.next("path:/b.cbz"), Some("path:/a.cbz"));
    assert_eq!(list.next("path:/a.cbz"), None);
    assert_eq!(list.previous("path:/a.cbz"), Some("path:/b.cbz"));
    let order = list.entries.iter().map(String::as_str);
    assert_eq!(
        cover_members(None, order, |_| true),
        ["path:/b.cbz", "path:/a.cbz"]
    );

    let moved = shelves.moving_entry("path:/a.cbz", 0, LIST);
    assert_eq!(
        moved.list(LIST).unwrap().entries,
        ["path:/a.cbz", "path:/b.cbz"]
    );
}

#[test]
fn list_progress_counts_only_what_the_source_reports() {
    let (shelves, _) = shelves_of(&library("written-by-ios.json"));
    let list = shelves
        .appending(["path:/c.cbz"], LIST)
        .list(LIST)
        .unwrap()
        .clone();
    let progress = list.progress(|e| match e {
        "path:/b.cbz" => Some(EntryReading::Finished),
        "path:/a.cbz" => Some(EntryReading::PartRead(0.3)),
        _ => None,
    });
    assert_eq!(progress.finished, 1);
    assert_eq!(progress.reported, 2);
    assert_eq!(progress.position, 1);
    assert_eq!(
        list.next_available("path:/b.cbz", |e| e != "path:/a.cbz"),
        Some("path:/c.cbz")
    );
}

#[test]
fn the_fixture_pins_put_both_shelves_first() {
    let (_, pins) = shelves_of(&library("written-by-ios.json"));
    assert!(pins.contains(&ShelfPin::Collection(COLLECTION.into())));
    assert!(pins.contains(&ShelfPin::List(LIST.into())));
    assert_eq!(
        pins.tokens(),
        strings(&library("written-by-android.json")["library"]["pinnedShelves"])
    );
}

#[test]
fn removing_a_source_takes_its_shelves_and_leaves_the_readers_own() {
    let (shelves, _) = shelves_of(&library("written-by-ios.json"));
    let server = ReadingList {
        origin: ShelfOrigin::Server("55555555-5555-5555-5555-555555555555".into()),
        ..ReadingList::local("Start here")
    };
    let shelves = shelves.adding_list(server);
    assert_eq!(shelves.lists.len(), 2);
    let after = shelves.removing_all_from("55555555-5555-5555-5555-555555555555");
    assert_eq!(after.lists.len(), 1);
    assert_eq!(after.collections.len(), 1);
}
