//! The library window's saved state: size, maximized flag and the display it was on.
//!
//! GTK saves no session before 4.26, so the app saves window state itself
//! (design, Decision 4). This module holds the pure value and its text form. It
//! depends on nothing from GTK, so it tests on any host; `session.rs` carries
//! the GTK side. On Wayland a window has no position, so none is saved.
//!
//! The text form is one `key=value` per line. Unknown keys are ignored and a
//! missing or unreadable value falls back to the default, so a later version
//! can add keys without breaking an older file, and a damaged file still opens
//! a window.

/// The smallest size the window accepts, so it works when tiled narrow.
pub const MIN_WIDTH: i32 = 360;
/// See [`MIN_WIDTH`].
pub const MIN_HEIGHT: i32 = 294;
/// The size of a window that has never been saved.
pub const DEFAULT_WIDTH: i32 = 1100;
/// See [`DEFAULT_WIDTH`].
pub const DEFAULT_HEIGHT: i32 = 720;

/// A display that is connected now: its connector name and its size in logical pixels.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Display {
    pub connector: String,
    pub width: i32,
    pub height: i32,
}

/// What the app remembers about the library window between two runs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WindowState {
    pub width: i32,
    pub height: i32,
    pub maximized: bool,
    /// The connector of the display the window was on, when it was known.
    pub display: Option<String>,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            width: DEFAULT_WIDTH,
            height: DEFAULT_HEIGHT,
            maximized: false,
            display: None,
        }
    }
}

impl WindowState {
    /// The text form, ready to write to a file.
    pub fn save(&self) -> String {
        let display = self.display.as_deref().unwrap_or_default();
        format!(
            "width={}\nheight={}\nmaximized={}\ndisplay={display}\n",
            self.width, self.height, self.maximized
        )
    }

    /// Reads the text form. Anything missing or unreadable takes its default.
    pub fn restore(text: &str) -> Self {
        let defaults = Self::default();
        let entries = text
            .lines()
            .filter(|line| !line.trim_start().starts_with('#'))
            .filter_map(|line| line.split_once('='))
            .map(|(key, value)| (key.trim(), value.trim()));
        entries.fold(defaults, |state, (key, value)| match key {
            "width" => Self {
                width: positive(value).unwrap_or(state.width),
                ..state
            },
            "height" => Self {
                height: positive(value).unwrap_or(state.height),
                ..state
            },
            "maximized" => Self {
                maximized: value.parse().unwrap_or(state.maximized),
                ..state
            },
            "display" => Self {
                display: Some(value.to_owned()).filter(|name| !name.is_empty()),
                ..state
            },
            _ => state,
        })
    }

    /// The state fitted to the displays connected now, so the window opens fully
    /// visible on a display that exists. A window whose display is gone, or that
    /// never recorded one, lands on the first display. The size never goes below
    /// the minimum and never above the display.
    pub fn fit(self, displays: &[Display]) -> Self {
        let kept = self
            .display
            .as_deref()
            .and_then(|name| displays.iter().find(|display| display.connector == name));
        let Some(display) = kept.or(displays.first()) else {
            return Self {
                width: self.width.max(MIN_WIDTH),
                height: self.height.max(MIN_HEIGHT),
                display: None,
                ..self
            };
        };
        Self {
            width: self.width.max(MIN_WIDTH).min(display.width.max(MIN_WIDTH)),
            height: self
                .height
                .max(MIN_HEIGHT)
                .min(display.height.max(MIN_HEIGHT)),
            display: Some(display.connector.clone()),
            ..self
        }
    }
}

fn positive(value: &str) -> Option<i32> {
    value.parse().ok().filter(|number| *number > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn laptop() -> Display {
        Display {
            connector: "eDP-1".into(),
            width: 1920,
            height: 1080,
        }
    }

    fn external() -> Display {
        Display {
            connector: "DP-2".into(),
            width: 2560,
            height: 1440,
        }
    }

    #[test]
    fn a_window_never_saved_opens_at_the_design_size() {
        let state = WindowState::default();
        assert_eq!((state.width, state.height), (DEFAULT_WIDTH, DEFAULT_HEIGHT));
        assert!(!state.maximized);
        assert_eq!(state.display, None);
    }

    #[test]
    fn save_then_restore_round_trips() {
        let state = WindowState {
            width: 1280,
            height: 800,
            maximized: true,
            display: Some("DP-2".into()),
        };
        assert_eq!(WindowState::restore(&state.save()), state);
    }

    #[test]
    fn restore_reads_an_empty_file_as_the_default() {
        assert_eq!(WindowState::restore(""), WindowState::default());
    }

    #[test]
    fn restore_takes_the_default_for_what_it_cannot_read() {
        let text = "width=wide\nheight=-5\nmaximized=maybe\ndisplay=\nfuture-key=1\n";
        assert_eq!(WindowState::restore(text), WindowState::default());
    }

    #[test]
    fn restore_keeps_what_it_can_read_beside_what_it_cannot() {
        let text = "# saved by StoryArc\nwidth = 900\nheight=broken\nmaximized=true\n";
        let state = WindowState::restore(text);
        assert_eq!(state.width, 900);
        assert_eq!(state.height, DEFAULT_HEIGHT);
        assert!(state.maximized);
    }

    #[test]
    fn fit_keeps_a_display_that_is_still_connected() {
        let state = WindowState {
            width: 1280,
            height: 800,
            maximized: false,
            display: Some("DP-2".into()),
        };
        let fitted = state.clone().fit(&[laptop(), external()]);
        assert_eq!(fitted, state);
    }

    #[test]
    fn fit_moves_a_window_whose_display_is_gone_to_one_that_exists() {
        let state = WindowState {
            width: 2400,
            height: 1300,
            maximized: false,
            display: Some("DP-2".into()),
        };
        let fitted = state.fit(&[laptop()]);
        assert_eq!(fitted.display.as_deref(), Some("eDP-1"));
        assert_eq!((fitted.width, fitted.height), (1920, 1080));
    }

    #[test]
    fn fit_gives_a_window_with_no_display_the_first_one() {
        let fitted = WindowState::default().fit(&[external(), laptop()]);
        assert_eq!(fitted.display.as_deref(), Some("DP-2"));
        assert_eq!(
            (fitted.width, fitted.height),
            (DEFAULT_WIDTH, DEFAULT_HEIGHT)
        );
    }

    #[test]
    fn fit_shrinks_a_window_larger_than_its_display() {
        let state = WindowState {
            width: 3000,
            height: 2000,
            maximized: true,
            display: Some("eDP-1".into()),
        };
        let fitted = state.fit(&[laptop()]);
        assert_eq!((fitted.width, fitted.height), (1920, 1080));
        assert!(fitted.maximized, "the maximized flag survives the fit");
    }

    #[test]
    fn fit_never_goes_below_the_minimum() {
        let state = WindowState {
            width: 100,
            height: 50,
            maximized: false,
            display: None,
        };
        let fitted = state.fit(&[laptop()]);
        assert_eq!((fitted.width, fitted.height), (MIN_WIDTH, MIN_HEIGHT));
    }

    #[test]
    fn fit_with_no_display_at_all_keeps_the_size_and_forgets_the_display() {
        let state = WindowState {
            width: 1280,
            height: 800,
            maximized: false,
            display: Some("DP-2".into()),
        };
        let fitted = state.fit(&[]);
        assert_eq!((fitted.width, fitted.height), (1280, 800));
        assert_eq!(fitted.display, None);
    }

    #[test]
    fn a_display_smaller_than_the_minimum_still_gets_the_minimum() {
        let tiny = Display {
            connector: "HDMI-1".into(),
            width: 300,
            height: 200,
        };
        let fitted = WindowState::default().fit(&[tiny]);
        assert_eq!((fitted.width, fitted.height), (MIN_WIDTH, MIN_HEIGHT));
    }
}
