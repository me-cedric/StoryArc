//! The library's cells (tasks 2.35a and 2.35b): the cover grid and the list over one
//! `GListModel`. What each cell shows is decided in `library/`; these functions only lay
//! it out. Home is `home_view.rs` and the publication page is `detail_view.rs`.

use std::cell::Cell;
use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, gio, glib};
use storyarc_core::domain::Publication;

use crate::covers::Covers;
use crate::library::entry::{LibraryEntry, UNAVAILABLE};
use crate::library::grid::CoverTier;
use crate::strings::{tr, tr_args, tr_plural};

/// The names the cell's labels carry, so one bind fills the grid and the list.
const TITLE: &str = "title";
const SUBTITLE: &str = "subtitle";
const NOTE: &str = "note";

/// One cell's data: the entry it shows and, unless the file could not be opened, the
/// core's record behind it. A cell that stands for a series holds its issues instead.
pub struct Item {
    pub entry: LibraryEntry,
    pub publication: Option<Publication>,
    /// The series' issues, in their order, when the cell stands for a series.
    pub issues: Vec<Publication>,
}

impl Item {
    pub fn publication(entry: LibraryEntry, publication: Publication) -> Self {
        Self {
            entry,
            publication: Some(publication),
            issues: Vec::new(),
        }
    }

    /// The file the cover comes from: the publication's, or a series' first issue's.
    pub fn path(&self) -> Option<PathBuf> {
        self.publication
            .as_ref()
            .or(self.issues.first())
            .and_then(|publication| publication.identity.normalized_path.clone())
            .map(PathBuf::from)
    }

    pub fn is_series(&self) -> bool {
        !self.issues.is_empty()
    }
}

pub fn boxed(item: Item) -> glib::BoxedAnyObject {
    glib::BoxedAnyObject::new(item)
}

/// The item a list position holds.
pub fn item_at(model: &impl IsA<gio::ListModel>, position: u32) -> Option<glib::BoxedAnyObject> {
    model.item(position).and_downcast::<glib::BoxedAnyObject>()
}

/// A cover at `width`, in a 2:3 box. The grid, the list and the detail page show the
/// cover whole (`library-browsing`, Cover art is shown whole); a Home card fills its box
/// (`home-screen`, Artwork is not letterboxed): pass `ContentFit::Cover` there.
pub fn cover_picture(width: i32) -> gtk::Picture {
    cover_picture_fitted(width, gtk::ContentFit::Contain)
}

pub fn cover_picture_fitted(width: i32, fit: gtk::ContentFit) -> gtk::Picture {
    let picture = gtk::Picture::builder()
        .content_fit(fit)
        .can_shrink(true)
        .css_classes(["card", "storyarc-cover"])
        .build();
    picture.set_size_request(width, width * 3 / 2);
    picture
}

/// What a right click on a cover does: the window builds the menu for the item the cell
/// holds, at the point clicked.
pub type CellMenu = Rc<dyn Fn(&gtk::Widget, &glib::BoxedAnyObject, f64, f64)>;

/// What every cell of a shelf shares: its model, the cover ladder, the menu, and whether
/// the window is in selection mode, where a click picks a cover rather than focusing it.
#[derive(Clone)]
pub struct CellHooks {
    pub model: gtk::MultiSelection,
    pub covers: Rc<Covers>,
    pub menu: CellMenu,
    pub selecting: Rc<Cell<bool>>,
}

/// The cover grid: covers at the tier's width, the title under each, the progress rail,
/// and a grey line for a cell whose library cannot be reached or that stands for a
/// series. A file that could not be opened shows its reason in place of the title.
pub fn grid_view(hooks: &CellHooks, tier: CoverTier) -> gtk::GridView {
    let factory = gtk::SignalListItemFactory::new();
    let setup = hooks.clone();
    factory.connect_setup(move |_, cell| {
        let Some(cell) = cell.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let column = gtk::Box::new(gtk::Orientation::Vertical, 6);
        column.append(&cover_picture(tier.min));
        column.append(
            &gtk::ProgressBar::builder()
                .css_classes(["osd"])
                .visible(false)
                .build(),
        );
        column.append(
            &gtk::Label::builder()
                .name(TITLE)
                .wrap(true)
                .lines(2)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .max_width_chars(14)
                .justify(gtk::Justification::Center)
                .build(),
        );
        column.append(
            &gtk::Label::builder()
                .name(NOTE)
                .wrap(true)
                .max_width_chars(14)
                .justify(gtk::Justification::Center)
                .css_classes(["dimmed", "caption"])
                .visible(false)
                .build(),
        );
        attach(cell, &column, &setup);
        cell.set_child(Some(&column));
    });
    let covers = hooks.covers.clone();
    factory.connect_bind(move |_, cell| bind(cell, &covers));
    gtk::GridView::builder()
        .model(&hooks.model)
        .factory(&factory)
        .max_columns(24)
        .single_click_activate(false)
        .enable_rubberband(true)
        .css_classes(["storyarc-grid"])
        .margin_start(12)
        .margin_end(12)
        .margin_top(12)
        .margin_bottom(12)
        .build()
}

/// The list: a small cover, the title, and a line of series, format and progress.
pub fn list_view(hooks: &CellHooks) -> gtk::ListView {
    let factory = gtk::SignalListItemFactory::new();
    let setup = hooks.clone();
    factory.connect_setup(move |_, cell| {
        let Some(cell) = cell.downcast_ref::<gtk::ListItem>() else {
            return;
        };
        let row = gtk::Box::builder()
            .spacing(12)
            .margin_top(6)
            .margin_bottom(6)
            .build();
        row.append(&cover_picture(40));
        let text = gtk::Box::new(gtk::Orientation::Vertical, 2);
        text.set_valign(gtk::Align::Center);
        text.append(
            &gtk::Label::builder()
                .name(TITLE)
                .xalign(0.0)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .build(),
        );
        text.append(
            &gtk::Label::builder()
                .name(SUBTITLE)
                .xalign(0.0)
                .css_classes(["dimmed", "caption"])
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .build(),
        );
        row.append(&text);
        attach(cell, &row, &setup);
        cell.set_child(Some(&row));
    });
    let covers = hooks.covers.clone();
    factory.connect_bind(move |_, cell| bind(cell, &covers));
    gtk::ListView::builder()
        .model(&hooks.model)
        .factory(&factory)
        .css_classes(["navigation-sidebar"])
        .build()
}

/// How many publications a series cell holds, said in the catalogue's plural.
fn holds(count: usize) -> String {
    tr_plural("shelves.count %d", "%d title", "%d titles", count as u64)
}

/// Fills a grid or list cell from its item. Both layouts share the walk: a picture,
/// then labels, then an optional progress bar, in any order.
fn bind(cell: &glib::Object, covers: &Rc<Covers>) {
    let Some(cell) = cell.downcast_ref::<gtk::ListItem>() else {
        return;
    };
    let (Some(item), Some(child)) = (
        cell.item().and_downcast::<glib::BoxedAnyObject>(),
        cell.child(),
    ) else {
        return;
    };
    let item = item.borrow::<Item>();
    let entry = &item.entry;
    let mut labels = Vec::new();
    let mut widget = child.first_child();
    while let Some(current) = widget {
        if let Some(picture) = current.downcast_ref::<gtk::Picture>() {
            covers.show(picture, &entry.id, item.path());
        } else if let Some(bar) = current.downcast_ref::<gtk::ProgressBar>() {
            let percent = entry.progress.percent();
            bar.set_visible(percent > 0);
            bar.set_fraction(f64::from(percent) / 100.0);
        } else if let Some(label) = current.downcast_ref::<gtk::Label>() {
            labels.push(label.clone());
        } else if let Some(text) = current.downcast_ref::<gtk::Box>() {
            let mut inner = text.first_child();
            while let Some(label) = inner {
                if let Some(label) = label.downcast_ref::<gtk::Label>() {
                    labels.push(label.clone());
                }
                inner = label.next_sibling();
            }
        }
        widget = current.next_sibling();
    }
    let title = entry.cell_label_key().unwrap_or(&entry.title);
    let unavailable = tr(UNAVAILABLE.0, UNAVAILABLE.1);
    let note = if entry.unavailable {
        Some(unavailable.clone())
    } else {
        item.is_series().then(|| holds(item.issues.len()))
    };
    for label in labels {
        match label.widget_name().as_str() {
            TITLE => {
                label.set_label(title);
                set_class(&label, "dimmed", entry.cannot_open.is_some());
            }
            SUBTITLE => label.set_label(&note.clone().unwrap_or_else(|| subtitle(entry))),
            NOTE => {
                label.set_label(note.as_deref().unwrap_or_default());
                label.set_visible(note.is_some());
            }
            _ => {}
        }
    }
    // Dimming is the only difference: the cell keeps its place and stays selectable.
    set_class(&child, "dimmed", entry.unavailable);
    child.set_tooltip_text(entry.unavailable.then_some(unavailable.as_str()));
    let mut description = entry.accessible_description();
    if item.is_series() {
        description = format!("{description}, {}", holds(item.issues.len()));
    }
    child.update_property(&[gtk::accessible::Property::Label(&description)]);
}

pub fn set_class(widget: &impl IsA<gtk::Widget>, class: &str, on: bool) {
    if on {
        widget.add_css_class(class);
    } else {
        widget.remove_css_class(class);
    }
}

/// A right click opens the cover's menu (`library/context.rs`). In selection mode a
/// primary click picks the cover or puts it back, and nothing opens.
fn attach(cell: &gtk::ListItem, child: &gtk::Box, hooks: &CellHooks) {
    let context = gtk::GestureClick::builder()
        .button(gdk::BUTTON_SECONDARY)
        .build();
    let weak = cell.downgrade();
    let open = hooks.menu.clone();
    context.connect_pressed(move |gesture, _, x, y| {
        let (Some(cell), Some(widget)) = (weak.upgrade(), gesture.widget()) else {
            return;
        };
        if let Some(item) = cell.item().and_downcast::<glib::BoxedAnyObject>() {
            gesture.set_state(gtk::EventSequenceState::Claimed);
            open(&widget, &item, x, y);
        }
    });
    child.add_controller(context);

    let pick = gtk::GestureClick::builder()
        .button(gdk::BUTTON_PRIMARY)
        .propagation_phase(gtk::PropagationPhase::Capture)
        .build();
    let weak = cell.downgrade();
    let model = hooks.model.clone();
    let selecting = hooks.selecting.clone();
    pick.connect_pressed(move |gesture, _, _, _| {
        let Some(cell) = weak.upgrade().filter(|_| selecting.get()) else {
            return;
        };
        gesture.set_state(gtk::EventSequenceState::Claimed);
        let position = cell.position();
        if model.is_selected(position) {
            model.unselect_item(position);
        } else {
            model.select_item(position, false);
        }
    });
    child.add_controller(pick);
}

/// The list's second line: the file's name when it could not be opened, else series,
/// format and progress.
fn subtitle(entry: &LibraryEntry) -> String {
    if entry.cannot_open.is_some() {
        return entry.title.clone();
    }
    let mut parts = Vec::new();
    if let Some(series) = &entry.series {
        parts.push(match entry.issue {
            Some(issue) => format!("{series} {issue}"),
            None => series.clone(),
        });
    }
    parts.push(entry.format.display_name().to_owned());
    let percent = entry.progress.percent();
    if percent > 0 {
        parts.push(tr_args(
            "library.cell.progress %d",
            "%d%% read",
            &[&percent],
        ));
    }
    parts.join(" · ")
}
