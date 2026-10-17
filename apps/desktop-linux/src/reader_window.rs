//! One reader window: one publication, its own page, chrome, full-screen and idle state
//! (tasks 2.25, 2.27, 2.28, 2.29, 2.32, 2.34). The rules are in `keys.rs`, `reading/`,
//! `progress.rs`, `fullscreen.rs`, `idle.rs` and `publication.rs`; this file hands GTK's
//! events to them and their answers back to GTK. Pointer and key input is
//! `reader_input.rs`.
//!
//! Pages decode on a worker through the core (`OpenPublication::decode_page`); the window
//! keeps the few around the reader's place and draws a quiet placeholder until each lands.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant};

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::{ReadingDirection, SpreadLayout};

use crate::app::{App, ReaderHandle, Shared};
use crate::commands::Scope;
use crate::fullscreen::FullScreen;
use crate::idle::IdleHold;
use crate::keys::{ChromeIdle, PageAction, PageModel, WheelAccumulator};
use crate::menus;
use crate::page_view::{PLACEHOLDER_SIZE, PageImage, PageView};
use crate::progress::ProgressWriter;
use crate::publication::{self, Availability, Publication};
use crate::reader_input;
use crate::reading::end::{self, Turned};
use crate::reading::{Size, SpreadDecision, ZoomModel};
use crate::session::{self, CoreProgress, LOG_DOMAIN};
use crate::settings::{Fit, Preferences};
use crate::strings::{tr, tr_args};
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH, WindowState};

/// How often the window looks at its timers: the chrome, the write clock, full screen,
/// and whether a resize changed the number of pages on screen.
const TICK: Duration = Duration::from_millis(250);
/// How many ticks between two looks at whether the file is still there.
const REACHABLE_EVERY: u32 = 8;
/// Pages kept decoded on either side of the reader's place.
const KEEP_AROUND: usize = 4;

const IMPLEMENTED: [&str; 11] = [
    "win.next-page",
    "win.previous-page",
    "win.first-page",
    "win.last-page",
    "win.fullscreen",
    "win.toggle-controls",
    "win.zoom-in",
    "win.zoom-out",
    "win.fit-page",
    "win.fit-width",
    "win.original-size",
];

pub struct Reader {
    pub(crate) window: adw::ApplicationWindow,
    pub(crate) publication: Publication,
    pages: Cell<PageModel>,
    progress: RefCell<ProgressWriter<CoreProgress>>,
    pub(crate) chrome: RefCell<ChromeIdle>,
    pub(crate) wheel: RefCell<WheelAccumulator>,
    pub(crate) full_screen: Cell<FullScreen>,
    idle: RefCell<IdleHold>,
    availability: Cell<Availability>,
    pub(crate) preferences: RefCell<Preferences>,
    ticks: Cell<u32>,
    toolbar: adw::ToolbarView,
    pub(crate) page_view: PageView,
    note: gtk::Label,
    counter: gtk::Label,
    banner: adw::Banner,
    pub(crate) menu: gio::Menu,
    decoded: RefCell<HashMap<usize, PageImage>>,
    requested: RefCell<HashSet<usize>>,
    wide: RefCell<HashSet<usize>>,
    layout: RefCell<SpreadLayout>,
    pairs: Cell<bool>,
    /// The direction the reader reads in now: the publication's own, or the one chosen.
    direction: Cell<ReadingDirection>,
    /// Whether the end screen stands in place of the page.
    at_end: Cell<bool>,
    /// The page surface and the end screen.
    content: gtk::Stack,
    end: EndScreen,
    shared: Weak<App>,
}

/// The end screen's widgets: what it says and the next issue it offers.
struct EndScreen {
    page: adw::StatusPage,
    next: gtk::Button,
    /// The next issue the button opens, while there is one.
    target: RefCell<Option<storyarc_core::domain::Publication>>,
}

impl Reader {
    /// The page the reader is on, counted from zero.
    pub fn page(&self) -> u32 {
        self.pages.get().page
    }

    pub(crate) fn direction(&self) -> ReadingDirection {
        self.direction.get()
    }

    pub(crate) fn right_to_left(&self) -> bool {
        self.direction() == ReadingDirection::RightToLeft
    }

    /// The reader chose a direction: it applies now, on the same page, and is
    /// remembered for the series (`comic-reader`, Overriding direction).
    pub(crate) fn set_direction(self: &Rc<Self>, direction: ReadingDirection) {
        if direction == self.direction.get() {
            return;
        }
        self.direction.set(direction);
        if let Some(shared) = self.shared.upgrade() {
            shared.choose_direction(&self.publication.record, direction);
        }
        self.show_screen();
    }

    /// Writes the pending position now, before the window closes or the app quits. A
    /// failure is logged and never held against the window or the app.
    pub fn flush(&self) {
        if let Err(failure) = self.progress.borrow_mut().flush() {
            glib::g_warning!(LOG_DOMAIN, "{failure}");
        }
    }

    /// A preference changed while this reader is open: it applies at once.
    pub fn preferences_changed(self: &Rc<Self>, preferences: &Preferences) {
        let fit_changed = self.preferences.borrow().fit != preferences.fit;
        *self.preferences.borrow_mut() = preferences.clone();
        if fit_changed {
            self.set_fit(preferences.fit);
        }
        self.relayout();
    }

    /// Turns one screen: a pair turns two pages, a lone page one. The zoom carries over.
    pub(crate) fn turn(self: &Rc<Self>, action: PageAction) {
        let current = self.pages.get();
        let outcome = end::turned(
            &self.layout.borrow(),
            current.page as usize,
            self.at_end.get(),
            action,
        );
        let landing = match outcome {
            Turned::Stays => return,
            Turned::End => {
                self.show_end();
                return;
            }
            Turned::Page(landing) => landing,
        };
        self.leave_end();
        let next = PageModel::new(u32::try_from(landing).unwrap_or(0), current.count);
        self.pages.set(next);
        self.progress.borrow_mut().turned(next.page, Instant::now());
        let zoom = self.page_view.zoom().turned(
            self.right_to_left(),
            self.page_view.fitted(),
            self.page_view.viewport(),
        );
        self.show_screen();
        self.page_view.set_zoom(self.opening_zoom(zoom));
    }

    /// Turned past the last page: the publication is finished, its last page written at
    /// once, and the end screen offers the next issue of the series when the library
    /// holds one (`comic-reader`, Reaching the end).
    fn show_end(&self) {
        let count = self.pages.get().count;
        {
            let mut progress = self.progress.borrow_mut();
            progress.turned(count.saturating_sub(1), Instant::now());
            if let Err(failure) = progress.flush() {
                glib::g_warning!(LOG_DOMAIN, "{failure}");
            }
        }
        let library = self
            .shared
            .upgrade()
            .map(|shared| shared.sources.publications())
            .unwrap_or_default();
        let next = end::next_in_series(&self.publication.record, &library).cloned();
        match &next {
            Some(next) => {
                self.end.next.set_label(&tr_args(
                    "reader.end.next %s",
                    "Next: %s",
                    &[&next.display_title],
                ));
                self.end.next.set_visible(true);
            }
            None => self.end.next.set_visible(false),
        }
        *self.end.target.borrow_mut() = next;
        self.at_end.set(true);
        self.content.set_visible_child_name("end");
        self.counter
            .set_label(&tr("reader.end.finished", "Finished"));
        self.chrome.borrow_mut().pointer_moved(Instant::now());
        self.apply_chrome();
        if let Some(shared) = self.shared.upgrade() {
            shared.progress_changed();
        }
    }

    fn leave_end(&self) {
        if self.at_end.replace(false) {
            self.content.set_visible_child_name("page");
        }
    }

    /// A fitted page that overflows the window (fit to width, original size) opens at its
    /// top rather than its middle.
    fn opening_zoom(&self, zoom: ZoomModel) -> ZoomModel {
        if zoom.is_zoomed() {
            return zoom;
        }
        zoom.panned(
            Size::new(0.0, f64::MAX / 4.0),
            self.page_view.fitted(),
            self.page_view.viewport(),
        )
    }

    pub(crate) fn set_zoom(&self, zoom: ZoomModel) {
        let settled = zoom.settled(self.page_view.fitted(), self.page_view.viewport());
        self.page_view.set_zoom(settled);
    }

    pub(crate) fn set_fit(&self, fit: Fit) {
        self.page_view.set_fit(fit);
        self.page_view
            .set_zoom(self.opening_zoom(ZoomModel::default()));
    }

    /// Recomputes the screens for the window's shape, keeping the reader on the same page.
    fn relayout(self: &Rc<Self>) {
        let pairs =
            SpreadDecision::pairs_for(self.preferences.borrow().layout, self.page_view.viewport());
        self.pairs.set(pairs);
        *self.layout.borrow_mut() = SpreadDecision::layout(
            self.publication.page_count as usize,
            &self.wide.borrow(),
            pairs,
            true,
        );
        self.show_screen();
    }

    /// Puts the current screen's pages on the page view, asks for the ones not decoded
    /// yet and the next screen's, and forgets pages far from the reader.
    fn show_screen(self: &Rc<Self>) {
        let page = self.pages.get();
        let (on_screen, ahead) = {
            let layout = self.layout.borrow();
            let slot = layout.slot_containing(page.page as usize);
            let on_screen = layout
                .slot(slot)
                .map(|spread| SpreadDecision::screen_order(spread, self.right_to_left()))
                .unwrap_or_default();
            let ahead: Vec<usize> = [slot + 1, slot.wrapping_sub(1)]
                .into_iter()
                .filter_map(|index| layout.slot(index))
                .flat_map(|spread| spread.pages())
                .collect();
            (on_screen, ahead)
        };
        let images: Vec<PageImage> = on_screen.iter().map(|index| self.image(*index)).collect();
        let description = tr_args(
            "reader.pageOfCount",
            "%d of %d",
            &[&page.label_number(), &page.count],
        );
        self.page_view.set_pages(images, &description);
        if !self.at_end.get() {
            self.counter.set_label(&description);
        }
        let failure = self.page_view.failure();
        self.note.set_label(failure.as_deref().unwrap_or_default());
        self.note.set_visible(failure.is_some());
        for index in on_screen.iter().chain(&ahead) {
            self.request(*index);
        }
        self.forget_far_pages(page.page as usize);
    }

    /// What the view draws for a page now: its pixels, or a placeholder of the shape its
    /// neighbours suggest.
    fn image(&self, index: usize) -> PageImage {
        if let Some(image) = self.decoded.borrow().get(&index) {
            return image.clone();
        }
        let (width, height) = PLACEHOLDER_SIZE;
        PageImage::Pending { width, height }
    }

    fn request(self: &Rc<Self>, index: usize) {
        if index >= self.publication.page_count as usize
            || self.decoded.borrow().contains_key(&index)
            || !self.requested.borrow_mut().insert(index)
        {
            return;
        }
        let publication = self.publication.clone();
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let decoded = gio::spawn_blocking(move || publication.decode(index)).await;
            let Some(reader) = weak.upgrade() else {
                return;
            };
            reader.requested.borrow_mut().remove(&index);
            let image = match decoded {
                Ok(Ok(page)) => {
                    if publication::is_wide(page.width, page.height) {
                        reader.wide.borrow_mut().insert(index);
                    }
                    PageImage::Ready(texture(page))
                }
                Ok(Err(reason)) => {
                    let (width, height) = PLACEHOLDER_SIZE;
                    PageImage::Failed {
                        width,
                        height,
                        reason,
                    }
                }
                Err(_) => return,
            };
            reader.decoded.borrow_mut().insert(index, image);
            reader.relayout();
        });
    }

    fn forget_far_pages(&self, page: usize) {
        let near = |index: &usize| index.abs_diff(page) <= KEEP_AROUND * 2;
        self.decoded.borrow_mut().retain(|index, _| near(index));
    }

    /// Shows or hides the chrome and the pointer as the idle model says.
    fn apply_chrome(&self) {
        let visible = self.chrome.borrow().is_visible();
        self.toolbar.set_reveal_top_bars(visible);
        self.toolbar.set_reveal_bottom_bars(visible);
        self.window
            .set_cursor_from_name(if visible { None } else { Some("none") });
    }

    pub(crate) fn pointer_moved(&self) {
        self.chrome.borrow_mut().pointer_moved(Instant::now());
        self.apply_chrome();
    }

    pub(crate) fn toggle_chrome(&self) {
        self.chrome.borrow_mut().toggle(Instant::now());
        self.apply_chrome();
    }

    pub(crate) fn toggle_full_screen(&self) {
        let next = self.full_screen.get().toggle(Instant::now());
        self.full_screen.set(next);
        self.window
            .set_fullscreened(matches!(next, FullScreen::Asking(_)));
        self.show_full_screen_state();
    }

    fn show_full_screen_state(&self) {
        let state = self.full_screen.get();
        if let Some(action) = self
            .window
            .lookup_action("fullscreen")
            .and_downcast::<gio::SimpleAction>()
        {
            action.set_enabled(state.is_available());
        }
        menus::reader_menu(&self.menu, state.note());
    }

    /// One look at the timers. Returns whether the session file should be rewritten.
    fn tick(self: &Rc<Self>) -> bool {
        let now = Instant::now();
        if self.chrome.borrow_mut().should_hide(now) {
            self.apply_chrome();
        }
        let observed = self
            .full_screen
            .get()
            .observed(self.window.is_fullscreen(), now);
        if observed != self.full_screen.get() {
            self.full_screen.set(observed);
            self.show_full_screen_state();
        }
        let pairs =
            SpreadDecision::pairs_for(self.preferences.borrow().layout, self.page_view.viewport());
        if pairs != self.pairs.get() {
            self.relayout();
        }
        let zoom = self.page_view.zoom();
        let settled = zoom.settled(self.page_view.fitted(), self.page_view.viewport());
        if settled != zoom {
            self.page_view.set_zoom(settled);
        }
        let ticks = self.ticks.get() + 1;
        self.ticks.set(ticks);
        if ticks.is_multiple_of(REACHABLE_EVERY) {
            let now_available = Availability::of(&self.publication.id, Publication::is_reachable);
            if now_available != self.availability.get() {
                self.availability.set(now_available);
                self.banner
                    .set_title(now_available.note().unwrap_or_default());
                self.banner.set_revealed(now_available.note().is_some());
            }
        }
        self.progress.borrow_mut().tick(now)
    }
}

use crate::covers::texture;

/// Opens a reader window for `publication`. `page` and `state` come from the session
/// file on a restore, or are the reader's last place and the default size for a new one.
pub fn open(
    shared: &Shared,
    publication: Publication,
    page: u32,
    state: Option<WindowState>,
) -> adw::ApplicationWindow {
    let app = shared.application();
    let menu = gio::Menu::new();
    menus::reader_menu(&menu, None);

    let page_view = PageView::default();
    page_view.set_hexpand(true);
    page_view.set_vexpand(true);
    let note = gtk::Label::builder()
        .css_classes(["dimmed", "caption"])
        .valign(gtk::Align::End)
        .margin_bottom(24)
        .wrap(true)
        .visible(false)
        .build();
    let surface = gtk::Overlay::builder()
        .css_classes(["storyarc-reader"])
        .child(&page_view)
        .build();
    surface.add_overlay(&note);
    let end = end_screen();
    let content = gtk::Stack::builder()
        .transition_type(gtk::StackTransitionType::Crossfade)
        .build();
    content.add_named(&surface, Some("page"));
    content.add_named(&end.page, Some("end"));

    let counter = gtk::Label::builder()
        .css_classes(["caption", "dimmed"])
        .ellipsize(gtk::pango::EllipsizeMode::End)
        .build();
    let bottom = adw::HeaderBar::builder()
        .show_start_title_buttons(false)
        .show_end_title_buttons(false)
        .title_widget(&counter)
        .build();

    let menu_button = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .tooltip_text("Reader menu")
        .menu_model(&menu)
        .build();
    let header = adw::HeaderBar::new();
    header.pack_end(&menu_button);
    header.set_title_widget(Some(&adw::WindowTitle::new(&publication.title, "")));

    let banner = adw::Banner::builder().build();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.add_top_bar(&banner);
    toolbar.add_bottom_bar(&bottom);
    toolbar.set_content(Some(&content));

    let window = adw::ApplicationWindow::builder()
        .application(&app)
        .title(&publication.title)
        .content(&toolbar)
        .build();
    window.set_size_request(MIN_WIDTH, MIN_HEIGHT);
    session::apply(&window, &state.unwrap_or_default());

    let preferences = shared.preferences();
    let progress = CoreProgress::new(
        shared.progress_store(),
        publication.record.identity.clone(),
        publication.page_count,
    );
    let reader = Rc::new(Reader {
        window: window.clone(),
        pages: Cell::new(PageModel::new(page, publication.page_count)),
        progress: RefCell::new(ProgressWriter::new(progress, publication.id.clone())),
        chrome: RefCell::default(),
        wheel: RefCell::default(),
        full_screen: Cell::default(),
        idle: RefCell::default(),
        availability: Cell::default(),
        preferences: RefCell::new(preferences.clone()),
        ticks: Cell::new(0),
        toolbar,
        page_view,
        note,
        counter,
        banner,
        menu,
        decoded: RefCell::default(),
        requested: RefCell::default(),
        wide: RefCell::new(publication.declared_spreads.clone()),
        layout: RefCell::new(SpreadLayout::single(publication.page_count as usize)),
        pairs: Cell::new(false),
        direction: Cell::new(shared.direction_for(&publication.record)),
        at_end: Cell::new(false),
        content,
        end,
        shared: Rc::downgrade(shared),
        publication: publication.clone(),
    });
    install_end_screen(&reader);
    reader.page_view.set_fit(preferences.fit);
    reader.relayout();

    install_actions(&window, &reader);
    reader_input::install_pointer(&reader);
    reader_input::install_keys(&reader);
    install_idle_inhibit(&window, &reader, &app);
    keep_chrome_while_menu_is_open(&menu_button, &reader);
    install_timer(&reader, shared);
    crate::launch::install_drop(window.upcast_ref(), shared);

    let weak_shared = Rc::downgrade(shared);
    let weak_reader = Rc::downgrade(&reader);
    let app = app.clone();
    window.connect_close_request(move |_| {
        if let Some(reader) = weak_reader.upgrade() {
            reader.flush();
            reader
                .idle
                .borrow_mut()
                .release(|cookie| app.uninhibit(cookie));
            if let Some(shared) = weak_shared.upgrade() {
                // A window closed by hand leaves the session; one closed by Quit stays in it.
                if !shared.quitting.get() {
                    shared.forget_reader(&reader.publication.id);
                    shared.save_session();
                    shared.progress_changed();
                }
            }
        }
        glib::Propagation::Proceed
    });

    shared.readers.borrow_mut().push(ReaderHandle {
        publication: publication.id.clone(),
        window: window.clone(),
        reader,
    });
    window.present();
    window
}

/// The end screen: it says the publication is finished and offers the next issue, the
/// last page again, and the library. Built once per window, filled when it is reached.
fn end_screen() -> EndScreen {
    let next = gtk::Button::builder()
        .css_classes(["pill", "suggested-action"])
        .halign(gtk::Align::Center)
        .visible(false)
        .build();
    let back = gtk::Button::builder()
        .label(tr("reader.end.back", "Back to the last page"))
        .css_classes(["pill"])
        .halign(gtk::Align::Center)
        .action_name("win.last-page")
        .build();
    let library = gtk::Button::builder()
        .label(tr("reader.end.library", "Library"))
        .css_classes(["pill"])
        .halign(gtk::Align::Center)
        .action_name("app.library")
        .build();
    let actions = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .halign(gtk::Align::Center)
        .build();
    actions.append(&next);
    actions.append(&back);
    actions.append(&library);
    let page = adw::StatusPage::builder()
        .icon_name("object-select-symbolic")
        .title(tr("reader.end.finished", "Finished"))
        .child(&actions)
        .css_classes(["storyarc-reader"])
        .build();
    EndScreen {
        page,
        next,
        target: RefCell::default(),
    }
}

/// The next issue opens in its own reader, as a cover in the library would open it.
fn install_end_screen(reader: &Rc<Reader>) {
    let weak = Rc::downgrade(reader);
    reader.end.next.connect_clicked(move |_| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        let target = reader.end.target.borrow().clone();
        let (Some(target), Some(shared)) = (target, reader.shared.upgrade()) else {
            return;
        };
        if let Some(path) = target.identity.normalized_path.as_deref()
            && let Err(reason) =
                crate::launch::open_publication(&shared, std::path::Path::new(path))
        {
            shared.toast(&reason);
        }
    });
}

fn install_actions(window: &adw::ApplicationWindow, reader: &Rc<Reader>) {
    menus::add_disabled_actions(window, Scope::Reader, &IMPLEMENTED);
    let direction = gio::SimpleAction::new_stateful(
        "reading-direction",
        Some(glib::VariantTy::STRING),
        &direction_name(reader.direction()).to_variant(),
    );
    let weak = Rc::downgrade(reader);
    direction.connect_activate(move |action, target| {
        let (Some(reader), Some(name)) = (
            weak.upgrade(),
            target.and_then(|target| target.get::<String>()),
        ) else {
            return;
        };
        let chosen = if name == "rtl" {
            ReadingDirection::RightToLeft
        } else {
            ReadingDirection::LeftToRight
        };
        action.set_state(&name.to_variant());
        reader.set_direction(chosen);
    });
    window.add_action(&direction);
    let pages = [
        ("next-page", PageAction::Next),
        ("previous-page", PageAction::Previous),
        ("first-page", PageAction::First),
        ("last-page", PageAction::Last),
    ];
    for (name, action) in pages {
        add(window, reader, name, move |reader| reader.turn(action));
    }
    add(window, reader, "fullscreen", |reader| {
        reader.toggle_full_screen();
    });
    add(window, reader, "toggle-controls", |reader| {
        reader.toggle_chrome();
    });
    add(window, reader, "zoom-in", |reader| {
        reader.set_zoom(reader.page_view.zoom().zoomed_in());
    });
    add(window, reader, "zoom-out", |reader| {
        reader.set_zoom(reader.page_view.zoom().zoomed_out());
    });
    add(window, reader, "fit-page", |reader| {
        reader.set_fit(Fit::Page)
    });
    add(window, reader, "fit-width", |reader| {
        reader.set_fit(Fit::Width);
    });
    add(window, reader, "original-size", |reader| {
        reader.set_fit(Fit::Original);
    });
}

fn direction_name(direction: ReadingDirection) -> &'static str {
    match direction {
        ReadingDirection::RightToLeft => "rtl",
        ReadingDirection::LeftToRight => "ltr",
    }
}

fn add(
    window: &adw::ApplicationWindow,
    reader: &Rc<Reader>,
    name: &str,
    activate: impl Fn(&Rc<Reader>) + 'static,
) {
    let simple = gio::SimpleAction::new(name, None);
    let weak = Rc::downgrade(reader);
    simple.connect_activate(move |_, _| {
        if let Some(reader) = weak.upgrade() {
            activate(&reader);
        }
    });
    window.add_action(&simple);
}

/// Holds the display awake while this window is the active one; silent on a refusal.
fn install_idle_inhibit(
    window: &adw::ApplicationWindow,
    reader: &Rc<Reader>,
    app: &adw::Application,
) {
    let weak = Rc::downgrade(reader);
    let app = app.clone();
    window.connect_is_active_notify(move |window| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        if window.is_active() {
            reader.idle.borrow_mut().hold(|| {
                app.inhibit(
                    Some(window),
                    gtk::ApplicationInhibitFlags::IDLE,
                    Some("Reading"),
                )
            });
        } else {
            reader
                .idle
                .borrow_mut()
                .release(|cookie| app.uninhibit(cookie));
        }
    });
}

/// An open menu holds the chrome, so it does not vanish under the pointer.
fn keep_chrome_while_menu_is_open(button: &gtk::MenuButton, reader: &Rc<Reader>) {
    if let Some(popover) = button.popover() {
        let weak = Rc::downgrade(reader);
        popover.connect_visible_notify(move |popover| {
            if let Some(reader) = weak.upgrade() {
                reader.chrome.borrow_mut().hold(popover.is_visible());
            }
        });
    }
}

fn install_timer(reader: &Rc<Reader>, shared: &Shared) {
    let weak = Rc::downgrade(reader);
    let weak_shared = Rc::downgrade(shared);
    glib::timeout_add_local(TICK, move || {
        let Some(reader) = weak.upgrade() else {
            return glib::ControlFlow::Break;
        };
        // A position that has just been written is the moment to rewrite the session
        // file, so a crash restores to this page.
        if reader.tick()
            && let Some(shared) = weak_shared.upgrade()
        {
            shared.save_session();
            shared.progress_changed();
        }
        glib::ControlFlow::Continue
    });
}
