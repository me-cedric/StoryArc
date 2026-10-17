//! What to do to a page before it is shown. Mirrored from `ImageAdjustments.swift`.
//!
//! `comic-reader`: "per-publication image adjustments for poorly scanned material",
//! offering "brightness, contrast, sharpness, colour inversion, and greyscale". The three
//! continuous values are signed and neutral at zero, so `is_neutral` is a comparison
//! against a fresh value rather than a list of magic numbers.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ImageAdjustments {
    /// −1 (black) to 1 (white), 0 unchanged.
    pub brightness: f64,
    /// −1 (flat) to 1 (hard), 0 unchanged.
    pub contrast: f64,
    /// 0 to 1. Not signed: blurring a scan is not a repair anyone asks for.
    pub sharpness: f64,
    /// White on black.
    pub is_inverted: bool,
    /// Colour removed.
    pub is_greyscale: bool,
    /// Uniform white or black margins trimmed, page by page.
    pub crops_borders: bool,
}

impl Default for ImageAdjustments {
    fn default() -> Self {
        Self {
            brightness: 0.0,
            contrast: 0.0,
            sharpness: 0.0,
            is_inverted: false,
            is_greyscale: false,
            crops_borders: false,
        }
    }
}

impl ImageAdjustments {
    /// The adjustments with every value brought back into its range. A slider cannot
    /// produce an out-of-range value; a decoded value from an altered store can, and a
    /// contrast of 40 is a black page.
    pub fn clamped(self) -> Self {
        Self {
            brightness: self.brightness.clamp(-1.0, 1.0),
            contrast: self.contrast.clamp(-1.0, 1.0),
            sharpness: self.sharpness.clamp(0.0, 1.0),
            ..self
        }
    }

    /// Nothing to do. Worth asking, because applying a no-op filter still costs a redraw
    /// of every page.
    pub fn is_neutral(&self) -> bool {
        *self == Self::default()
    }

    /// The multiplier a renderer wants for contrast, where 1 is unchanged.
    pub fn contrast_factor(&self) -> f64 {
        1.0 + self.contrast
    }

    /// The offset a renderer wants for brightness, in the same units as the pixel values.
    pub fn brightness_offset(&self) -> f64 {
        self.brightness
    }

    /// These adjustments, with the border trim off where this page must not be trimmed.
    /// Every other adjustment stays.
    pub fn trimming_borders(self, is_allowed: bool) -> Self {
        if is_allowed {
            self
        } else {
            Self {
                crops_borders: false,
                ..self
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fresh_adjustment_does_nothing() {
        assert!(ImageAdjustments::default().is_neutral());
        assert!(
            !ImageAdjustments {
                brightness: 0.1,
                ..Default::default()
            }
            .is_neutral()
        );
    }

    #[test]
    fn values_outside_the_range_are_brought_back_into_it() {
        let wild = ImageAdjustments {
            brightness: 9.0,
            contrast: -9.0,
            sharpness: -1.0,
            ..Default::default()
        }
        .clamped();
        assert_eq!(
            (wild.brightness, wild.contrast, wild.sharpness),
            (1.0, -1.0, 0.0)
        );
    }

    #[test]
    fn contrast_is_offered_as_the_multiplier_a_renderer_takes() {
        assert_eq!(ImageAdjustments::default().contrast_factor(), 1.0);
        assert_eq!(
            ImageAdjustments {
                contrast: 1.0,
                ..Default::default()
            }
            .contrast_factor(),
            2.0
        );
    }

    #[test]
    fn excusing_a_page_from_the_trim_leaves_everything_else_alone() {
        let all = ImageAdjustments {
            brightness: 0.25,
            contrast: -0.5,
            sharpness: 0.75,
            is_inverted: true,
            is_greyscale: true,
            crops_borders: true,
        };
        let excused = all.trimming_borders(false);
        assert_eq!(
            excused,
            ImageAdjustments {
                crops_borders: false,
                ..all
            }
        );
        assert_eq!(all.trimming_borders(true), all);
        assert!(
            !ImageAdjustments::default()
                .trimming_borders(true)
                .crops_borders
        );
    }

    #[test]
    fn a_store_written_before_a_field_existed_still_reads() {
        let decoded: ImageAdjustments = serde_json::from_str(r#"{"brightness":0.5}"#).unwrap();
        assert_eq!(decoded.brightness, 0.5);
        assert!(!decoded.is_greyscale);
        let json = serde_json::to_string(&decoded).unwrap();
        assert_eq!(
            serde_json::from_str::<ImageAdjustments>(&json).unwrap(),
            decoded
        );
    }
}
