//! The page surface of a reader window: the pages of one screen, fitted, zoomed, panned
//! and slid by a drag, drawn straight from the textures the core decoded. A page still
//! decoding, or one that cannot be read, is a quiet placeholder with its reason, never a
//! spinner over the artwork (`desktop-experience`, A page that has not loaded).
//!
//! The geometry is `reading::zoom`; this widget only draws what it is told.

use std::cell::{Cell, RefCell};

use gtk::prelude::*;
use gtk::subclass::prelude::*;
use gtk::{gdk, glib, graphene, gsk};

use crate::reading::{Size, ZoomModel, fitted_size};
use crate::settings::Fit;

/// One page of the screen, as the view draws it.
#[derive(Clone, Debug)]
pub enum PageImage {
    /// Decoded, with its pixels.
    Ready(gdk::Texture),
    /// Still decoding: drawn as a quiet block of this shape.
    Pending { width: f64, height: f64 },
    /// Could not be decoded: a quiet block and the reason under it.
    Failed {
        width: f64,
        height: f64,
        reason: String,
    },
}

impl PageImage {
    fn size(&self) -> Size {
        match self {
            Self::Ready(texture) => {
                Size::new(f64::from(texture.width()), f64::from(texture.height()))
            }
            Self::Pending { width, height } | Self::Failed { width, height, .. } => {
                Size::new(*width, *height)
            }
        }
    }
}

/// A portrait page's shape until its own size is known.
pub const PLACEHOLDER_SIZE: (f64, f64) = (2.0, 3.0);

/// The pages of a screen side by side at a common height, as one image size.
pub fn combined_size(pages: &[Size]) -> Size {
    let height = pages.iter().map(|page| page.height).fold(0.0_f64, f64::max);
    if height <= 0.0 {
        return Size::ZERO;
    }
    let width = pages
        .iter()
        .filter(|page| page.height > 0.0)
        .map(|page| page.width * height / page.height)
        .sum();
    Size::new(width, height)
}

mod imp {
    use super::*;

    #[derive(Default)]
    pub struct PageView {
        pub pages: RefCell<Vec<PageImage>>,
        pub zoom: Cell<ZoomModel>,
        pub fit: Cell<Fit>,
        /// How far a drag has slid the page, in logical pixels.
        pub slide: Cell<f64>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for PageView {
        const NAME: &'static str = "StoryArcPageView";
        type Type = super::PageView;
        type ParentType = gtk::Widget;

        fn class_init(klass: &mut Self::Class) {
            klass.set_css_name("storyarc-page");
            klass.set_accessible_role(gtk::AccessibleRole::Img);
        }
    }

    impl ObjectImpl for PageView {}

    impl WidgetImpl for PageView {
        fn snapshot(&self, snapshot: &gtk::Snapshot) {
            let widget = self.obj();
            let viewport = widget.viewport();
            let pages = self.pages.borrow();
            let sizes: Vec<Size> = pages.iter().map(PageImage::size).collect();
            let fitted = widget.fitted();
            if fitted.width <= 0.0 {
                return;
            }
            let zoom = self.zoom.get();
            let scaled = Size::new(fitted.width * zoom.scale(), fitted.height * zoom.scale());
            let x = (viewport.width - scaled.width) / 2.0 + zoom.offset().width + self.slide.get();
            let y = (viewport.height - scaled.height) / 2.0 + zoom.offset().height;
            let combined = combined_size(&sizes);
            let unit = scaled.height / combined.height.max(1.0);
            let mut left = x;
            for (page, size) in pages.iter().zip(&sizes) {
                let width = if size.height > 0.0 {
                    size.width * combined.height / size.height * unit
                } else {
                    0.0
                };
                let bounds =
                    graphene::Rect::new(left as f32, y as f32, width as f32, scaled.height as f32);
                match page {
                    PageImage::Ready(texture) => snapshot.append_scaled_texture(
                        texture,
                        gsk::ScalingFilter::Trilinear,
                        &bounds,
                    ),
                    PageImage::Pending { .. } | PageImage::Failed { .. } => {
                        snapshot.append_color(&placeholder_colour(&*widget), &bounds);
                    }
                }
                left += width;
            }
        }
    }
}

/// The quiet block: the page colour of the reading theme, a shade off the background.
fn placeholder_colour(widget: &impl IsA<gtk::Widget>) -> gdk::RGBA {
    let colour = widget.as_ref().color();
    gdk::RGBA::new(colour.red(), colour.green(), colour.blue(), 0.08)
}

glib::wrapper! {
    pub struct PageView(ObjectSubclass<imp::PageView>)
        @extends gtk::Widget,
        @implements gtk::Accessible, gtk::Buildable, gtk::ConstraintTarget;
}

impl Default for PageView {
    fn default() -> Self {
        glib::Object::new()
    }
}

impl PageView {
    pub fn viewport(&self) -> Size {
        Size::new(f64::from(self.width()), f64::from(self.height()))
    }

    /// The screen's pages at scale 1 under the fit.
    pub fn fitted(&self) -> Size {
        let sizes: Vec<Size> = self
            .imp()
            .pages
            .borrow()
            .iter()
            .map(PageImage::size)
            .collect();
        fitted_size(
            self.imp().fit.get(),
            combined_size(&sizes),
            self.viewport(),
            f64::from(self.scale_factor()),
        )
    }

    /// The pages of the screen, from the left of the screen to the right, with what to
    /// announce for them.
    pub fn set_pages(&self, pages: Vec<PageImage>, description: &str) {
        *self.imp().pages.borrow_mut() = pages;
        self.update_property(&[gtk::accessible::Property::Label(description)]);
        self.queue_draw();
    }

    /// The reason a page on screen could not be decoded, if one could not.
    pub fn failure(&self) -> Option<String> {
        self.imp()
            .pages
            .borrow()
            .iter()
            .find_map(|page| match page {
                PageImage::Failed { reason, .. } => Some(reason.clone()),
                _ => None,
            })
    }

    pub fn zoom(&self) -> ZoomModel {
        self.imp().zoom.get()
    }

    pub fn set_zoom(&self, zoom: ZoomModel) {
        self.imp().zoom.set(zoom);
        self.queue_draw();
    }

    pub fn fit(&self) -> Fit {
        self.imp().fit.get()
    }

    pub fn set_fit(&self, fit: Fit) {
        self.imp().fit.set(fit);
        self.queue_draw();
    }

    pub fn set_slide(&self, slide: f64) {
        self.imp().slide.set(slide);
        self.queue_draw();
    }

    /// Whether the page as drawn is larger than the window on either axis, so a wheel or
    /// a drag pans it rather than turning it.
    pub fn overflows(&self) -> bool {
        let fitted = self.fitted();
        let scale = self.zoom().scale();
        let viewport = self.viewport();
        fitted.width * scale > viewport.width + 0.5 || fitted.height * scale > viewport.height + 0.5
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_pages_side_by_side_share_one_height() {
        let pages = [Size::new(1000.0, 1500.0), Size::new(500.0, 750.0)];
        assert_eq!(combined_size(&pages), Size::new(2000.0, 1500.0));
        assert_eq!(combined_size(&[]), Size::ZERO);
        assert_eq!(combined_size(&[Size::new(2.0, 3.0)]), Size::new(2.0, 3.0));
    }
}
