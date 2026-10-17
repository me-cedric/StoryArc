//! Image adjustments, per series (`comic-reader`, Image adjustments): brightness,
//! contrast, sharpness, inversion and greyscale with a live preview, and the border trim
//! with a way to turn it off for one page that trims wrongly. A change applies to the
//! series, never to everything read. The arithmetic is the core's
//! (`storyarc_core::image::adjusted`); this keeps the choices.
//!
//! One line per series in a small file. Pure, so it tests on any host.

use std::collections::{BTreeMap, BTreeSet};

use storyarc_core::domain::{ImageAdjustments, Publication};

use super::direction::key_of;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Adjustments {
    chosen: BTreeMap<String, ImageAdjustments>,
    /// Pages the trim must leave alone, by publication path.
    untrimmed: BTreeMap<String, BTreeSet<usize>>,
}

impl Adjustments {
    pub fn for_publication(&self, publication: &Publication) -> ImageAdjustments {
        self.chosen
            .get(&key_of(publication))
            .copied()
            .unwrap_or_default()
    }

    pub fn choose(&mut self, publication: &Publication, adjustments: ImageAdjustments) {
        let key = key_of(publication);
        let adjustments = adjustments.clamped();
        if adjustments.is_neutral() {
            self.chosen.remove(&key);
        } else {
            self.chosen.insert(key, adjustments);
        }
    }

    /// What one page is drawn with: the series' adjustments, the trim off where the
    /// reader turned it off for this page.
    pub fn for_page(&self, publication: &Publication, id: &str, page: usize) -> ImageAdjustments {
        let allowed = !self
            .untrimmed
            .get(id)
            .is_some_and(|pages| pages.contains(&page));
        self.for_publication(publication).trimming_borders(allowed)
    }

    pub fn is_trimmed_here(&self, id: &str, page: usize) -> bool {
        !self
            .untrimmed
            .get(id)
            .is_some_and(|pages| pages.contains(&page))
    }

    /// Turns the trim off or back on for one page.
    pub fn set_trim_here(&mut self, id: &str, page: usize, trimmed: bool) {
        let pages = self.untrimmed.entry(id.to_owned()).or_default();
        if trimmed {
            pages.remove(&page);
        } else {
            pages.insert(page);
        }
        if pages.is_empty() {
            self.untrimmed.remove(id);
        }
    }

    pub fn save(&self) -> String {
        let mut text = String::new();
        for (key, a) in &self.chosen {
            text.push_str(&format!(
                "series\t{key}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                a.brightness,
                a.contrast,
                a.sharpness,
                a.is_inverted,
                a.is_greyscale,
                a.crops_borders
            ));
        }
        for (id, pages) in &self.untrimmed {
            let list: Vec<String> = pages.iter().map(usize::to_string).collect();
            text.push_str(&format!("untrimmed\t{id}\t{}\n", list.join(",")));
        }
        text
    }

    pub fn restore(text: &str) -> Self {
        let mut adjustments = Self::default();
        for line in text.lines() {
            let fields: Vec<&str> = line.split('\t').collect();
            match fields.as_slice() {
                [
                    "series",
                    key,
                    brightness,
                    contrast,
                    sharpness,
                    inverted,
                    grey,
                    crops,
                ] => {
                    let (Ok(brightness), Ok(contrast), Ok(sharpness)) =
                        (brightness.parse(), contrast.parse(), sharpness.parse())
                    else {
                        continue;
                    };
                    let value = ImageAdjustments {
                        brightness,
                        contrast,
                        sharpness,
                        is_inverted: *inverted == "true",
                        is_greyscale: *grey == "true",
                        crops_borders: *crops == "true",
                    }
                    .clamped();
                    adjustments.chosen.insert((*key).to_owned(), value);
                }
                ["untrimmed", id, pages] => {
                    let pages: BTreeSet<usize> = pages
                        .split(',')
                        .filter_map(|page| page.parse().ok())
                        .collect();
                    if !pages.is_empty() {
                        adjustments.untrimmed.insert((*id).to_owned(), pages);
                    }
                }
                _ => {}
            }
        }
        adjustments
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

    fn brighter() -> ImageAdjustments {
        ImageAdjustments {
            brightness: 0.3,
            is_greyscale: true,
            crops_borders: true,
            ..ImageAdjustments::default()
        }
    }

    #[test]
    fn an_adjustment_applies_to_the_series_and_never_globally() {
        let mut adjustments = Adjustments::default();
        adjustments.choose(&issue("/a1.cbz", "Akira"), brighter());
        assert_eq!(
            adjustments.for_publication(&issue("/a2.cbz", "Akira")),
            brighter()
        );
        assert!(
            adjustments
                .for_publication(&issue("/s.cbz", "Saga"))
                .is_neutral()
        );
    }

    #[test]
    fn the_trim_can_be_turned_off_for_one_page_that_trims_wrongly() {
        let mut adjustments = Adjustments::default();
        let akira = issue("/a1.cbz", "Akira");
        adjustments.choose(&akira, brighter());
        adjustments.set_trim_here("/a1.cbz", 3, false);
        assert!(!adjustments.for_page(&akira, "/a1.cbz", 3).crops_borders);
        assert!(adjustments.for_page(&akira, "/a1.cbz", 4).crops_borders);
        assert_eq!(adjustments.for_page(&akira, "/a1.cbz", 3).brightness, 0.3);
        adjustments.set_trim_here("/a1.cbz", 3, true);
        assert!(adjustments.is_trimmed_here("/a1.cbz", 3));
    }

    #[test]
    fn the_adjustments_survive_a_relaunch_clamped() {
        let mut adjustments = Adjustments::default();
        adjustments.choose(&issue("/a1.cbz", "Akira"), brighter());
        adjustments.set_trim_here("/a1.cbz", 2, false);
        assert_eq!(Adjustments::restore(&adjustments.save()), adjustments);
        let wild = Adjustments::restore("series\tseries:X\t40\t0\t0\tfalse\tfalse\tfalse\n");
        assert_eq!(wild.for_publication(&issue("/x.cbz", "X")).brightness, 1.0);
    }

    #[test]
    fn going_back_to_neutral_forgets_the_series() {
        let mut adjustments = Adjustments::default();
        let akira = issue("/a1.cbz", "Akira");
        adjustments.choose(&akira, brighter());
        adjustments.choose(&akira, ImageAdjustments::default());
        assert_eq!(adjustments.save(), "");
    }
}
