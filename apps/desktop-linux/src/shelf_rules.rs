//! Collections and reading lists as the Linux app shows them (task 3.19a, as 3.15a;
//! `collections-and-reading-lists`). Pure over the core's `Shelves`, `PinnedShelves` and
//! `ShelfEditQueue`: the sidebar's section, the shelf page's members, Add to Shelf, bulk
//! removal, the shelves Home draws and the entries an offline edit still owes a server.
//! `shelf_ui.rs` is the GTK side.

use storyarc_core::domain::{Publication, Timestamp};
use storyarc_core::portability::{LibrarySnapshot, document::DocumentTombstone};
use storyarc_core::shelves::{
    PinnedShelves, PublicationCollection, ReadingList, ShelfEditQueue, ShelfKind, ShelfPin, Shelves,
};

/// A shelf, by kind and id.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ShelfRef {
    Collection(String),
    List(String),
}

impl ShelfRef {
    pub fn pin(&self) -> ShelfPin {
        match self {
            Self::Collection(id) => ShelfPin::Collection(id.clone()),
            Self::List(id) => ShelfPin::List(id.clone()),
        }
    }
}

/// One row of the sidebar's Shelves section.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SidebarShelf {
    pub shelf: ShelfRef,
    pub name: String,
    pub count: usize,
    pub pinned: bool,
    /// Defined by a server rather than on this device.
    pub from_server: bool,
}

/// The shelves in the sidebar: pinned first in the reader's order of pinning, then
/// collections, then reading lists, each by name.
pub fn sidebar(shelves: &Shelves, pins: &PinnedShelves) -> Vec<SidebarShelf> {
    let mut rows: Vec<SidebarShelf> = Vec::new();
    let mut collections: Vec<&PublicationCollection> = shelves.collections.iter().collect();
    collections.sort_by_key(|c| c.name.to_lowercase());
    for c in collections {
        rows.push(SidebarShelf {
            shelf: ShelfRef::Collection(c.id.clone()),
            name: c.name.clone(),
            count: c.members.len(),
            pinned: pins.contains(&ShelfPin::Collection(c.id.clone())),
            from_server: c.origin.source_id().is_some(),
        });
    }
    let mut lists: Vec<&ReadingList> = shelves.lists.iter().collect();
    lists.sort_by_key(|l| l.name.to_lowercase());
    for l in lists {
        rows.push(SidebarShelf {
            shelf: ShelfRef::List(l.id.clone()),
            name: l.name.clone(),
            count: l.entries.len(),
            pinned: pins.contains(&ShelfPin::List(l.id.clone())),
            from_server: l.origin.source_id().is_some(),
        });
    }
    pins.ordering(&rows, |row| row.shelf.pin())
}

/// A new local collection. A blank name makes nothing.
pub fn create_collection(shelves: &Shelves, name: &str) -> (Shelves, Option<ShelfRef>) {
    let name = name.trim();
    if name.is_empty() {
        return (shelves.clone(), None);
    }
    let collection = PublicationCollection::local(name);
    let id = collection.id.clone();
    (
        shelves.adding_collection(collection),
        Some(ShelfRef::Collection(id)),
    )
}

/// A new local reading list. A blank name makes nothing.
pub fn create_list(shelves: &Shelves, name: &str) -> (Shelves, Option<ShelfRef>) {
    let name = name.trim();
    if name.is_empty() {
        return (shelves.clone(), None);
    }
    let list = ReadingList::local(name);
    let id = list.id.clone();
    (shelves.adding_list(list), Some(ShelfRef::List(id)))
}

/// Add to Shelf: the publications join the shelf (a list keeps them in the order given,
/// after what it holds).
pub fn add_to(shelves: &Shelves, shelf: &ShelfRef, publications: &[Publication]) -> Shelves {
    let ids: Vec<String> = publications.iter().map(Publication::id).collect();
    let ids = ids.iter().map(String::as_str);
    match shelf {
        ShelfRef::Collection(id) => shelves.adding_members(ids, id),
        ShelfRef::List(id) => shelves.appending(ids, id),
    }
}

/// The bulk action: remove the publications from the shelf. The files and the reading
/// positions are not touched.
pub fn remove_from(shelves: &Shelves, shelf: &ShelfRef, publications: &[Publication]) -> Shelves {
    let ids: Vec<String> = publications.iter().map(Publication::id).collect();
    let ids = ids.iter().map(String::as_str);
    match shelf {
        ShelfRef::Collection(id) => shelves.removing_members(ids, id),
        ShelfRef::List(id) => ids.fold(shelves.clone(), |next, entry| {
            next.removing_entry(entry, id)
        }),
    }
}

/// Deletes a shelf, whatever its kind. Its members stay in the library.
pub fn delete(shelves: &Shelves, shelf: &ShelfRef) -> Shelves {
    match shelf {
        ShelfRef::Collection(id) => shelves.deleting_collection(id),
        ShelfRef::List(id) => shelves.deleting_list(id),
    }
}

/// What the shelf page lists: a list in its own order, a collection in the library's
/// order. A member the library does not hold now (its source is away) is counted apart
/// rather than dropped from the shelf.
#[derive(Clone, Debug, PartialEq)]
pub struct ShelfPage {
    pub name: String,
    pub publications: Vec<Publication>,
    pub unavailable: usize,
}

pub fn page(shelves: &Shelves, shelf: &ShelfRef, library: &[Publication]) -> Option<ShelfPage> {
    let find = |id: &str| library.iter().find(|p| p.id() == id).cloned();
    match shelf {
        ShelfRef::Collection(id) => {
            let c = shelves.collection(id)?;
            let publications: Vec<Publication> = library
                .iter()
                .filter(|p| c.members.contains(&p.id()))
                .cloned()
                .collect();
            Some(ShelfPage {
                name: c.name.clone(),
                unavailable: c.members.len() - publications.len(),
                publications,
            })
        }
        ShelfRef::List(id) => {
            let l = shelves.list(id)?;
            let publications: Vec<Publication> = l.entries.iter().filter_map(|e| find(e)).collect();
            Some(ShelfPage {
                name: l.name.clone(),
                unavailable: l.entries.len() - publications.len(),
                publications,
            })
        }
    }
}

/// How many publications Home shows from a shelf.
pub const HOME_LIMIT: usize = 12;

/// A shelf on Home.
#[derive(Clone, Debug, PartialEq)]
pub struct HomeShelf {
    pub shelf: ShelfRef,
    pub name: String,
    pub publications: Vec<Publication>,
    pub total: usize,
}

/// The shelves Home draws: only the pinned ones, in the order pinned, and only those with
/// something in the library to show.
pub fn home(shelves: &Shelves, pins: &PinnedShelves, library: &[Publication]) -> Vec<HomeShelf> {
    sidebar(shelves, pins)
        .into_iter()
        .filter(|row| row.pinned)
        .filter_map(|row| {
            let page = page(shelves, &row.shelf, library)?;
            (!page.publications.is_empty()).then(|| HomeShelf {
                shelf: row.shelf,
                name: page.name,
                total: page.publications.len(),
                publications: page.publications.into_iter().take(HOME_LIMIT).collect(),
            })
        })
        .collect()
}

/// Pin or unpin a shelf.
pub fn toggle_pin(pins: &PinnedShelves, shelf: &ShelfRef) -> PinnedShelves {
    pins.toggling(shelf.pin())
}

/// The entries of a server shelf an offline edit still owes the server: shown grey, with
/// a line that says they are waiting.
#[allow(dead_code)] // server shelves arrive with the Kavita shelf pull; the model is tested
pub fn pending_entries(
    queue: &ShelfEditQueue,
    source_id: &str,
    shelf_id: i64,
    kind: ShelfKind,
) -> Vec<String> {
    queue
        .edits
        .iter()
        .filter(|e| {
            e.shelf.source_id == source_id && e.shelf.shelf_id == shelf_id && e.shelf.kind == kind
        })
        .map(|e| e.entry.clone())
        .collect()
}

/// The snapshot with `shelf` stamped as changed at `now`, so the sync merge keeps the
/// later edit of two devices.
pub fn touched(snapshot: &LibrarySnapshot, shelf: &ShelfRef, now: Timestamp) -> LibrarySnapshot {
    let mut next = snapshot.clone();
    match shelf {
        ShelfRef::Collection(id) => next
            .shelves
            .collections
            .iter_mut()
            .filter(|c| &c.id == id)
            .for_each(|c| c.changed_at = now),
        ShelfRef::List(id) => next
            .shelves
            .lists
            .iter_mut()
            .filter(|l| &l.id == id)
            .for_each(|l| l.changed_at = now),
    }
    next
}

/// Deletes a shelf and records the deletion, so it travels to the other devices.
pub fn deleted(
    snapshot: &LibrarySnapshot,
    shelf: &ShelfRef,
    now: Timestamp,
    device: &str,
) -> LibrarySnapshot {
    let id = match shelf {
        ShelfRef::Collection(id) | ShelfRef::List(id) => id.clone(),
    };
    let mut next = snapshot.clone();
    next.shelves = delete(&snapshot.shelves, shelf);
    next.pinned_shelves = if snapshot.pinned_shelves.contains(&shelf.pin()) {
        snapshot.pinned_shelves.toggling(shelf.pin())
    } else {
        snapshot.pinned_shelves.clone()
    };
    next.removed_shelves.retain(|t| t.id != id);
    next.removed_shelves.push(DocumentTombstone {
        id,
        removed_at: now,
        removed_by: Some(device.to_owned()),
    });
    next
}

#[cfg(test)]
mod tests {
    use super::*;
    use storyarc_core::domain::{
        MetadataOrigin, PublicationFormat, PublicationIdentity, Timestamp,
    };
    use storyarc_core::shelves::{ShelfEdit, ShelfKey};

    fn publication(name: &str) -> Publication {
        Publication::new(
            PublicationIdentity::path(format!("/comics/{name}.cbz")),
            PublicationFormat::Cbz,
            name,
            MetadataOrigin::Inferred,
        )
    }

    fn library() -> Vec<Publication> {
        ["a", "b", "c", "d"].map(publication).to_vec()
    }

    #[test]
    fn a_blank_name_makes_no_shelf_and_a_named_one_is_found_again() {
        let (same, none) = create_collection(&Shelves::default(), "   ");
        assert!(none.is_none() && same == Shelves::default());
        let (shelves, shelf) = create_collection(&Shelves::default(), " Favourites ");
        let rows = sidebar(&shelves, &PinnedShelves::default());
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].name, "Favourites");
        assert_eq!(Some(rows[0].shelf.clone()), shelf);
    }

    #[test]
    fn membership_adds_once_and_a_list_keeps_the_order_it_was_given() {
        let lib = library();
        let (shelves, c) = create_collection(&Shelves::default(), "Set");
        let c = c.unwrap();
        let shelves = add_to(&shelves, &c, &[lib[2].clone(), lib[0].clone()]);
        let shelves = add_to(&shelves, &c, &[lib[0].clone()]);
        let shown = page(&shelves, &c, &lib).unwrap();
        // A collection lists in the library's order.
        assert_eq!(shown.publications, vec![lib[0].clone(), lib[2].clone()]);
        let (shelves, l) = create_list(&shelves, "Order");
        let l = l.unwrap();
        let shelves = add_to(
            &shelves,
            &l,
            &[lib[2].clone(), lib[0].clone(), lib[2].clone()],
        );
        let shown = page(&shelves, &l, &lib).unwrap();
        assert_eq!(shown.publications, vec![lib[2].clone(), lib[0].clone()]);
    }

    #[test]
    fn the_bulk_remove_takes_publications_off_the_shelf_and_leaves_the_library() {
        let lib = library();
        let (shelves, c) = create_collection(&Shelves::default(), "Set");
        let c = c.unwrap();
        let shelves = add_to(&shelves, &c, &lib);
        let shelves = remove_from(&shelves, &c, &[lib[1].clone(), lib[3].clone()]);
        assert_eq!(page(&shelves, &c, &lib).unwrap().publications.len(), 2);
        let (shelves, l) = create_list(&shelves, "L");
        let l = l.unwrap();
        let shelves = add_to(&shelves, &l, &lib);
        let shelves = remove_from(&shelves, &l, &[lib[0].clone()]);
        assert_eq!(page(&shelves, &l, &lib).unwrap().publications[0], lib[1]);
        assert_eq!(lib.len(), 4);
    }

    #[test]
    fn a_member_the_library_does_not_hold_is_counted_not_dropped() {
        let lib = library();
        let (shelves, c) = create_collection(&Shelves::default(), "Set");
        let c = c.unwrap();
        let shelves = add_to(&shelves, &c, &lib);
        let shown = page(&shelves, &c, &lib[..2]).unwrap();
        assert_eq!((shown.publications.len(), shown.unavailable), (2, 2));
        assert_eq!(delete(&shelves, &c).collections.len(), 0);
    }

    #[test]
    fn pinned_shelves_come_first_in_the_order_pinned_and_home_draws_only_those() {
        let lib = library();
        let (s, one) = create_collection(&Shelves::default(), "Alpha");
        let (s, two) = create_collection(&s, "Beta");
        let (s, empty) = create_collection(&s, "Gamma");
        let (one, two, empty) = (one.unwrap(), two.unwrap(), empty.unwrap());
        let s = add_to(&s, &one, &lib[..1]);
        let s = add_to(&s, &two, &lib[1..]);
        let none = PinnedShelves::default();
        assert!(home(&s, &none, &lib).is_empty());
        assert_eq!(sidebar(&s, &none)[0].name, "Alpha");
        let pins = toggle_pin(&toggle_pin(&none, &empty), &two);
        let rows = sidebar(&s, &pins);
        assert!(rows[0].pinned && rows[1].pinned && !rows[2].pinned);
        // Home: pinned only, and a pinned shelf with nothing to show is absent.
        let drawn = home(&s, &pins, &lib);
        assert_eq!(drawn.len(), 1);
        assert_eq!(drawn[0].name, "Beta");
        assert_eq!(drawn[0].total, 3);
        assert!(toggle_pin(&pins, &two).tokens().len() == 1);
    }

    #[test]
    fn an_edit_a_server_has_not_seen_is_listed_as_pending_for_that_shelf_only() {
        let key = ShelfKey::new("src", 7, ShelfKind::ReadingList);
        let other = ShelfKey::new("src", 8, ShelfKind::ReadingList);
        let queue = ShelfEditQueue::default()
            .queueing(ShelfEdit {
                shelf: key,
                entry: "chapter:1".into(),
                title: "One".into(),
                made_at: Timestamp(1),
            })
            .queueing(ShelfEdit {
                shelf: other,
                entry: "chapter:2".into(),
                title: "Two".into(),
                made_at: Timestamp(2),
            });
        assert_eq!(
            pending_entries(&queue, "src", 7, ShelfKind::ReadingList),
            vec!["chapter:1".to_owned()]
        );
        assert!(pending_entries(&queue, "src", 7, ShelfKind::Collection).is_empty());
    }

    #[test]
    fn a_change_is_stamped_and_a_deletion_leaves_a_tombstone_and_no_pin() {
        let (shelves, c) = create_collection(&Shelves::default(), "Set");
        let c = c.unwrap();
        let snapshot = LibrarySnapshot {
            pinned_shelves: toggle_pin(&PinnedShelves::default(), &c),
            shelves,
            ..LibrarySnapshot::default()
        };
        let stamped = touched(&snapshot, &c, Timestamp(77));
        assert_eq!(stamped.shelves.collections[0].changed_at, Timestamp(77));
        let gone = deleted(&stamped, &c, Timestamp(90), "linux");
        assert!(gone.shelves.collections.is_empty());
        assert!(gone.pinned_shelves.is_empty());
        assert_eq!(gone.removed_shelves.len(), 1);
        assert_eq!(gone.removed_shelves[0].removed_at, Timestamp(90));
    }
}
