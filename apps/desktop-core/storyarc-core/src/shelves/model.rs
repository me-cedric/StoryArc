//! Collections and reading lists as values, mirrored from StoryArcKit's `Shelves.swift`.
//!
//! A **collection** is unordered and a publication may be in any number of them; a **reading
//! list** is ordered and its order is the point. Both are held by id, a UUID kept as its
//! lowercase hyphenated text so ids written by iOS (upper case) and Android (lower case)
//! compare equal. Members are publication keys (`path:/a.cbz`, `sha:…`), as the library
//! document writes them.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::domain::Timestamp;

/// A UUID as lowercase hyphenated text, or `None` for text that is not one.
pub fn shelf_id(text: &str) -> Option<String> {
    uuid::Uuid::parse_str(text.trim())
        .ok()
        .map(|id| id.hyphenated().to_string())
}

/// A fresh shelf id.
pub fn new_shelf_id() -> String {
    uuid::Uuid::new_v4().hyphenated().to_string()
}

/// Where a shelf lives: on this device, or on a server source (by its id).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "sourceId")]
pub enum ShelfOrigin {
    Local,
    Server(String),
}

impl ShelfOrigin {
    pub fn source_id(&self) -> Option<&str> {
        match self {
            Self::Local => None,
            Self::Server(id) => Some(id),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PublicationCollection {
    pub id: String,
    pub name: String,
    pub members: BTreeSet<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_member_id: Option<String>,
    pub origin: ShelfOrigin,
    /// The last local change, for the sync merge; the epoch until one is stamped.
    #[serde(default)]
    pub changed_at: Timestamp,
}

impl PublicationCollection {
    pub fn local(name: impl Into<String>) -> Self {
        Self {
            id: new_shelf_id(),
            name: name.into(),
            members: BTreeSet::new(),
            cover_member_id: None,
            origin: ShelfOrigin::Local,
            changed_at: Timestamp::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingList {
    pub id: String,
    pub name: String,
    pub entries: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_member_id: Option<String>,
    pub origin: ShelfOrigin,
    #[serde(default)]
    pub changed_at: Timestamp,
}

/// What a source says about one entry's reading.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum EntryReading {
    Unread,
    /// Part-read, with the fraction reached.
    PartRead(f64),
    Finished,
}

/// How far through a list the reader is (`collections-and-reading-lists`, *Progress through
/// a list*).
#[derive(Debug, Clone, PartialEq)]
pub struct ListProgress {
    /// Entries whose source reports them finished.
    pub finished: usize,
    /// Entries whose source reports a read state at all: the count's denominator. An entry
    /// the source says nothing about is excluded rather than counted unread.
    pub reported: usize,
    /// The index of the first entry not finished, `entries.len()` when all are.
    pub position: usize,
}

impl ReadingList {
    pub fn local(name: impl Into<String>) -> Self {
        Self {
            id: new_shelf_id(),
            name: name.into(),
            entries: Vec::new(),
            cover_member_id: None,
            origin: ShelfOrigin::Local,
            changed_at: Timestamp::default(),
        }
    }

    /// The entry after `id` in list order, regardless of series or source.
    pub fn next(&self, id: &str) -> Option<&str> {
        let at = self.entries.iter().position(|e| e == id)?;
        self.entries.get(at + 1).map(String::as_str)
    }

    pub fn previous(&self, id: &str) -> Option<&str> {
        let at = self.entries.iter().position(|e| e == id)?;
        at.checked_sub(1)
            .and_then(|i| self.entries.get(i))
            .map(String::as_str)
    }

    /// The next entry that can be opened: an entry its source removed stays in the list,
    /// marked unavailable, and the "next" flow steps over it rather than stopping.
    pub fn next_available(&self, id: &str, available: impl Fn(&str) -> bool) -> Option<&str> {
        let at = self.entries.iter().position(|e| e == id)?;
        self.entries[at + 1..]
            .iter()
            .map(String::as_str)
            .find(|e| available(e))
    }

    pub fn progress(&self, reading: impl Fn(&str) -> Option<EntryReading>) -> ListProgress {
        let states: Vec<Option<EntryReading>> = self.entries.iter().map(|e| reading(e)).collect();
        ListProgress {
            finished: states
                .iter()
                .filter(|s| matches!(s, Some(EntryReading::Finished)))
                .count(),
            reported: states.iter().filter(|s| s.is_some()).count(),
            position: states
                .iter()
                .position(|s| !matches!(s, Some(EntryReading::Finished)))
                .unwrap_or(self.entries.len()),
        }
    }
}

/// How many covers a composite holds.
pub const COMPOSITE_COVERS: usize = 4;

/// The covers a shelf's card is drawn from (*Cover for a collection*, *Cover for a reading
/// list*): the reader's chosen member alone when its cover is there; otherwise the first four
/// members, in the order given, whose covers are available. Empty means the placeholder a
/// publication with no cover shows, never an empty frame. For a reading list `ordered` is
/// list order, because the order is what a reading list means; for a collection it is the
/// library's order.
pub fn cover_members<'a>(
    chosen: Option<&'a str>,
    ordered: impl IntoIterator<Item = &'a str>,
    has_cover: impl Fn(&str) -> bool,
) -> Vec<&'a str> {
    if let Some(chosen) = chosen
        && has_cover(chosen)
    {
        return vec![chosen];
    }
    ordered
        .into_iter()
        .filter(|m| has_cover(m))
        .take(COMPOSITE_COVERS)
        .collect()
}

/// Every collection and reading list, local and server-defined, in one value.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Shelves {
    pub collections: Vec<PublicationCollection>,
    pub lists: Vec<ReadingList>,
}

fn trimmed(name: &str) -> Option<String> {
    let name = name.trim();
    (!name.is_empty()).then(|| name.to_owned())
}

impl Shelves {
    fn map_collection(&self, id: &str, change: impl Fn(&mut PublicationCollection)) -> Self {
        let mut next = self.clone();
        next.collections
            .iter_mut()
            .filter(|c| c.id == id)
            .for_each(change);
        next
    }

    fn map_list(&self, id: &str, change: impl Fn(&mut ReadingList)) -> Self {
        let mut next = self.clone();
        next.lists
            .iter_mut()
            .filter(|l| l.id == id)
            .for_each(change);
        next
    }

    pub fn collection(&self, id: &str) -> Option<&PublicationCollection> {
        self.collections.iter().find(|c| c.id == id)
    }

    pub fn list(&self, id: &str) -> Option<&ReadingList> {
        self.lists.iter().find(|l| l.id == id)
    }

    pub fn adding_collection(&self, collection: PublicationCollection) -> Self {
        if self.collection(&collection.id).is_some() {
            return self.clone();
        }
        let mut next = self.clone();
        next.collections.push(collection);
        next
    }

    /// Renames; a blank name changes nothing.
    pub fn renaming_collection(&self, id: &str, name: &str) -> Self {
        match trimmed(name) {
            Some(name) => self.map_collection(id, |c| c.name = name.clone()),
            None => self.clone(),
        }
    }

    pub fn adding_members<'a>(&self, members: impl IntoIterator<Item = &'a str>, id: &str) -> Self {
        let members: Vec<String> = members.into_iter().map(str::to_owned).collect();
        self.map_collection(id, |c| c.members.extend(members.iter().cloned()))
    }

    /// Removes members; a cover that is no longer a member is no cover.
    pub fn removing_members<'a>(
        &self,
        members: impl IntoIterator<Item = &'a str>,
        id: &str,
    ) -> Self {
        let members: Vec<String> = members.into_iter().map(str::to_owned).collect();
        self.map_collection(id, |c| {
            for m in &members {
                c.members.remove(m);
            }
            if c.cover_member_id
                .as_ref()
                .is_some_and(|cover| !c.members.contains(cover))
            {
                c.cover_member_id = None;
            }
        })
    }

    /// Sets or clears the chosen cover; a member that is not in the collection is refused.
    pub fn setting_collection_cover(&self, member: Option<&str>, id: &str) -> Self {
        self.map_collection(id, |c| {
            if member.is_none_or(|m| c.members.contains(m)) {
                c.cover_member_id = member.map(str::to_owned);
            }
        })
    }

    pub fn deleting_collection(&self, id: &str) -> Self {
        let mut next = self.clone();
        next.collections.retain(|c| c.id != id);
        next
    }

    pub fn adding_list(&self, list: ReadingList) -> Self {
        if self.list(&list.id).is_some() {
            return self.clone();
        }
        let mut next = self.clone();
        next.lists.push(list);
        next
    }

    pub fn renaming_list(&self, id: &str, name: &str) -> Self {
        match trimmed(name) {
            Some(name) => self.map_list(id, |l| l.name = name.clone()),
            None => self.clone(),
        }
    }

    pub fn setting_list_cover(&self, member: Option<&str>, id: &str) -> Self {
        self.map_list(id, |l| {
            if member.is_none_or(|m| l.entries.iter().any(|e| e == m)) {
                l.cover_member_id = member.map(str::to_owned);
            }
        })
    }

    /// Appends entries the list does not hold yet, in the order given.
    pub fn appending<'a>(&self, entries: impl IntoIterator<Item = &'a str>, id: &str) -> Self {
        let entries: Vec<String> = entries.into_iter().map(str::to_owned).collect();
        self.map_list(id, |l| {
            for e in &entries {
                if !l.entries.contains(e) {
                    l.entries.push(e.clone());
                }
            }
        })
    }

    pub fn removing_entry(&self, entry: &str, id: &str) -> Self {
        self.map_list(id, |l| {
            l.entries.retain(|e| e != entry);
            if l.cover_member_id.as_deref() == Some(entry) {
                l.cover_member_id = None;
            }
        })
    }

    /// Moves an entry. `to` is an index in the list *before* the move, as a drag reports it.
    pub fn moving_entry(&self, entry: &str, to: usize, id: &str) -> Self {
        self.map_list(id, |l| {
            if let Some(from) = l.entries.iter().position(|e| e == entry) {
                let row = l.entries.remove(from);
                let to = if to > from { to - 1 } else { to };
                l.entries.insert(to.min(l.entries.len()), row);
            }
        })
    }

    pub fn deleting_list(&self, id: &str) -> Self {
        let mut next = self.clone();
        next.lists.retain(|l| l.id != id);
        next
    }

    /// The collections a publication is in.
    pub fn collections_containing(&self, member: &str) -> Vec<&PublicationCollection> {
        self.collections
            .iter()
            .filter(|c| c.members.contains(member))
            .collect()
    }

    /// Forgets every shelf a removed source defined; the reader's own are untouched.
    pub fn removing_all_from(&self, source_id: &str) -> Self {
        let from = |o: &ShelfOrigin| o.source_id() == Some(source_id);
        Self {
            collections: self
                .collections
                .iter()
                .filter(|c| !from(&c.origin))
                .cloned()
                .collect(),
            lists: self
                .lists
                .iter()
                .filter(|l| !from(&l.origin))
                .cloned()
                .collect(),
        }
    }
}
