//! What the search page says (`library-browsing`, Search; `navigation-shell`, Reaching
//! search): before anything is typed it offers recent searches, or says in one sentence
//! that there is nothing to suggest; with results it states what it searched and where;
//! with none it names what was searched and offers to widen a narrowed scope.
//!
//! The scope is the library's availability axis: everything, or only what can be read
//! now, with no network and no folder to wait for. It persists with the recent searches
//! in one small file. Pure, so it tests on any host.

use storyarc_core::domain::Publication;
use storyarc_core::library::{LibraryIndex, ProgressIndex, ReadState};

use crate::strings::{tr, tr_args};

/// The publications search offers before a word is typed (`navigation-shell`, What
/// search opens onto): one in progress, one never opened, and the next of a series the
/// reader has read, each only when the library has one, and never the same one twice.
/// Everything comes from the device; nothing is fetched to be suggested.
pub fn suggestions(publications: &[Publication], progress: &ProgressIndex) -> Vec<Publication> {
    let in_progress = LibraryIndex::continue_reading(publications, 1, progress);
    let never_opened = publications
        .iter()
        .filter(|publication| progress.summary(publication).state == ReadState::Unread)
        .max_by_key(|publication| publication.added_at)
        .cloned();
    let next = LibraryIndex::up_next(publications, 1, progress);
    let mut offered: Vec<Publication> = Vec::new();
    for candidate in in_progress.into_iter().chain(never_opened).chain(next) {
        if offered.iter().all(|kept| kept.id() != candidate.id()) {
            offered.push(candidate);
        }
    }
    offered
}

/// How many recent searches are kept.
pub const RECENT_LIMIT: usize = 8;

/// The shortest query worth remembering.
const REMEMBERED_FROM: usize = 2;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Scope {
    #[default]
    Everywhere,
    /// Only what can be read now: a folder that is offline or needs access drops out.
    OnDevice,
}

impl Scope {
    pub fn label(self) -> String {
        match self {
            Self::Everywhere => tr("library.scope.all", "Everywhere"),
            Self::OnDevice => tr("source.onThisDevice", "On this device"),
        }
    }
}

/// The recent searches, newest first, and the scope the reader chose.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SearchMemory {
    pub recent: Vec<String>,
    pub scope: Scope,
}

impl SearchMemory {
    /// A query the reader left or acted on: it goes to the front, once.
    pub fn remember(&mut self, query: &str) {
        let query = query.trim();
        if query.chars().count() < REMEMBERED_FROM {
            return;
        }
        let folded = query.to_lowercase();
        self.recent.retain(|kept| kept.to_lowercase() != folded);
        self.recent.insert(0, query.to_owned());
        self.recent.truncate(RECENT_LIMIT);
    }

    pub fn clear(&mut self) {
        self.recent.clear();
    }

    pub fn save(&self) -> String {
        let scope = match self.scope {
            Scope::Everywhere => "everywhere",
            Scope::OnDevice => "on-device",
        };
        let mut text = format!("scope\t{scope}\n");
        for query in &self.recent {
            text.push_str(&format!("recent\t{}\n", query.replace(['\n', '\t'], " ")));
        }
        text
    }

    pub fn restore(text: &str) -> Self {
        let mut memory = Self::default();
        for line in text.lines() {
            match line.split_once('\t') {
                Some(("scope", "on-device")) => memory.scope = Scope::OnDevice,
                Some(("recent", query))
                    if !query.trim().is_empty() && memory.recent.len() < RECENT_LIMIT =>
                {
                    memory.recent.push(query.to_owned());
                }
                _ => {}
            }
        }
        memory
    }
}

/// What the search page shows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SearchPage {
    /// Nothing typed: the recent searches to offer again.
    Suggestions(Vec<String>),
    /// Nothing typed, no recent search and an empty library: one sentence, and the
    /// library's own way of adding a folder.
    NothingToSuggest,
    /// Results, under the line that states what was searched and where.
    Results { line: String },
    /// No match: the sentence names the query, and a narrowed scope can be widened.
    NoResults { line: String, can_widen: bool },
}

impl SearchPage {
    pub fn of(text: &str, found: usize, memory: &SearchMemory, library_is_empty: bool) -> Self {
        let query = text.trim();
        if query.is_empty() {
            if !memory.recent.is_empty() {
                return Self::Suggestions(memory.recent.clone());
            }
            if library_is_empty {
                return Self::NothingToSuggest;
            }
            return Self::Suggestions(Vec::new());
        }
        if found == 0 {
            let mut line = tr_args(
                "library.empty.search %s",
                "Nothing matches “%s”.",
                &[&query],
            );
            if memory.scope == Scope::OnDevice {
                line = format!("{line} {}", scope_note(memory.scope));
            }
            return Self::NoResults {
                line,
                can_widen: memory.scope == Scope::OnDevice,
            };
        }
        Self::Results {
            line: format!(
                "{} · {}",
                tr_args("library.search.results %s", "Results for “%s”", &[&query]),
                memory.scope.label()
            ),
        }
    }
}

fn scope_note(scope: Scope) -> String {
    format!("({})", scope.label())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_query_is_remembered_once_newest_first_and_capped() {
        let mut memory = SearchMemory::default();
        memory.remember("saga");
        memory.remember("Monstress");
        memory.remember("SAGA");
        assert_eq!(memory.recent, ["SAGA", "Monstress"]);
        memory.remember(" x ");
        assert_eq!(memory.recent.len(), 2, "a single letter is not kept");
        for index in 0..20 {
            memory.remember(&format!("query {index}"));
        }
        assert_eq!(memory.recent.len(), RECENT_LIMIT);
        assert_eq!(memory.recent[0], "query 19");
        memory.clear();
        assert!(memory.recent.is_empty());
    }

    #[test]
    fn the_recent_searches_and_the_scope_survive_a_relaunch() {
        let mut memory = SearchMemory {
            scope: Scope::OnDevice,
            ..SearchMemory::default()
        };
        memory.remember("saga");
        memory.remember("tab\there");
        let restored = SearchMemory::restore(&memory.save());
        assert_eq!(restored.scope, Scope::OnDevice);
        assert_eq!(restored.recent, ["tab here", "saga"]);
        assert_eq!(SearchMemory::restore("garbage"), SearchMemory::default());
    }

    #[test]
    fn opening_search_offers_recent_searches_or_says_there_is_nothing() {
        let mut memory = SearchMemory::default();
        assert_eq!(
            SearchPage::of("", 0, &memory, true),
            SearchPage::NothingToSuggest
        );
        assert_eq!(
            SearchPage::of("  ", 0, &memory, false),
            SearchPage::Suggestions(Vec::new())
        );
        memory.remember("saga");
        assert_eq!(
            SearchPage::of("", 0, &memory, true),
            SearchPage::Suggestions(vec!["saga".into()])
        );
    }

    #[test]
    fn search_opens_onto_one_in_progress_one_never_opened_and_the_next_in_a_series() {
        use storyarc_core::domain::{
            MetadataOrigin, PublicationFormat, PublicationIdentity, Timestamp,
        };

        use crate::library::adapter::tests::reading;

        let issue = |series: &str, number: &str, added: i64| {
            let mut publication = Publication::new(
                PublicationIdentity::path(format!("/c/{series} {number}.cbz")),
                PublicationFormat::Cbz,
                format!("{series} {number}"),
                MetadataOrigin::Inferred,
            );
            publication.series = Some(series.into());
            publication.number = Some(number.into());
            publication.added_at = Some(Timestamp(added));
            publication
        };
        let library = [
            issue("Saga", "1", 1),
            issue("Saga", "2", 2),
            issue("Akira", "1", 3),
            issue("Blame", "1", 9),
        ];
        let progress = ProgressIndex::new(vec![
            reading(&library[0], 9, 10, 10).finished(true, Timestamp(10)),
            reading(&library[2], 3, 10, 20),
        ]);
        let titles: Vec<String> = suggestions(&library, &progress)
            .into_iter()
            .map(|p| p.display_title)
            .collect();
        assert_eq!(titles, ["Akira 1", "Blame 1", "Saga 2"]);
        assert!(suggestions(&[], &ProgressIndex::default()).is_empty());
    }

    #[test]
    fn results_state_what_was_searched_and_where() {
        let mut memory = SearchMemory::default();
        assert_eq!(
            SearchPage::of("saga", 3, &memory, false),
            SearchPage::Results {
                line: "Results for “saga” · Everywhere".into()
            }
        );
        memory.scope = Scope::OnDevice;
        assert_eq!(
            SearchPage::of("saga", 3, &memory, false),
            SearchPage::Results {
                line: "Results for “saga” · On this device".into()
            }
        );
    }

    #[test]
    fn no_results_names_the_query_and_offers_to_widen_a_narrowed_scope() {
        let mut memory = SearchMemory::default();
        assert_eq!(
            SearchPage::of("zzz", 0, &memory, false),
            SearchPage::NoResults {
                line: "Nothing matches “zzz”.".into(),
                can_widen: false
            }
        );
        memory.scope = Scope::OnDevice;
        assert_eq!(
            SearchPage::of("zzz", 0, &memory, false),
            SearchPage::NoResults {
                line: "Nothing matches “zzz”. (On this device)".into(),
                can_widen: true
            }
        );
    }
}
