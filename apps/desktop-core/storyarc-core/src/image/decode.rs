//! Decoding a page's bytes into RGBA pixels. Mirrored from `PageDecoder.swift`.
//!
//! The codec is read from the bytes by [`PageCodec`], never from the entry's name, and each
//! codec goes to one decoder: the `image` crate for JPEG, PNG, WebP and GIF, `zune-heic` for
//! HEIC (the `heic` feature, on by default), and `image` over dav1d for AVIF (the `avif`
//! feature, off by default because it needs the libdav1d system library). A codec with no
//! decoder in this build is refused by name, which is what the reader's placeholder shows.
//!
//! The size is read from the header first and a page over [`MAX_PAGE_PIXELS`] is refused
//! before anything is allocated: a page is untrusted input, and a header claiming 30,000 by
//! 30,000 pixels would otherwise cost 3.6 GB before the decoder found out it was lying.

use std::fmt;
use std::io::Cursor;

use ::image::imageops::FilterType;
use ::image::{
    DynamicImage, GrayAlphaImage, GrayImage, ImageDecoder, ImageError, ImageFormat, ImageReader,
    Limits, RgbImage, RgbaImage,
};
use serde::Serialize;

use crate::formats::PageCodec;

/// The most pixels a page may have: 100 million, 400 MB once decoded to RGBA. A
/// 600 dpi scan of a tabloid page is about 70 million.
pub const MAX_PAGE_PIXELS: u64 = 100_000_000;

/// The longest edge a decoder is allowed to read. Wider than any page; narrower than what
/// a crafted header can claim.
const MAX_EDGE: u32 = 30_000;

/// How much wider than tall a page must be to count as a double-page spread. iOS's
/// `PageDecoder.isSpread` default, deliberately generous: a page that is merely a little
/// wide is not a spread, and guessing wrong is worse than not guessing.
pub const SPREAD_THRESHOLD: f64 = 1.2;

/// A page's size in pixels.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct PageSize {
    pub width: u32,
    pub height: u32,
}

/// A decoded page: 8-bit RGBA, not premultiplied, rows top to bottom with no padding, so
/// `rgba.len() == width * height * 4`.
#[derive(Clone, PartialEq, Eq)]
pub struct DecodedPage {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

impl fmt::Debug for DecodedPage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DecodedPage")
            .field("width", &self.width)
            .field("height", &self.height)
            .field("bytes", &self.rgba.len())
            .finish()
    }
}

impl DecodedPage {
    pub fn size(&self) -> PageSize {
        PageSize {
            width: self.width,
            height: self.height,
        }
    }

    fn from_image(image: DynamicImage) -> Self {
        let rgba = image.into_rgba8();
        Self {
            width: rgba.width(),
            height: rgba.height(),
            rgba: rgba.into_raw(),
        }
    }
}

/// Why a page could not be decoded. Each case names what the reader is told.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PageDecodeError {
    /// The bytes are not an image any decoder recognises.
    Unrecognised,
    /// An image in a codec this build has no decoder for: JPEG XL, BMP and TIFF always, HEIC
    /// and AVIF when their feature is off.
    Unsupported(PageCodec),
    /// Recognised, and the decode failed: a truncated or damaged page, usually.
    Failed { codec: PageCodec, detail: String },
    /// The header claims more pixels than [`MAX_PAGE_PIXELS`].
    TooLarge {
        codec: PageCodec,
        width: u32,
        height: u32,
    },
}

impl PageDecodeError {
    /// The codec the page is in, as the reader is told it, when the bytes say.
    pub fn codec_name(&self) -> Option<&'static str> {
        match self {
            Self::Unrecognised => None,
            Self::Unsupported(codec)
            | Self::Failed { codec, .. }
            | Self::TooLarge { codec, .. } => Some(codec.display_name()),
        }
    }
}

impl fmt::Display for PageDecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unrecognised => f.write_str("the page is not an image"),
            Self::Unsupported(codec) => write!(
                f,
                "{} pages cannot be decoded on this system",
                codec.display_name()
            ),
            Self::Failed { codec, detail } => {
                write!(f, "the {} page is damaged: {detail}", codec.display_name())
            }
            Self::TooLarge {
                codec,
                width,
                height,
            } => write!(
                f,
                "the {} page is {width} by {height} pixels, too large to show",
                codec.display_name()
            ),
        }
    }
}

impl std::error::Error for PageDecodeError {}

/// Whether this build decodes pages in `codec`.
pub fn can_decode(codec: PageCodec) -> bool {
    match codec {
        PageCodec::Jpeg | PageCodec::Png | PageCodec::Gif | PageCodec::Webp => true,
        PageCodec::Heic => cfg!(feature = "heic"),
        PageCodec::Avif => cfg!(feature = "avif"),
        PageCodec::JpegXl | PageCodec::Bmp | PageCodec::Tiff => false,
    }
}

/// A page's size, read from its header without decoding the pixels. Cheap enough to call
/// while laying out a whole publication's spreads.
pub fn dimensions(data: &[u8]) -> Result<PageSize, PageDecodeError> {
    let codec = supported_codec(data)?;
    let (width, height) = match codec {
        PageCodec::Heic => heic::dimensions(data)?,
        _ => reader(data, codec)?
            .into_dimensions()
            .map_err(|error| failure(codec, error))?,
    };
    Ok(PageSize { width, height })
}

/// Decodes a page, at most `max_pixel_size` on its longest edge and never larger than it
/// is. Passing what the display needs rather than `None` is the difference between a 2000
/// by 3000 page costing 24 MB and costing what it is shown at.
///
/// The orientation a JPEG or HEIC declares is applied, so the page arrives upright.
pub fn decode(data: &[u8], max_pixel_size: Option<u32>) -> Result<DecodedPage, PageDecodeError> {
    let codec = supported_codec(data)?;
    let size = dimensions(data)?;
    if u64::from(size.width) * u64::from(size.height) > MAX_PAGE_PIXELS {
        return Err(PageDecodeError::TooLarge {
            codec,
            width: size.width,
            height: size.height,
        });
    }
    let image = match codec {
        PageCodec::Heic => heic::decode(data)?,
        _ => decode_with_image(data, codec)?,
    };
    Ok(DecodedPage::from_image(downsampled(image, max_pixel_size)))
}

/// Whether a page is a double-page spread, by iOS's threshold.
pub fn is_spread(size: PageSize) -> bool {
    is_spread_at(size, SPREAD_THRESHOLD)
}

/// Whether a page is at least `threshold` times wider than tall. A page with no height is
/// not a spread.
pub fn is_spread_at(size: PageSize, threshold: f64) -> bool {
    size.height > 0 && f64::from(size.width) / f64::from(size.height) >= threshold
}

/// The codec the bytes are in, refused unless this build decodes it.
fn supported_codec(data: &[u8]) -> Result<PageCodec, PageDecodeError> {
    let codec = PageCodec::of(data).ok_or(PageDecodeError::Unrecognised)?;
    if can_decode(codec) {
        Ok(codec)
    } else {
        Err(PageDecodeError::Unsupported(codec))
    }
}

fn image_format(codec: PageCodec) -> Option<ImageFormat> {
    match codec {
        PageCodec::Jpeg => Some(ImageFormat::Jpeg),
        PageCodec::Png => Some(ImageFormat::Png),
        PageCodec::Gif => Some(ImageFormat::Gif),
        PageCodec::Webp => Some(ImageFormat::WebP),
        PageCodec::Avif => Some(ImageFormat::Avif),
        PageCodec::Heic | PageCodec::JpegXl | PageCodec::Bmp | PageCodec::Tiff => None,
    }
}

fn reader(data: &[u8], codec: PageCodec) -> Result<ImageReader<Cursor<&[u8]>>, PageDecodeError> {
    let format = image_format(codec).ok_or(PageDecodeError::Unsupported(codec))?;
    let mut reader = ImageReader::with_format(Cursor::new(data), format);
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_EDGE);
    limits.max_image_height = Some(MAX_EDGE);
    // RGBA of the largest page allowed, plus the decoder's own working set.
    limits.max_alloc = Some(MAX_PAGE_PIXELS * 4 + 64 * 1024 * 1024);
    reader.limits(limits);
    Ok(reader)
}

fn decode_with_image(data: &[u8], codec: PageCodec) -> Result<DynamicImage, PageDecodeError> {
    let mut decoder = reader(data, codec)?
        .into_decoder()
        .map_err(|error| failure(codec, error))?;
    let orientation = decoder
        .orientation()
        .map_err(|error| failure(codec, error))?;
    let mut image = DynamicImage::from_decoder(decoder).map_err(|error| failure(codec, error))?;
    image.apply_orientation(orientation);
    Ok(image)
}

fn failure(codec: PageCodec, error: ImageError) -> PageDecodeError {
    match error {
        ImageError::Unsupported(_) => PageDecodeError::Unsupported(codec),
        ImageError::Limits(_) => PageDecodeError::TooLarge {
            codec,
            width: 0,
            height: 0,
        },
        other => PageDecodeError::Failed {
            codec,
            detail: other.to_string(),
        },
    }
}

/// The page scaled so its longest edge is at most `max`, never enlarged. Rounded the way
/// ImageIO's thumbnail rounds: 2000 by 3000 at 600 is 400 by 600.
fn downsampled(image: DynamicImage, max: Option<u32>) -> DynamicImage {
    let (width, height) = (image.width(), image.height());
    let longest = width.max(height);
    let Some(max) = max.filter(|max| *max > 0 && *max < longest) else {
        return image;
    };
    let scale = f64::from(max) / f64::from(longest);
    let scaled = |edge: u32| ((f64::from(edge) * scale).round() as u32).clamp(1, max);
    image.resize_exact(scaled(width), scaled(height), FilterType::Triangle)
}

/// Builds an image from interleaved 8-bit samples in `channels` channels per pixel. Only the
/// HEIC decoder hands over raw samples.
#[cfg_attr(not(feature = "heic"), allow(dead_code))]
fn from_samples(width: u32, height: u32, channels: usize, pixels: Vec<u8>) -> Option<DynamicImage> {
    match channels {
        1 => GrayImage::from_raw(width, height, pixels).map(DynamicImage::ImageLuma8),
        2 => GrayAlphaImage::from_raw(width, height, pixels).map(DynamicImage::ImageLumaA8),
        3 => RgbImage::from_raw(width, height, pixels).map(DynamicImage::ImageRgb8),
        4 => RgbaImage::from_raw(width, height, pixels).map(DynamicImage::ImageRgba8),
        _ => None,
    }
}

#[cfg(feature = "heic")]
mod heic {
    //! HEIC through `zune-heic`, with Apple's hardware decoder off so a Mac decodes a page
    //! exactly as Windows and Linux do.

    use ::image::DynamicImage;
    use zune_heic::HeifDecoder;
    use zune_heic::zune_core::bytestream::ZCursor;
    use zune_heic::zune_core::colorspace::ColorSpace;
    use zune_heic::zune_core::options::DecoderOptions;

    use super::{MAX_EDGE, PageCodec, PageDecodeError, from_samples};

    fn decoder(data: &[u8]) -> HeifDecoder<ZCursor<&[u8]>> {
        let options = DecoderOptions::default()
            .hvec_set_use_videotoolbox(false)
            .set_max_width(MAX_EDGE as usize)
            .set_max_height(MAX_EDGE as usize);
        HeifDecoder::new_with_options(ZCursor::new(data), options)
    }

    fn failed(detail: impl ToString) -> PageDecodeError {
        PageDecodeError::Failed {
            codec: PageCodec::Heic,
            detail: detail.to_string(),
        }
    }

    fn size(decoder: &HeifDecoder<ZCursor<&[u8]>>) -> Result<(u32, u32), PageDecodeError> {
        let width = decoder.width().ok_or_else(|| failed("no width"))?;
        let height = decoder.height().ok_or_else(|| failed("no height"))?;
        Ok((
            u32::try_from(width).map_err(failed)?,
            u32::try_from(height).map_err(failed)?,
        ))
    }

    pub(super) fn dimensions(data: &[u8]) -> Result<(u32, u32), PageDecodeError> {
        let mut decoder = decoder(data);
        decoder
            .decode_headers()
            .map_err(|e| failed(format!("{e:?}")))?;
        size(&decoder)
    }

    pub(super) fn decode(data: &[u8]) -> Result<DynamicImage, PageDecodeError> {
        let mut decoder = decoder(data);
        let pixels = decoder.decode().map_err(|e| failed(format!("{e:?}")))?;
        let (width, height) = size(&decoder)?;
        let channels = match decoder.colorspace() {
            Some(ColorSpace::Luma) => 1,
            Some(ColorSpace::LumaA) => 2,
            Some(ColorSpace::RGB) => 3,
            Some(ColorSpace::RGBA) => 4,
            other => return Err(failed(format!("colour space {other:?}"))),
        };
        from_samples(width, height, channels, pixels)
            .ok_or_else(|| failed("the decoder returned the wrong number of samples"))
    }
}

#[cfg(not(feature = "heic"))]
mod heic {
    use ::image::DynamicImage;

    use super::{PageCodec, PageDecodeError};

    pub(super) fn dimensions(_: &[u8]) -> Result<(u32, u32), PageDecodeError> {
        Err(PageDecodeError::Unsupported(PageCodec::Heic))
    }

    pub(super) fn decode(_: &[u8]) -> Result<DynamicImage, PageDecodeError> {
        Err(PageDecodeError::Unsupported(PageCodec::Heic))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_codec_is_either_decoded_or_refused_by_name() {
        for codec in [
            PageCodec::Jpeg,
            PageCodec::Png,
            PageCodec::Gif,
            PageCodec::Webp,
            PageCodec::Avif,
            PageCodec::Heic,
            PageCodec::JpegXl,
            PageCodec::Bmp,
            PageCodec::Tiff,
        ] {
            let error = PageDecodeError::Unsupported(codec);
            assert!(error.to_string().contains(codec.display_name()));
        }
        assert!(can_decode(PageCodec::Jpeg));
        assert!(!can_decode(PageCodec::JpegXl));
        assert_eq!(can_decode(PageCodec::Heic), cfg!(feature = "heic"));
        assert_eq!(can_decode(PageCodec::Avif), cfg!(feature = "avif"));
    }

    #[test]
    fn downsampling_rounds_like_image_io_and_never_enlarges() {
        let page = DynamicImage::new_rgba8(2000, 3000);
        let small = downsampled(page.clone(), Some(600));
        assert_eq!((small.width(), small.height()), (400, 600));
        let same = downsampled(page.clone(), Some(3000));
        assert_eq!((same.width(), same.height()), (2000, 3000));
        let zero = downsampled(page, Some(0));
        assert_eq!(zero.width(), 2000);
        let sliver = downsampled(DynamicImage::new_rgba8(5000, 2), Some(100));
        assert_eq!((sliver.width(), sliver.height()), (100, 1));
    }

    #[test]
    fn samples_in_an_unexpected_layout_are_refused() {
        assert!(from_samples(2, 2, 3, vec![0; 12]).is_some());
        assert!(from_samples(2, 2, 3, vec![0; 11]).is_none());
        assert!(from_samples(2, 2, 5, vec![0; 20]).is_none());
    }
}
