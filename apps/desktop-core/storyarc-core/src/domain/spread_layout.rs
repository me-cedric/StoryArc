//! The reader's page order once two pages may share the screen. Mirrored from
//! `SpreadLayout.swift`; Android's `SpreadLayout` is the same type.
//!
//! `comic-reader`: two consecutive portrait pages in a landscape window are shown side by
//! side in reading order, a page detected as a single wide spread is shown alone and never
//! split across two turns, and the reader can offset the pairing by one page. All three
//! rules are arithmetic, and arithmetic is the thing that diverges silently between
//! codebases, so they live here rather than in either reader.

use std::collections::HashSet;

/// One slot in the reader's page order: a page on its own, or two facing pages, in the
/// publication's own order. Which side each page lands on is the view's business.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Spread {
    pub leading: usize,
    pub trailing: Option<usize>,
}

impl Spread {
    /// The pages in this slot, in reading order.
    pub fn pages(&self) -> Vec<usize> {
        match self.trailing {
            Some(trailing) => vec![self.leading, trailing],
            None => vec![self.leading],
        }
    }

    pub fn is_pair(&self) -> bool {
        self.trailing.is_some()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpreadLayout {
    /// The slots, in the publication's own order.
    pub slots: Vec<Spread>,
    /// Which slot each page landed in, by page number. Precomputed because the reader
    /// asks on every layout pass.
    slot_of_page: Vec<usize>,
}

impl SpreadLayout {
    /// Every page on its own: portrait, a continuous scroll, and a publication of one page.
    pub fn single(page_count: usize) -> Self {
        Self::new(
            (0..page_count)
                .map(|leading| Spread {
                    leading,
                    trailing: None,
                })
                .collect(),
        )
    }

    /// Facing pages, paired.
    ///
    /// `wide` holds the pages that take the width of two — declared by `ComicInfo` or found
    /// to be landscape when they decoded. Each one stands alone, and so does the page that
    /// would otherwise have been paired with it. `is_offset` shifts the pairing by one so
    /// the cover stands alone.
    pub fn paired(page_count: usize, wide: &HashSet<usize>, is_offset: bool) -> Self {
        let mut slots = Vec::new();
        let mut index = 0;
        if is_offset && page_count > 0 {
            slots.push(Spread {
                leading: 0,
                trailing: None,
            });
            index = 1;
        }
        while index < page_count {
            let alone =
                wide.contains(&index) || index + 1 >= page_count || wide.contains(&(index + 1));
            if alone {
                slots.push(Spread {
                    leading: index,
                    trailing: None,
                });
                index += 1;
            } else {
                slots.push(Spread {
                    leading: index,
                    trailing: Some(index + 1),
                });
                index += 2;
            }
        }
        Self::new(slots)
    }

    fn new(slots: Vec<Spread>) -> Self {
        let page_count: usize = slots.iter().map(|spread| spread.pages().len()).sum();
        let mut slot_of_page = vec![0; page_count];
        for (slot, spread) in slots.iter().enumerate() {
            for page in spread.pages() {
                if let Some(entry) = slot_of_page.get_mut(page) {
                    *entry = slot;
                }
            }
        }
        Self {
            slots,
            slot_of_page,
        }
    }

    pub fn count(&self) -> usize {
        self.slots.len()
    }

    /// The slot a page is shown in. Zero for a page that is not in this layout.
    pub fn slot_containing(&self, page: usize) -> usize {
        self.slot_of_page.get(page).copied().unwrap_or(0)
    }

    pub fn slot(&self, index: usize) -> Option<&Spread> {
        self.slots.get(index)
    }

    /// Whether anything here is actually a pair, which decides whether the offset control
    /// is offered at all.
    pub fn has_pairs(&self) -> bool {
        self.slots.iter().any(Spread::is_pair)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shape(layout: &SpreadLayout) -> Vec<Vec<usize>> {
        layout.slots.iter().map(Spread::pages).collect()
    }

    fn wide(pages: &[usize]) -> HashSet<usize> {
        pages.iter().copied().collect()
    }

    #[test]
    fn portrait_shows_every_page_on_its_own_and_nothing_has_no_slots() {
        assert_eq!(
            shape(&SpreadLayout::single(4)),
            vec![vec![0], vec![1], vec![2], vec![3]]
        );
        assert!(SpreadLayout::single(0).slots.is_empty());
        assert!(SpreadLayout::paired(0, &wide(&[]), true).slots.is_empty());
    }

    #[test]
    fn landscape_pairs_consecutive_pages_and_leaves_an_odd_tail_alone() {
        assert_eq!(
            shape(&SpreadLayout::paired(6, &wide(&[]), false)),
            vec![vec![0, 1], vec![2, 3], vec![4, 5]]
        );
        assert_eq!(
            shape(&SpreadLayout::paired(5, &wide(&[]), false)),
            vec![vec![0, 1], vec![2, 3], vec![4]]
        );
    }

    #[test]
    fn a_wide_page_stands_alone_and_so_does_its_neighbour() {
        assert_eq!(
            shape(&SpreadLayout::paired(6, &wide(&[2]), false)),
            vec![vec![0, 1], vec![2], vec![3, 4], vec![5]]
        );
        assert_eq!(
            shape(&SpreadLayout::paired(6, &wide(&[3]), false)),
            vec![vec![0, 1], vec![2], vec![3], vec![4, 5]]
        );
        assert_eq!(
            shape(&SpreadLayout::paired(4, &wide(&[1, 2]), false)),
            vec![vec![0], vec![1], vec![2], vec![3]]
        );
    }

    #[test]
    fn the_offset_stands_the_cover_alone() {
        assert_eq!(
            shape(&SpreadLayout::paired(6, &wide(&[]), true)),
            vec![vec![0], vec![1, 2], vec![3, 4], vec![5]]
        );
    }

    #[test]
    fn a_page_knows_its_slot_and_an_outsider_resolves_to_the_first() {
        let layout = SpreadLayout::paired(6, &wide(&[2]), false);
        assert_eq!(
            [0, 1, 2, 4, 5].map(|page| layout.slot_containing(page)),
            [0, 0, 1, 2, 3]
        );
        assert_eq!(SpreadLayout::single(3).slot_containing(99), 0);
        assert_eq!(SpreadLayout::single(3).slot(99), None);
    }

    #[test]
    fn a_publication_of_nothing_but_wide_pages_has_no_pairing_to_offset() {
        assert!(!SpreadLayout::paired(3, &wide(&[0, 1, 2]), false).has_pairs());
        assert!(SpreadLayout::paired(4, &wide(&[]), false).has_pairs());
        assert!(!SpreadLayout::single(4).has_pairs());
    }
}
