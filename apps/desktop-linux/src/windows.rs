//! The window model: one library window and any number of reader windows, each
//! reading one publication, all of them restored after a quit or a crash.
//!
//! Built on the `WindowState` of wave 1. This module decides; `session.rs` reads and
//! writes the file and `main.rs` opens the windows. Pure, so it tests on any host.
//!
//! The text form extends wave 1's one-section file: a `[library]` section holding
//! the library's `WindowState` lines, then one `[reader]` section per reader window
//! holding its publication, its page and its own `WindowState` lines. A wave 1 file
//! with no section header still reads as the library window.

use crate::window_state::{Display, WindowState};

/// What the app remembers about one reader window.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReaderWindowState {
    /// The publication's identity: today its path, later the core's record id.
    pub publication: String,
    /// The page the reader was on, counted from zero.
    pub page: u32,
    pub window: WindowState,
}

/// Every window, as it was when the app last saved.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SessionState {
    pub library: WindowState,
    pub readers: Vec<ReaderWindowState>,
}

/// What opening a publication should do: present the window it already has, or make one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Open {
    Present(usize),
    New,
}

/// The windows to open at launch, fitted to the displays connected now.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RestorePlan {
    pub library: WindowState,
    pub readers: Vec<ReaderWindowState>,
    /// The publications whose window could not be restored, for the library to name
    /// in grey. Their page stays in the progress store.
    pub missing: Vec<String>,
}

impl SessionState {
    /// The text form, ready to write to a file.
    pub fn save(&self) -> String {
        let mut text = format!("[library]\n{}", self.library.save());
        for reader in &self.readers {
            text.push_str(&format!(
                "[reader]\npublication={}\npage={}\n{}",
                reader.publication,
                reader.page,
                reader.window.save()
            ));
        }
        text
    }

    /// Reads the text form. A reader section with no publication is dropped; anything
    /// else missing or unreadable takes its default.
    pub fn restore(text: &str) -> Self {
        let mut sections: Vec<(&str, String)> = vec![("library", String::new())];
        for line in text.lines() {
            let trimmed = line.trim();
            match trimmed {
                "[library]" => sections.push(("library", String::new())),
                "[reader]" => sections.push(("reader", String::new())),
                _ => {
                    if let Some((_, body)) = sections.last_mut() {
                        body.push_str(line);
                        body.push('\n');
                    }
                }
            }
        }
        let mut state = Self::default();
        for (kind, body) in sections {
            match kind {
                "library" if !body.trim().is_empty() => {
                    state.library = WindowState::restore(&body);
                }
                "reader" => {
                    if let Some(reader) = reader_from(&body) {
                        state.readers.push(reader);
                    }
                }
                _ => {}
            }
        }
        state
    }

    /// One window per publication: the window that already reads it, or a new one.
    pub fn open(&self, publication: &str) -> Open {
        self.readers
            .iter()
            .position(|reader| reader.publication == publication)
            .map_or(Open::New, Open::Present)
    }

    /// Records a reader window, replacing the record of a window on the same publication.
    pub fn with_reader(mut self, reader: ReaderWindowState) -> Self {
        match self.open(&reader.publication) {
            Open::Present(index) => self.readers[index] = reader,
            Open::New => self.readers.push(reader),
        }
        self
    }

    /// Forgets a reader window, when it closes by hand rather than with the app.
    pub fn without_reader(mut self, publication: &str) -> Self {
        self.readers
            .retain(|reader| reader.publication != publication);
        self
    }

    /// The windows to open now. Each is fitted to a display that exists; a reader whose
    /// publication cannot be reopened is named instead of opened.
    pub fn plan(self, displays: &[Display], can_open: impl Fn(&str) -> bool) -> RestorePlan {
        let mut plan = RestorePlan {
            library: self.library.fit(displays),
            ..RestorePlan::default()
        };
        for reader in self.readers {
            if can_open(&reader.publication) {
                plan.readers.push(ReaderWindowState {
                    window: reader.window.fit(displays),
                    ..reader
                });
            } else {
                plan.missing.push(reader.publication);
            }
        }
        plan
    }
}

fn reader_from(body: &str) -> Option<ReaderWindowState> {
    let value = |wanted: &str| {
        body.lines()
            .filter_map(|line| line.split_once('='))
            .map(|(key, value)| (key.trim(), value.trim()))
            .find(|(key, _)| *key == wanted)
            .map(|(_, value)| value.to_owned())
    };
    let publication = value("publication").filter(|path| !path.is_empty())?;
    Some(ReaderWindowState {
        publication,
        page: value("page")
            .and_then(|page| page.parse().ok())
            .unwrap_or(0),
        window: WindowState::restore(body),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::window_state::{DEFAULT_HEIGHT, DEFAULT_WIDTH, MIN_HEIGHT, MIN_WIDTH};

    fn laptop() -> Display {
        Display {
            connector: "eDP-1".into(),
            width: 1920,
            height: 1080,
        }
    }

    fn reader(publication: &str, page: u32, display: &str) -> ReaderWindowState {
        ReaderWindowState {
            publication: publication.into(),
            page,
            window: WindowState {
                width: 800,
                height: 1000,
                maximized: false,
                display: Some(display.into()),
            },
        }
    }

    fn session() -> SessionState {
        SessionState {
            library: WindowState {
                width: 1280,
                height: 800,
                maximized: true,
                display: Some("eDP-1".into()),
            },
            readers: vec![
                reader("/comics/a.cbz", 12, "eDP-1"),
                reader("/comics/b.cbz", 3, "DP-2"),
            ],
        }
    }

    #[test]
    fn save_then_restore_round_trips_the_library_and_every_reader() {
        let state = session();
        assert_eq!(SessionState::restore(&state.save()), state);
    }

    #[test]
    fn a_wave_one_file_with_no_sections_still_reads_as_the_library_window() {
        let text = "width=900\nheight=600\nmaximized=false\ndisplay=eDP-1\n";
        let state = SessionState::restore(text);
        assert_eq!((state.library.width, state.library.height), (900, 600));
        assert!(state.readers.is_empty());
    }

    #[test]
    fn an_empty_or_damaged_file_opens_the_library_at_the_default_size() {
        assert_eq!(SessionState::restore(""), SessionState::default());
        let state = SessionState::restore("[reader]\npage=4\n[reader]\npublication=\n");
        assert_eq!(state.library, WindowState::default());
        assert!(
            state.readers.is_empty(),
            "a reader with no publication is dropped"
        );
    }

    #[test]
    fn a_reader_takes_defaults_for_what_it_cannot_read() {
        let text = "[library]\nwidth=1000\n[reader]\npublication=/x.cbz\npage=many\nwidth=700\n";
        let state = SessionState::restore(text);
        assert_eq!(state.readers.len(), 1);
        assert_eq!(state.readers[0].page, 0);
        assert_eq!(state.readers[0].window.width, 700);
        assert_eq!(state.readers[0].window.height, DEFAULT_HEIGHT);
    }

    #[test]
    fn opening_a_publication_that_is_already_open_presents_its_window() {
        let state = session();
        assert_eq!(state.open("/comics/b.cbz"), Open::Present(1));
        assert_eq!(state.open("/comics/c.cbz"), Open::New);
    }

    #[test]
    fn recording_a_reader_keeps_one_window_per_publication() {
        let state = session().with_reader(reader("/comics/a.cbz", 20, "eDP-1"));
        assert_eq!(state.readers.len(), 2);
        assert_eq!(state.readers[0].page, 20);
        let state = state.with_reader(reader("/comics/c.cbz", 0, "eDP-1"));
        assert_eq!(state.readers.len(), 3);
        let state = state.without_reader("/comics/a.cbz");
        assert_eq!(state.readers.len(), 2);
        assert_eq!(state.open("/comics/a.cbz"), Open::New);
    }

    #[test]
    fn restoration_reopens_every_window_on_its_previous_page() {
        let plan = session().plan(&[laptop()], |_| true);
        assert!(plan.library.maximized);
        assert_eq!(plan.readers.len(), 2);
        assert_eq!(plan.readers[0].page, 12);
        assert_eq!(plan.readers[1].page, 3);
        assert!(plan.missing.is_empty());
    }

    #[test]
    fn a_window_on_a_display_that_is_gone_opens_on_one_that_exists() {
        let plan = session().plan(&[laptop()], |_| true);
        assert_eq!(plan.readers[1].window.display.as_deref(), Some("eDP-1"));
        assert_eq!(
            (plan.readers[1].window.width, plan.readers[1].window.height),
            (800, 1000)
        );
        let plan = session().plan(&[], |_| true);
        assert_eq!(plan.library.display, None);
    }

    #[test]
    fn a_publication_that_cannot_be_reopened_is_named_and_the_others_open() {
        let plan = session().plan(&[laptop()], |publication| publication != "/comics/b.cbz");
        assert_eq!(plan.readers.len(), 1);
        assert_eq!(plan.readers[0].publication, "/comics/a.cbz");
        assert_eq!(plan.missing, vec!["/comics/b.cbz".to_owned()]);
    }

    #[test]
    fn a_restored_reader_never_opens_below_the_minimum_size() {
        let tiny = SessionState::default().with_reader(ReaderWindowState {
            publication: "/x.cbz".into(),
            page: 0,
            window: WindowState {
                width: 10,
                height: 10,
                maximized: false,
                display: None,
            },
        });
        let plan = tiny.plan(&[laptop()], |_| true);
        assert_eq!(
            (plan.readers[0].window.width, plan.readers[0].window.height),
            (MIN_WIDTH, MIN_HEIGHT)
        );
        assert_eq!(
            (plan.library.width, plan.library.height),
            (DEFAULT_WIDTH, DEFAULT_HEIGHT)
        );
    }
}
