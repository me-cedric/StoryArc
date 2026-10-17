//! The colour a publication's cover brings to its own page (`publication-detail`, Colour
//! taken from the cover). A Rust mirror of StoryArcKit's `CoverAccent`, case for case, so
//! one book has one colour on every app: a 32 by 32 census of the cover, paper, ink and
//! grey abstaining, the dominant bucket's average, then a wash darkened until white text
//! on it clears 4.5:1. A cover that is nearly all paper and ink yields nothing, and the
//! page falls back to the app's own accent, made legible the same way.
//!
//! Pure over RGBA bytes, so it tests on any host. The chrome never takes the colour.

use crate::settings::Rgb;

/// The census grid's edge.
pub const SAMPLE_EDGE: usize = 32;

/// White text on the wash clears this (WCAG AA for body text).
pub const TEXT_FLOOR: f64 = 4.5;

/// Point-samples straight RGBA rows down to the census grid, as packed `0xRRGGBB`.
pub fn census(rgba: &[u8], width: usize, height: usize) -> Vec<u32> {
    if width == 0 || height == 0 || rgba.len() < width * height * 4 {
        return Vec::new();
    }
    let mut pixels = Vec::with_capacity(SAMPLE_EDGE * SAMPLE_EDGE);
    for row in 0..SAMPLE_EDGE {
        let y = row * height / SAMPLE_EDGE;
        for column in 0..SAMPLE_EDGE {
            let x = column * width / SAMPLE_EDGE;
            let at = (y * width + x) * 4;
            pixels.push(
                u32::from(rgba[at]) << 16 | u32::from(rgba[at + 1]) << 8 | u32::from(rgba[at + 2]),
            );
        }
    }
    pixels
}

/// Paper, ink and near-greys do not vote.
fn carries_colour(red: i32, green: i32, blue: i32) -> bool {
    let highest = red.max(green).max(blue);
    let lowest = red.min(green).min(blue);
    highest - lowest >= 24 && highest >= 24 && lowest <= 232
}

/// The dominant colour of a census, or `None` when it has none: fewer than a tenth of
/// the pixels carry colour, so the "dominant" colour would be a logo.
pub fn dominant(pixels: &[u32]) -> Option<Rgb> {
    let mut counts = [0usize; 512];
    let mut sums = [[0usize; 3]; 512];
    for pixel in pixels {
        let (red, green, blue) = (
            ((pixel >> 16) & 0xFF) as i32,
            ((pixel >> 8) & 0xFF) as i32,
            (pixel & 0xFF) as i32,
        );
        if !carries_colour(red, green, blue) {
            continue;
        }
        let key = ((red >> 5) << 6 | (green >> 5) << 3 | (blue >> 5)) as usize;
        counts[key] += 1;
        sums[key][0] += red as usize;
        sums[key][1] += green as usize;
        sums[key][2] += blue as usize;
    }
    let counted: usize = counts.iter().sum();
    if counted == 0 || counted * 10 < pixels.len() {
        return None;
    }
    // The lowest key wins a tie, as on the phones.
    let (winner, total) =
        counts.iter().enumerate().fold(
            (0, 0),
            |best, (key, count)| {
                if *count > best.1 { (key, *count) } else { best }
            },
        );
    let channel = |index: usize| u8::try_from(sums[winner][index] / total).unwrap_or(u8::MAX);
    Some(Rgb {
        r: channel(0),
        g: channel(1),
        b: channel(2),
    })
}

fn linear(channel: u8) -> f64 {
    let value = f64::from(channel) / 255.0;
    if value <= 0.039_28 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

/// WCAG relative luminance.
pub fn luminance(colour: Rgb) -> f64 {
    0.2126 * linear(colour.r) + 0.7152 * linear(colour.g) + 0.0722 * linear(colour.b)
}

/// The WCAG contrast ratio of two colours.
pub fn contrast(a: Rgb, b: Rgb) -> f64 {
    let (light, dark) = {
        let (x, y) = (luminance(a), luminance(b));
        if x >= y { (x, y) } else { (y, x) }
    };
    (light + 0.05) / (dark + 0.05)
}

const WHITE: Rgb = Rgb {
    r: 255,
    g: 255,
    b: 255,
};

/// `colour` darkened, keeping its hue, by `amount` from 0 (unchanged) to 1 (black).
fn darkened(colour: Rgb, amount: f64) -> Rgb {
    let scale = |channel: u8| (f64::from(channel) * (1.0 - amount)) as u8;
    Rgb {
        r: scale(colour.r),
        g: scale(colour.g),
        b: scale(colour.b),
    }
}

/// The wash: `colour` darkened in twentieths until white text on it clears the floor.
/// Black always does, so there is always an answer.
pub fn wash_for(colour: Rgb) -> Rgb {
    (0..=20)
        .map(|step| darkened(colour, f64::from(step) / 20.0))
        .find(|candidate| contrast(*candidate, WHITE) >= TEXT_FLOOR)
        .unwrap_or(Rgb { r: 0, g: 0, b: 0 })
}

/// The page's wash for a cover's RGBA, or for the app's accent when the cover yields
/// nothing usable: monochrome, nearly white, nearly black, or not sampled at all.
pub fn page_wash(cover: Option<(&[u8], usize, usize)>, accent: Rgb) -> Rgb {
    let derived = cover
        .map(|(rgba, width, height)| census(rgba, width, height))
        .and_then(|pixels| dominant(&pixels));
    wash_for(derived.unwrap_or(accent))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(width: usize, height: usize, rgb: [u8; 3]) -> Vec<u8> {
        (0..width * height)
            .flat_map(|_| [rgb[0], rgb[1], rgb[2], 255])
            .collect()
    }

    const ACCENT: Rgb = Rgb {
        r: 0x8A,
        g: 0x4D,
        b: 0xF0,
    };

    #[test]
    fn a_coloured_cover_gives_its_own_colour_made_legible_under_white_text() {
        let cover = solid(64, 96, [200, 40, 30]);
        let derived = dominant(&census(&cover, 64, 96)).expect("a red cover has a colour");
        assert!(derived.r > 150 && derived.g < 80, "{derived:?}");
        let wash = page_wash(Some((&cover, 64, 96)), ACCENT);
        assert!(contrast(wash, WHITE) >= TEXT_FLOOR, "{wash:?}");
        assert!(
            wash.r > wash.g && wash.r > wash.b,
            "the hue is kept: {wash:?}"
        );
    }

    #[test]
    fn a_cover_with_no_usable_colour_falls_back_to_the_accent() {
        for grey in [[250, 250, 250], [5, 5, 5], [128, 128, 128]] {
            let cover = solid(32, 32, grey);
            assert_eq!(dominant(&census(&cover, 32, 32)), None, "{grey:?}");
            assert_eq!(page_wash(Some((&cover, 32, 32)), ACCENT), wash_for(ACCENT));
        }
        assert_eq!(page_wash(None, ACCENT), wash_for(ACCENT));
        assert_eq!(census(&[], 0, 0), Vec::<u32>::new());
    }

    #[test]
    fn a_logo_on_paper_is_not_a_colour() {
        let mut cover = solid(32, 32, [250, 250, 250]);
        for pixel in cover.chunks_mut(4).take(50) {
            pixel.copy_from_slice(&[10, 120, 250, 255]);
        }
        assert_eq!(dominant(&census(&cover, 32, 32)), None);
    }

    #[test]
    fn the_floor_is_never_lowered_to_keep_a_colour() {
        for colour in [[255, 255, 0], [0, 255, 255], [255, 200, 220]] {
            let wash = wash_for(Rgb {
                r: colour[0],
                g: colour[1],
                b: colour[2],
            });
            assert!(
                contrast(wash, WHITE) >= TEXT_FLOOR,
                "{colour:?} gave {wash:?}"
            );
        }
        assert!((contrast(WHITE, Rgb { r: 0, g: 0, b: 0 }) - 21.0).abs() < 0.01);
    }
}
