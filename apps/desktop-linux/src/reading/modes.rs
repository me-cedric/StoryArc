//! How pages change in a reader (`page-transitions`, Transition modes; `comic-reader`,
//! Page transitions in the comic reader): Slide, Fast fade or Scroll, chosen per
//! publication and remembered for its series, with the global default from the
//! preferences for a series never opened. The curl is offered, unavailable with its
//! reason, until wave 5 builds it on Linux. Scroll runs on the vertical axis unless the
//! reader chose the horizontal one, stitches pages with no gap unless the reader asked
//! for one, and keeps its exact place within a page.
//!
//! Kept in one small file, one line per choice. Pure, so it tests on any host.

use std::collections::BTreeMap;

use storyarc_core::domain::Publication;

use super::direction::key_of;
use crate::strings::tr;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    Curl,
    #[default]
    Slide,
    Fade,
    Scroll,
}

impl Mode {
    pub const ALL: [Self; 4] = [Self::Curl, Self::Slide, Self::Fade, Self::Scroll];

    pub fn key(self) -> &'static str {
        match self {
            Self::Curl => "curl",
            Self::Slide => "slide",
            Self::Fade => "fade",
            Self::Scroll => "scroll",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|mode| mode.key() == key)
    }

    pub fn label(self) -> String {
        match self {
            Self::Curl => tr("theme.pageTurn.curl", "Curl"),
            Self::Slide => tr("theme.pageTurn.slide", "Slide"),
            Self::Fade => tr("theme.pageTurn.fade", "Fast fade"),
            Self::Scroll => tr("theme.pageTurn.scroll", "Continuous scroll"),
        }
    }

    /// Why a mode cannot apply, when it cannot: shown beside it, never silently absent
    /// (`page-transitions`, A mode is unavailable for the content).
    pub fn unavailable_reason(self) -> Option<String> {
        (self == Self::Curl).then(|| {
            tr(
                "reader.pageTurn.curl.later",
                "The curl comes to Linux in a later version",
            )
        })
    }

    /// The animation a turn runs: none with reduced motion, where a slide becomes the
    /// nearest still mode, the fade; and none at all in Scroll, which never turns.
    pub fn animation(self, reduced_motion: bool) -> Animation {
        match (self, reduced_motion) {
            (Self::Scroll, _) => Animation::None,
            (Self::Slide | Self::Curl, false) => Animation::Slide,
            (_, true) | (Self::Fade, false) => Animation::Fade,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Animation {
    None,
    Slide,
    Fade,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Axis {
    #[default]
    Vertical,
    Horizontal,
}

/// One series' choice.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ModeChoice {
    pub mode: Mode,
    pub axis: Axis,
    /// A separator between pages in Scroll; stitched with no gap by default.
    pub gap: bool,
}

/// Where Scroll left a publication: the page, and how far down it, from 0 to 1.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ScrollPlace {
    pub page: u32,
    pub fraction: f64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ModeChoices {
    chosen: BTreeMap<String, ModeChoice>,
    places: BTreeMap<String, ScrollPlace>,
}

impl ModeChoices {
    /// The choice for a publication: its series' or its own, else the default.
    pub fn for_publication(&self, publication: &Publication, default: Mode) -> ModeChoice {
        self.chosen
            .get(&key_of(publication))
            .copied()
            .unwrap_or(ModeChoice {
                mode: default,
                ..ModeChoice::default()
            })
    }

    pub fn choose(&mut self, publication: &Publication, choice: ModeChoice) {
        self.chosen.insert(key_of(publication), choice);
    }

    /// Where Scroll left a publication, by the path it was opened from.
    pub fn place(&self, id: &str) -> Option<ScrollPlace> {
        self.places.get(id).copied()
    }

    pub fn keep_place(&mut self, id: &str, place: ScrollPlace) {
        self.places.insert(
            id.to_owned(),
            ScrollPlace {
                fraction: place.fraction.clamp(0.0, 1.0),
                ..place
            },
        );
    }

    pub fn save(&self) -> String {
        let mut text = String::new();
        for (key, choice) in &self.chosen {
            let axis = match choice.axis {
                Axis::Vertical => "vertical",
                Axis::Horizontal => "horizontal",
            };
            text.push_str(&format!(
                "mode\t{key}\t{}\t{axis}\t{}\n",
                choice.mode.key(),
                if choice.gap { "gap" } else { "stitched" }
            ));
        }
        for (id, place) in &self.places {
            text.push_str(&format!(
                "place\t{id}\t{}\t{}\n",
                place.page, place.fraction
            ));
        }
        text
    }

    /// Reads the file back; a damaged line is skipped.
    pub fn restore(text: &str) -> Self {
        let mut choices = Self::default();
        for line in text.lines() {
            let fields: Vec<&str> = line.split('\t').collect();
            match fields.as_slice() {
                ["mode", key, mode, axis, gap] => {
                    let Some(mode) = Mode::from_key(mode) else {
                        continue;
                    };
                    let axis = if *axis == "horizontal" {
                        Axis::Horizontal
                    } else {
                        Axis::Vertical
                    };
                    choices.chosen.insert(
                        (*key).to_owned(),
                        ModeChoice {
                            mode,
                            axis,
                            gap: *gap == "gap",
                        },
                    );
                }
                ["place", id, page, fraction] => {
                    if let (Ok(page), Ok(fraction)) = (page.parse(), fraction.parse()) {
                        choices.keep_place(id, ScrollPlace { page, fraction });
                    }
                }
                _ => {}
            }
        }
        choices
    }
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;

    fn issue(path: &str, series: &str) -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path(path),
            PublicationFormat::Cbz,
            "Issue",
            MetadataOrigin::Inferred,
        );
        publication.series = Some(series.into());
        publication
    }

    #[test]
    fn a_series_never_opened_takes_the_global_default() {
        let choices = ModeChoices::default();
        let choice = choices.for_publication(&issue("/a.cbz", "Saga"), Mode::Fade);
        assert_eq!(choice.mode, Mode::Fade);
        assert_eq!(choice.axis, Axis::Vertical, "Scroll defaults to vertical");
        assert!(!choice.gap, "pages are stitched with no gap by default");
    }

    #[test]
    fn a_mode_chosen_for_one_issue_applies_to_its_whole_series() {
        let mut choices = ModeChoices::default();
        let scroll = ModeChoice {
            mode: Mode::Scroll,
            axis: Axis::Horizontal,
            gap: true,
        };
        choices.choose(&issue("/a1.cbz", "Akira"), scroll);
        assert_eq!(
            choices.for_publication(&issue("/a2.cbz", "Akira"), Mode::Slide),
            scroll
        );
        assert_eq!(
            choices
                .for_publication(&issue("/s.cbz", "Saga"), Mode::Slide)
                .mode,
            Mode::Slide
        );
    }

    #[test]
    fn the_choices_and_the_exact_scroll_place_survive_a_relaunch() {
        let mut choices = ModeChoices::default();
        choices.choose(
            &issue("/a1.cbz", "Akira"),
            ModeChoice {
                mode: Mode::Scroll,
                axis: Axis::Vertical,
                gap: false,
            },
        );
        choices.keep_place(
            "/a1.cbz",
            ScrollPlace {
                page: 7,
                fraction: 0.375,
            },
        );
        let restored = ModeChoices::restore(&choices.save());
        assert_eq!(restored, choices);
        assert_eq!(
            restored.place("/a1.cbz"),
            Some(ScrollPlace {
                page: 7,
                fraction: 0.375
            })
        );
        assert_eq!(
            ModeChoices::restore("mode\tx\twobble\tvertical\tgap\n"),
            ModeChoices::default()
        );
    }

    #[test]
    fn the_curl_is_shown_unavailable_with_its_reason_and_the_others_apply() {
        assert!(Mode::Curl.unavailable_reason().is_some());
        for mode in [Mode::Slide, Mode::Fade, Mode::Scroll] {
            assert_eq!(mode.unavailable_reason(), None);
        }
    }

    #[test]
    fn reduced_motion_turns_a_slide_into_the_fade_and_scroll_never_animates() {
        assert_eq!(Mode::Slide.animation(false), Animation::Slide);
        assert_eq!(Mode::Slide.animation(true), Animation::Fade);
        assert_eq!(Mode::Fade.animation(false), Animation::Fade);
        assert_eq!(Mode::Scroll.animation(false), Animation::None);
    }
}
