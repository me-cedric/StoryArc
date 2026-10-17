//! The cover grid and the list: the cover ladder by shelf width, the columns that
//! follow it, grouping by series, and selection by click, Control-click and
//! Shift-click (`docs/designs/desktop/README.md` section 4).

use std::collections::BTreeSet;

use super::entry::LibraryEntry;
use crate::settings::CoverSize;

/// The gap between covers, the `md` token.
pub const GRID_GAP: i32 = 12;
/// No cover grows past this, however wide the window.
pub const COVER_CAP: i32 = 168;

/// The minimum cover width for a shelf width, from the README ladder.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CoverTier {
    pub min: i32,
    pub max: i32,
}

impl CoverTier {
    pub const SMALL: i32 = 104;
    pub const MEDIUM: i32 = 132;
    pub const LARGE: i32 = 158;

    /// The tier the shelf's own width asks for, or the size the reader picked.
    pub fn for_width(shelf_width: i32, size: CoverSize) -> Self {
        let min = match size {
            CoverSize::Small => Self::SMALL,
            CoverSize::Medium => Self::MEDIUM,
            CoverSize::Large => Self::LARGE,
            CoverSize::Automatic if shelf_width < 600 => Self::SMALL,
            CoverSize::Automatic if shelf_width < 840 => Self::MEDIUM,
            CoverSize::Automatic => Self::LARGE,
        };
        Self {
            min,
            max: COVER_CAP,
        }
    }

    /// How many covers fit across: a wider window adds columns and never stretches a
    /// cover past the cap. Always at least one.
    pub fn columns(self, shelf_width: i32) -> u32 {
        let per_cover = self.min + GRID_GAP;
        ((shelf_width + GRID_GAP) / per_cover).max(1) as u32
    }

    /// The width each cover takes once the columns share the shelf, capped.
    pub fn cell_width(self, shelf_width: i32) -> i32 {
        let columns = self.columns(shelf_width) as i32;
        let shared = (shelf_width - GRID_GAP * (columns - 1)) / columns;
        shared.clamp(self.min.min(shelf_width.max(1)), self.max)
    }
}

/// Publications in one series, in issue order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SeriesGroup<'a> {
    pub name: String,
    pub entries: Vec<&'a LibraryEntry>,
}

/// The grid over a slice of entries: it holds references, never a widget per entry,
/// so 10,000 publications cost nothing until a cell is bound.
#[derive(Clone, Debug)]
pub struct GridModel<'a> {
    entries: &'a [LibraryEntry],
    tier: CoverTier,
    shelf_width: i32,
}

impl<'a> GridModel<'a> {
    pub fn new(entries: &'a [LibraryEntry], shelf_width: i32, size: CoverSize) -> Self {
        Self {
            entries,
            tier: CoverTier::for_width(shelf_width, size),
            shelf_width,
        }
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn tier(&self) -> CoverTier {
        self.tier
    }

    pub fn columns(&self) -> u32 {
        self.tier.columns(self.shelf_width)
    }

    pub fn cell_width(&self) -> i32 {
        self.tier.cell_width(self.shelf_width)
    }

    pub fn entry(&self, index: usize) -> Option<&'a LibraryEntry> {
        self.entries.get(index)
    }

    /// The entries grouped by series, groups by name, issues in order. A publication
    /// with no series is its own group under its title.
    pub fn grouped_by_series(&self) -> Vec<SeriesGroup<'a>> {
        let mut groups: Vec<SeriesGroup<'a>> = Vec::new();
        for entry in self.entries {
            let name = entry.series.clone().unwrap_or_else(|| entry.title.clone());
            match groups.iter_mut().find(|group| group.name == name) {
                Some(group) => group.entries.push(entry),
                None => groups.push(SeriesGroup {
                    name,
                    entries: vec![entry],
                }),
            }
        }
        for group in &mut groups {
            group
                .entries
                .sort_by_key(|entry| (entry.issue.unwrap_or(u32::MAX), entry.title.clone()));
        }
        groups.sort_by_key(|group| group.name.to_lowercase());
        groups
    }
}

/// Which modifier a click carried.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClickModifier {
    None,
    Control,
    Shift,
}

/// The selected cells: a plain click selects one, Control-click toggles one more,
/// Shift-click extends from the anchor.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Selection {
    selected: BTreeSet<usize>,
    anchor: Option<usize>,
}

impl Selection {
    pub fn click(&mut self, index: usize, modifier: ClickModifier) {
        match modifier {
            ClickModifier::None => {
                self.selected.clear();
                self.selected.insert(index);
                self.anchor = Some(index);
            }
            ClickModifier::Control => {
                if !self.selected.remove(&index) {
                    self.selected.insert(index);
                }
                self.anchor = Some(index);
            }
            ClickModifier::Shift => {
                let anchor = self.anchor.unwrap_or(index);
                let (from, to) = (anchor.min(index), anchor.max(index));
                self.selected.extend(from..=to);
            }
        }
    }

    pub fn select_all(&mut self, count: usize) {
        self.selected.extend(0..count);
    }

    pub fn clear(&mut self) {
        self.selected.clear();
        self.anchor = None;
    }

    pub fn is_selected(&self, index: usize) -> bool {
        self.selected.contains(&index)
    }

    pub fn len(&self) -> usize {
        self.selected.len()
    }

    pub fn is_empty(&self) -> bool {
        self.selected.is_empty()
    }

    pub fn indices(&self) -> impl Iterator<Item = usize> + '_ {
        self.selected.iter().copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::fixtures::{corpus, entry};
    use crate::library::{Cover, Progress};

    #[test]
    fn an_empty_library_has_no_cells_and_still_a_grid() {
        let entries: Vec<LibraryEntry> = Vec::new();
        let grid = GridModel::new(&entries, 900, CoverSize::Automatic);
        assert!(grid.is_empty());
        assert_eq!(grid.len(), 0);
        assert!(grid.grouped_by_series().is_empty());
        assert!(grid.columns() >= 1);
    }

    #[test]
    fn ten_thousand_publications_are_a_model_over_a_slice() {
        let entries: Vec<LibraryEntry> = (0..10_000)
            .map(|n| entry(&format!("{n}.cbz"), &format!("Title {n}"), 24))
            .collect();
        let grid = GridModel::new(&entries, 1400, CoverSize::Automatic);
        assert_eq!(grid.len(), 10_000);
        assert_eq!(
            grid.entry(9_999).map(|e| e.title.as_str()),
            Some("Title 9999")
        );
        assert_eq!(grid.entry(10_000), None);
        assert_eq!(grid.tier().min, CoverTier::LARGE);
    }

    #[test]
    fn the_cover_ladder_follows_the_shelf_width_and_the_reader_can_pick_a_size() {
        assert_eq!(CoverTier::for_width(400, CoverSize::Automatic).min, 104);
        assert_eq!(CoverTier::for_width(700, CoverSize::Automatic).min, 132);
        assert_eq!(CoverTier::for_width(840, CoverSize::Automatic).min, 158);
        assert_eq!(CoverTier::for_width(1920, CoverSize::Small).min, 104);
        assert_eq!(CoverTier::for_width(400, CoverSize::Large).min, 158);
        assert_eq!(
            CoverTier::for_width(1920, CoverSize::Automatic).max,
            COVER_CAP
        );
    }

    #[test]
    fn a_wider_window_adds_columns_and_never_stretches_a_cover_past_the_cap() {
        let tier = CoverTier::for_width(1920, CoverSize::Automatic);
        assert_eq!(tier.columns(1920), 11);
        assert_eq!(tier.columns(360), 2);
        assert_eq!(tier.columns(100), 1);
        assert!(tier.cell_width(1920) <= COVER_CAP);
        assert!(tier.cell_width(1920) >= tier.min);
        let narrow = CoverTier::for_width(360, CoverSize::Automatic);
        assert_eq!(narrow.columns(360), 3);
        assert!(narrow.cell_width(360) >= 104);
        assert_eq!(
            CoverTier::for_width(90, CoverSize::Small).cell_width(90),
            90,
            "a shelf narrower than a cover shows one"
        );
    }

    #[test]
    fn grouping_by_series_orders_issues_and_leaves_singletons_under_their_title() {
        let entries = corpus();
        let grid = GridModel::new(&entries, 900, CoverSize::Automatic);
        let groups = grid.grouped_by_series();
        let names: Vec<&str> = groups.iter().map(|g| g.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "Ebook Fixture",
                "Fixture Series",
                "Mislabelled Zip",
                "Seven Zip"
            ]
        );
        let series = &groups[1];
        assert_eq!(series.entries.len(), 2);
        assert_eq!(series.entries[0].issue, Some(1));
        assert_eq!(series.entries[1].issue, Some(2));
    }

    #[test]
    fn a_click_selects_one_control_adds_and_shift_extends() {
        let mut selection = Selection::default();
        selection.click(2, ClickModifier::None);
        assert_eq!(selection.indices().collect::<Vec<_>>(), [2]);
        selection.click(5, ClickModifier::None);
        assert_eq!(
            selection.indices().collect::<Vec<_>>(),
            [5],
            "a plain click replaces"
        );
        selection.click(7, ClickModifier::Control);
        assert_eq!(selection.indices().collect::<Vec<_>>(), [5, 7]);
        selection.click(7, ClickModifier::Control);
        assert_eq!(
            selection.indices().collect::<Vec<_>>(),
            [5],
            "Control-click toggles"
        );
        // The last Control-click moved the anchor to 7, as GTK's lists do.
        selection.click(1, ClickModifier::Shift);
        assert_eq!(
            selection.indices().collect::<Vec<_>>(),
            [1, 2, 3, 4, 5, 6, 7]
        );
        assert!(selection.is_selected(3));
        selection.select_all(8);
        assert_eq!(selection.len(), 8);
        selection.clear();
        assert!(selection.is_empty());
        selection.click(4, ClickModifier::Shift);
        assert_eq!(
            selection.indices().collect::<Vec<_>>(),
            [4],
            "no anchor: shift selects the one"
        );
    }

    #[test]
    fn the_cover_ladder_and_the_file_that_cannot_open_keep_their_place_in_the_grid() {
        let entries = corpus();
        let grid = GridModel::new(&entries, 900, CoverSize::Automatic);
        assert_eq!(grid.entry(0).map(|e| e.cover), Some(Cover::Full));
        assert_eq!(grid.entry(1).map(|e| e.cover), Some(Cover::Thumbnail));
        assert_eq!(grid.entry(2).map(|e| e.cover), Some(Cover::Placeholder));
        let broken = grid.entry(4).unwrap();
        assert_eq!(broken.cell_label_key(), Some("library.cell.cannotOpen.cb7"));
        assert_eq!(grid.len(), 5, "the entry stays in the grid");
        assert!(
            broken
                .accessible_description()
                .ends_with("cannot be opened")
        );
        assert_eq!(
            grid.entry(0).unwrap().accessible_description(),
            "Natural Sort, Fixture Series 1, 30% read, downloaded"
        );
        assert_eq!(Progress::Finished.percent(), 100);
        assert_eq!(Progress::Reading { index: 1, of: 0 }.percent(), 0);
    }
}
