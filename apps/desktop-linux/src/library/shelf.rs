//! What the shelf draws from the arranged publications (`library-browsing`,
//! Presentation): a series as one row, or every issue as its own cell, as the reader
//! chose under View; and the index down the trailing edge for the orders that file a
//! row under a letter. Pure, so it tests on any host.

use storyarc_core::domain::Publication;
use storyarc_core::library::LibraryIndex;

use super::query::Sort;
use super::query::fold;

/// Series or issues: the grouping the View menu names. Series is what a reader who
/// never chose gets.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Grouping {
    #[default]
    Series,
    Issues,
}

/// Grid or list.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Layout {
    #[default]
    Grid,
    List,
}

/// The view choices, kept across visits (`library-browsing`, Switching layout and The
/// choice between series and issues).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ViewChoice {
    pub layout: Layout,
    pub grouping: Grouping,
}

impl ViewChoice {
    pub fn save(self) -> String {
        format!(
            "layout={}\ngrouping={}\n",
            match self.layout {
                Layout::Grid => "grid",
                Layout::List => "list",
            },
            match self.grouping {
                Grouping::Series => "series",
                Grouping::Issues => "issues",
            }
        )
    }

    pub fn restore(text: &str) -> Self {
        text.lines().filter_map(|line| line.split_once('=')).fold(
            Self::default(),
            |view, (key, value)| match (key.trim(), value.trim()) {
                ("layout", "list") => Self {
                    layout: Layout::List,
                    ..view
                },
                ("grouping", "issues") => Self {
                    grouping: Grouping::Issues,
                    ..view
                },
                _ => view,
            },
        )
    }
}

/// One row of the shelf.
#[derive(Clone, Debug, PartialEq)]
pub enum Row {
    Publication(Box<Publication>),
    /// A series, once, with its issues in their own order.
    Series {
        name: String,
        issues: Vec<Publication>,
    },
}

impl Row {
    /// What the row is filed under: its title, or its series' name.
    pub fn title(&self) -> &str {
        match self {
            Self::Publication(publication) => &publication.display_title,
            Self::Series { name, .. } => name,
        }
    }
}

/// The rows for the arranged publications. Under Series, every series the shelf holds
/// more than one issue of becomes one row where its first issue stood, holding its issues
/// in issue order; a publication in no series, or the only one of its series here, stays
/// a row of its own, since a group of one says nothing a cover does not. Under Issues,
/// every publication is a row.
pub fn rows(arranged: Vec<Publication>, grouping: Grouping) -> Vec<Row> {
    if grouping == Grouping::Issues {
        return arranged
            .into_iter()
            .map(|publication| Row::Publication(Box::new(publication)))
            .collect();
    }
    let mut rows: Vec<Row> = Vec::new();
    for publication in arranged {
        let Some(series) = LibraryIndex::series_name(&publication).map(str::to_owned) else {
            rows.push(Row::Publication(Box::new(publication)));
            continue;
        };
        let existing = rows.iter_mut().find_map(|row| match row {
            Row::Series { name, issues } if *name == series => Some(issues),
            _ => None,
        });
        match existing {
            Some(issues) => issues.push(publication),
            None => rows.push(Row::Series {
                name: series,
                issues: vec![publication],
            }),
        }
    }
    rows.into_iter()
        .map(|row| match row {
            Row::Series { mut issues, .. } if issues.len() == 1 => {
                Row::Publication(Box::new(issues.remove(0)))
            }
            Row::Series { name, issues } => Row::Series {
                name,
                issues: in_series_order(issues),
            },
            single => single,
        })
        .collect()
}

/// A series' issues in their own order: by issue number, a publication with none last.
pub fn in_series_order(mut issues: Vec<Publication>) -> Vec<Publication> {
    issues.sort_by(|a, b| issue_number(a).total_cmp(&issue_number(b)));
    issues
}

fn issue_number(publication: &Publication) -> f64 {
    publication
        .number
        .as_deref()
        .and_then(|number| number.trim().parse::<f64>().ok())
        .unwrap_or(f64::MAX)
}

/// One entry of the index: the letter, and the first row filed under it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IndexEntry {
    pub letter: String,
    pub position: u32,
}

/// The letter a title is filed under: its first letter, folded and upper case, or `#`
/// for a title that does not start with a letter.
pub fn filed_under(title: &str) -> String {
    match fold(title.trim()).chars().next() {
        Some(first) if first.is_alphabetic() => first.to_uppercase().collect(),
        _ => "#".into(),
    }
}

/// The index for the shelf: one entry per letter the shelf files a row under, in the
/// shelf's order, for a sort by title or series only. Every other order files nothing
/// under a letter, so it has no index at all.
pub fn index(titles: &[&str], sort: Sort) -> Vec<IndexEntry> {
    if !matches!(sort, Sort::Title | Sort::Series) {
        return Vec::new();
    }
    let mut entries: Vec<IndexEntry> = Vec::new();
    for (position, title) in titles.iter().enumerate() {
        let letter = filed_under(title);
        if entries.iter().all(|entry| entry.letter != letter) {
            entries.push(IndexEntry {
                letter,
                position: u32::try_from(position).unwrap_or(u32::MAX),
            });
        }
    }
    entries
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;

    fn publication(title: &str, series: Option<(&str, &str)>) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(format!("/comics/{title}.cbz")),
            PublicationFormat::Cbz,
            title,
            MetadataOrigin::Inferred,
        );
        if let Some((name, number)) = series {
            publication.series = Some(name.into());
            publication.number = Some(number.into());
        }
        publication
    }

    fn shelf() -> Vec<Publication> {
        vec![
            publication("Akira 2", Some(("Akira", "2"))),
            publication("Blacksad", None),
            publication("Akira 1", Some(("Akira", "1"))),
            publication("Saga 10", Some(("Saga", "10"))),
            publication("Saga 9", Some(("Saga", "9"))),
            publication("Monstress 1", Some(("Monstress", "1"))),
        ]
    }

    #[test]
    fn a_series_is_one_row_holding_its_issues_in_order() {
        let rows = rows(shelf(), Grouping::Series);
        assert_eq!(rows.len(), 4);
        let titles: Vec<&str> = rows.iter().map(Row::title).collect();
        assert_eq!(titles, ["Akira", "Blacksad", "Saga", "Monstress 1"]);
        let Row::Series { issues, .. } = &rows[2] else {
            panic!("Saga is a series row");
        };
        let order: Vec<&str> = issues.iter().map(|p| p.display_title.as_str()).collect();
        assert_eq!(order, ["Saga 9", "Saga 10"], "#10 follows #9");
        assert!(
            matches!(rows[3], Row::Publication(_)),
            "the only issue of its series here stays a cover of its own"
        );
    }

    #[test]
    fn a_shelf_of_issues_has_one_cell_per_publication() {
        let rows = rows(shelf(), Grouping::Issues);
        assert_eq!(rows.len(), 6);
        assert!(rows.iter().all(|row| matches!(row, Row::Publication(_))));
    }

    #[test]
    fn the_view_choice_persists_and_series_is_the_default() {
        assert_eq!(ViewChoice::default().grouping, Grouping::Series);
        let chosen = ViewChoice {
            layout: Layout::List,
            grouping: Grouping::Issues,
        };
        assert_eq!(ViewChoice::restore(&chosen.save()), chosen);
        assert_eq!(ViewChoice::restore("nonsense"), ViewChoice::default());
    }

    #[test]
    fn the_index_holds_one_entry_per_letter_in_the_shelf_s_order() {
        let titles = ["Akira", "Ásterix", "Blacksad", "300", "Saga"];
        let entries = index(&titles, Sort::Title);
        let letters: Vec<&str> = entries.iter().map(|e| e.letter.as_str()).collect();
        assert_eq!(letters, ["A", "B", "#", "S"]);
        assert_eq!(entries[1].position, 2);
        assert_eq!(entries[2].position, 3, "a row under no letter is #");
    }

    #[test]
    fn a_sort_no_letter_describes_has_no_index() {
        let titles = ["Akira", "Blacksad"];
        assert!(index(&titles, Sort::LastRead).is_empty());
        assert!(index(&titles, Sort::DateAdded).is_empty());
        assert_eq!(index(&titles, Sort::Series).len(), 2);
    }
}
