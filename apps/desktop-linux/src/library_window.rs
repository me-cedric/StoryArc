//! The library window (tasks 2.30, 2.31, 2.35a to 2.35d): a sidebar with Home, Library,
//! Downloads and the folder libraries, and a content column that holds Home, the cover
//! grid or the list, and the detail page pushed over them. The search field stays in the
//! header bar; once entered, its page takes over the content column, and leaving it
//! returns to the destination the reader came from.
//!
//! The menus are `library_menus.rs`, the search page `library_search.rs` and its
//! behaviour `library_find.rs`, the header bar and selection mode `library_selection.rs`,
//! the notices `library_notices.rs`, what the cells are made from `library_data.rs`, and
//! what the window does with its cells `library_cells.rs`.

use std::cell::{Cell, RefCell};
use std::collections::BTreeSet;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::{Publication, Timestamp};
use storyarc_core::library::ProgressIndex;
use storyarc_core::locale::Collation;

use crate::app::Shared;
use crate::commands::Scope;
use crate::covers::Covers;
use crate::detail_panes::{self, DetailPanes};
use crate::folders::Access;
use crate::home_view::{self, HomeHooks};
use crate::library::entry::LibraryEntry;
use crate::library::grid::CoverTier;
use crate::library::home::{Home, Moment, Shelf};
use crate::library::notice::Skipped;
use crate::library::query::{Destination, QueryState};
use crate::library::search::{SearchMemory, SearchPage};
use crate::library::shelf::{self, Grouping, Layout, Row, ViewChoice};
use crate::library_cells;
use crate::library_menus;
use crate::library_search::SearchUi;
use crate::library_views::{self, CellHooks, Item};
use crate::opening::LaunchAction;
use crate::strings::{tr, tr_args};
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH, WindowState};
use crate::{
    downloads_ui, launch, library_data, library_find, library_notices, library_selection, menus,
    network_ui, remote_browse, session, shelf_ui, sources,
};

const SECTIONS: [(&str, &str, Destination); 3] = [
    ("sidebar.home", "Home", Destination::Home),
    ("sidebar.library", "Library", Destination::Library),
    ("sidebar.downloads", "Downloads", Destination::Downloads),
];

const IMPLEMENTED: [&str; 14] = [
    "win.add-share",
    "win.add-catalogue",
    "win.add-kavita",
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
    "win.select-all",
];

/// The library window's widgets and what the header bar holds.
pub struct LibraryUi {
    pub(crate) window: adw::ApplicationWindow,
    pub(crate) split: adw::NavigationSplitView,
    pub(crate) sections: gtk::ListBox,
    pub(crate) folders: gtk::ListBox,
    pub(crate) shelves: gtk::ListBox,
    pub(crate) navigation: adw::NavigationView,
    pub(crate) panes: DetailPanes,
    pub(crate) stack: gtk::Stack,
    pub(crate) home: adw::Bin,
    pub(crate) layouts: gtk::Stack,
    pub(crate) grid: gtk::GridView,
    pub(crate) list: gtk::ListView,
    pub(crate) rail: gtk::Box,
    pub(crate) store: gio::ListStore,
    pub(crate) selection: gtk::MultiSelection,
    pub(crate) selecting: Rc<Cell<bool>>,
    pub(crate) header: gtk::Stack,
    pub(crate) selection_title: adw::WindowTitle,
    pub(crate) selection_bar: gtk::ActionBar,
    pub(crate) mark_read: gtk::Button,
    pub(crate) search: gtk::SearchEntry,
    pub(crate) search_ui: SearchUi,
    pub(crate) filter_button: gtk::MenuButton,
    pub(crate) sort_button: gtk::MenuButton,
    pub(crate) skipped_banner: adw::Banner,
    pub(crate) access_banner: adw::Banner,
    /// The files the reader dismissed the notice for.
    pub(crate) dismissed: RefCell<BTreeSet<Skipped>>,
    /// The folder the access banner offers to choose again.
    pub(crate) withdrawn: Cell<Option<usize>>,
    pub(crate) state: RefCell<QueryState>,
    pub(crate) memory: RefCell<SearchMemory>,
    pub(crate) view: Cell<ViewChoice>,
    /// When the reader last looked before this session, for Recently added.
    pub(crate) last_looked: Option<Timestamp>,
    pub(crate) covers: Rc<Covers>,
    pub(crate) tier: Cell<CoverTier>,
    pub(crate) collation: Collation,
}

impl LibraryUi {
    pub fn tier(&self) -> CoverTier {
        self.tier.get()
    }
}

/// Builds and presents the library window. `missing` names the readers that could not
/// be reopened at launch, said once in grey.
pub fn open(shared: &Shared, state: &WindowState, missing: &[String]) -> adw::ApplicationWindow {
    let sections = sections_list();
    let folders = gtk::ListBox::builder()
        .css_classes(["navigation-sidebar"])
        .build();
    let shelves = gtk::ListBox::builder()
        .css_classes(["navigation-sidebar"])
        .build();
    let split = adw::NavigationSplitView::builder()
        .sidebar(&sidebar_page(&sections, &folders, &shelves))
        .build();

    let store = gio::ListStore::new::<glib::BoxedAnyObject>();
    let selection = gtk::MultiSelection::new(Some(store.clone()));
    let covers = Rc::new(Covers::default());
    let tier = CoverTier::for_width(state.width, shared.preferences().cover_size);
    let selecting = Rc::new(Cell::new(false));
    let counted = selection.clone();
    let hooks = CellHooks {
        model: selection.clone(),
        covers: covers.clone(),
        menu: library_cells::cell_menu(shared, move || {
            usize::try_from(counted.selection().size()).unwrap_or(usize::MAX)
        }),
        selecting: selecting.clone(),
    };
    let grid = library_views::grid_view(&hooks, tier);
    let list = library_views::list_view(&hooks);
    let layouts = gtk::Stack::new();
    layouts.add_named(&scrolled(&grid), Some("grid"));
    layouts.add_named(&scrolled(&list), Some("list"));
    let rail = library_cells::index_rail();
    let shelf = gtk::Overlay::builder().child(&layouts).build();
    shelf.add_overlay(&rail);
    let downloads = downloads_ui::page(shared);
    let search_ui = SearchUi::new();
    let home = adw::Bin::new();
    let stack = gtk::Stack::builder()
        .transition_type(gtk::StackTransitionType::Crossfade)
        .build();
    stack.add_named(&home, Some("home"));
    stack.add_named(&shelf, Some("library"));
    stack.add_named(&downloads, Some("downloads"));
    stack.add_named(&search_ui.page, Some("search"));

    let search = gtk::SearchEntry::builder()
        .placeholder_text(tr("library.search", "Search"))
        .hexpand(true)
        .max_width_chars(32)
        .build();
    let content = library_selection::ContentBars::new(&search);
    let skipped_banner = adw::Banner::new("");
    let access_banner = adw::Banner::new("");
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&content.header);
    toolbar.add_top_bar(&access_banner);
    toolbar.add_top_bar(&skipped_banner);
    toolbar.add_top_bar(&search_ui.strip);
    toolbar.add_bottom_bar(&content.selection_bar);
    toolbar.set_content(Some(&stack));
    let navigation = adw::NavigationView::new();
    navigation.add(
        &adw::NavigationPage::builder()
            .title("StoryArc")
            .tag("content")
            .child(&toolbar)
            .build(),
    );
    let pane = adw::Bin::new();
    let panes = adw::OverlaySplitView::builder()
        .content(&navigation)
        .sidebar(&pane)
        .sidebar_position(gtk::PackType::End)
        .collapsed(false)
        .show_sidebar(false)
        .min_sidebar_width(320.0)
        .max_sidebar_width(480.0)
        .sidebar_width_fraction(0.4)
        .build();
    split.set_content(Some(&adw::NavigationPage::new(&panes, "StoryArc")));

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

    let memory = session::load_search();
    let view = session::load_view();
    let ui = Rc::new(LibraryUi {
        window: window.clone(),
        split,
        sections,
        folders,
        shelves,
        navigation,
        panes: DetailPanes::new(panes, pane),
        stack,
        home,
        layouts,
        grid: grid.clone(),
        list: list.clone(),
        rail,
        store,
        selection,
        selecting,
        header: content.stack,
        selection_title: content.selection_title,
        selection_bar: content.selection_bar,
        mark_read: content.mark_read,
        search,
        search_ui,
        filter_button: content.filter,
        sort_button: content.sort,
        skipped_banner,
        access_banner,
        dismissed: RefCell::default(),
        withdrawn: Cell::new(None),
        state: RefCell::new(QueryState {
            scope: memory.scope,
            ..QueryState::at(Destination::Home)
        }),
        memory: RefCell::new(memory),
        view: Cell::new(view),
        last_looked: session::looked_now(),
        covers,
        tier: Cell::new(tier),
        collation: Collation::new(crate::strings::language()),
    });
    ui.layouts.set_visible_child_name(match view.layout {
        Layout::Grid => "grid",
        Layout::List => "list",
    });
    install_actions(shared, &ui);
    shelf_ui::install(shared, &ui);
    connect(shared, &ui, &grid, &list);
    detail_panes::follow_width(shared, &ui);
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

fn sidebar_page(
    sections: &gtk::ListBox,
    folders: &gtk::ListBox,
    shelves: &gtk::ListBox,
) -> adw::NavigationPage {
    let menu_button = gtk::MenuButton::builder()
        .icon_name("open-menu-symbolic")
        .tooltip_text(tr("menu.main", "Main menu"))
        .menu_model(&menus::primary_menu())
        .primary(true)
        .build();
    let add_menu = gio::Menu::new();
    add_menu.append(
        Some(&tr("library.addSource", "Add Folder…")),
        Some("win.add-source"),
    );
    add_menu.append(
        Some(&tr("sources.add.share", "A computer on your network")),
        Some("win.add-share"),
    );
    add_menu.append(
        Some(&tr("sources.add.catalogue", "Online library")),
        Some("win.add-catalogue"),
    );
    add_menu.append(
        Some(&tr("sources.add.kavita", "Kavita library")),
        Some("win.add-kavita"),
    );
    let add = gtk::MenuButton::builder()
        .icon_name("list-add-symbolic")
        .tooltip_text(tr("sources.add", "Add a library"))
        .menu_model(&add_menu)
        .build();
    add.update_property(&[gtk::accessible::Property::Label(&tr(
        "sources.add",
        "Add a library",
    ))]);
    let header = adw::HeaderBar::new();
    header.pack_start(&add);
    header.pack_end(&menu_button);
    let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    column.append(sections);
    column.append(
        &gtk::Label::builder()
            .label(tr("sidebar.libraries", "Libraries"))
            .xalign(0.0)
            .margin_start(12)
            .margin_top(12)
            .css_classes(["heading", "dimmed"])
            .build(),
    );
    column.append(folders);
    column.append(
        &gtk::Label::builder()
            .label(tr("shelves.title", "Shelves"))
            .xalign(0.0)
            .margin_start(12)
            .margin_top(12)
            .css_classes(["heading", "dimmed"])
            .build(),
    );
    column.append(shelves);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&scrolled(&column)));
    adw::NavigationPage::new(&toolbar, "StoryArc")
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
    let on = shared.clone();
    add(window, "add-share", move |window| {
        network_ui::present_share(&on, window.upcast_ref());
    });
    let on = shared.clone();
    add(window, "add-catalogue", move |window| {
        network_ui::present_catalogue(&on, window.upcast_ref());
    });
    let on = shared.clone();
    add(window, "add-kavita", move |window| {
        network_ui::present_kavita(&on, window.upcast_ref());
    });
    let weak = Rc::downgrade(ui);
    add(window, "find", move |_| {
        if let Some(ui) = weak.upgrade() {
            ui.search.grab_focus();
        }
    });
    for (name, layout) in [("view-grid", Layout::Grid), ("view-list", Layout::List)] {
        let on = shared.clone();
        add(window, name, move |_| set_layout(&on, layout));
    }
    install_view_actions(shared, ui);
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
    library_menus::install(window, shared, |shared| {
        refresh(shared);
    });
    library_selection::install_selection_actions(shared, ui);
}

/// The View menu's two choices, kept across visits.
fn install_view_actions(shared: &Shared, ui: &Rc<LibraryUi>) {
    let view = ui.view.get();
    let layout = gio::SimpleAction::new_stateful(
        "layout",
        Some(glib::VariantTy::STRING),
        &match view.layout {
            Layout::Grid => "grid",
            Layout::List => "list",
        }
        .to_variant(),
    );
    let on = shared.clone();
    layout.connect_activate(move |_, target| {
        let list = target.and_then(|t| t.get::<String>()).as_deref() == Some("list");
        set_layout(&on, if list { Layout::List } else { Layout::Grid });
    });
    ui.window.add_action(&layout);
    let grouping = gio::SimpleAction::new_stateful(
        "grouping",
        Some(glib::VariantTy::STRING),
        &match view.grouping {
            Grouping::Series => "series",
            Grouping::Issues => "issues",
        }
        .to_variant(),
    );
    let on = shared.clone();
    grouping.connect_activate(move |action, target| {
        let Some(target) = target.and_then(|t| t.get::<String>()) else {
            return;
        };
        action.set_state(&target.to_variant());
        if let Some(ui) = on.library_ui.borrow().clone() {
            let grouping = if target == "issues" {
                Grouping::Issues
            } else {
                Grouping::Series
            };
            let view = ViewChoice {
                grouping,
                ..ui.view.get()
            };
            ui.view.set(view);
            session::save_view(view);
        }
        refresh(&on);
    });
    ui.window.add_action(&grouping);
}

fn set_layout(shared: &Shared, layout: Layout) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let view = ViewChoice {
        layout,
        ..ui.view.get()
    };
    ui.view.set(view);
    session::save_view(view);
    let name = match layout {
        Layout::Grid => "grid",
        Layout::List => "list",
    };
    ui.layouts.set_visible_child_name(name);
    if let Some(action) = ui
        .window
        .lookup_action("layout")
        .and_downcast::<gio::SimpleAction>()
    {
        action.set_state(&name.to_variant());
    }
}

pub(crate) fn add(
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
            ui.folders.unselect_all();
            {
                let mut state = ui.state.borrow_mut();
                state.destination = *destination;
                state.filters.source = None;
            }
            library_find::leave_search(&on, &ui);
            library_menus::reflect(&ui.window, &ui.state.borrow());
            ui.navigation.pop_to_tag("content");
            ui.split.set_show_content(true);
        }
        refresh(&on);
    });
    // A folder in the sidebar is a second way into the library: the library, narrowed to
    // that folder by the same filter the Filter menu offers by name.
    let on = shared.clone();
    ui.shelves.connect_row_activated(move |list, row| {
        if let Some(ui) = on.library_ui.borrow().clone() {
            ui.sections.unselect_all();
            ui.folders.unselect_all();
        }
        let _ = list;
        shelf_ui::activate_row(&on, row.index() as usize);
    });
    let on = shared.clone();
    ui.folders.connect_row_activated(move |_, row| {
        let Some(ui) = on.library_ui.borrow().clone() else {
            return;
        };
        let folders = on.sources.summary().len();
        if row.index() as usize >= folders {
            ui.sections.unselect_all();
            remote_browse::open(&on, row.index() as usize - folders);
            return;
        }
        let Some((name, _, _)) = on.sources.summary().into_iter().nth(row.index() as usize) else {
            return;
        };
        ui.sections.unselect_all();
        {
            let mut state = ui.state.borrow_mut();
            state.destination = Destination::Library;
            state.filters.source = Some(name);
        }
        library_find::leave_search(&on, &ui);
        library_menus::reflect(&ui.window, &ui.state.borrow());
        ui.navigation.pop_to_tag("content");
        ui.split.set_show_content(true);
        refresh(&on);
    });
    library_find::connect_search(shared, ui);
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
    library_notices::connect_banners(shared, ui);
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

/// Enter or a double click on a cell: a series opens on its own page, a publication its
/// detail page, and a file that could not be opened says why.
pub(crate) fn activate_item(shared: &Shared, model: Option<gtk::SelectionModel>, position: u32) {
    let Some(item) = model.and_then(|model| library_views::item_at(&model, position)) else {
        return;
    };
    let item = item.borrow::<Item>();
    if item.is_series() {
        if let Some(ui) = shared.library_ui.borrow().clone() {
            let page = library_cells::series_page(shared, &item.entry.title, &item.issues);
            ui.navigation.push(&page);
        }
        return;
    }
    match &item.publication {
        Some(publication) => library_data::show_detail(shared, publication),
        None => {
            if let Some(reason) = &item.entry.cannot_open {
                shared.toast(&format!("{}: {reason}", item.entry.title));
            }
        }
    }
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

/// A shelf's heading on Home: the library, filtered and sorted the way the shelf is.
fn show_shelf(shared: &Shared, shelf: Shelf) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    ui.sections.select_row(ui.sections.row_at_index(1).as_ref());
    let (read_state, sort) = shelf.link();
    {
        let mut state = ui.state.borrow_mut();
        state.filters.read_state = read_state;
        state.sort = sort;
    }
    library_menus::reflect(&ui.window, &ui.state.borrow());
    refresh(shared);
}

/// A position was written: Home follows, and the grid keeps its scroll and selection.
fn refresh_home(shared: &Shared) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let publications = shared.sources.publications();
    show_home(
        shared,
        &ui,
        &publications,
        &library_data::progress_index(shared),
    );
}

fn show_home(
    shared: &Shared,
    ui: &LibraryUi,
    publications: &[Publication],
    progress: &ProgressIndex,
) {
    let moment = Moment {
        last_looked: ui.last_looked,
        now: Timestamp::now(),
    };
    let home = Home::of(publications, progress, moment);
    let weak = Rc::downgrade(shared);
    let card_shared = Rc::downgrade(shared);
    let card_progress = library_data::progress_index(shared);
    let hooks = HomeHooks {
        open: library_data::read(shared),
        card: Rc::new(move |publication: &Publication| {
            card_shared
                .upgrade()
                .map(|shared| library_data::card_state(&shared, &card_progress, publication))
                .unwrap_or_default()
        }),
        show_all: Rc::new(move |shelf| {
            if let Some(shared) = weak.upgrade() {
                show_shelf(&shared, shelf);
            }
        }),
    };
    let pinned: Vec<home_view::PinnedRow> = shelf_ui::home_rows(shared)
        .into_iter()
        .map(|row| {
            let weak = Rc::downgrade(shared);
            let shelf = row.shelf.clone();
            home_view::PinnedRow {
                name: row.name,
                total: row.total,
                publications: row.publications,
                open: Rc::new(move || {
                    if let Some(shared) = weak.upgrade() {
                        shelf_ui::show(&shared, &shelf);
                    }
                }),
            }
        })
        .collect();
    ui.home.set_child(Some(&home_view::home_page(
        &home, &pinned, &ui.covers, &hooks,
    )));
}

/// Rebuilds what the library shows from the folders and the progress store: the folder
/// rows, Home, the banners, the header bar's buttons, the search page and the grid's
/// model under the header bar's query.
pub fn refresh(shared: &Shared) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let publications = shared.sources.publications();
    let progress = library_data::progress_index(shared);
    refresh_folders(shared, &ui);
    shelf_ui::fill_sidebar(shared, &ui.shelves);
    if let Some(fill) = shared.shelf_fill.borrow().as_ref() {
        fill();
    }
    library_notices::refresh_banners(shared, &ui);
    show_home(shared, &ui, &publications, &progress);

    let state = ui.state.borrow().clone();
    let source = |publication: &Publication| shared.sources.source_of(publication);
    let shown = state.arrange(&publications, &progress, &ui.collation, source);
    let found = shown.len();
    let grouping = if state.results_take_over() {
        Grouping::Issues
    } else {
        ui.view.get().grouping
    };
    let rows = shelf::rows(shown, grouping);
    let titles: Vec<&str> = rows.iter().map(Row::title).collect();
    let index = shelf::index(&titles, state.sort);
    let mut items: Vec<glib::BoxedAnyObject> = rows
        .into_iter()
        .map(|row| match row {
            Row::Publication(publication) => library_data::item_for(shared, &publication),
            Row::Series { name, issues } => {
                library_data::series_item(shared, &progress, name, issues)
            }
        })
        .map(library_views::boxed)
        .collect();
    if state.destination == Destination::Library
        && !state.results_take_over()
        && state.to_core() == QueryState::at(Destination::Library).to_core()
        && state.filters.source.is_none()
    {
        items.extend(shared.sources.skipped().into_iter().map(|(name, reason)| {
            library_views::boxed(Item {
                entry: LibraryEntry::could_not_open(&name, &reason, ""),
                publication: None,
                issues: Vec::new(),
            })
        }));
    }
    ui.store.splice(0, ui.store.n_items(), &items);
    fill_index(&ui, &index);
    refresh_header(&ui, &state);

    let page = SearchPage::of(
        &state.text,
        found,
        &ui.memory.borrow(),
        publications.is_empty(),
    );
    let searching = state.results_take_over();
    let offered = if searching && state.text.trim().is_empty() {
        crate::library::search::suggestions(&publications, &progress)
    } else {
        Vec::new()
    };
    let show_results = ui.search_ui.show(&page, searching, offered);
    let child = if searching {
        if show_results { "library" } else { "search" }
    } else {
        match state.destination {
            Destination::Home => "home",
            Destination::Downloads | Destination::Downloaded => "downloads",
            _ => "library",
        }
    };
    ui.stack.set_visible_child_name(child);
}

fn fill_index(ui: &Rc<LibraryUi>, index: &[shelf::IndexEntry]) {
    let weak = Rc::downgrade(ui);
    library_cells::fill_index(
        &ui.rail,
        index,
        Rc::new(move |position| {
            if let Some(ui) = weak.upgrade() {
                let flags = gtk::ListScrollFlags::FOCUS;
                if ui.layouts.visible_child_name().as_deref() == Some("list") {
                    ui.list.scroll_to(position, flags, None);
                } else {
                    ui.grid.scroll_to(position, flags, None);
                }
            }
        }),
    );
}

/// The header bar's buttons say what they hold: the filters active, the ordering, and
/// one entry per folder in the Filter menu.
fn refresh_header(ui: &LibraryUi, state: &QueryState) {
    ui.filter_button
        .set_label(&library_menus::filter_label(state));
    ui.filter_button
        .update_property(&[gtk::accessible::Property::Label(
            &library_menus::filter_description(state),
        )]);
    ui.sort_button
        .set_label(&library_menus::sort_label(state.sort));
}

/// The folder rows: each folder by name, a way into the library narrowed to it. The
/// state of a folder and what can be done about it live in Settings, under Libraries
/// (`navigation-shell`, Reaching a source's configuration).
fn refresh_folders(shared: &Shared, ui: &Rc<LibraryUi>) {
    let chosen = ui.state.borrow().filters.source.clone();
    ui.folders.remove_all();
    for (name, access, _) in shared.sources.summary() {
        let title = gtk::Label::builder()
            .label(&name)
            .xalign(0.0)
            .ellipsize(gtk::pango::EllipsizeMode::Middle)
            .build();
        library_views::set_class(&title, "dimmed", access != Access::Readable);
        ui.folders.append(&title);
        if chosen.as_deref() == Some(name.as_str())
            && let Some(row) = ui.folders.last_child().and_downcast::<gtk::ListBoxRow>()
        {
            ui.folders.select_row(Some(&row));
        }
    }
    // The network libraries follow the folders: grey when unreachable or signed out.
    for entry in shared.remote.entries.borrow().iter() {
        let line = gtk::Box::builder().spacing(6).build();
        line.append(&gtk::Image::from_icon_name("network-server-symbolic"));
        let title = gtk::Label::builder()
            .label(&entry.record.name)
            .xalign(0.0)
            .ellipsize(gtk::pango::EllipsizeMode::Middle)
            .build();
        library_views::set_class(&title, "dimmed", entry.grey.is_some());
        line.append(&title);
        ui.folders.append(&line);
    }
}
