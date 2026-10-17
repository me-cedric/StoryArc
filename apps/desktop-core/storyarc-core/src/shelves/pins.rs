//! Pinned shelves and the shelves a server told the app about, mirrored from StoryArcKit's
//! `PinnedShelves.swift` and `RememberedShelf.swift`.
//!
//! The home surface lists server-defined shelves "from what was written down when a source
//! last answered" and never asks a server for them, so a server's shelves are remembered here
//! with their counts, and pins are tokens the library document carries as `pinnedShelves`.

use std::collections::BTreeSet;

use super::edits::ShelfKind;
use super::model::shelf_id;

/// What can be pinned to the top of the shelves.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum ShelfPin {
    Collection(String),
    List(String),
    Server {
        kind: ShelfKind,
        source_id: String,
        server_id: i64,
    },
}

impl ShelfPin {
    /// `collection:<id>`, `list:<id>`, or `server:<kind>:<source>:<shelf>`.
    pub fn token(&self) -> String {
        match self {
            Self::Collection(id) => format!("collection:{id}"),
            Self::List(id) => format!("list:{id}"),
            Self::Server {
                kind,
                source_id,
                server_id,
            } => format!("server:{}:{source_id}:{server_id}", kind.token()),
        }
    }

    pub fn of_token(token: &str) -> Option<Self> {
        let (head, rest) = token.split_once(':')?;
        match head {
            "server" => {
                let mut parts = rest.split(':');
                let kind = ShelfKind::of_token(parts.next()?)?;
                let source_id = shelf_id(parts.next()?)?;
                let server_id = parts.next()?.parse().ok()?;
                parts.next().is_none().then_some(Self::Server {
                    kind,
                    source_id,
                    server_id,
                })
            }
            "collection" => Some(Self::Collection(shelf_id(rest)?)),
            "list" => Some(Self::List(shelf_id(rest)?)),
            _ => None,
        }
    }
}

/// The reader's pins: a set, written sorted so two devices write the same text.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PinnedShelves {
    pins: BTreeSet<ShelfPin>,
}

impl PinnedShelves {
    /// Reads tokens, dropping any it does not understand.
    pub fn of_tokens<'a>(tokens: impl IntoIterator<Item = &'a str>) -> Self {
        Self {
            pins: tokens.into_iter().filter_map(ShelfPin::of_token).collect(),
        }
    }

    pub fn tokens(&self) -> Vec<String> {
        let mut tokens: Vec<String> = self.pins.iter().map(ShelfPin::token).collect();
        tokens.sort();
        tokens
    }

    pub fn contains(&self, pin: &ShelfPin) -> bool {
        self.pins.contains(pin)
    }

    pub fn is_empty(&self) -> bool {
        self.pins.is_empty()
    }

    pub fn toggling(&self, pin: ShelfPin) -> Self {
        let mut pins = self.pins.clone();
        if !pins.remove(&pin) {
            pins.insert(pin);
        }
        Self { pins }
    }

    /// The pinned shelves first, each part keeping the order it was given in.
    pub fn ordering<T: Clone>(&self, shelves: &[T], pin: impl Fn(&T) -> ShelfPin) -> Vec<T> {
        let (pinned, rest): (Vec<T>, Vec<T>) = shelves
            .iter()
            .cloned()
            .partition(|s| self.contains(&pin(s)));
        pinned.into_iter().chain(rest).collect()
    }
}

/// A shelf a server described when it last answered, kept for the home surface.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RememberedShelf {
    pub kind: ShelfKind,
    pub source_id: String,
    pub server_id: i64,
    pub title: String,
    pub count: Option<u64>,
    pub finished: Option<u64>,
}

impl RememberedShelf {
    pub fn id(&self) -> String {
        format!(
            "{}:{}:{}:{}",
            self.kind.token(),
            self.source_id,
            self.server_id,
            self.title
        )
    }

    pub fn pin(&self) -> ShelfPin {
        ShelfPin::Server {
            kind: self.kind,
            source_id: self.source_id.clone(),
            server_id: self.server_id,
        }
    }

    /// The stored line: the id, then the counts after tabs when either is known.
    pub fn token(&self) -> String {
        if self.count.is_none() && self.finished.is_none() {
            return self.id();
        }
        let n = |v: Option<u64>| v.map(|v| v.to_string()).unwrap_or_default();
        format!("{}\t{}\t{}", self.id(), n(self.count), n(self.finished))
    }

    pub fn of_token(token: &str) -> Option<Self> {
        let mut sections = token.split('\t');
        let mut parts = sections.next()?.splitn(4, ':');
        let kind = ShelfKind::of_token(parts.next()?)?;
        let source_id = shelf_id(parts.next()?)?;
        let server_id = parts.next()?.parse().ok()?;
        let title = parts.next().filter(|t| !t.is_empty())?.to_owned();
        let count = sections.next().and_then(|c| c.parse().ok());
        let finished = sections.next().and_then(|c| c.parse().ok());
        Some(Self {
            kind,
            source_id,
            server_id,
            title,
            count,
            finished,
        })
    }

    /// The lines as stored: sorted, one per line.
    pub fn stored(shelves: &[Self]) -> String {
        let mut tokens: Vec<String> = shelves.iter().map(Self::token).collect();
        tokens.sort();
        tokens.join("\n")
    }

    pub fn of_stored(text: &str) -> Vec<Self> {
        text.lines().filter_map(Self::of_token).collect()
    }

    /// Replaces what one source described, after it answered a refresh. The others stay as
    /// they were written, which is what lets the home surface draw with every source away.
    pub fn replacing_source(remembered: &[Self], source_id: &str, now: Vec<Self>) -> Vec<Self> {
        remembered
            .iter()
            .filter(|s| s.source_id != source_id)
            .cloned()
            .chain(now)
            .collect()
    }

    /// Forgets a removed source's shelves.
    pub fn removing_source(remembered: &[Self], source_id: &str) -> Vec<Self> {
        Self::replacing_source(remembered, source_id, Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SOURCE: &str = "55555555-5555-5555-5555-555555555555";

    #[test]
    fn pins_read_both_cases_of_id_and_write_sorted_tokens() {
        let pins = PinnedShelves::of_tokens([
            "list:44444444-4444-4444-4444-444444444444",
            "collection:33333333-3333-3333-3333-333333333333",
            "server:collection:55555555-5555-5555-5555-555555555555:7",
            "nonsense",
            "collection:not-a-uuid",
        ]);
        assert_eq!(
            pins.tokens(),
            [
                "collection:33333333-3333-3333-3333-333333333333",
                "list:44444444-4444-4444-4444-444444444444",
                "server:collection:55555555-5555-5555-5555-555555555555:7",
            ]
        );
        let upper = PinnedShelves::of_tokens(["collection:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"]);
        assert!(upper.contains(&ShelfPin::Collection(
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa".into()
        )));
    }

    #[test]
    fn pinned_shelves_come_first_in_their_given_order() {
        let a = ShelfPin::List(SOURCE.into());
        let pins = PinnedShelves::default().toggling(a.clone());
        let ordered = pins.ordering(&[1, 2, 3], |n| {
            if *n == 3 {
                a.clone()
            } else {
                ShelfPin::Collection(n.to_string())
            }
        });
        assert_eq!(ordered, [3, 1, 2]);
        assert!(pins.toggling(a).is_empty());
    }

    #[test]
    fn a_remembered_shelf_round_trips_with_and_without_its_counts() {
        let shelf = RememberedShelf {
            kind: ShelfKind::ReadingList,
            source_id: SOURCE.into(),
            server_id: 3,
            title: "Start: here".into(),
            count: Some(12),
            finished: None,
        };
        assert_eq!(
            RememberedShelf::of_token(&shelf.token()),
            Some(shelf.clone())
        );
        let bare = RememberedShelf {
            count: None,
            ..shelf.clone()
        };
        assert_eq!(bare.token(), bare.id());
        assert_eq!(
            RememberedShelf::of_stored(&RememberedShelf::stored(&[shelf.clone(), bare.clone()]))
                .len(),
            2
        );
        assert!(RememberedShelf::removing_source(&[shelf], SOURCE).is_empty());
    }
}
