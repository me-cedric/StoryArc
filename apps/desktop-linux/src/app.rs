//! What every window shares: the preferences, the theme, the system accent, the
//! library window and the open readers. One `Rc<App>` is made in `main` and cloned
//! into the closures that need it; the windows capture it weakly where they would
//! otherwise keep themselves alive.

use std::cell::{Cell, OnceCell, RefCell};
use std::rc::Rc;

use storyarc_core::domain::{self as library_record, ReadingDirection};
use storyarc_core::library;
use storyarc_core::portability::LibrarySnapshot;

use crate::library_window::LibraryUi;
use crate::opening::LaunchAction;
use crate::reader_window::Reader;
use crate::reading::adjust::Adjustments;
use crate::reading::direction::DirectionChoices;
use crate::reading::modes::{Mode, ModeChoice, ModeChoices};
use crate::session;
use crate::settings::{Layout, Preferences, Rgb};
use crate::sources::Sources;
use crate::theme::Theme;
use crate::windows::{Open, ReaderWindowState, SessionState};

pub type Shared = Rc<App>;

/// The library window's refresh: `true` for the whole library, `false` for Home only.
pub type LibraryRefresh = Box<dyn Fn(bool)>;

/// One open reader window and the state behind it.
pub struct ReaderHandle {
    pub publication: String,
    pub window: adw::ApplicationWindow,
    pub reader: Rc<Reader>,
}

#[derive(Default)]
pub struct App {
    preferences: RefCell<Preferences>,
    pub theme: OnceCell<Theme>,
    pub application: OnceCell<adw::Application>,
    /// The accent the settings portal reports, when it reports one.
    pub system_accent: Cell<Option<Rgb>>,
    pub library: RefCell<Option<adw::ApplicationWindow>>,
    pub readers: RefCell<Vec<ReaderHandle>>,
    /// The EPUB windows, by the path they read (task 4.10). Not in the session file yet.
    pub epub_windows: RefCell<Vec<(String, adw::ApplicationWindow)>>,
    /// The one player for audiobooks and read-aloud (task 4.14), made when first asked.
    player: RefCell<Option<Rc<crate::player::Player>>>,
    /// Set while Quit closes the windows, so each one keeps its place in the session.
    pub quitting: Cell<bool>,
    /// The publications whose window could not be restored at launch, for the library
    /// to name in grey.
    pub missing: RefCell<Vec<String>>,
    /// The one preferences dialog, so a second Control and comma presents it again.
    pub preferences_dialog: RefCell<Option<adw::PreferencesDialog>>,
    /// Where the library shows a file that could not be opened.
    pub library_toasts: RefCell<Option<adw::ToastOverlay>>,
    /// The core's progress store, opened once in startup.
    progress: OnceCell<Rc<library::ProgressStore>>,
    /// What the library window does when the folders or the reading positions changed.
    /// `true` rebuilds the grid as well as Home; `false` rebuilds Home only.
    pub on_library_changed: RefCell<Option<LibraryRefresh>>,
    /// The folder libraries.
    pub sources: Sources,
    /// The library window's widgets while it is open.
    pub library_ui: RefCell<Option<Rc<LibraryUi>>>,
    /// A static action of the desktop entry the first launch runs instead of restoring.
    pub launch_action: Cell<Option<LaunchAction>>,
    /// Whether the missing file chooser was named this session; it is named once.
    pub chooser_named: Cell<bool>,
    /// The reading directions the reader chose, by series or publication.
    directions: RefCell<DirectionChoices>,
    /// How pages change, by series, and where Scroll left each publication.
    pub modes: RefCell<ModeChoices>,
    /// The image adjustments, by series.
    pub adjustments: RefCell<Adjustments>,
    /// The core's network services, built on a worker at start.
    pub services: crate::services::Handle,
    /// The network libraries the reader added.
    pub remote: crate::network_ui::RemoteState,
    /// The download queue and its transfers.
    pub downloads: crate::downloads_ui::Downloads,
    /// What this device keeps of the library document: shelves, pins, deletions.
    pub document: RefCell<LibrarySnapshot>,
    /// A reading position changed since the sync document was last written.
    pub position_changed: Cell<bool>,
    /// Redraws the open shelf page from the document, when one is open.
    pub shelf_fill: RefCell<Option<Box<dyn Fn()>>>,
    /// The Sync row's grey line.
    pub sync_line: RefCell<String>,
    /// The shelf the library window shows, when one is open.
    pub open_shelf: RefCell<Option<crate::shelf_rules::ShelfRef>>,
}

impl App {
    pub fn new() -> Shared {
        Rc::new(Self {
            preferences: RefCell::new(session::load_preferences()),
            directions: RefCell::new(session::load_directions()),
            modes: RefCell::new(session::load_modes()),
            adjustments: RefCell::new(session::load_adjustments()),
            document: RefCell::new(session::load_library_snapshot()),
            ..Self::default()
        })
    }

    /// The page turn a publication opens with: its series' choice, else the default the
    /// preferences hold (Continuous scroll there means Scroll).
    pub fn mode_for(&self, publication: &library_record::Publication) -> ModeChoice {
        let default = if self.preferences.borrow().layout == Layout::Scroll {
            Mode::Scroll
        } else {
            Mode::Slide
        };
        self.modes.borrow().for_publication(publication, default)
    }

    /// Remembers a page turn for the publication's series, and writes it.
    pub fn choose_mode(&self, publication: &library_record::Publication, choice: ModeChoice) {
        self.modes.borrow_mut().choose(publication, choice);
        session::save_modes(&self.modes.borrow());
    }

    /// Changes the adjustments, then writes them.
    pub fn update_adjustments(&self, change: impl FnOnce(&mut Adjustments)) {
        change(&mut self.adjustments.borrow_mut());
        session::save_adjustments(&self.adjustments.borrow());
    }

    /// The direction a publication opens in: the reader's choice, else its own.
    pub fn direction_for(&self, publication: &library_record::Publication) -> ReadingDirection {
        self.directions.borrow().for_publication(publication)
    }

    /// Remembers the reader's direction for the publication's series, and writes it.
    pub fn choose_direction(
        &self,
        publication: &library_record::Publication,
        direction: ReadingDirection,
    ) {
        let text = {
            let mut directions = self.directions.borrow_mut();
            directions.choose(publication, direction);
            directions.save()
        };
        session::save_directions(&text);
    }

    /// The core's progress store, opened on first use.
    /// The player, made on first use so a session that never plays starts no engine.
    pub fn player(self: &Rc<Self>) -> Rc<crate::player::Player> {
        if let Some(player) = self.player.borrow().as_ref() {
            return player.clone();
        }
        let player = crate::player::Player::new(self);
        *self.player.borrow_mut() = Some(player.clone());
        player
    }

    pub fn progress_store(&self) -> Rc<library::ProgressStore> {
        self.progress
            .get_or_init(|| Rc::new(session::open_progress_store()))
            .clone()
    }

    /// The folders changed: the library rebuilds what it shows.
    pub fn library_changed(&self) {
        if let Some(refresh) = self.on_library_changed.borrow().as_ref() {
            refresh(true);
        }
    }

    /// A reading position was written: Home follows it, and the grid keeps its scroll.
    pub fn progress_changed(&self) {
        self.position_changed.set(true);
        if let Some(refresh) = self.on_library_changed.borrow().as_ref() {
            refresh(false);
        }
    }

    pub fn application(&self) -> adw::Application {
        self.application
            .get()
            .cloned()
            .expect("the application is set in startup")
    }

    pub fn preferences(&self) -> Preferences {
        self.preferences.borrow().clone()
    }

    /// Changes the preferences, writes them, and applies them to the theme and to every
    /// open reader at once (`desktop-experience`, Preferences while a reader is open).
    pub fn update_preferences(&self, change: impl FnOnce(&mut Preferences)) {
        let next = {
            let mut preferences = self.preferences.borrow_mut();
            change(&mut preferences);
            preferences.clone()
        };
        session::save_preferences(&next);
        self.apply_theme();
        let readers: Vec<Rc<Reader>> = self
            .readers
            .borrow()
            .iter()
            .map(|h| h.reader.clone())
            .collect();
        for reader in readers {
            reader.preferences_changed(&next);
        }
    }

    pub fn apply_theme(&self) {
        if let Some(theme) = self.theme.get() {
            theme.apply(&self.preferences(), self.system_accent.get());
        }
    }

    /// The system accent changed, or was read for the first time.
    pub fn system_accent_changed(&self, accent: Option<Rgb>) {
        self.system_accent.set(accent);
        self.apply_theme();
    }

    /// The reader window that already reads a publication, if any.
    pub fn reader_for(&self, publication: &str) -> Option<adw::ApplicationWindow> {
        self.readers
            .borrow()
            .iter()
            .find(|handle| handle.publication == publication)
            .map(|handle| handle.window.clone())
    }

    pub fn open(&self, publication: &str) -> Open {
        self.session_state().open(publication)
    }

    /// Every window as it is now, for the session file.
    pub fn session_state(&self) -> SessionState {
        let library = self
            .library
            .borrow()
            .as_ref()
            .map(session::capture)
            .unwrap_or_default();
        let readers = self
            .readers
            .borrow()
            .iter()
            .map(|handle| ReaderWindowState {
                publication: handle.publication.clone(),
                page: handle.reader.page(),
                window: session::capture(&handle.window),
            })
            .collect();
        SessionState { library, readers }
    }

    pub fn save_session(&self) {
        session::save(&self.session_state());
    }

    /// Forgets a reader window that closed by hand.
    pub fn forget_reader(&self, publication: &str) {
        self.readers
            .borrow_mut()
            .retain(|handle| handle.publication != publication);
    }

    /// Names a file that could not be opened, in the library, in grey.
    pub fn toast(&self, text: &str) {
        if let Some(overlay) = self.library_toasts.borrow().as_ref() {
            overlay.add_toast(adw::Toast::new(text));
        }
    }
}
