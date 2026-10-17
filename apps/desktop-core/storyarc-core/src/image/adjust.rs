//! The reader's adjustments applied to a decoded page (task 2.6 of `desktop-clients`).
//! Mirrored from the readers' `PageAdjustments`: iOS's `ReaderPage` and `Adjusted`, and
//! Android's `PageAdjustments.kt`.
//!
//! The order is iOS's: the border trim, then sharpening, then the colour adjustments, and
//! among those greyscale, brightness, contrast and inversion last, "so the reader's
//! brightness and contrast are what they see rather than their opposites".
//!
//! Two choices the phones leave open, made here and recorded:
//!
//! - **The colour arithmetic is 8-bit sRGB, clamped after each step**, the way a chain of
//!   compositing filters behaves. Greyscale is Rec. 709 luma, Android's `setToSaturation(0)`
//!   to within a thousandth. Brightness adds its value times 255 and contrast scales about
//!   mid-grey, which is what both phones do. (Android applies brightness *after* contrast
//!   and iOS before; this follows iOS, and the difference is recorded for the phones' owners.)
//! - **Sharpening is Android's luminance unsharp mask** (`sharpenedPixel`), because iOS's
//!   `CISharpenLuminance` is a closed kernel and Android's is written down.

use crate::domain::{BorderCrop, BorderInset, ImageAdjustments};

use super::decode::DecodedPage;

/// The edge of the thumbnail the margin is detected on. A margin is uniform by definition,
/// so it survives being scaled down, and reading every pixel of a page is not worth it.
const THUMBNAIL_SIDE: u32 = 256;

/// The page as the reader asked to see it. A neutral adjustment returns an unchanged copy.
pub fn adjusted(page: &DecodedPage, adjustments: &ImageAdjustments) -> DecodedPage {
    let adjustments = adjustments.clamped();
    if adjustments.is_neutral() {
        return page.clone();
    }
    let trimmed = cropped(page, adjustments.crops_borders);
    let sharpened = sharpened(&trimmed, adjustments.sharpness);
    coloured(sharpened, &adjustments)
}

/// The page with its uniform margin trimmed, or an unchanged copy when there is none or the
/// trim is off.
pub fn cropped(page: &DecodedPage, is_enabled: bool) -> DecodedPage {
    if !is_enabled {
        return page.clone();
    }
    let (_, _, scale) = thumbnail_geometry(page);
    let inset = border_inset(page);
    if inset.is_empty() {
        return page.clone();
    }
    // Back up to the page's own scale, as Android does it: whole pixels, never past the page.
    let left = (f64::from(inset.left) * scale) as u32;
    let top = (f64::from(inset.top) * scale) as u32;
    let right = (f64::from(inset.right) * scale) as u32;
    let bottom = (f64::from(inset.bottom) * scale) as u32;
    let width = page.width.saturating_sub(left + right);
    let height = page.height.saturating_sub(top + bottom);
    if width == 0 || height == 0 {
        return page.clone();
    }
    let row_bytes = (page.width * 4) as usize;
    let rgba = (top..top + height)
        .flat_map(|y| {
            let start = y as usize * row_bytes + left as usize * 4;
            page.rgba[start..start + width as usize * 4].iter().copied()
        })
        .collect();
    DecodedPage {
        width,
        height,
        rgba,
    }
}

/// The margin to trim, in pixels of the thumbnail it was found on. [`cropped`] scales it.
pub fn border_inset(page: &DecodedPage) -> BorderInset {
    let (width, height, scale) = thumbnail_geometry(page);
    // Nearest-neighbour sampling of the page at the thumbnail's grid, read as luminance:
    // iOS draws the thumbnail into a grey context, and a margin is grey by definition.
    BorderCrop::inset(width, height, |x, y| {
        let source_x = ((f64::from(x) * scale) as u32).min(page.width - 1);
        let source_y = ((f64::from(y) * scale) as u32).min(page.height - 1);
        let offset = ((source_y * page.width + source_x) * 4) as usize;
        let [r, g, b] = [
            page.rgba[offset],
            page.rgba[offset + 1],
            page.rgba[offset + 2],
        ];
        (0.299 * f64::from(r) + 0.587 * f64::from(g) + 0.114 * f64::from(b)).round() as u8
    })
}

/// The thumbnail's size and the factor from a thumbnail pixel back to a page pixel.
fn thumbnail_geometry(page: &DecodedPage) -> (u32, u32, f64) {
    let longest = page.width.max(page.height);
    if longest <= THUMBNAIL_SIDE || page.width == 0 || page.height == 0 {
        return (page.width, page.height, 1.0);
    }
    let factor = f64::from(THUMBNAIL_SIDE) / f64::from(longest);
    let width = ((f64::from(page.width) * factor) as u32).max(1);
    let height = ((f64::from(page.height) * factor) as u32).max(1);
    (width, height, f64::from(page.width) / f64::from(width))
}

/// Android's luminance unsharp mask: the centre weighted up, its four neighbours down, the
/// result mixed back by `amount`, and each pixel's own channels scaled by how far its
/// luminance moved, so a colour scan gains no fringes.
pub fn sharpened(page: &DecodedPage, amount: f64) -> DecodedPage {
    if amount <= 0.0 || page.width == 0 || page.height == 0 {
        return page.clone();
    }
    let (width, height) = (page.width as usize, page.height as usize);
    let luma: Vec<f64> = page
        .rgba
        .as_chunks::<4>()
        .0
        .iter()
        .map(|pixel| {
            0.299 * f64::from(pixel[0]) + 0.587 * f64::from(pixel[1]) + 0.114 * f64::from(pixel[2])
        })
        .collect();
    let rgba = (0..height)
        .flat_map(|y| (0..width).map(move |x| (x, y)))
        .flat_map(|(x, y)| {
            let at = |x: usize, y: usize| luma[y * width + x];
            let neighbours = at(x.saturating_sub(1), y)
                + at((x + 1).min(width - 1), y)
                + at(x, y.saturating_sub(1))
                + at(x, (y + 1).min(height - 1));
            let here = at(x, y);
            let sharp = here * 5.0 - neighbours;
            let mixed = here + (sharp - here) * amount;
            let ratio = if here > 0.0 {
                (mixed / here).clamp(0.0, 3.0)
            } else {
                1.0
            };
            let offset = (y * width + x) * 4;
            let channel = |c: usize| {
                (f64::from(page.rgba[offset + c]) * ratio)
                    .round()
                    .clamp(0.0, 255.0) as u8
            };
            [channel(0), channel(1), channel(2), page.rgba[offset + 3]]
        })
        .collect();
    DecodedPage {
        width: page.width,
        height: page.height,
        rgba,
    }
}

/// Greyscale, brightness, contrast and inversion, in iOS's order, on every pixel.
fn coloured(page: DecodedPage, adjustments: &ImageAdjustments) -> DecodedPage {
    let factor = adjustments.contrast_factor();
    let offset = adjustments.brightness_offset();
    let has_colour_change =
        adjustments.is_greyscale || offset != 0.0 || factor != 1.0 || adjustments.is_inverted;
    if !has_colour_change {
        return page;
    }
    let step = |value: f64| -> f64 {
        let brightened = (value + offset).clamp(0.0, 1.0);
        let contrasted = ((brightened - 0.5) * factor + 0.5).clamp(0.0, 1.0);
        if adjustments.is_inverted {
            1.0 - contrasted
        } else {
            contrasted
        }
    };
    let to_byte = |value: f64| (value * 255.0).round() as u8;
    let rgba = page
        .rgba
        .as_chunks::<4>()
        .0
        .iter()
        .flat_map(|pixel| {
            let [r, g, b] = [pixel[0], pixel[1], pixel[2]].map(|c| f64::from(c) / 255.0);
            let [r, g, b] = if adjustments.is_greyscale {
                let luma = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
                [luma; 3]
            } else {
                [r, g, b]
            };
            [
                to_byte(step(r)),
                to_byte(step(g)),
                to_byte(step(b)),
                pixel[3],
            ]
        })
        .collect();
    DecodedPage {
        width: page.width,
        height: page.height,
        rgba,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat(width: u32, height: u32, colour: [u8; 4]) -> DecodedPage {
        DecodedPage {
            width,
            height,
            rgba: colour.repeat((width * height) as usize),
        }
    }

    #[test]
    fn alpha_is_never_adjusted() {
        let page = flat(2, 2, [10, 20, 30, 128]);
        let all = ImageAdjustments {
            brightness: 0.3,
            contrast: 0.4,
            sharpness: 1.0,
            is_inverted: true,
            is_greyscale: true,
            crops_borders: true,
        };
        assert!(
            adjusted(&page, &all)
                .rgba
                .as_chunks::<4>()
                .0
                .iter()
                .all(|p| p[3] == 128)
        );
    }

    #[test]
    fn out_of_range_values_are_clamped_before_they_reach_a_pixel() {
        let page = flat(1, 1, [100, 100, 100, 255]);
        let wild = ImageAdjustments {
            brightness: 9.0,
            ..Default::default()
        };
        assert_eq!(adjusted(&page, &wild).rgba, [255, 255, 255, 255]);
    }

    #[test]
    fn a_small_page_is_its_own_thumbnail() {
        assert_eq!(thumbnail_geometry(&flat(100, 200, [0; 4])), (100, 200, 1.0));
        let (w, h, scale) = thumbnail_geometry(&flat(2000, 3000, [0; 4]));
        assert_eq!((w, h), (170, 256));
        assert!((scale - 2000.0 / 170.0).abs() < 1e-9);
    }

    #[test]
    fn an_empty_page_is_left_alone() {
        let empty = DecodedPage {
            width: 0,
            height: 0,
            rgba: Vec::new(),
        };
        assert_eq!(sharpened(&empty, 1.0), empty);
        assert_eq!(cropped(&empty, true), empty);
    }
}
