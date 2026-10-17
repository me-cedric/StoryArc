//! The library window (tasks 2.30, 2.31, 2.35a to 2.35d): a sidebar with Home, Library,
//! Downloads and the folder libraries, and a content column that holds Home, the cover
//! grid or the list, and the detail page pushed over them. The search field stays in the
//! header bar; while text is in it, its results take over the content column, and
//! clearing it returns to the destination the reader came from.

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::Publication;
use storyarc_core::library::ProgressIndex;
use storyarc_core::locale::Collation;

use crate::app::Shared;
use crate::commands::Scope;
use crate::covers::Covers;
use crate::folders::Access;
use crate::library::detail::Detail;
use crate::library::entry::{Format, LibraryEntry};
use crate::library::grid::CoverTier;
use crate::library::home::Home;
use crate::library::query::{Destination, QueryState, ReadState, Sort};
use crate::library_views::{self, Item};
use crate::opening::LaunchAction;
use crate::strings::{tr, tr_args};
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH, WindowState};
use crate::{launch, menus, session, sources};

const SECTIONS: [(&str, &str, Destination); 3] = [
    ("sidebar.home", "Home", Destination::Home),
    ("sidebar.library", "Library", Destination::Library),
    ("sidebar.downloads", "Downloads", Destination::Downloads),
];

/// The progress records the library reads at most, newest first.
const PROGRESS_RECORDS: usize = 100_000;

const IMPLEMENTED: [&str; 10] = [
    "win.open-file",
    "win.add-source",
    "win.refresh-sources",
    "win.find",
    "win.view-grid",
    "win.view-list",
    "win.show-home",
    "win.show-library",
    "win.show-downloads",
    "win.back",
];

/// The library window's widgets and what the header bar holds.
pub struct LibraryUi {
    window: adw::ApplicationWindow,
    split: adw::NavigationSplitView,
    sections: gtk::ListBox,
    folders: gtk::ListBox,
    navigation: adw::NavigationView,
    stack: gtk::Stack,
    home: adw::Bin,
    layouts: gtk::Stack,
    store: gio::ListStore,
    search: gtk::SearchEntry,
    state: RefCell<QueryState>,
    covers: Rc<Covers>,
    collation: Collation,
}

/// Builds and presents the library window. `missing` names the readers that could not
/// be reopened at launch, said once in grey.
pub fn open(shared: &Shared, state: &WindowState, missing: &[String]) -> adw::ApplicationWindow {
    let sections = sections_list();
    let folders = gtk::ListBox::builder()
        .css_classes(["navigation-sidebar"])
        .selection_mode(gtk::SelectionMode::None)
        .build();
    let split = adw::NavigationSplitView::builder()
        .sidebar(&sidebar_page(&sections, &folders))
        .build();

    let store = gio::ListStore::new::<glib::BoxedAnyObject>();
    let selection = gtk::MultiSelection::new(Some(store.clone()));
    let covers = Rc::new(Covers::default());
    let tier = CoverTier::for_width(state.width, shared.preferences().cover_size);
    let grid = library_views::grid_view(&selection, &covers, tier);
    let list = library_views::list_view(&selection, &covers);
    let layouts = gtk::Stack::new();
    layouts.add_named(&scrolled(&grid), Some("grid"));
    layouts.add_named(&scrolled(&list), Some("list"));
    let downloads = adw::StatusPage::builder()
        .icon_name("folder-download-symbolic")
        .title(tr("sidebar.downloads", "Downloads"))
        .description("Publications you download from a server appear here.")
        .build();
    let home = adw::Bin::new();
    let stack = gtk::Stack::builder()
        .transition_type(gtk::StackTransitionType::Crossfade)
        .build();
    stack.add_named(&home, Some("home"));
    stack.add_named(&layouts, Some("library"));
    stack.add_named(&downloads, Some("downloads"));

    let search = gtk::SearchEntry::builder()
        .placeholder_text(tr("library.search", "Search"))
        .hexpand(true)
        .max_width_chars(32)
        .build();
    let navigation = adw::NavigationView::new();
    navigation.add(&content_page(&stack, &search));
    split.set_content(Some(&adw::NavigationPage::new(&navigation, "StoryArc")));

    let overlay = adw::ToastOverlay::new();
    overlay.set_child(Some(&split));
    let window = adw::ApplicationWindow::builder()
        .application(&shared.application())
        .title("StoryArc")
        .content(&overlay)
        .build();
    // The minimum size is a size request: libadwaita sets one of its own only from 1.6.
    window.set_size_request(MIN_WIDTH, MIN_HEIGHT);
    session::apply(&window, state);
    window.add_breakpoint(narrow_breakpoint(&split));
    search.set_key_capture_widget(Some(&window));

    let ui = Rc::new(LibraryUi {
        window: window.clone(),
        split,
        sections,
        folders,
        navigation,
        stack,
        home,
        layouts,
        store,
        search,
        state: RefCell::new(QueryState::at(Destination::Home)),
        covers,
        collation: Collation::new(crate::strings::language()),
    });
    install_actions(shared, &ui);
    connect(shared, &ui, &grid, &list);
    launch::install_drop(window.upcast_ref(), shared);

    *shared.library_toasts.borrow_mut() = Some(overlay);
    *shared.library.borrow_mut() = Some(window.clone());
    *shared.library_ui.borrow_mut() = Some(ui.clone());
    let weak = Rc::downgrade(shared);
    *shared.on_library_changed.borrow_mut() = Some(Box::new(move |full| {
        if let Some(shared) = weak.upgrade() {
            if full {
                refresh(&shared);
            } else {
                refresh_home(&shared);
            }
        }
    }));
    ui.sections.select_row(ui.sections.row_at_index(0).as_ref());
    refresh(shared);
    window.present();
    if !missing.is_empty() {
        shared.toast(&tr_args(
            "restore.missing",
            "Could not reopen: %s",
            &[&missing.join(", ")],
        ));
    }
    window
}

fn scrolled(child: &impl IsA<gtk::Widget>) -> gtk::ScrolledWindow {
    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .child(child)
        .build()
}

fn narrow_breakpoint(split: &adw::NavigationSplitView) -> adw::Breakpoint {
    let condition = adw::BreakpointCondition::parse("max-width: 600sp").expect("valid condition");
    let breakpoint = adw::Breakpoint::new(condition);
    breakpoint.add_setter(split, "collapsed", Some(&true.to_value()));
    breakpoint
}

fn sections_list() -> gtk::ListBox {
    let list = gtk::ListBox::builder()
        .css_classes(["navigation-sidebar"])
        .build();
    for (key, english, _) in SECTIONS {
        list.append(
            &gtk::Label::builder()
                .label(tr(key, english))
                .xalign(0.0)
                .build(),
        );
    }
    list
}

fn sidebar_page(sections: &gtk::ListBox, folders: &gtk::ListBox) -> adw::NavigationPage {
    let menu_button = gtk::MenuButton::builder()
        .icon_name("open-menu-symbolic")
        .tooltip_text(tr("menu.main", "Main menu"))
        .menu_model(&menus::primary_menu())
        .primary(true)
        .build();
    let add = gtk::Button::builder()
        .icon_name("list-add-symbolic")
        .tooltip_text(tr("library.addSource", "Add Folder…"))
        .action_name("win.add-source")
        .build();
    let header = adw::HeaderBar::new();
    header.pack_start(&add);
    header.pack_end(&menu_button);
    let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    column.append(sections);
    column.append(
        &gtk::Label::builder()
            .label("Folders")
            .xalign(0.0)
            .margin_start(12)
            .margin_top(12)
            .css_classes(["heading", "dimmed"])
            .build(),
    );
    column.append(folders);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&scrolled(&column)));
    adw::NavigationPage::new(&toolbar, "StoryArc")
}

fn content_page(stack: &gtk::Stack, search: &gtk::SearchEntry) -> adw::NavigationPage {
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(search));
    let view = gtk::MenuButton::builder()
        .icon_name("view-grid-symbolic")
        .tooltip_text("View")
        .menu_model(&view_menu())
        .build();
    let filter = gtk::MenuButton::builder()
        .label("Filter")
        .tooltip_text("Filter")
        .menu_model(&filter_menu())
        .build();
    let sort = gtk::MenuButton::builder()
        .icon_name("view-sort-ascending-symbolic")
        .tooltip_text("Sort")
        .menu_model(&sort_menu())
        .build();
    header.pack_end(&view);
    header.pack_end(&sort);
    header.pack_end(&filter);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(stack));
    adw::NavigationPage::builder()
        .title("StoryArc")
        .tag("content")
        .child(&toolbar)
        .build()
}

fn view_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    menu.append(Some("Grid"), Some("win.view-grid"));
    menu.append(Some("List"), Some("win.view-list"));
    menu
}

const FORMATS: [(&str, Option<Format>); 5] = [
    ("any", None),
    ("cbz", Some(Format::Cbz)),
    ("cbr", Some(Format::Cbr)),
    ("cbt", Some(Format::Cbt)),
    ("folder", Some(Format::Folder)),
];
const STATES: [(&str, &str, Option<ReadState>); 4] = [
    ("any", "Any State", None),
    ("unread", "Unread", Some(ReadState::Unread)),
    ("reading", "Reading", Some(ReadState::Reading)),
    ("finished", "Finished", Some(ReadState::Finished)),
];
const SORTS: [(&str, &str, Sort); 4] = [
    ("title", "Title", Sort::Title),
    ("series", "Series", Sort::Series),
    ("date-added", "Date Added", Sort::DateAdded),
    ("last-read", "Last Read", Sort::LastRead),
];

/// How a filter or sort choice changes the header bar's state.
type FilterChange = fn(&mut QueryState, &str);

fn filter_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    let formats = gio::Menu::new();
    for (target, format) in FORMATS {
        let label = format.map_or("Any Format", Format::display_name);
        formats.append(Some(label), Some(&format!("win.filter-format::{target}")));
    }
    menu.append_section(Some("Format"), &formats);
    let states = gio::Menu::new();
    for (target, label, _) in STATES {
        states.append(Some(label), Some(&format!("win.filter-state::{target}")));
    }
    menu.append_section(Some("Reading State"), &states);
    menu
}

fn sort_menu() -> gio::Menu {
    let menu = gio::Menu::new();
    for (target, label, _) in SORTS {
        menu.append(Some(label), Some(&format!("win.sort::{target}")));
    }
    menu
}

fn install_actions(shared: &Shared, ui: &Rc<LibraryUi>) {
    let window = &ui.window;
    menus::add_disabled_actions(window, Scope::Library, &IMPLEMENTED);
    let on = shared.clone();
    add(window, "open-file", move |window| {
        launch::choose_files(&on, window.upcast_ref());
    });
    let on = shared.clone();
    add(window, "add-source", move |window| {
        sources::choose(&on, window.upcast_ref(), None);
    });
    let on = shared.clone();
    add(window, "refresh-sources", move |_| sources::refresh(&on));
    let weak = Rc::downgrade(ui);
    add(window, "find", move |_| {
        if let Some(ui) = weak.upgrade() {
            ui.search.grab_focus();
        }
    });
    for (name, child) in [("view-grid", "grid"), ("view-list", "list")] {
        let weak = Rc::downgrade(ui);
        add(window, name, move |_| {
            if let Some(ui) = weak.upgrade() {
                ui.layouts.set_visible_child_name(child);
            }
        });
    }
    for (index, name) in ["show-home", "show-library", "show-downloads"]
        .into_iter()
        .enumerate()
    {
        let weak = Rc::downgrade(ui);
        add(window, name, move |_| {
            if let Some(ui) = weak.upgrade() {
                let row = ui.sections.row_at_index(index as i32);
                ui.sections.select_row(row.as_ref());
            }
        });
    }
    let weak = Rc::downgrade(ui);
    add(window, "back", move |_| {
        if let Some(ui) = weak.upgrade() {
            ui.navigation.pop();
        }
    });
    let filters: [(&str, &str, FilterChange); 3] = [
        ("filter-format", "any", |state, target| {
            state.filters.format = FORMATS
                .iter()
                .find(|(name, _)| *name == target)
                .and_then(|(_, format)| *format);
        }),
        ("filter-state", "any", |state, target| {
            state.filters.read_state = STATES
                .iter()
                .find(|(name, _, _)| *name == target)
                .and_then(|(_, _, read)| *read);
        }),
        ("sort", "title", |state, target| {
            state.sort = SORTS
                .iter()
                .find(|(name, _, _)| *name == target)
                .map_or(Sort::Title, |(_, _, sort)| *sort);
        }),
    ];
    for (name, initial, change) in filters {
        let action = gio::SimpleAction::new_stateful(
            name,
            Some(glib::VariantTy::STRING),
            &initial.to_variant(),
        );
        let on = shared.clone();
        action.connect_activate(move |action, target| {
            let Some(target) = target.and_then(|target| target.get::<String>()) else {
                return;
            };
            action.set_state(&target.to_variant());
            if let Some(ui) = on.library_ui.borrow().clone() {
                change(&mut ui.state.borrow_mut(), &target);
            }
            refresh(&on);
        });
        window.add_action(&action);
    }
}

fn add(
    window: &adw::ApplicationWindow,
    name: &str,
    activate: impl Fn(&adw::ApplicationWindow) + 'static,
) {
    let action = gio::SimpleAction::new(name, None);
    let weak = window.downgrade();
    action.connect_activate(move |_, _| {
        if let Some(window) = weak.upgrade() {
            activate(&window);
        }
    });
    window.add_action(&action);
}

fn connect(shared: &Shared, ui: &Rc<LibraryUi>, grid: &gtk::GridView, list: &gtk::ListView) {
    let on = shared.clone();
    ui.sections.connect_row_selected(move |_, row| {
        let Some(row) = row else {
            return;
        };
        let Some((_, _, destination)) = SECTIONS.get(row.index() as usize) else {
            return;
        };
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.state.borrow_mut().destination = *destination;
            ui.navigation.pop_to_tag("content");
            ui.split.set_show_content(true);
        }
        refresh(&on);
    });
    let on = shared.clone();
    ui.search.connect_search_changed(move |entry| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.state.borrow_mut().typed(&entry.text());
        }
        refresh(&on);
    });
    ui.search.connect_stop_search(|entry| entry.set_text(""));
    let on = shared.clone();
    grid.connect_activate(move |grid, position| activate_item(&on, grid.model(), position));
    let on = shared.clone();
    list.connect_activate(move |list, position| activate_item(&on, list.model(), position));
    let on = shared.clone();
    ui.window.connect_is_active_notify(move |window| {
        if window.is_active() {
            sources::refresh(&on);
        }
    });
    let weak = Rc::downgrade(shared);
    ui.window.connect_close_request(move |_| {
        if let Some(shared) = weak.upgrade() {
            if !shared.quitting.get() {
                shared.save_session();
            }
            shared.library_ui.borrow_mut().take();
            shared.on_library_changed.borrow_mut().take();
            shared.library_toasts.borrow_mut().take();
        }
        glib::Propagation::Proceed
    });
}

/// Enter or a double click on a cell: the detail page, or the reason a file that could
/// not be opened gives.
fn activate_item(shared: &Shared, model: Option<gtk::SelectionModel>, position: u32) {
    let Some(item) = model.and_then(|model| library_views::item_at(&model, position)) else {
        return;
    };
    let item = item.borrow::<Item>();
    match &item.publication {
        Some(publication) => push_detail(shared, publication),
        None => {
            if let Some(reason) = &item.entry.cannot_open {
                shared.toast(&format!("{}: {reason}", item.entry.title));
            }
        }
    }
}

fn progress_index(shared: &Shared) -> ProgressIndex {
    ProgressIndex::new(
        shared
            .progress_store()
            .recent(PROGRESS_RECORDS)
            .unwrap_or_default(),
    )
}

fn push_detail(shared: &Shared, publication: &Publication) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let progress = progress_index(shared);
    let detail = Detail::of(
        publication,
        progress.summary(publication),
        shared.sources.source_of(publication),
    );
    let page = library_views::detail_page(&detail, publication, &ui.covers, read(shared));
    ui.navigation.push(&page);
}

/// Opens a publication in a reader window, naming a refusal in grey.
fn read(shared: &Shared) -> Rc<dyn Fn(&Publication)> {
    let weak = Rc::downgrade(shared);
    Rc::new(move |publication: &Publication| {
        let Some(shared) = weak.upgrade() else {
            return;
        };
        let Some(path) = publication.identity.normalized_path.clone() else {
            return;
        };
        if let Err(reason) = launch::open_publication(&shared, &PathBuf::from(path)) {
            shared.toast(&reason);
        }
    })
}

/// Brings the library to a destination of the desktop entry's static actions.
pub fn show(shared: &Shared, action: LaunchAction) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let index = match action {
        LaunchAction::Downloads => 2,
        LaunchAction::Library => 1,
        LaunchAction::ContinueReading => 0,
    };
    ui.sections
        .select_row(ui.sections.row_at_index(index).as_ref());
}

/// A position was written: Home follows, and the grid keeps its scroll and selection.
fn refresh_home(shared: &Shared) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let publications = shared.sources.publications();
    show_home(shared, &ui, &publications, &progress_index(shared));
}

fn show_home(
    shared: &Shared,
    ui: &LibraryUi,
    publications: &[Publication],
    progress: &ProgressIndex,
) {
    let home = Home::of(publications, progress);
    ui.home.set_child(Some(&library_views::home_page(
        &home,
        &ui.covers,
        read(shared),
    )));
}

/// Rebuilds what the library shows from the folders and the progress store: the folder
/// rows, Home, and the grid's model under the header bar's query.
pub fn refresh(shared: &Shared) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let publications = shared.sources.publications();
    let progress = progress_index(shared);
    refresh_folders(shared, &ui);
    show_home(shared, &ui, &publications, &progress);

    let state = ui.state.borrow().clone();
    let source_name =
        |publication: &Publication| shared.sources.source_of(publication).map(|(name, _)| name);
    let shown = state.arrange(&publications, &progress, &ui.collation, source_name);
    let mut items: Vec<glib::BoxedAnyObject> = shown
        .into_iter()
        .map(|publication| {
            let source = source_name(&publication).unwrap_or_default();
            let entry =
                LibraryEntry::from_core(&publication, progress.summary(&publication), &source);
            library_views::boxed(Item {
                entry,
                publication: Some(publication),
            })
        })
        .collect();
    if state.destination == Destination::Library
        && state.to_core() == QueryState::at(Destination::Library).to_core()
    {
        items.extend(shared.sources.skipped().into_iter().map(|(name, reason)| {
            library_views::boxed(Item {
                entry: LibraryEntry::could_not_open(&name, &reason, ""),
                publication: None,
            })
        }));
    }
    ui.store.splice(0, ui.store.n_items(), &items);

    let child = if state.results_take_over() {
        "library"
    } else {
        match state.destination {
            Destination::Home => "home",
            Destination::Downloads | Destination::Downloaded => "downloads",
            _ => "library",
        }
    };
    ui.stack.set_visible_child_name(child);
}

/// The folder rows: each folder's name, a grey line when it is offline, needs access or
/// is not watched live, and Choose Again on one that needs access.
fn refresh_folders(shared: &Shared, ui: &Rc<LibraryUi>) {
    ui.folders.remove_all();
    for (index, (name, access, not_live)) in shared.sources.summary().into_iter().enumerate() {
        let row = gtk::Box::builder().spacing(6).build();
        let text = gtk::Box::new(gtk::Orientation::Vertical, 2);
        text.set_hexpand(true);
        let title = gtk::Label::builder()
            .label(&name)
            .xalign(0.0)
            .ellipsize(gtk::pango::EllipsizeMode::Middle)
            .build();
        if access != Access::Readable {
            title.add_css_class("dimmed");
        }
        text.append(&title);
        if let Some(note) = access.note().map(str::to_owned).or(not_live) {
            text.append(
                &gtk::Label::builder()
                    .label(&note)
                    .xalign(0.0)
                    .wrap(true)
                    .css_classes(["dimmed", "caption"])
                    .build(),
            );
        }
        row.append(&text);
        if access == Access::Withdrawn {
            let again = gtk::Button::builder()
                .label("Choose Again…")
                .valign(gtk::Align::Center)
                .css_classes(["flat"])
                .build();
            let on = shared.clone();
            let window = ui.window.clone();
            again.connect_clicked(move |_| sources::choose_again(&on, window.upcast_ref(), index));
            row.append(&again);
        }
        ui.folders.append(&row);
    }
}
