//! Continuous scroll (`comic-reader`, Continuous scroll and Scroll axis for webtoons;
//! `page-transitions`, Scroll axis): every page one after the other on one axis, stitched
//! with no gap unless the reader asked for a separator. Each page holds its own shape
//! from its header before it decodes, so the strip never jumps as pages land; pages
//! decode as they come near the window. The place is kept exactly: the page at the top
//! and how far down it.

use std::cell::{Cell, RefCell};

use adw::prelude::*;
use gtk::gdk;

use crate::reading::modes::{Axis, ScrollPlace};

/// A page's shape before it decodes: portrait, as most comic pages are.
const PORTRAIT: (i32, i32) = (2, 3);

pub struct ScrollView {
    pub scrolled: gtk::ScrolledWindow,
    strip: gtk::Box,
    pictures: RefCell<Vec<gtk::Picture>>,
    sizes: RefCell<Vec<(i32, i32)>>,
    /// The pages that hold pixels now.
    loaded: RefCell<std::collections::HashSet<usize>>,
    axis: Cell<Axis>,
}

impl ScrollView {
    pub fn new() -> Self {
        let strip = gtk::Box::new(gtk::Orientation::Vertical, 0);
        let scrolled = gtk::ScrolledWindow::builder()
            .child(&strip)
            .hexpand(true)
            .vexpand(true)
            .css_classes(["storyarc-reader"])
            .build();
        Self {
            scrolled,
            strip,
            pictures: RefCell::default(),
            sizes: RefCell::default(),
            loaded: RefCell::default(),
            axis: Cell::new(Axis::Vertical),
        }
    }

    /// Lays out `count` pages on `axis`, each in the shape `sizes` gives (width, height),
    /// with a separator between them when `gap` is set.
    pub fn build(&self, count: usize, sizes: &[(i32, i32)], axis: Axis, gap: bool) {
        while let Some(child) = self.strip.first_child() {
            self.strip.remove(&child);
        }
        self.axis.set(axis);
        let (orientation, h_policy, v_policy) = match axis {
            Axis::Vertical => (
                gtk::Orientation::Vertical,
                gtk::PolicyType::Never,
                gtk::PolicyType::Automatic,
            ),
            Axis::Horizontal => (
                gtk::Orientation::Horizontal,
                gtk::PolicyType::Automatic,
                gtk::PolicyType::Never,
            ),
        };
        self.strip.set_orientation(orientation);
        self.strip.set_spacing(if gap { 12 } else { 0 });
        self.scrolled.set_policy(h_policy, v_policy);
        let pictures: Vec<gtk::Picture> = (0..count)
            .map(|index| {
                let (width, height) = sizes.get(index).copied().unwrap_or(PORTRAIT);
                let picture = gtk::Picture::builder()
                    .paintable(&gdk::Paintable::new_empty(width.max(1), height.max(1)))
                    .content_fit(gtk::ContentFit::Contain)
                    .can_shrink(true)
                    .build();
                picture.update_property(&[gtk::accessible::Property::Label(
                    &crate::strings::tr_args("reader.thumbnail %d", "Page %d", &[&(index + 1)]),
                )]);
                self.strip.append(&picture);
                picture
            })
            .collect();
        *self.pictures.borrow_mut() = pictures;
        *self.sizes.borrow_mut() = sizes.to_vec();
        self.loaded.borrow_mut().clear();
    }

    /// Draws a decoded page in its place.
    pub fn show_page(&self, index: usize, texture: &gdk::Texture) {
        if let Some(picture) = self.pictures.borrow().get(index) {
            picture.set_paintable(Some(texture));
            self.loaded.borrow_mut().insert(index);
        }
    }

    /// Lets go of the pixels of every page not in `keep`; each falls back to its shape.
    pub fn release_except(&self, keep: &[usize]) {
        let sizes = self.sizes.borrow();
        let pictures = self.pictures.borrow();
        self.loaded.borrow_mut().retain(|index| {
            if keep.contains(index) {
                return true;
            }
            if let Some(picture) = pictures.get(*index) {
                let (width, height) = sizes.get(*index).copied().unwrap_or(PORTRAIT);
                picture.set_paintable(Some(&gdk::Paintable::new_empty(
                    width.max(1),
                    height.max(1),
                )));
            }
            false
        });
    }

    fn adjustment(&self) -> gtk::Adjustment {
        match self.axis.get() {
            Axis::Vertical => self.scrolled.vadjustment(),
            Axis::Horizontal => self.scrolled.hadjustment(),
        }
    }

    /// Where each page starts and how long it is along the axis, in the strip's units.
    fn extents(&self) -> Vec<(f64, f64)> {
        self.pictures
            .borrow()
            .iter()
            .map(|picture| {
                let bounds = picture.compute_bounds(&self.strip);
                match (bounds, self.axis.get()) {
                    (Some(rect), Axis::Vertical) => (f64::from(rect.y()), f64::from(rect.height())),
                    (Some(rect), Axis::Horizontal) => {
                        (f64::from(rect.x()), f64::from(rect.width()))
                    }
                    (None, _) => (0.0, 0.0),
                }
            })
            .collect()
    }

    /// The place now: the page at the leading edge of the window and how far into it.
    pub fn place(&self) -> ScrollPlace {
        let offset = self.adjustment().value();
        place_at(&self.extents(), offset)
    }

    /// Scrolls to a place.
    pub fn go_to(&self, place: ScrollPlace) {
        let extents = self.extents();
        if let Some((start, length)) = extents.get(place.page as usize) {
            self.adjustment().set_value(start + length * place.fraction);
        }
    }

    /// The pages any part of which is within `margin` windows of the window.
    pub fn near(&self, margin: f64) -> Vec<usize> {
        let adjustment = self.adjustment();
        let window = adjustment.page_size();
        let from = adjustment.value() - window * margin;
        let to = adjustment.value() + window * (1.0 + margin);
        self.extents()
            .iter()
            .enumerate()
            .filter(|(_, (start, length))| start + length >= from && *start <= to)
            .map(|(index, _)| index)
            .collect()
    }

    pub fn on_scrolled(&self, changed: impl Fn() + 'static) {
        let changed = std::rc::Rc::new(changed);
        for adjustment in [self.scrolled.vadjustment(), self.scrolled.hadjustment()] {
            let changed = changed.clone();
            adjustment.connect_value_changed(move |_| changed());
        }
    }
}

/// The page whose extent holds `offset`, and how far into it, from 0 to 1.
pub fn place_at(extents: &[(f64, f64)], offset: f64) -> ScrollPlace {
    let index = extents
        .iter()
        .rposition(|(start, _)| *start <= offset + 0.5)
        .unwrap_or(0);
    let (start, length) = extents.get(index).copied().unwrap_or((0.0, 0.0));
    let fraction = if length > 0.0 {
        ((offset - start) / length).clamp(0.0, 1.0)
    } else {
        0.0
    };
    ScrollPlace {
        page: u32::try_from(index).unwrap_or(0),
        fraction,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_place_is_the_page_at_the_leading_edge_and_how_far_into_it() {
        let extents = [(0.0, 1000.0), (1000.0, 1500.0), (2500.0, 500.0)];
        assert_eq!(
            place_at(&extents, 0.0),
            ScrollPlace {
                page: 0,
                fraction: 0.0
            }
        );
        assert_eq!(
            place_at(&extents, 1750.0),
            ScrollPlace {
                page: 1,
                fraction: 0.5
            }
        );
        assert_eq!(place_at(&extents, 2600.0).page, 2);
        assert_eq!(place_at(&[], 30.0).page, 0);
    }
}
