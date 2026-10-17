//! Page decoding (task 2.5 of `desktop-clients`), asserted the way iOS's `PageDecoderTests`
//! and Android's `PageDecoderInstrumentedTest` assert it: from the shared corpus, against the
//! numbers its manifest records, with the tolerance those suites record.
//!
//! The corpus pages are all PNG, so the other formats are pinned by seven small pages in
//! `tests/images`, each the corpus's flat colour (185, 199, 243) at 48 by 72 pixels, written by
//! ffmpeg, cwebp and macOS `sips`. Lossless files decode to the colour exactly. Lossy ones
//! decode to a colour their encoder chose, and their digest pins that the decoder gives the
//! same answer on every desktop: the CI runners are the three systems, and this file runs on
//! each of them.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use corpus::manifest;
use sha2::{Digest, Sha256};
use storyarc_core::formats::{ComicArchive, PageCodec};
use storyarc_core::image::{self, DecodedPage, PageDecodeError, PageSize};

/// The corpus's flat page colour, `large-page.cbz`'s `expectedPagePixel`.
const PAGE_COLOUR: [u8; 3] = [185, 199, 243];

fn test_image(name: &str) -> Vec<u8> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/images")
        .join(name);
    std::fs::read(&path).unwrap_or_else(|error| panic!("{}: {error}", path.display()))
}

fn first_page(archive: &str) -> Vec<u8> {
    let opened = ComicArchive::open_file(manifest::path(&format!("comics/{archive}"))).unwrap();
    opened.data(&opened.pages()[0]).unwrap()
}

fn centre(page: &DecodedPage) -> [u8; 4] {
    let (x, y) = (page.width / 2, page.height / 2);
    let offset = ((y * page.width + x) * 4) as usize;
    page.rgba[offset..offset + 4].try_into().unwrap()
}

fn within(actual: [u8; 4], expected: [u8; 3], tolerance: u8) -> bool {
    (0..3).all(|channel| actual[channel].abs_diff(expected[channel]) <= tolerance)
}

fn digest(page: &DecodedPage) -> String {
    let mut hasher = Sha256::new();
    hasher.update(page.width.to_le_bytes());
    hasher.update(page.height.to_le_bytes());
    hasher.update(&page.rgba);
    hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

mod corpus_pages {
    use super::*;

    #[test]
    fn dimensions_come_from_the_header() {
        let fixture = manifest::comic("comics/large-page.cbz");
        let pinned = fixture.page_dimensions.as_ref().unwrap();
        assert_eq!(
            image::dimensions(&first_page("large-page.cbz")).unwrap(),
            PageSize {
                width: pinned[0],
                height: pinned[1]
            }
        );
    }

    #[test]
    fn a_full_decode_carries_the_exact_pixels_the_fixture_drew() {
        let fixture = manifest::comic("comics/large-page.cbz");
        let expected = fixture.expected_page_pixel.as_ref().unwrap();
        let page = image::decode(&first_page("large-page.cbz"), None).unwrap();
        assert_eq!((page.width, page.height), (2000, 3000));
        assert_eq!(page.rgba.len(), 2000 * 3000 * 4);
        let [r, g, b, a] = centre(&page);
        assert_eq!(
            [r as i64, g as i64, b as i64],
            [expected[0], expected[1], expected[2]]
        );
        assert_eq!(a, 255);
    }

    #[test]
    fn downsampling_bounds_the_longest_edge_and_keeps_the_colour_within_one_step() {
        let page = image::decode(&first_page("large-page.cbz"), Some(600)).unwrap();
        assert_eq!((page.width, page.height), (400, 600));
        // The recorded tolerance of both phones: one step per channel at a 5:1 reduction.
        assert!(within(centre(&page), PAGE_COLOUR, 1), "{:?}", centre(&page));
    }

    #[test]
    fn asking_for_more_than_the_page_has_does_not_upscale() {
        let page = image::decode(&first_page("large-page.cbz"), Some(9000)).unwrap();
        assert_eq!((page.width, page.height), (2000, 3000));
    }

    #[test]
    fn a_tiny_page_still_decodes() {
        let data = first_page("natural-sort.cbz");
        assert_eq!(
            image::dimensions(&data).unwrap(),
            PageSize {
                width: 2,
                height: 3
            }
        );
        assert_eq!(image::decode(&data, None).unwrap().width, 2);
    }

    #[test]
    fn a_double_page_spread_is_detected_from_its_aspect_ratio() {
        let fixture = manifest::comic("comics/double-page-spread.cbz");
        let opened = ComicArchive::open_file(manifest::path(&fixture.file)).unwrap();
        let verdicts: Vec<usize> = opened
            .pages()
            .iter()
            .enumerate()
            .filter(|(_, page)| {
                image::is_spread(image::dimensions(&opened.data(page).unwrap()).unwrap())
            })
            .map(|(index, _)| index)
            .collect();
        assert_eq!(&verdicts, fixture.spread_indices.as_ref().unwrap());
    }

    #[test]
    fn a_merely_slightly_wide_page_is_not_a_spread() {
        let size = |width, height| PageSize { width, height };
        assert!(!image::is_spread(size(110, 100)));
        assert!(image::is_spread(size(120, 100)));
        assert!(image::is_spread(size(200, 100)));
        assert!(!image::is_spread(size(100, 0)));
    }

    #[test]
    fn a_page_in_a_codec_nothing_decodes_is_refused_by_name() {
        let fixture = manifest::comic("comics/unsupported-codec.cbz");
        let opened = ComicArchive::open_file(manifest::path(&fixture.file)).unwrap();
        let jxl = opened
            .pages()
            .iter()
            .find(|page| page.path.ends_with(".jxl"))
            .unwrap();
        let error = image::decode(&opened.data(jxl).unwrap(), None).unwrap_err();
        assert_eq!(error, PageDecodeError::Unsupported(PageCodec::JpegXl));
        assert_eq!(
            Some(error.codec_name().unwrap()),
            fixture.expected_undecodable_codec.as_deref()
        );
        assert!(error.to_string().contains("JPEG XL"), "{error}");
    }

    /// Every page of every CBZ and CBT in the corpus, decoded and digested. RAR is left out:
    /// on Windows the core reads no compressed RAR page until task 1.7, and a digest table
    /// that differs by system would hide the thing it exists to catch.
    #[test]
    fn the_corpus_decodes_to_the_same_digests_on_every_desktop() {
        let pinned: &[(&str, &str)] = &CORPUS_DIGESTS;
        let mut actual = Vec::new();
        for fixture in &manifest::manifest().comics {
            if !(fixture.file.ends_with(".cbz") || fixture.file.ends_with(".cbt")) {
                continue;
            }
            let Ok(opened) = ComicArchive::open_file(manifest::path(&fixture.file)) else {
                continue;
            };
            let mut hasher = Sha256::new();
            for page in opened.pages() {
                let outcome = opened
                    .data(page)
                    .map_err(|error| error.to_string())
                    .and_then(|data| image::decode(&data, None).map_err(|e| e.to_string()));
                match outcome {
                    Ok(decoded) => hasher.update(digest(&decoded)),
                    Err(reason) => hasher.update(reason),
                }
            }
            let combined: String = hasher
                .finalize()
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect();
            actual.push((fixture.file.clone(), combined[..16].to_owned()));
        }
        let actual: Vec<(&str, &str)> = actual
            .iter()
            .map(|(file, digest)| (file.as_str(), digest.as_str()))
            .collect();
        assert_eq!(actual, pinned, "{actual:#?}");
    }

    /// The first sixteen hex digits of each archive's combined page digest.
    /// Archives holding the same pages share a digest, which is itself a check.
    const CORPUS_DIGESTS: [(&str, &str); 17] = [
        ("comics/natural-sort.cbz", "8e4e863277b174ea"),
        ("comics/nested-chapters.cbz", "0fa918f506bfedcc"),
        ("comics/non-image-entries.cbz", "cad96c155b676abd"),
        ("comics/single-page.cbz", "dd1678abb5fef969"),
        ("comics/double-page-spread.cbz", "6058f14d36767685"),
        ("comics/stored-entries.cbz", "7e0463497eefff94"),
        ("comics/zip64.cbz", "7e0463497eefff94"),
        ("comics/archive-comment.cbz", "7e0463497eefff94"),
        ("comics/data-descriptor.cbz", "7e0463497eefff94"),
        ("comics/large-page.cbz", "bcd9e9df80bb7865"),
        ("comics/truncated.cbz", "0aa8423ea4746d08"),
        ("comics/no-pages.cbz", "e3b0c44298fc1c14"),
        ("comics/unsupported-codec.cbz", "50939e428b60d8b6"),
        ("comics/tar-store.cbt", "7e0463497eefff94"),
        ("comics/tar-nested-chapters.cbt", "7e0463497eefff94"),
        ("comics/manga-metadata.cbz", "5b8ef6ff6e17b3fc"),
        ("comics/japanese-no-direction.cbz", "dd1678abb5fef969"),
    ];
}

mod formats {
    use super::*;

    fn decodes_to(name: &str, codec: PageCodec, tolerance: u8) -> DecodedPage {
        let data = test_image(name);
        assert_eq!(PageCodec::of(&data), Some(codec), "{name}");
        assert_eq!(
            image::dimensions(&data).unwrap(),
            PageSize {
                width: 48,
                height: 72
            },
            "{name}"
        );
        let page = image::decode(&data, None).unwrap_or_else(|error| panic!("{name}: {error}"));
        assert_eq!((page.width, page.height), (48, 72), "{name}");
        assert_eq!(page.rgba.len(), 48 * 72 * 4, "{name}");
        assert!(
            within(centre(&page), PAGE_COLOUR, tolerance),
            "{name}: {:?}",
            centre(&page)
        );
        page
    }

    #[test]
    fn png_gif_and_lossless_webp_decode_exactly() {
        for (name, codec) in [
            ("page.png", PageCodec::Png),
            ("page.gif", PageCodec::Gif),
            ("page-lossless.webp", PageCodec::Webp),
        ] {
            decodes_to(name, codec, 0);
        }
    }

    /// Lossy encoders move a flat colour by a few steps when they subsample its chroma.
    /// That is the encoder's choice, made once when the file was written; the digests below
    /// are what pin the decoder.
    #[test]
    fn jpeg_and_lossy_webp_decode_near_the_colour_they_were_written_from() {
        decodes_to("page.jpg", PageCodec::Jpeg, 4);
        decodes_to("page.webp", PageCodec::Webp, 4);
    }

    #[cfg(feature = "heic")]
    #[test]
    fn heic_decodes_with_the_core_s_own_decoder() {
        decodes_to("page.heic", PageCodec::Heic, 4);
    }

    #[cfg(not(feature = "heic"))]
    #[test]
    fn heic_without_its_decoder_is_refused_by_name() {
        let error = image::decode(&test_image("page.heic"), None).unwrap_err();
        assert_eq!(error, PageDecodeError::Unsupported(PageCodec::Heic));
        assert!(error.to_string().contains("HEIC"), "{error}");
    }

    #[cfg(feature = "avif")]
    #[test]
    fn avif_decodes_through_dav1d() {
        decodes_to("page.avif", PageCodec::Avif, 4);
    }

    #[cfg(not(feature = "avif"))]
    #[test]
    fn avif_without_its_decoder_is_refused_by_name() {
        let data = test_image("page.avif");
        for error in [
            image::decode(&data, None).unwrap_err(),
            image::dimensions(&data).unwrap_err(),
        ] {
            assert_eq!(error, PageDecodeError::Unsupported(PageCodec::Avif));
            assert_eq!(error.codec_name(), Some("AVIF"));
            assert!(error.to_string().contains("AVIF"), "{error}");
        }
    }

    #[test]
    fn decoded_pages_have_the_same_digest_on_every_desktop() {
        let mut names = vec![
            "page.png",
            "page.gif",
            "page-lossless.webp",
            "page.jpg",
            "page.webp",
        ];
        if cfg!(feature = "heic") {
            names.push("page.heic");
        }
        if cfg!(feature = "avif") {
            names.push("page.avif");
        }
        let actual: Vec<(&str, String)> = names
            .into_iter()
            .map(|name| {
                let page = image::decode(&test_image(name), None).unwrap();
                (name, digest(&page)[..16].to_owned())
            })
            .collect();
        for (name, digest) in &actual {
            let pinned = FORMAT_DIGESTS
                .iter()
                .find(|(pinned_name, _)| pinned_name == name)
                .map(|(_, digest)| *digest);
            assert_eq!(pinned, Some(digest.as_str()), "{name}: {actual:#?}");
        }
    }

    /// The first sixteen hex digits of each test page's decoded digest.
    /// PNG, GIF and lossless WebP hold the same pixels, so they share one.
    const FORMAT_DIGESTS: [(&str, &str); 7] = [
        ("page.png", "f0641fedc2dab857"),
        ("page.gif", "f0641fedc2dab857"),
        ("page-lossless.webp", "f0641fedc2dab857"),
        ("page.jpg", "1f83479c13a1f6d3"),
        ("page.webp", "a240887109653d5e"),
        ("page.heic", "55e4e5f29d454a28"),
        ("page.avif", "1f83479c13a1f6d3"),
    ];

    #[test]
    fn bytes_that_are_not_an_image_are_reported_not_crashed_on() {
        let junk = b"this is not a picture";
        assert_eq!(
            image::dimensions(junk).unwrap_err(),
            PageDecodeError::Unrecognised
        );
        assert_eq!(
            image::decode(junk, None).unwrap_err(),
            PageDecodeError::Unrecognised
        );
        assert_eq!(PageDecodeError::Unrecognised.codec_name(), None);
    }

    #[test]
    fn a_truncated_page_names_its_codec_and_says_it_is_damaged() {
        let mut data = test_image("page.jpg");
        data.truncate(data.len() / 2);
        let error = image::decode(&data, None).unwrap_err();
        assert!(
            matches!(
                error,
                PageDecodeError::Failed {
                    codec: PageCodec::Jpeg,
                    ..
                }
            ),
            "{error:?}"
        );
        assert!(error.to_string().contains("JPEG"), "{error}");
    }

    #[test]
    fn a_header_claiming_a_page_too_large_to_hold_is_refused_before_decoding() {
        // A PNG header for 30,000 by 30,000 pixels, and an empty image chunk after it.
        let mut png = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        let mut header = 30_000u32.to_be_bytes().to_vec();
        header.extend_from_slice(&30_000u32.to_be_bytes());
        header.extend_from_slice(&[8, 6, 0, 0, 0]);
        for (kind, body) in [(b"IHDR", header), (b"IDAT", Vec::new())] {
            let mut chunk = kind.to_vec();
            chunk.extend_from_slice(&body);
            png.extend_from_slice(&(body.len() as u32).to_be_bytes());
            png.extend_from_slice(&chunk);
            png.extend_from_slice(&crc32(&chunk).to_be_bytes());
        }
        assert_eq!(
            image::dimensions(&png).unwrap(),
            PageSize {
                width: 30_000,
                height: 30_000
            }
        );
        let error = image::decode(&png, None).unwrap_err();
        assert!(
            matches!(
                error,
                PageDecodeError::TooLarge {
                    codec: PageCodec::Png,
                    ..
                }
            ),
            "{error:?}"
        );
    }

    fn crc32(bytes: &[u8]) -> u32 {
        let mut crc = 0xFFFF_FFFFu32;
        for byte in bytes {
            crc ^= u32::from(*byte);
            for _ in 0..8 {
                crc = if crc & 1 == 1 {
                    (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >> 1
                };
            }
        }
        !crc
    }
}
