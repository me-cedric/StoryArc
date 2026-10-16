//! What every window shares: the preferences, the theme, the system accent, the
//! library window and the open readers. One `Rc<App>` is made in `main` and cloned
//! into the closures that need it; the windows capture it weakly where they would
//! otherwise keep themselves alive.

use std::cell::{Cell, OnceCell, RefCell};
use std::rc::Rc;

use crate::reader_window::Reader;
use crate::session;
use crate::settings::{Preferences, Rgb};
use crate::theme::Theme;
use crate::windows::{Open, ReaderWindowState, SessionState};

pub type Shared = Rc<App>;

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
    /// Set while Quit closes the windows, so each one keeps its place in the session.
    pub quitting: Cell<bool>,
    /// The publications whose window could not be restored at launch, for the library
    /// to name in grey.
    pub missing: RefCell<Vec<String>>,
    /// The one preferences dialog, so a second Control and comma presents it again.
    pub preferences_dialog: RefCell<Option<adw::PreferencesDialog>>,
    /// Where the library shows a file that could not be opened.
    pub library_toasts: RefCell<Option<adw::ToastOverlay>>,
}

impl App {
    pub fn new() -> Shared {
        Rc::new(Self {
            preferences: RefCell::new(session::load_preferences()),
            ..Self::default()
        })
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
