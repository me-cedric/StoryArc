//! Chapters and the page browser (`comic-reader`, Navigation within a publication and
//! Page browser). A Rust mirror of StoryArcKit's `ChapterBrowser`: a chapter starts where
//! the container declares one (ComicInfo's bookmarks), named by its own title or by its
//! position among the chapters; the browser names the chapter of the centred page, badges
//! each chapter's first page and ticks the slider at each start. With no markers there
//! is no name, no badge and no tick.
//!
//! The browser itself: the current page centred and larger, the pages beside it smaller
//! unless motion is reduced, each numbered; browsing never moves the reader, and a jump
//! offers the way back. Right to left, the carousel and the slider run from the right.
//! Pure, so it tests on any host.

use crate::strings::tr_args;

/// Where a chapter starts, and its own name when the marker carries one.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Marker {
    pub index: usize,
    pub title: Option<String>,
}

/// The markers from a container's declared starts and their titles, in page order.
pub fn markers(starts: &[usize], titles: &std::collections::HashMap<usize, String>) -> Vec<Marker> {
    let mut sorted = starts.to_vec();
    sorted.sort_unstable();
    sorted.dedup();
    sorted
        .into_iter()
        .map(|index| Marker {
            index,
            title: titles
                .get(&index)
                .map(|title| title.trim().to_owned())
                .filter(|title| !title.is_empty()),
        })
        .collect()
}

/// The marker in force at `page`: the last that starts at or before it.
pub fn active(page: usize, markers: &[Marker]) -> Option<&Marker> {
    markers.iter().rev().find(|marker| marker.index <= page)
}

/// What the browser names above the carousel for `page`, or nothing with no markers or
/// before the first chapter starts.
pub fn label(page: usize, markers: &[Marker]) -> Option<String> {
    let marker = active(page, markers)?;
    Some(match &marker.title {
        Some(title) => title.clone(),
        None => position_label(markers, marker.index),
    })
}

fn position_label(markers: &[Marker], index: usize) -> String {
    let position = markers
        .iter()
        .position(|marker| marker.index == index)
        .unwrap_or(0)
        + 1;
    tr_args("reader.chapter.number %d", "Chapter %d", &[&position])
}

/// The badge on a chapter's first page: the number its title is, when it is nothing but
/// a number, else the chapter's position. `None` for a page that starts no chapter.
pub fn badge(page: usize, markers: &[Marker]) -> Option<String> {
    let position = markers.iter().position(|marker| marker.index == page)?;
    let marker = &markers[position];
    Some(
        marker
            .title
            .as_deref()
            .filter(|title| title.chars().all(|c| c.is_ascii_digit() || c == '.'))
            .map_or_else(|| (position + 1).to_string(), str::to_owned),
    )
}

/// The page the next chapter starts at, or `None` past the last one.
pub fn next_chapter(page: usize, markers: &[Marker]) -> Option<usize> {
    markers
        .iter()
        .map(|marker| marker.index)
        .find(|start| *start > page)
}

/// The page the previous chapter starts at: the start of the chapter the reader is in
/// when they are past its first page, else the one before.
pub fn previous_chapter(page: usize, markers: &[Marker]) -> Option<usize> {
    markers
        .iter()
        .rev()
        .map(|marker| marker.index)
        .find(|start| *start < page)
}

/// The pages in the carousel's order from left to right: page one at the right end
/// when the publication reads right to left.
pub fn carousel_order(count: usize, right_to_left: bool) -> Vec<usize> {
    if right_to_left {
        (0..count).rev().collect()
    } else {
        (0..count).collect()
    }
}

/// The slider's value for a page, and back: mirrored right to left, so dragging toward
/// the reading direction moves on.
pub fn slider_value(page: usize, count: usize, right_to_left: bool) -> f64 {
    let last = count.saturating_sub(1);
    let position = if right_to_left {
        last.saturating_sub(page)
    } else {
        page
    };
    position as f64
}

pub fn page_at(value: f64, count: usize, right_to_left: bool) -> usize {
    let last = count.saturating_sub(1);
    let position = (value.round().max(0.0) as usize).min(last);
    if right_to_left {
        last - position
    } else {
        position
    }
}

/// How large a page beside the centred one is drawn, from 1 (centred) down. With reduced
/// motion every page is the same size and the outline marks the centred one.
pub fn scale(distance: usize, reduced_motion: bool) -> f64 {
    if reduced_motion || distance == 0 {
        1.0
    } else {
        0.8
    }
}

/// What a page in the carousel announces: its number, its chapter, and whether it is
/// the page the reader is on.
pub fn page_announcement(page: usize, current: usize, markers: &[Marker]) -> String {
    let mut parts = vec![tr_args("reader.thumbnail %d", "Page %d", &[&(page + 1)])];
    if let Some(chapter) = label(page, markers) {
        parts.push(chapter);
    }
    if page == current {
        parts.push(crate::strings::tr("reader.current", "current page"));
    }
    parts.join(", ")
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn chapters() -> Vec<Marker> {
        let titles = HashMap::from([(4, "The Storm".to_owned()), (9, "12".to_owned())]);
        markers(&[9, 0, 4, 4], &titles)
    }

    #[test]
    fn markers_are_ordered_named_by_title_or_by_position() {
        let markers = chapters();
        assert_eq!(markers.len(), 3);
        assert_eq!(label(0, &markers).as_deref(), Some("Chapter 1"));
        assert_eq!(label(5, &markers).as_deref(), Some("The Storm"));
        assert_eq!(label(9, &markers).as_deref(), Some("12"));
        assert_eq!(label(3, &markers).as_deref(), Some("Chapter 1"));
    }

    #[test]
    fn no_markers_means_no_name_no_badge_and_no_chapter_moves() {
        assert_eq!(label(3, &[]), None);
        assert_eq!(badge(0, &[]), None);
        assert_eq!(next_chapter(0, &[]), None);
        let late = markers(&[5], &HashMap::new());
        assert_eq!(label(2, &late), None, "before the first chapter starts");
    }

    #[test]
    fn a_chapter_s_first_page_carries_its_number_or_its_position() {
        let markers = chapters();
        assert_eq!(badge(0, &markers).as_deref(), Some("1"));
        assert_eq!(badge(4, &markers).as_deref(), Some("2"), "a named chapter");
        assert_eq!(badge(9, &markers).as_deref(), Some("12"), "a numbered one");
        assert_eq!(badge(5, &markers), None);
    }

    #[test]
    fn next_and_previous_chapter_move_between_starts() {
        let markers = chapters();
        assert_eq!(next_chapter(1, &markers), Some(4));
        assert_eq!(next_chapter(9, &markers), None);
        assert_eq!(
            previous_chapter(6, &markers),
            Some(4),
            "the start of this one"
        );
        assert_eq!(previous_chapter(4, &markers), Some(0), "the one before");
        assert_eq!(previous_chapter(0, &markers), None);
    }

    #[test]
    fn right_to_left_the_carousel_and_the_slider_run_from_the_right() {
        assert_eq!(carousel_order(3, false), [0, 1, 2]);
        assert_eq!(carousel_order(3, true), [2, 1, 0]);
        assert_eq!(slider_value(0, 10, true), 9.0);
        assert_eq!(page_at(9.0, 10, true), 0);
        assert_eq!(page_at(2.4, 10, false), 2);
        assert_eq!(page_at(40.0, 10, false), 9);
        for page in 0..10 {
            assert_eq!(page_at(slider_value(page, 10, true), 10, true), page);
        }
    }

    #[test]
    fn with_reduced_motion_no_page_scales() {
        assert_eq!(scale(0, false), 1.0);
        assert!(scale(1, false) < 1.0);
        assert_eq!(scale(1, true), 1.0);
    }

    #[test]
    fn a_page_announces_its_number_its_chapter_and_that_it_is_current() {
        let markers = chapters();
        assert_eq!(
            page_announcement(4, 4, &markers),
            "Page 5, The Storm, current page"
        );
        assert_eq!(page_announcement(1, 4, &[]), "Page 2");
    }
}
