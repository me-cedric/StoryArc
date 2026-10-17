//! Home's widgets (task 2.35c, `home-screen`): the shelves `library/home.rs` decides, in
//! order, each a row of same-sized cards. A card shows how far through the reader is as
//! a rail and in words, names the author where there is one, and is dimmed with a line
//! saying so when its folder cannot be read now; it never leaves the row. A shelf that
//! holds more than it shows says how many, and its heading leads to the library filtered
//! the same way.

use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use storyarc_core::domain::Publication;

use crate::covers::Covers;
use crate::library::grid::CoverTier;
use crate::library::home::{Home, Shelf, ShelfRow};
use crate::library_views::{cover_picture_fitted, set_class};
use crate::strings::{tr, tr_args};

/// What a card says besides its cover and title.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CardState {
    /// How far through, in whole percent, when the publication is started.
    pub percent: Option<u32>,
    /// Its folder cannot be read now.
    pub unavailable: bool,
}

/// What Home needs from the window: how to open a publication, what a card says, and
/// where a shelf's heading leads.
pub struct HomeHooks {
    pub open: Rc<dyn Fn(&Publication)>,
    pub card: Rc<dyn Fn(&Publication) -> CardState>,
    pub show_all: Rc<dyn Fn(Shelf)>,
}

/// Home: the shelves with something on them. An empty library is a status page that
/// offers to add a folder; a library with no history yet says where to start.
/// A pinned shelf on Home: its publications, how many it holds, and where its heading goes.
pub struct PinnedRow {
    pub name: String,
    pub total: usize,
    pub publications: Vec<Publication>,
    pub open: Rc<dyn Fn()>,
}

pub fn home_page(
    home: &Home,
    pinned: &[PinnedRow],
    covers: &Rc<Covers>,
    hooks: &HomeHooks,
) -> gtk::Widget {
    let shelves = match home {
        Home::EmptyLibrary => {
            let add = gtk::Button::builder()
                .label(tr("library.addSource", "Add Folder…"))
                .action_name("win.add-source")
                .halign(gtk::Align::Center)
                .css_classes(["pill", "suggested-action"])
                .build();
            return adw::StatusPage::builder()
                .icon_name(crate::APP_ID)
                .title(tr("library.empty.title", "Nothing here yet"))
                .description(tr(
                    "library.empty.subtitle",
                    "Choose a file and start reading. You can add a whole folder whenever you like.",
                ))
                .child(&add)
                .build()
                .upcast();
        }
        Home::Shelves(shelves) if shelves.is_empty() && pinned.is_empty() => {
            let browse = gtk::Button::builder()
                .label(tr("sidebar.library", "Library"))
                .action_name("win.show-library")
                .halign(gtk::Align::Center)
                .css_classes(["pill"])
                .build();
            return adw::StatusPage::builder()
                .icon_name("document-open-recent-symbolic")
                .title(tr("home.title", "Home"))
                .description(tr(
                    "home.nothingOpen",
                    "Nothing open yet. Pick something from your library.",
                ))
                .child(&browse)
                .build()
                .upcast();
        }
        Home::Shelves(shelves) => shelves,
    };
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(24)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(24)
        .margin_end(24)
        .build();
    for row in shelves {
        column.append(&shelf_row(row, covers, hooks));
    }
    for row in pinned {
        column.append(&pinned_row(row, covers, hooks));
    }
    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .child(
            &adw::Clamp::builder()
                .maximum_size(1200)
                .child(&column)
                .build(),
        )
        .build()
        .upcast()
}

/// The heading: the shelf's name, and where it holds more than it shows, how many, as a
/// button that leads to the full list in the library.
fn heading(row: &ShelfRow, hooks: &HomeHooks) -> gtk::Widget {
    let (key, english) = row.shelf.title();
    let title = gtk::Label::builder()
        .label(tr(key, english))
        .xalign(0.0)
        .hexpand(true)
        .css_classes(["title-3"])
        .accessible_role(gtk::AccessibleRole::Heading)
        .build();
    let line = gtk::Box::builder().spacing(12).build();
    line.append(&title);
    let all = gtk::Button::builder()
        .label(if row.is_truncated() {
            format!("{} · {}", tr("library.title", "Library"), row.total)
        } else {
            tr("library.title", "Library")
        })
        .tooltip_text(tr("home.seeAll", "Shows all of them"))
        .css_classes(["flat"])
        .valign(gtk::Align::Center)
        .build();
    let show_all = hooks.show_all.clone();
    let shelf = row.shelf;
    all.connect_clicked(move |_| show_all(shelf));
    line.append(&all);
    line.upcast()
}

fn shelf_row(row: &ShelfRow, covers: &Rc<Covers>, hooks: &HomeHooks) -> gtk::Box {
    let section = gtk::Box::new(gtk::Orientation::Vertical, 12);
    section.append(&heading(row, hooks));
    let flow = gtk::FlowBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .max_children_per_line(12)
        .column_spacing(12)
        .row_spacing(12)
        .homogeneous(true)
        .build();
    for publication in &row.publications {
        flow.append(&card(publication, covers, hooks));
    }
    section.append(&flow);
    section
}

/// One card: the cover filling its box, the rail and the words for how far through, the
/// title and the author.
fn card(publication: &Publication, covers: &Rc<Covers>, hooks: &HomeHooks) -> gtk::Button {
    let state = (hooks.card)(publication);
    let tile = gtk::Box::new(gtk::Orientation::Vertical, 6);
    let picture = cover_picture_fitted(CoverTier::SMALL, gtk::ContentFit::Cover);
    let path = publication
        .identity
        .normalized_path
        .clone()
        .map(PathBuf::from);
    covers.show(&picture, &publication.id(), path);
    tile.append(&picture);
    let mut said = vec![publication.display_title.clone()];
    if let Some(percent) = state.percent {
        let read = tr_args("library.cell.progress %d", "%d%% read", &[&percent]);
        tile.append(
            &gtk::ProgressBar::builder()
                .fraction(f64::from(percent.min(100)) / 100.0)
                .css_classes(["osd"])
                .tooltip_text(&read)
                .build(),
        );
        said.push(read);
    }
    tile.append(
        &gtk::Label::builder()
            .label(&publication.display_title)
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .max_width_chars(12)
            .build(),
    );
    if let Some(author) = publication.authors.first() {
        tile.append(
            &gtk::Label::builder()
                .label(author)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .max_width_chars(12)
                .css_classes(["dimmed", "caption"])
                .build(),
        );
        said.push(author.clone());
    }
    if state.unavailable {
        let note = tr("home.unavailable", "Not on this device right now");
        tile.append(
            &gtk::Label::builder()
                .label(&note)
                .wrap(true)
                .max_width_chars(12)
                .justify(gtk::Justification::Center)
                .css_classes(["dimmed", "caption"])
                .build(),
        );
        said.push(note);
    }
    let button = gtk::Button::builder()
        .child(&tile)
        .css_classes(["flat"])
        .tooltip_text(&publication.display_title)
        .build();
    // Dimmed, never dropped: the card stays in its row and still opens its reason.
    set_class(&tile, "dimmed", state.unavailable);
    button.update_property(&[gtk::accessible::Property::Label(&said.join(", "))]);
    let open = hooks.open.clone();
    let publication = publication.clone();
    button.connect_clicked(move |_| open(&publication));
    button
}

/// A pinned shelf: the shelf's name for a heading, which leads to its page, over a row of
/// cards like any other.
fn pinned_row(row: &PinnedRow, covers: &Rc<Covers>, hooks: &HomeHooks) -> gtk::Box {
    let section = gtk::Box::new(gtk::Orientation::Vertical, 12);
    let line = gtk::Box::builder().spacing(12).build();
    line.append(
        &gtk::Label::builder()
            .label(&row.name)
            .xalign(0.0)
            .hexpand(true)
            .css_classes(["title-3"])
            .accessible_role(gtk::AccessibleRole::Heading)
            .build(),
    );
    let all = gtk::Button::builder()
        .label(format!("{} · {}", tr("shelves.open", "Shelf"), row.total))
        .css_classes(["flat"])
        .valign(gtk::Align::Center)
        .build();
    let open = row.open.clone();
    all.connect_clicked(move |_| open());
    line.append(&all);
    section.append(&line);
    let flow = gtk::FlowBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .max_children_per_line(12)
        .column_spacing(12)
        .row_spacing(12)
        .homogeneous(true)
        .build();
    for publication in &row.publications {
        flow.append(&card(publication, covers, hooks));
    }
    section.append(&flow);
    section
}
