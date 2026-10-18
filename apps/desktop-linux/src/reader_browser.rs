//! The page browser (`comic-reader`, Page browser; Navigation within a publication): the
//! current page centred and larger, the pages beside it smaller unless motion is reduced,
//! each numbered, a slider ticked at each chapter start and the chapter's name above.
//! Browsing never moves the reader; choosing a page jumps there and offers the way back.
//! Right to left, the carousel and the slider run from the right. The rules are
//! `reading/chapters.rs`.

use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use crate::covers::texture;
use crate::reader_window::Reader;
use crate::reading::chapters;
use crate::strings::{tr, tr_args};

/// A thumbnail never decodes larger than this on its longest edge.
const THUMBNAIL_EDGE: u32 = 192;
/// The size of the centred page's cell, and of the others at the scale the rule gives.
const CELL: (i32, i32) = (112, 168);
const SPACING: i32 = 8;
/// Pages decoded each side of the centred one.
const AROUND: usize = 6;

struct Browser {
    reader: Rc<Reader>,
    count: usize,
    right_to_left: bool,
    reduced_motion: bool,
    cells: Vec<gtk::Button>,
    pictures: Vec<gtk::Picture>,
    centre: Cell<usize>,
    pending: RefCell<HashSet<usize>>,
    carousel: gtk::ScrolledWindow,
    chapter: gtk::Label,
    slider: gtk::Scale,
    go: gtk::Button,
    /// Cell positions by page, from the order the carousel runs in.
    positions: Vec<usize>,
}

pub fn present(reader: &Rc<Reader>) {
    let count = reader.publication.page_count as usize;
    if count == 0 {
        return;
    }
    let right_to_left = reader.right_to_left();
    let reduced_motion =
        !gtk::Settings::default().is_some_and(|settings| settings.is_gtk_enable_animations());
    let current = reader.page() as usize;
    let markers = &reader.publication.markers;

    let strip = gtk::Box::builder()
        .spacing(SPACING)
        .margin_start(12)
        .margin_end(12)
        .halign(gtk::Align::Start)
        .valign(gtk::Align::Center)
        .build();
    let order = chapters::carousel_order(count, right_to_left);
    let mut positions = vec![0; count];
    let mut cells: Vec<Option<gtk::Button>> = vec![None; count];
    let mut pictures: Vec<Option<gtk::Picture>> = vec![None; count];
    for (position, page) in order.iter().enumerate() {
        positions[*page] = position;
        let picture = gtk::Picture::builder()
            .content_fit(gtk::ContentFit::Contain)
            .can_shrink(true)
            .vexpand(true)
            .build();
        let number = chapters::badge(*page, markers).map_or_else(
            || (page + 1).to_string(),
            |badge| format!("{} · {badge}", page + 1),
        );
        let caption = gtk::Label::builder()
            .label(&number)
            .css_classes(["caption", "numeric"])
            .build();
        let body = gtk::Box::new(gtk::Orientation::Vertical, 4);
        body.append(&picture);
        body.append(&caption);
        let cell = gtk::Button::builder()
            .child(&body)
            .css_classes(["flat"])
            .build();
        cell.update_property(&[gtk::accessible::Property::Label(
            &chapters::page_announcement(*page, current, markers),
        )]);
        strip.append(&cell);
        cells[*page] = Some(cell);
        pictures[*page] = Some(picture);
    }
    let carousel = gtk::ScrolledWindow::builder()
        .child(&strip)
        .hscrollbar_policy(gtk::PolicyType::Automatic)
        .vscrollbar_policy(gtk::PolicyType::Never)
        .min_content_height(CELL.1 + 48)
        .build();
    let chapter = gtk::Label::builder()
        .css_classes(["heading"])
        .xalign(0.0)
        .build();
    let last = (count - 1) as f64;
    let slider = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, last.max(1.0), 1.0);
    slider.set_draw_value(false);
    slider.set_sensitive(count > 1);
    slider.set_value(chapters::slider_value(current, count, right_to_left));
    slider.update_property(&[gtk::accessible::Property::Label(&tr(
        "reader.slider",
        "Page",
    ))]);
    for marker in markers {
        slider.add_mark(
            chapters::slider_value(marker.index, count, right_to_left),
            gtk::PositionType::Bottom,
            None,
        );
    }
    let go = gtk::Button::builder()
        .css_classes(["suggested-action", "pill"])
        .halign(gtk::Align::Center)
        .build();

    let body = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(12)
        .margin_bottom(18)
        .margin_start(18)
        .margin_end(18)
        .build();
    body.append(&chapter);
    body.append(&carousel);
    body.append(&slider);
    body.append(&go);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&body));
    let dialog = adw::Dialog::builder()
        .title(tr("reader.goToPage", "Go to Page"))
        .content_width(640)
        .child(&toolbar)
        .default_widget(&go)
        .build();

    let browser = Rc::new(Browser {
        reader: reader.clone(),
        count,
        right_to_left,
        reduced_motion,
        cells: cells.into_iter().flatten().collect(),
        pictures: pictures.into_iter().flatten().collect(),
        centre: Cell::new(current),
        pending: RefCell::default(),
        carousel,
        chapter,
        slider: slider.clone(),
        go: go.clone(),
        positions,
    });
    for (page, cell) in browser.cells.iter().enumerate() {
        let (browser, dialog) = (browser.clone(), dialog.clone());
        cell.connect_clicked(move |_| {
            dialog.close();
            browser.reader.jump_to(page);
        });
    }
    let weak = Rc::downgrade(&browser);
    slider.connect_value_changed(move |slider| {
        if let Some(browser) = weak.upgrade() {
            let page = chapters::page_at(slider.value(), browser.count, browser.right_to_left);
            browser.centre_on(page);
        }
    });
    let weak = Rc::downgrade(&browser);
    let closing = dialog.clone();
    go.connect_clicked(move |_| {
        closing.close();
        if let Some(browser) = weak.upgrade() {
            browser.reader.jump_to(browser.centre.get());
        }
    });
    // Enter on the slider goes to the page it shows; a Scale does not take Enter itself.
    let enter = gtk::EventControllerKey::new();
    enter.set_propagation_phase(gtk::PropagationPhase::Capture);
    let (focus, go_to) = (slider.clone(), go.clone());
    enter.connect_key_pressed(move |_, key, _, _| {
        let is_enter = matches!(key, gdk::Key::Return | gdk::Key::KP_Enter);
        if is_enter && focus.has_focus() {
            go_to.emit_clicked();
            glib::Propagation::Stop
        } else {
            glib::Propagation::Proceed
        }
    });
    dialog.add_controller(enter);
    browser.centre_on(current);
    // The carousel has its width once it is laid out; the centred page waits for that.
    let weak = Rc::downgrade(&browser);
    glib::timeout_add_local_once(std::time::Duration::from_millis(60), move || {
        if let Some(browser) = weak.upgrade() {
            browser.scroll_to_centre();
        }
    });
    dialog.present(Some(&reader.window));
    slider.grab_focus();
}

impl Browser {
    /// The browser's own place changed: the cell sizes, the chapter's name, the words on
    /// the button, and the thumbnails near it. The reader's page does not move.
    fn centre_on(self: &Rc<Self>, page: usize) {
        let before = self.centre.replace(page);
        self.size_cell(before, false);
        self.size_cell(page, true);
        let markers = &self.reader.publication.markers;
        self.chapter
            .set_label(&chapters::label(page, markers).unwrap_or_default());
        self.chapter.set_visible(!markers.is_empty());
        self.go.set_label(&tr_args(
            "reader.goToPage %d",
            "Go to page %d",
            &[&(page + 1)],
        ));
        self.slider
            .update_property(&[gtk::accessible::Property::ValueText(
                &chapters::page_announcement(page, self.reader.page() as usize, markers),
            )]);
        self.scroll_to_centre();
        let from = page.saturating_sub(AROUND);
        let to = (page + AROUND).min(self.count - 1);
        for index in from..=to {
            self.request(index);
        }
    }

    fn size_cell(&self, page: usize, centred: bool) {
        let distance = usize::from(!centred);
        let scale = chapters::scale(distance, self.reduced_motion);
        if let Some(cell) = self.cells.get(page) {
            cell.set_size_request(
                (f64::from(CELL.0) * scale).round() as i32,
                (f64::from(CELL.1) * scale).round() as i32,
            );
            if self.reduced_motion {
                if centred {
                    cell.add_css_class("suggested-action");
                } else {
                    cell.remove_css_class("suggested-action");
                }
            }
        }
    }

    fn scroll_to_centre(&self) {
        let adjustment = self.carousel.hadjustment();
        let position = self.positions.get(self.centre.get()).copied().unwrap_or(0);
        let cell = f64::from(CELL.0 + SPACING);
        let middle = 12.0 + position as f64 * cell + f64::from(CELL.0) / 2.0;
        adjustment.set_value((middle - adjustment.page_size() / 2.0).max(0.0));
    }

    fn request(self: &Rc<Self>, index: usize) {
        if let Some(texture) = self.reader.thumbnails.borrow().get(&index) {
            self.pictures[index].set_paintable(Some(texture));
            return;
        }
        if !self.pending.borrow_mut().insert(index) {
            return;
        }
        let publication = self.reader.publication.clone();
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let decoded = gio::spawn_blocking(move || {
                publication.decode_adjusted(
                    index,
                    THUMBNAIL_EDGE,
                    (0, 1),
                    &storyarc_core::domain::ImageAdjustments::default(),
                )
            })
            .await;
            let Some(browser) = weak.upgrade() else {
                return;
            };
            browser.pending.borrow_mut().remove(&index);
            if let Ok(Ok(page)) = decoded {
                let texture: gdk::Texture = texture(page);
                browser.pictures[index].set_paintable(Some(&texture));
                browser
                    .reader
                    .thumbnails
                    .borrow_mut()
                    .insert(index, texture);
            }
        });
    }
}
