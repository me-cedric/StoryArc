//! One reader window: one publication, its own page, chrome, full-screen and idle state
//! (tasks 2.25, 2.27, 2.29, 2.32, 2.34). The rules are in `keys.rs`, `progress.rs`,
//! `fullscreen.rs`, `idle.rs` and `publication.rs`; this file hands GTK's events to them
//! and their answers back to GTK.
//!
//! The core decodes no page yet (task 2.5), so the page area shows the page's number
//! and name. Zoom, pan, spreads and drag to turn (2.28) wait for the decoder.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::{Duration, Instant};

use adw::prelude::*;
use gtk::{gdk, gio, glib};

use crate::app::{ReaderHandle, Shared};
use crate::commands::Scope;
use crate::fullscreen::FullScreen;
use crate::idle::IdleHold;
use crate::keys::{
    self, ChromeIdle, ClickAction, Modifiers, PageAction, PageModel, WheelAccumulator,
};
use crate::menus;
use crate::progress::ProgressWriter;
use crate::publication::{Availability, Publication};
use crate::session::{self, FileProgressStore, LOG_DOMAIN};
use crate::settings::Preferences;
use crate::strings::tr_args;
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH, WindowState};

/// How often the window looks at its timers: the chrome, the write clock, full screen.
const TICK: Duration = Duration::from_millis(250);
/// How many ticks between two looks at whether the file is still there.
const REACHABLE_EVERY: u32 = 8;

const IMPLEMENTED: [&str; 6] = [
    "win.next-page",
    "win.previous-page",
    "win.first-page",
    "win.last-page",
    "win.fullscreen",
    "win.toggle-controls",
];

pub struct Reader {
    window: adw::ApplicationWindow,
    publication: Publication,
    pages: Cell<PageModel>,
    progress: RefCell<ProgressWriter<FileProgressStore>>,
    chrome: RefCell<ChromeIdle>,
    wheel: RefCell<WheelAccumulator>,
    full_screen: Cell<FullScreen>,
    idle: RefCell<IdleHold>,
    availability: Cell<Availability>,
    preferences: RefCell<Preferences>,
    ticks: Cell<u32>,
    toolbar: adw::ToolbarView,
    title: gtk::Label,
    detail: gtk::Label,
    counter: gtk::Label,
    banner: adw::Banner,
    menu: gio::Menu,
}

impl Reader {
    /// The page the reader is on, counted from zero.
    pub fn page(&self) -> u32 {
        self.pages.get().page
    }

    /// Writes the pending position now, before the window closes or the app quits. A
    /// failure is logged and never held against the window or the app.
    pub fn flush(&self) {
        if let Err(failure) = self.progress.borrow_mut().flush() {
            glib::g_warning!(LOG_DOMAIN, "{failure}");
        }
    }

    /// A preference changed while this reader is open: it applies at once.
    pub fn preferences_changed(&self, preferences: &Preferences) {
        *self.preferences.borrow_mut() = preferences.clone();
        self.refresh();
    }

    fn turn(&self, action: PageAction) {
        let Some(next) = self.pages.get().apply(action) else {
            return;
        };
        self.go_to(next);
    }

    fn go_to(&self, next: PageModel) {
        self.pages.set(next);
        self.progress.borrow_mut().turned(next.page, Instant::now());
        self.refresh();
    }

    fn refresh(&self) {
        let pages = self.pages.get();
        let preferences = self.preferences.borrow();
        self.title
            .set_label(&format!("Page {}", pages.label_number()));
        let name = self
            .publication
            .page_names
            .get(pages.page as usize)
            .map_or("", String::as_str);
        self.detail.set_label(&format!(
            "{name}\n{} · {}",
            preferences.layout.label().1,
            preferences.fit.label().1
        ));
        self.counter.set_label(&tr_args(
            "reader.pageOfCount",
            "%d of %d",
            &[&pages.label_number(), &pages.count],
        ));
    }

    /// Shows or hides the chrome and the pointer as the idle model says.
    fn apply_chrome(&self) {
        let visible = self.chrome.borrow().is_visible();
        self.toolbar.set_reveal_top_bars(visible);
        self.toolbar.set_reveal_bottom_bars(visible);
        self.window
            .set_cursor_from_name(if visible { None } else { Some("none") });
    }

    fn pointer_moved(&self) {
        self.chrome.borrow_mut().pointer_moved(Instant::now());
        self.apply_chrome();
    }

    fn toggle_chrome(&self) {
        self.chrome.borrow_mut().toggle(Instant::now());
        self.apply_chrome();
    }

    fn toggle_full_screen(&self) {
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
    fn tick(&self) -> bool {
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

/// Opens a reader window for `publication`. `page` and `state` come from the session
/// file on a restore, or are the first page and the default size for a new window.
pub fn open(
    shared: &Shared,
    publication: Publication,
    page: u32,
    state: Option<WindowState>,
) -> adw::ApplicationWindow {
    let app = shared.application();
    let menu = gio::Menu::new();
    menus::reader_menu(&menu, None);

    let title = gtk::Label::builder().css_classes(["title-1"]).build();
    let detail = gtk::Label::builder()
        .css_classes(["dimmed"])
        .justify(gtk::Justification::Center)
        .build();
    let page_box = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .valign(gtk::Align::Center)
        .halign(gtk::Align::Center)
        .build();
    page_box.append(&title);
    page_box.append(&detail);
    let content = gtk::Box::builder()
        .css_classes(["storyarc-reader"])
        .hexpand(true)
        .vexpand(true)
        .build();
    content.append(&page_box);
    page_box.set_hexpand(true);

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

    let reader = Rc::new(Reader {
        window: window.clone(),
        pages: Cell::new(PageModel::new(page, publication.page_count)),
        progress: RefCell::new(ProgressWriter::new(
            FileProgressStore,
            publication.id.clone(),
        )),
        chrome: RefCell::default(),
        wheel: RefCell::default(),
        full_screen: Cell::default(),
        idle: RefCell::default(),
        availability: Cell::default(),
        preferences: RefCell::new(shared.preferences()),
        ticks: Cell::new(0),
        toolbar,
        title,
        detail,
        counter,
        banner,
        menu,
        publication: publication.clone(),
    });
    reader.refresh();

    install_actions(&window, &reader);
    install_pointer(&content, &window, &reader);
    install_keys(&window, &reader, shared);
    install_idle_inhibit(&window, &reader, &app);
    keep_chrome_while_menu_is_open(&menu_button, &reader);
    install_timer(&reader, shared);

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

fn install_actions(window: &adw::ApplicationWindow, reader: &Rc<Reader>) {
    menus::add_disabled_actions(window, Scope::Reader, &IMPLEMENTED);
    let pages = [
        ("next-page", PageAction::Next),
        ("previous-page", PageAction::Previous),
        ("first-page", PageAction::First),
        ("last-page", PageAction::Last),
    ];
    for (name, action) in pages {
        let simple = gio::SimpleAction::new(name, None);
        let weak = Rc::downgrade(reader);
        simple.connect_activate(move |_, _| {
            if let Some(reader) = weak.upgrade() {
                reader.turn(action);
            }
        });
        window.add_action(&simple);
    }
    let weak = Rc::downgrade(reader);
    let full = gio::SimpleAction::new("fullscreen", None);
    full.connect_activate(move |_, _| {
        if let Some(reader) = weak.upgrade() {
            reader.toggle_full_screen();
        }
    });
    window.add_action(&full);
    let weak = Rc::downgrade(reader);
    let controls = gio::SimpleAction::new("toggle-controls", None);
    controls.connect_activate(move |_, _| {
        if let Some(reader) = weak.upgrade() {
            reader.toggle_chrome();
        }
    });
    window.add_action(&controls);
}

/// Pointer reading (task 2.27): motion reveals the chrome, the edges turn pages, the
/// middle toggles the chrome, the wheel turns pages a notch at a time and a right click
/// opens the reader menu.
fn install_pointer(content: &gtk::Box, window: &adw::ApplicationWindow, reader: &Rc<Reader>) {
    let motion = gtk::EventControllerMotion::new();
    let weak = Rc::downgrade(reader);
    motion.connect_motion(move |_, _, _| {
        if let Some(reader) = weak.upgrade() {
            reader.pointer_moved();
        }
    });
    window.add_controller(motion);

    let click = gtk::GestureClick::builder()
        .button(gdk::BUTTON_PRIMARY)
        .build();
    let weak = Rc::downgrade(reader);
    click.connect_released(move |gesture, _, x, _| {
        let (Some(reader), Some(widget)) = (weak.upgrade(), gesture.widget()) else {
            return;
        };
        let zones_on = reader.preferences.borrow().click_zones;
        let direction = reader.publication.direction;
        match keys::click_action(
            keys::zone(x, f64::from(widget.width())),
            direction,
            zones_on,
        ) {
            ClickAction::Turn(action) => reader.turn(action),
            ClickAction::ToggleChrome => reader.toggle_chrome(),
        }
    });
    content.add_controller(click);

    let context = gtk::GestureClick::builder()
        .button(gdk::BUTTON_SECONDARY)
        .build();
    let popover = gtk::PopoverMenu::from_model(Some(&reader.menu));
    popover.set_parent(content);
    popover.set_has_arrow(false);
    context.connect_pressed(move |_, _, x, y| {
        popover.set_pointing_to(Some(&gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover.popup();
    });
    content.add_controller(context);

    let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
    let weak = Rc::downgrade(reader);
    scroll.connect_scroll(move |_, _, dy| {
        let Some(reader) = weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        let action = reader.wheel.borrow_mut().scrolled(dy);
        if let Some(action) = action {
            reader.turn(action);
        }
        glib::Propagation::Stop
    });
    content.add_controller(scroll);
}

/// The keys of the table that have no modifier: they are not application accelerators,
/// so a text field keeps them, and the reader maps them itself.
fn install_keys(window: &adw::ApplicationWindow, reader: &Rc<Reader>, _shared: &Shared) {
    let controller = gtk::EventControllerKey::new();
    let weak = Rc::downgrade(reader);
    controller.connect_key_pressed(move |_, key, _, state| {
        let Some(reader) = weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        let focused_text = gtk::prelude::GtkWindowExt::focus(&reader.window)
            .is_some_and(|widget| widget.is::<gtk::Editable>() || widget.is::<gtk::Text>());
        let mapped = match key {
            gdk::Key::Left => keys::Key::Left,
            gdk::Key::Right => keys::Key::Right,
            gdk::Key::Up => keys::Key::Up,
            gdk::Key::Down => keys::Key::Down,
            gdk::Key::space => keys::Key::Space,
            gdk::Key::Page_Up => keys::Key::PageUp,
            gdk::Key::Page_Down => keys::Key::PageDown,
            gdk::Key::Home => keys::Key::Home,
            gdk::Key::End => keys::Key::End,
            gdk::Key::Escape => keys::Key::Escape,
            _ => keys::Key::Other,
        };
        if mapped == keys::Key::Escape && !focused_text {
            if reader.full_screen.get().leaves_on_escape() {
                reader.toggle_full_screen();
                return glib::Propagation::Stop;
            }
            return glib::Propagation::Proceed;
        }
        let modifiers = Modifiers {
            shift: state.contains(gdk::ModifierType::SHIFT_MASK),
            control: state.contains(gdk::ModifierType::CONTROL_MASK),
            alt: state.contains(gdk::ModifierType::ALT_MASK),
        };
        match keys::page_action(
            mapped,
            modifiers,
            reader.publication.direction,
            focused_text,
        ) {
            Some(action) => {
                reader.turn(action);
                glib::Propagation::Stop
            }
            None => glib::Propagation::Proceed,
        }
    });
    window.add_controller(controller);
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
        }
        glib::ControlFlow::Continue
    });
}
