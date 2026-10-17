//! The library's widgets (tasks 2.35a to 2.35d): the cover grid and the list over one
//! `GListModel`, Home's shelves, and the publication detail page. What each shows is
//! decided in `library/`; these functions only lay it out.

use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::Publication;

use crate::covers::Covers;
use crate::library::detail::Detail;
use crate::library::entry::LibraryEntry;
use crate::library::grid::CoverTier;
use crate::library::home::{Home, Shelf};
use crate::strings::tr;

/// One cell's data: the entry it shows and, unless the file could not be opened, the
/// core's record behind it.
pub struct Item {
    pub entry: LibraryEntry,
    pub publication: Option<Publication>,
}

impl Item {
    pub fn path(&self) -> Option<PathBuf> {
        self.publication
            .as_ref()
            .and_then(|publication| publication.identity.normalized_path.clone())
            .map(PathBuf::from)
    }
}

pub fn boxed(item: Item) -> glib::BoxedAnyObject {
    glib::BoxedAnyObject::new(item)
}

/// The item a list position holds.
pub fn item_at(model: &impl IsA<gio::ListModel>, position: u32) -> Option<glib::BoxedAnyObject> {
    model.item(position).and_downcast::<glib::BoxedAnyObject>()
}

fn cover_picture(width: i32) -> gtk::Picture {
    let picture = gtk::Picture::builder()
        .content_fit(gtk::ContentFit::Cover)
        .can_shrink(true)
        .css_classes(["card", "storyarc-cover"])
        .build();
    picture.set_size_request(width, width * 3 / 2);
    picture
}

/// The cover grid: covers at the tier's width, the title under each, and the progress
/// rail. A file that could not be opened shows its reason in place of the title, dimmed.
pub fn grid_view(
    model: &gtk::MultiSelection,
    covers: &Rc<Covers>,
    tier: CoverTier,
) -> gtk::GridView {
    let factory = gtk::SignalListItemFactory::new();
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
                .wrap(true)
                .lines(2)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .max_width_chars(14)
                .justify(gtk::Justification::Center)
                .build(),
        );
        cell.set_child(Some(&column));
    });
    let covers = covers.clone();
    factory.connect_bind(move |_, cell| bind(cell, &covers));
    gtk::GridView::builder()
        .model(model)
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
pub fn list_view(model: &gtk::MultiSelection, covers: &Rc<Covers>) -> gtk::ListView {
    let factory = gtk::SignalListItemFactory::new();
    factory.connect_setup(|_, cell| {
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
                .xalign(0.0)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .build(),
        );
        text.append(
            &gtk::Label::builder()
                .xalign(0.0)
                .css_classes(["dimmed", "caption"])
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .build(),
        );
        row.append(&text);
        cell.set_child(Some(&row));
    });
    let covers = covers.clone();
    factory.connect_bind(move |_, cell| bind(cell, &covers));
    gtk::ListView::builder()
        .model(model)
        .factory(&factory)
        .css_classes(["navigation-sidebar"])
        .build()
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
    if let Some(label) = labels.first() {
        label.set_label(title);
        if entry.cannot_open.is_some() {
            label.add_css_class("dimmed");
        } else {
            label.remove_css_class("dimmed");
        }
    }
    if let Some(label) = labels.get(1) {
        label.set_label(&subtitle(entry));
    }
    child.update_property(&[gtk::accessible::Property::Label(
        &entry.accessible_description(),
    )]);
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
        parts.push(format!("{percent}%"));
    }
    parts.join(" · ")
}

/// Home: Keep Reading, then Up Next, each present only with something on it. An empty
/// library is a status page that offers to add a folder; a library with no history yet
/// says where to start.
pub fn home_page(home: &Home, covers: &Rc<Covers>, open: Rc<dyn Fn(&Publication)>) -> gtk::Widget {
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
                .description("Add a folder of comics, or drop one on this window.")
                .child(&add)
                .build()
                .upcast();
        }
        Home::Shelves(shelves) if shelves.is_empty() => {
            let browse = gtk::Button::builder()
                .label(tr("sidebar.library", "Library"))
                .action_name("win.show-library")
                .halign(gtk::Align::Center)
                .css_classes(["pill"])
                .build();
            return adw::StatusPage::builder()
                .icon_name("document-open-recent-symbolic")
                .title("Nothing in Progress")
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
    for (shelf, publications) in shelves {
        column.append(&shelf_row(*shelf, publications, covers, &open));
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

fn shelf_row(
    shelf: Shelf,
    publications: &[Publication],
    covers: &Rc<Covers>,
    open: &Rc<dyn Fn(&Publication)>,
) -> gtk::Box {
    let (key, english) = shelf.title();
    let section = gtk::Box::new(gtk::Orientation::Vertical, 12);
    section.append(
        &gtk::Label::builder()
            .label(tr(key, english))
            .xalign(0.0)
            .css_classes(["title-3"])
            .accessible_role(gtk::AccessibleRole::Heading)
            .build(),
    );
    let row = gtk::FlowBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .max_children_per_line(12)
        .column_spacing(12)
        .row_spacing(12)
        .homogeneous(true)
        .build();
    for publication in publications {
        let tile = gtk::Box::new(gtk::Orientation::Vertical, 6);
        let picture = cover_picture(CoverTier::SMALL);
        let path = publication
            .identity
            .normalized_path
            .clone()
            .map(PathBuf::from);
        covers.show(&picture, &publication.id(), path);
        tile.append(&picture);
        tile.append(
            &gtk::Label::builder()
                .label(&publication.display_title)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .max_width_chars(12)
                .build(),
        );
        let button = gtk::Button::builder()
            .child(&tile)
            .css_classes(["flat"])
            .tooltip_text(&publication.display_title)
            .build();
        let open = open.clone();
        let publication = publication.clone();
        button.connect_clicked(move |_| open(&publication));
        row.append(&button);
    }
    section.append(&row);
    section
}

/// The detail page pushed over the library in a narrow window.
pub fn detail_page(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    read: Rc<dyn Fn(&Publication)>,
) -> adw::NavigationPage {
    adw::NavigationPage::builder()
        .title(&detail.title)
        .tag("detail")
        .child(&detail_view(detail, publication, covers, read))
        .build()
}

/// The second pane of a wide window before a cover is chosen: one sentence.
pub fn pane_placeholder() -> gtk::Widget {
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::builder().show_title(false).build());
    toolbar.set_content(Some(
        &adw::StatusPage::builder()
            .title("No Publication Chosen")
            .description("Choose a cover to see its page here.")
            .build(),
    ));
    toolbar.upcast()
}

/// The detail page's content, with its own header bar: the cover on a wash, the title,
/// one primary action, a menu, and the line that names where the file lives. The same
/// view is pushed in a narrow window and stands beside the library in a wide one.
pub fn detail_view(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    read: Rc<dyn Fn(&Publication)>,
) -> adw::ToolbarView {
    let path = publication.identity.normalized_path.clone();
    let column = detail_column(detail, publication, covers, read);
    let toolbar = adw::ToolbarView::new();
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(&adw::WindowTitle::new(&detail.title, "")));
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .child(
                &adw::Clamp::builder()
                    .maximum_size(640)
                    .child(&column)
                    .build(),
            )
            .build(),
    ));
    toolbar.insert_action_group("detail", Some(&show_in_files(path)));
    toolbar
}

fn show_in_files(path: Option<String>) -> gio::SimpleActionGroup {
    let group = gio::SimpleActionGroup::new();
    let show = gio::SimpleAction::new("show-in-files", None);
    show.connect_activate(move |_, _| {
        if let Some(path) = &path {
            gtk::FileLauncher::new(Some(&gio::File::for_path(path))).open_containing_folder(
                gtk::Window::NONE,
                None::<&gio::Cancellable>,
                |_| {},
            );
        }
    });
    group.add_action(&show);
    group
}

fn detail_column(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    read: Rc<dyn Fn(&Publication)>,
) -> gtk::Box {
    let picture = cover_picture(220);
    picture.set_halign(gtk::Align::Center);
    let path = publication.identity.normalized_path.clone();
    covers.show(&picture, &publication.id(), path.clone().map(PathBuf::from));
    let wash = gtk::Box::builder()
        .css_classes(["storyarc-cover-wash"])
        .halign(gtk::Align::Fill)
        .build();
    wash.append(&picture);
    picture.set_hexpand(true);

    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(24)
        .margin_end(24)
        .build();
    column.append(&wash);
    column.append(
        &gtk::Label::builder()
            .label(&detail.title)
            .wrap(true)
            .css_classes(["title-1"])
            .build(),
    );
    if let Some(subtitle) = &detail.subtitle {
        column.append(
            &gtk::Label::builder()
                .label(subtitle)
                .wrap(true)
                .css_classes(["dimmed"])
                .build(),
        );
    }
    let primary = gtk::Button::builder()
        .label(detail.primary.label())
        .sensitive(detail.primary.is_enabled())
        .css_classes(["pill", "suggested-action"])
        .build();
    let target = publication.clone();
    primary.connect_clicked(move |_| read(&target));
    let menu = gio::Menu::new();
    menu.append(Some("Show in Files"), Some("detail.show-in-files"));
    let more = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .tooltip_text("More")
        .menu_model(&menu)
        .css_classes(["circular"])
        .build();
    let actions = gtk::Box::builder()
        .spacing(12)
        .halign(gtk::Align::Center)
        .build();
    actions.append(&primary);
    actions.append(&more);
    column.append(&actions);
    if let Some(note) = detail.note {
        column.append(
            &gtk::Label::builder()
                .label(note)
                .css_classes(["dimmed"])
                .build(),
        );
    }
    if let Some(count) = detail.page_count {
        column.append(
            &gtk::Label::builder()
                .label(format!("{count} pages"))
                .css_classes(["dimmed", "caption"])
                .build(),
        );
    }
    column.append(
        &gtk::Label::builder()
            .label(&detail.location)
            .wrap(true)
            .wrap_mode(gtk::pango::WrapMode::WordChar)
            .selectable(true)
            .css_classes(["dimmed", "caption"])
            .build(),
    );
    column
}
