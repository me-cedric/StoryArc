//! The zoom of one page in a reader window, as a multiple of its fit.
//!
//! `desktop-experience`, Zoom and pan with a pointer. Every input (pinch, Control and the
//! wheel, a double click, the keys) lands on the one number, so Fit Page and a double
//! click agree. The limits are the iOS zoom model's: a ceiling of 6 and a double-tap level
//! of 2.5 times the fit, copied until parent task 5.12 shares them.

use crate::settings::Fit;

/// A width and a height in logical pixels.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Size {
    pub width: f64,
    pub height: f64,
}

impl Size {
    pub const ZERO: Self = Self {
        width: 0.0,
        height: 0.0,
    };

    pub fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ZoomModel {
    /// Multiple of the fit. 1 is the page fitted to the viewport.
    scale: f64,
    /// How far the zoomed page is panned from centred, in logical pixels.
    offset: Size,
}

impl Default for ZoomModel {
    fn default() -> Self {
        Self {
            scale: 1.0,
            offset: Size::ZERO,
        }
    }
}

impl ZoomModel {
    pub const CEILING: f64 = 6.0;
    pub const DOUBLE_CLICK_FACTOR: f64 = 2.5;
    /// One menu or key step. Eight steps from fit reach the ceiling.
    pub const KEY_STEP: f64 = 1.25;
    /// How much one wheel notch zooms with Control held.
    pub const WHEEL_STEP: f64 = 1.1;
    /// Past-fit tolerance, so rounding never reads as zoomed.
    pub const FIT_TOLERANCE: f64 = 1.01;

    pub fn scale(&self) -> f64 {
        self.scale
    }

    pub fn offset(&self) -> Size {
        self.offset
    }

    pub fn is_zoomed(&self) -> bool {
        self.scale > Self::FIT_TOLERANCE
    }

    pub fn fitted(&self) -> Self {
        Self::default()
    }

    pub fn zoomed_in(&self) -> Self {
        self.scaled_to(self.scale * Self::KEY_STEP)
    }

    pub fn zoomed_out(&self) -> Self {
        self.scaled_to(self.scale / Self::KEY_STEP)
    }

    /// A pinch, as a multiplier over the scale at its start.
    pub fn magnified(&self, factor: f64) -> Self {
        self.scaled_to(self.scale * factor)
    }

    /// Wheel notches with the system modifier held. Positive zooms in.
    pub fn wheeled(&self, notches: f64) -> Self {
        self.scaled_to(self.scale * Self::WHEEL_STEP.powf(notches))
    }

    /// Double click: the phone's double-tap level from fit, and fit again from anywhere else.
    pub fn double_clicked(&self) -> Self {
        if self.is_zoomed() {
            self.fitted()
        } else {
            self.scaled_to(Self::DOUBLE_CLICK_FACTOR)
        }
    }

    /// The zoom for the page a turn lands on: the same level, at the page's top, on the
    /// side reading starts from. A fitted page stays fitted (`comic-reader`, Zoom persists).
    pub fn turned(&self, right_to_left: bool, fitted: Size, viewport: Size) -> Self {
        if !self.is_zoomed() {
            return self.fitted();
        }
        let slack = Self::slack(fitted, self.scale, viewport);
        let x = if right_to_left {
            -slack.width
        } else {
            slack.width
        };
        Self {
            scale: self.scale,
            offset: Size::new(x, slack.height),
        }
    }

    /// A pan by `delta`, kept inside the page's edges for this viewport.
    pub fn panned(&self, delta: Size, fitted: Size, viewport: Size) -> Self {
        let proposed = Size::new(
            self.offset.width + delta.width,
            self.offset.height + delta.height,
        );
        Self {
            scale: self.scale,
            offset: Self::clamped(proposed, fitted, self.scale, viewport),
        }
    }

    /// The offset with the page's edges respected after a resize or a zoom change.
    pub fn settled(&self, fitted: Size, viewport: Size) -> Self {
        Self {
            scale: self.scale,
            offset: Self::clamped(self.offset, fitted, self.scale, viewport),
        }
    }

    /// Clamps to the limits; a step beyond one changes nothing and says nothing.
    fn scaled_to(&self, proposed: f64) -> Self {
        let scale = proposed.clamp(1.0, Self::CEILING);
        let next = Self {
            scale,
            offset: self.offset,
        };
        if next.is_zoomed() {
            next
        } else {
            Self {
                scale,
                offset: Size::ZERO,
            }
        }
    }

    fn slack(fitted: Size, scale: f64, viewport: Size) -> Size {
        Size::new(
            ((fitted.width * scale - viewport.width) / 2.0).max(0.0),
            ((fitted.height * scale - viewport.height) / 2.0).max(0.0),
        )
    }

    /// The furthest a zoomed page may be panned: half the overflow on each axis, and
    /// nothing on an axis where the page still fits.
    pub fn clamped(offset: Size, fitted: Size, scale: f64, viewport: Size) -> Size {
        let slack = Self::slack(fitted, scale, viewport);
        Size::new(
            offset.width.clamp(-slack.width, slack.width),
            offset.height.clamp(-slack.height, slack.height),
        )
    }
}

/// The size a page of `image` takes when fitted whole inside `viewport`.
pub fn fit_inside(image: Size, viewport: Size) -> Size {
    if image.width <= 0.0 || image.height <= 0.0 {
        return Size::ZERO;
    }
    let scale = (viewport.width / image.width).min(viewport.height / image.height);
    Size::new(image.width * scale, image.height * scale)
}

/// The size a page of `image` pixels takes at scale 1 under the reader's fit: whole inside
/// the window, the window's width, or one image pixel per device pixel.
pub fn fitted_size(fit: Fit, image: Size, viewport: Size, device_scale: f64) -> Size {
    if image.width <= 0.0 || image.height <= 0.0 {
        return Size::ZERO;
    }
    match fit {
        Fit::Page => fit_inside(image, viewport),
        Fit::Width => Size::new(viewport.width, image.height * viewport.width / image.width),
        Fit::Original => {
            let scale = device_scale.max(1.0);
            Size::new(image.width / scale, image.height / scale)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_fit_sizes_the_page_its_own_way() {
        let image = Size::new(1000.0, 1500.0);
        assert_eq!(
            fitted_size(Fit::Page, image, VIEWPORT, 1.0),
            Size::new(400.0, 600.0)
        );
        assert_eq!(
            fitted_size(Fit::Width, image, VIEWPORT, 1.0),
            Size::new(800.0, 1200.0)
        );
        assert_eq!(
            fitted_size(Fit::Original, image, VIEWPORT, 2.0),
            Size::new(500.0, 750.0)
        );
        assert_eq!(
            fitted_size(Fit::Width, Size::ZERO, VIEWPORT, 1.0),
            Size::ZERO
        );
    }

    const FITTED: Size = Size {
        width: 400.0,
        height: 600.0,
    };
    const VIEWPORT: Size = Size {
        width: 800.0,
        height: 600.0,
    };

    #[test]
    fn keys_step_in_and_out_and_never_pass_the_limits_silently() {
        let mut zoom = ZoomModel::default();
        for _ in 0..40 {
            zoom = zoom.zoomed_in();
        }
        assert_eq!(zoom.scale(), ZoomModel::CEILING);
        assert_eq!(zoom.zoomed_in(), zoom);
        for _ in 0..40 {
            zoom = zoom.zoomed_out();
        }
        assert_eq!(zoom.scale(), 1.0);
        assert!(!zoom.is_zoomed());
        assert_eq!(zoom.zoomed_out(), zoom);
    }

    #[test]
    fn a_double_click_gives_the_phone_level_from_fit_and_fits_from_anywhere_else() {
        let once = ZoomModel::default().double_clicked();
        assert_eq!(once.scale(), ZoomModel::DOUBLE_CLICK_FACTOR);
        assert_eq!(once.double_clicked().scale(), 1.0);
        assert_eq!(
            ZoomModel::default().zoomed_in().double_clicked().scale(),
            1.0
        );
    }

    #[test]
    fn pinch_and_the_wheel_multiply_the_scale_inside_the_limits() {
        assert_eq!(ZoomModel::default().magnified(2.0).scale(), 2.0);
        assert_eq!(
            ZoomModel::default().magnified(100.0).scale(),
            ZoomModel::CEILING
        );
        assert_eq!(ZoomModel::default().magnified(0.2).scale(), 1.0);
        let wheeled = ZoomModel::default().wheeled(3.0);
        assert!((wheeled.scale() - ZoomModel::WHEEL_STEP.powi(3)).abs() < 0.0001);
        assert_eq!(ZoomModel::default().wheeled(-3.0).scale(), 1.0);
    }

    #[test]
    fn a_fitted_page_cannot_pan_and_a_zoomed_one_pans_to_its_edges_and_no_further() {
        let delta = Size::new(500.0, 500.0);
        let fitted = ZoomModel::default().panned(delta, FITTED, VIEWPORT);
        assert_eq!(fitted.offset(), Size::ZERO);
        let zoomed = ZoomModel::default().magnified(3.0);
        let panned = zoomed.panned(delta, FITTED, VIEWPORT);
        // 400 x 3 = 1200 wide against 800: 200 of slack each side. 600 x 3 against 600: 600.
        assert_eq!(panned.offset(), Size::new(200.0, 500.0));
        let again = panned.panned(delta, FITTED, VIEWPORT);
        assert_eq!(again.offset(), Size::new(200.0, 600.0));
    }

    #[test]
    fn a_turn_keeps_the_zoom_and_opens_the_page_at_its_top_on_the_reading_side() {
        let viewport = Size::new(400.0, 600.0);
        let zoomed =
            ZoomModel::default()
                .magnified(2.0)
                .panned(Size::new(-50.0, -300.0), FITTED, viewport);
        let next = zoomed.turned(false, FITTED, viewport);
        assert_eq!(next.scale(), 2.0);
        assert_eq!(next.offset(), Size::new(200.0, 300.0));
        let manga = zoomed.turned(true, FITTED, viewport);
        assert_eq!(manga.offset(), Size::new(-200.0, 300.0));
        let fitted = ZoomModel::default().turned(false, FITTED, viewport);
        assert_eq!(fitted, ZoomModel::default());
    }

    #[test]
    fn fit_clears_the_pan_and_a_resize_settles_the_pan_inside_the_new_edges() {
        let zoomed =
            ZoomModel::default()
                .magnified(3.0)
                .panned(Size::new(150.0, 0.0), FITTED, VIEWPORT);
        assert_eq!(zoomed.fitted(), ZoomModel::default());
        let wider = Size::new(1400.0, 600.0);
        assert_eq!(zoomed.settled(FITTED, wider).offset().width, 0.0);
    }

    #[test]
    fn a_page_fits_whole_inside_the_viewport_keeping_its_shape() {
        let tall = fit_inside(Size::new(1000.0, 1500.0), VIEWPORT);
        assert_eq!(tall, Size::new(400.0, 600.0));
        let wide = fit_inside(Size::new(2000.0, 1000.0), VIEWPORT);
        assert_eq!(wide, Size::new(800.0, 400.0));
        assert_eq!(fit_inside(Size::ZERO, VIEWPORT), Size::ZERO);
    }
}
