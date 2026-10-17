//! Image adjustments over decoded pages (task 2.6 of `desktop-clients`), against the corpus.
//!
//! The phones apply adjustments while drawing (SwiftUI modifiers on iOS, a colour matrix on
//! Android) and record no adjusted pixels, so the expectation here is iOS's arithmetic worked
//! by hand on `large-page.cbz`'s flat colour (185, 199, 243), within the one step per
//! channel the phones' decoder tests allow: greyscale by Rec. 709 luma, then brightness as an
//! offset, then contrast about mid-grey, then inversion last.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use corpus::manifest;
use storyarc_core::domain::ImageAdjustments;
use storyarc_core::formats::ComicArchive;
use storyarc_core::image::{self, DecodedPage};

fn large_page() -> DecodedPage {
    let opened = ComicArchive::open_file(manifest::path("comics/large-page.cbz")).unwrap();
    let data = opened.data(&opened.pages()[0]).unwrap();
    // Downsampled, as the reader draws it: the arithmetic is per pixel either way.
    image::decode(&data, Some(300)).unwrap()
}

fn centre(page: &DecodedPage) -> [u8; 4] {
    let offset = (((page.height / 2) * page.width + page.width / 2) * 4) as usize;
    page.rgba[offset..offset + 4].try_into().unwrap()
}

fn assert_near(page: &DecodedPage, expected: [u8; 3], what: &str) {
    let actual = centre(page);
    for channel in 0..3 {
        assert!(
            actual[channel].abs_diff(expected[channel]) <= 1,
            "{what}: {actual:?} is not within one step of {expected:?}"
        );
    }
    assert_eq!(actual[3], 255, "{what}: alpha moved");
}

fn with(adjust: impl FnOnce(&mut ImageAdjustments)) -> ImageAdjustments {
    let mut adjustments = ImageAdjustments::default();
    adjust(&mut adjustments);
    adjustments
}

#[test]
fn neutral_adjustments_leave_the_page_alone() {
    let page = large_page();
    assert_eq!(image::adjusted(&page, &ImageAdjustments::default()), page);
}

#[test]
fn each_adjustment_matches_the_ios_arithmetic_within_one_step() {
    let page = large_page();
    let cases: [(&str, ImageAdjustments, [u8; 3]); 6] = [
        (
            "greyscale",
            with(|a| a.is_greyscale = true),
            [199, 199, 199],
        ),
        (
            "brightness +0.1",
            with(|a| a.brightness = 0.1),
            [211, 225, 255],
        ),
        (
            "brightness -0.5",
            with(|a| a.brightness = -0.5),
            [58, 72, 116],
        ),
        ("contrast +0.5", with(|a| a.contrast = 0.5), [214, 235, 255]),
        ("contrast -1", with(|a| a.contrast = -1.0), [128, 128, 128]),
        ("inverted", with(|a| a.is_inverted = true), [70, 56, 12]),
    ];
    for (what, adjustments, expected) in cases {
        assert_near(&image::adjusted(&page, &adjustments), expected, what);
    }
}

#[test]
fn inversion_comes_last_so_a_brightened_page_is_not_sent_darker() {
    let page = large_page();
    // Brightened by 0.1 then inverted: 255 - 210.5, not (255 - 185) + 25.5.
    let adjustments = with(|a| {
        a.brightness = 0.1;
        a.is_inverted = true;
    });
    assert_near(
        &image::adjusted(&page, &adjustments),
        [44, 30, 0],
        "brightened then inverted",
    );
    // And every step together: grey 199.2, plus 25.5, contrast 1.5 about the middle, which
    // is past white, then inverted to black.
    let everything = with(|a| {
        a.is_greyscale = true;
        a.brightness = 0.1;
        a.contrast = 0.5;
        a.is_inverted = true;
    });
    assert_near(&image::adjusted(&page, &everything), [0, 0, 0], "all four");
}

#[test]
fn sharpening_leaves_a_flat_page_flat_and_lifts_an_edge() {
    let page = large_page();
    let sharpened = image::adjusted(&page, &with(|a| a.sharpness = 1.0));
    assert_near(&sharpened, [185, 199, 243], "a flat page sharpened");

    // A grey step: the dark side of the edge goes darker, the light side lighter.
    let (width, height) = (8u32, 4u32);
    let rgba: Vec<u8> = (0..height)
        .flat_map(|_| {
            (0..width).flat_map(|x| {
                if x < 4 {
                    [80, 80, 80, 255]
                } else {
                    [160, 160, 160, 255]
                }
            })
        })
        .collect();
    let step = DecodedPage {
        width,
        height,
        rgba,
    };
    let out = image::adjusted(&step, &with(|a| a.sharpness = 1.0));
    let at = |x: u32| out.rgba[((width + x) * 4) as usize];
    assert!(at(3) < 80, "the dark side of the edge: {}", at(3));
    assert!(at(4) > 160, "the light side of the edge: {}", at(4));
    assert_eq!(at(0), 80, "away from the edge nothing moves");
}

#[test]
fn a_white_margin_is_trimmed_and_the_trim_can_be_excused() {
    // 300 by 400 with a 30 pixel white margin around the corpus's colour.
    let (width, height, margin) = (300u32, 400u32, 30u32);
    let rgba: Vec<u8> = (0..height)
        .flat_map(|y| {
            (0..width).flat_map(move |x| {
                let inside =
                    x >= margin && y >= margin && x < width - margin && y < height - margin;
                if inside {
                    [185, 199, 243, 255]
                } else {
                    [255, 255, 255, 255]
                }
            })
        })
        .collect();
    let page = DecodedPage {
        width,
        height,
        rgba,
    };
    let crops = with(|a| a.crops_borders = true);
    let trimmed = image::adjusted(&page, &crops);
    // Detected on a thumbnail of at most 256 pixels, so the trim lands within the scale step.
    assert!(
        trimmed.width.abs_diff(width - 2 * margin) <= 2,
        "{} wide",
        trimmed.width
    );
    assert!(
        trimmed.height.abs_diff(height - 2 * margin) <= 2,
        "{} tall",
        trimmed.height
    );
    assert_eq!(
        trimmed.rgba.len(),
        (trimmed.width * trimmed.height * 4) as usize
    );
    assert_near(&trimmed, [185, 199, 243], "the artwork inside the trim");
    let excused = image::adjusted(&page, &crops.trimming_borders(false));
    assert_eq!((excused.width, excused.height), (width, height));
    // The corpus's own page has no margin and keeps its size.
    let plain = large_page();
    let kept = image::adjusted(&plain, &crops);
    assert_eq!((kept.width, kept.height), (plain.width, plain.height));
}
