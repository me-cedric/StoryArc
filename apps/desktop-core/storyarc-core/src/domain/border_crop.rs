//! Finds the uniform margin around a scanned page. Mirrored from `BorderCrop.swift`;
//! Android's `BorderCrop` is the same rule.
//!
//! `comic-reader`: "uniform white or black margins are detected and trimmed per page". The
//! rule is deliberately timid. A row is margin only if every sample in it is within
//! [`BorderCrop::TOLERANCE`] of the line it started from *and* that line is near-white or
//! near-black, and the run must end at an edge. Artwork that happens to start with a pale
//! sky is not a margin, and a page cropped into is worse than a page not cropped at all.

/// One page's edges, as the number of pixels to trim from each.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct BorderInset {
    pub top: u32,
    pub left: u32,
    pub bottom: u32,
    pub right: u32,
}

impl BorderInset {
    /// Nothing to trim.
    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

pub struct BorderCrop;

impl BorderCrop {
    /// How far two samples may differ and still count as the same colour, out of 255.
    /// Twelve, because a JPEG's flat white is not flat.
    pub const TOLERANCE: i32 = 12;

    /// How much of a page may be taken. Beyond this the detection is wrong about something.
    pub const LIMIT: f64 = 0.4;

    /// How far the first line of artwork must sit from the margin for the margin to be one.
    /// Without it a smooth gradient reads as a deep margin.
    pub const EDGE: i32 = Self::TOLERANCE * 3;

    /// What to trim from a page of this size. `sample` reads one channel's brightness,
    /// 0 to 255, at a point.
    pub fn inset(width: u32, height: u32, sample: impl Fn(u32, u32) -> u8) -> BorderInset {
        if width <= 2 || height <= 2 {
            return BorderInset::default();
        }
        let sample = |x: u32, y: u32| i32::from(sample(x, y));
        let cap_x = (f64::from(width) * Self::LIMIT) as u32;
        let cap_y = (f64::from(height) * Self::LIMIT) as u32;
        // Probed down the middle, not down the corner: a corner stays margin all the way
        // through the page, so a run measured there never meets the edge that ends it.
        let (middle_x, middle_y) = (width / 2, height / 2);
        BorderInset {
            top: Self::run(
                cap_y,
                |n| sample(middle_x, n),
                |n| Self::uniform_row(n, width, &sample),
            ),
            left: Self::run(
                cap_x,
                |n| sample(n, middle_y),
                |n| Self::uniform_column(n, height, &sample),
            ),
            bottom: Self::run(
                cap_y,
                |n| sample(middle_x, height - 1 - n),
                |n| Self::uniform_row(height - 1 - n, width, &sample),
            ),
            right: Self::run(
                cap_x,
                |n| sample(width - 1 - n, middle_y),
                |n| Self::uniform_column(width - 1 - n, height, &sample),
            ),
        }
    }

    /// How many lines in from an edge are margin, and zero unless they end at one.
    fn run(cap: u32, value: impl Fn(u32) -> i32, is_margin: impl Fn(u32) -> bool) -> u32 {
        let reference = value(0);
        let mut count = 0;
        // Each line must look like the first one, not merely like the line before it: a
        // gradient satisfies the second and none of it is a margin.
        while count < cap && is_margin(count) && (value(count) - reference).abs() <= Self::TOLERANCE
        {
            count += 1;
        }
        if count > 0 && (value(count) - reference).abs() >= Self::EDGE {
            count
        } else {
            0
        }
    }

    fn uniform_row(row: u32, width: u32, sample: &impl Fn(u32, u32) -> i32) -> bool {
        let first = sample(0, row);
        Self::is_paper_or_ink(first)
            && (0..width)
                .step_by((width / 64).max(1) as usize)
                .all(|x| (sample(x, row) - first).abs() <= Self::TOLERANCE)
    }

    fn uniform_column(column: u32, height: u32, sample: &impl Fn(u32, u32) -> i32) -> bool {
        let first = sample(column, 0);
        Self::is_paper_or_ink(first)
            && (0..height)
                .step_by((height / 64).max(1) as usize)
                .all(|y| (sample(column, y) - first).abs() <= Self::TOLERANCE)
    }

    /// Whether a value is close enough to white or to black to be a margin at all.
    fn is_paper_or_ink(value: i32) -> bool {
        value >= 226 || value <= 30
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A page with `margin` pixels of `paper` around a block of `art`, as iOS's tests draw it.
    fn page(margin: u32, paper: u8, art: u8) -> impl Fn(u32, u32) -> u8 {
        move |x, y| {
            let inside = x >= margin && y >= margin && x < 100 - margin && y < 100 - margin;
            if inside { art } else { paper }
        }
    }

    #[test]
    fn a_white_margin_is_found_on_every_edge() {
        assert_eq!(
            BorderCrop::inset(100, 100, page(10, 255, 40)),
            BorderInset {
                top: 10,
                left: 10,
                bottom: 10,
                right: 10
            }
        );
    }

    #[test]
    fn a_black_margin_is_found_too() {
        assert_eq!(BorderCrop::inset(100, 100, page(6, 0, 200)).top, 6);
    }

    #[test]
    fn a_page_with_no_margin_is_left_alone() {
        assert!(BorderCrop::inset(100, 100, |_, _| 128).is_empty());
    }

    #[test]
    fn a_mid_grey_band_is_not_a_margin() {
        assert!(BorderCrop::inset(100, 100, page(10, 128, 40)).is_empty());
    }

    #[test]
    fn a_gradient_is_not_a_margin() {
        assert!(BorderCrop::inset(100, 100, |_, y| (255 - y * 2) as u8).is_empty());
    }

    #[test]
    fn a_page_that_is_all_one_colour_is_left_alone() {
        assert!(BorderCrop::inset(100, 100, |_, _| 255).is_empty());
    }

    #[test]
    fn nothing_is_trimmed_past_the_limit() {
        let inset = BorderCrop::inset(100, 100, page(45, 255, 40));
        assert!(inset.top + inset.bottom < 100);
        assert!(inset.top <= 40);
    }

    #[test]
    fn a_page_too_small_to_sample_is_left_alone() {
        assert!(BorderCrop::inset(1, 1, |_, _| 255).is_empty());
    }
}
