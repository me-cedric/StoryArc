//! The reader's preferences, and the chrome accent they decide.
//!
//! The values and their text form live here, with no GTK in them, so they test on any
//! host. `preferences_dialog.rs` shows them and `theme.rs` applies them. The file is the
//! same `key=value` form as the window state, in the app's data directory: GSettings
//! needs a compiled schema installed by the packaging lane, and until that lands a
//! plain file keeps the setting across a relaunch (a deviation from `linux.md`
//! section 5, recorded in the lane report).
//!
//! The chrome accent follows the owner's answer of 2026-10-07 (`design.md`, Open
//! Question 1): the StoryArc brand colour by default, the system accent only where the
//! reader chose it *and* the system offers one. On the libadwaita 1.5 floor the system
//! offers none, so the choice is absent and the brand colour stays. A colour taken from
//! a cover stays inside the readers and is the same under both choices.

use crate::style;

/// A colour as the stylesheet writes it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    /// Reads `#RRGGBB`, as the generated tokens spell it.
    pub fn parse(text: &str) -> Option<Self> {
        let hex = text.trim().strip_prefix('#')?;
        if hex.len() != 6 {
            return None;
        }
        let channel = |at: usize| u8::from_str_radix(&hex[at..at + 2], 16).ok();
        Some(Self {
            r: channel(0)?,
            g: channel(2)?,
            b: channel(4)?,
        })
    }

    /// From the settings portal's `(ddd)` triple, each channel in 0 to 1.
    pub fn from_unit(r: f64, g: f64, b: f64) -> Option<Self> {
        let channel = |value: f64| {
            (0.0..=1.0)
                .contains(&value)
                .then(|| (value * 255.0).round() as u8)
        };
        Some(Self {
            r: channel(r)?,
            g: channel(g)?,
            b: channel(b)?,
        })
    }

    pub fn hex(self) -> String {
        format!("#{:02X}{:02X}{:02X}", self.r, self.g, self.b)
    }
}

/// The appearance the reader chose. `System` follows the settings portal and is light
/// where no portal answers.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Appearance {
    #[default]
    System,
    Light,
    Dark,
    OledDark,
    Natural,
}

impl Appearance {
    pub const ALL: [Self; 5] = [
        Self::System,
        Self::Light,
        Self::Dark,
        Self::OledDark,
        Self::Natural,
    ];

    fn key(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
            Self::OledDark => "oled-dark",
            Self::Natural => "natural",
        }
    }

    fn from_key(key: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|appearance| appearance.key() == key)
    }

    /// Whether this appearance asks the style manager for dark, light, or the system.
    pub fn forces_dark(self) -> Option<bool> {
        match self {
            Self::System | Self::Natural => None,
            Self::Light => Some(false),
            Self::Dark | Self::OledDark => Some(true),
        }
    }
}

/// Whose accent colours the library chrome.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Accent {
    #[default]
    StoryArc,
    System,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum CoverSize {
    #[default]
    Automatic,
    Small,
    Medium,
    Large,
}

impl CoverSize {
    pub const ALL: [Self; 4] = [Self::Automatic, Self::Small, Self::Medium, Self::Large];

    fn key(self) -> &'static str {
        match self {
            Self::Automatic => "automatic",
            Self::Small => "small",
            Self::Medium => "medium",
            Self::Large => "large",
        }
    }
}

/// How a reader lays pages out by default. `Auto` pairs pages by window shape.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Layout {
    #[default]
    Auto,
    Single,
    TwoPages,
    Scroll,
}

impl Layout {
    pub const ALL: [Self; 4] = [Self::Auto, Self::Single, Self::TwoPages, Self::Scroll];

    fn key(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Single => "single",
            Self::TwoPages => "two-pages",
            Self::Scroll => "scroll",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Fit {
    #[default]
    Page,
    Width,
    Original,
}

impl Fit {
    pub const ALL: [Self; 3] = [Self::Page, Self::Width, Self::Original];

    fn key(self) -> &'static str {
        match self {
            Self::Page => "page",
            Self::Width => "width",
            Self::Original => "original",
        }
    }
}

/// Everything the preferences dialog edits.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Preferences {
    pub appearance: Appearance,
    pub accent: Accent,
    pub cover_size: CoverSize,
    pub layout: Layout,
    pub fit: Fit,
    /// Edge click zones in a reader: on by default (owner, 2026-10-07).
    pub click_zones: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            appearance: Appearance::default(),
            accent: Accent::default(),
            cover_size: CoverSize::default(),
            layout: Layout::default(),
            fit: Fit::default(),
            click_zones: true,
        }
    }
}

impl Preferences {
    /// The text form, ready to write to a file.
    pub fn save(&self) -> String {
        format!(
            "appearance={}\naccent={}\ncover-size={}\nlayout={}\nfit={}\nclick-zones={}\n",
            self.appearance.key(),
            match self.accent {
                Accent::StoryArc => "storyarc",
                Accent::System => "system",
            },
            self.cover_size.key(),
            self.layout.key(),
            self.fit.key(),
            self.click_zones
        )
    }

    /// Reads the text form. Anything missing or unreadable takes its default.
    pub fn restore(text: &str) -> Self {
        let entries = text
            .lines()
            .filter(|line| !line.trim_start().starts_with('#'))
            .filter_map(|line| line.split_once('='))
            .map(|(key, value)| (key.trim(), value.trim()));
        entries.fold(Self::default(), |prefs, (key, value)| match key {
            "appearance" => Self {
                appearance: Appearance::from_key(value).unwrap_or(prefs.appearance),
                ..prefs
            },
            "accent" => Self {
                accent: match value {
                    "storyarc" => Accent::StoryArc,
                    "system" => Accent::System,
                    _ => prefs.accent,
                },
                ..prefs
            },
            "cover-size" => Self {
                cover_size: CoverSize::ALL
                    .into_iter()
                    .find(|size| size.key() == value)
                    .unwrap_or(prefs.cover_size),
                ..prefs
            },
            "layout" => Self {
                layout: Layout::ALL
                    .into_iter()
                    .find(|layout| layout.key() == value)
                    .unwrap_or(prefs.layout),
                ..prefs
            },
            "fit" => Self {
                fit: Fit::ALL
                    .into_iter()
                    .find(|fit| fit.key() == value)
                    .unwrap_or(prefs.fit),
                ..prefs
            },
            "click-zones" => Self {
                click_zones: value.parse().unwrap_or(prefs.click_zones),
                ..prefs
            },
            _ => prefs,
        })
    }
}

/// The StoryArc brand accent, read from the generated tokens so the two cannot drift.
pub fn brand_accent() -> Rgb {
    style::token_colour("storyarc_brand_accent")
        .expect("the generated tokens carry the brand accent")
}

/// Whether the settings offer the choice to follow the system accent: only where the
/// system offers one. On the libadwaita 1.5 floor nothing does, so the row is absent.
pub fn offers_system_accent(system: Option<Rgb>) -> bool {
    system.is_some()
}

/// The accent the library chrome takes right now. A stored `System` choice on a
/// system that offers no accent (a settings file carried from another machine, or a
/// portal that went away) falls back to the brand colour.
pub fn chrome_accent(choice: Accent, system: Option<Rgb>) -> Rgb {
    match (choice, system) {
        (Accent::System, Some(accent)) => accent,
        _ => brand_accent(),
    }
}

/// The accent inside a reader or a detail page: the colour taken from the cover, when
/// there is one, under either chrome choice; otherwise the chrome's accent.
pub fn reader_accent(cover: Option<Rgb>, choice: Accent, system: Option<Rgb>) -> Rgb {
    cover.unwrap_or_else(|| chrome_accent(choice, system))
}

/// What a row shows for a choice: the iOS catalogue key when it has one, else the
/// English text, which `strings::tr` falls back to.
pub type Label = (Option<&'static str>, &'static str);

impl Appearance {
    pub fn label(self) -> Label {
        match self {
            Self::System => (Some("appearance.system"), "System"),
            Self::Light => (Some("appearance.light"), "Light"),
            Self::Dark => (Some("appearance.dark"), "Dark"),
            Self::OledDark => (Some("appearance.oledDark"), "OLED Dark"),
            Self::Natural => (Some("appearance.natural"), "Natural"),
        }
    }
}

impl Accent {
    /// The two choices, the System one only where the system offers an accent.
    pub fn choices(system: Option<Rgb>) -> Vec<Self> {
        if offers_system_accent(system) {
            vec![Self::StoryArc, Self::System]
        } else {
            vec![Self::StoryArc]
        }
    }

    pub fn label(self) -> Label {
        match self {
            Self::StoryArc => (None, "StoryArc"),
            Self::System => (Some("appearance.system"), "System"),
        }
    }
}

impl Layout {
    pub fn label(self) -> Label {
        match self {
            Self::Auto => (None, "Automatic"),
            Self::Single => (None, "Single page"),
            Self::TwoPages => (None, "Two pages"),
            Self::Scroll => (None, "Continuous scroll"),
        }
    }
}

impl Fit {
    pub fn label(self) -> Label {
        match self {
            Self::Page => (None, "Fit page"),
            Self::Width => (None, "Fit width"),
            Self::Original => (None, "Original size"),
        }
    }
}

#[cfg(test)]
mod label_tests {
    use super::*;

    #[test]
    fn the_system_accent_choice_exists_only_where_the_system_offers_an_accent() {
        let blue = Some(Rgb {
            r: 53,
            g: 132,
            b: 228,
        });
        assert_eq!(
            Accent::choices(blue),
            vec![Accent::StoryArc, Accent::System]
        );
        assert_eq!(Accent::choices(None), vec![Accent::StoryArc]);
    }

    #[test]
    fn every_choice_has_a_label() {
        for appearance in Appearance::ALL {
            assert!(!appearance.label().1.is_empty());
        }
        for layout in Layout::ALL {
            assert!(!layout.label().1.is_empty());
        }
        for fit in Fit::ALL {
            assert!(!fit.label().1.is_empty());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SYSTEM_BLUE: Rgb = Rgb {
        r: 0x35,
        g: 0x84,
        b: 0xE4,
    };

    #[test]
    fn the_brand_accent_comes_from_the_generated_tokens() {
        assert_eq!(brand_accent().hex(), "#8A4DF0");
    }

    #[test]
    fn colours_parse_and_print_as_the_tokens_spell_them() {
        assert_eq!(Rgb::parse("#8a4df0"), Some(brand_accent()));
        assert_eq!(Rgb::parse("8A4DF0"), None);
        assert_eq!(Rgb::parse("#8A4D"), None);
        assert_eq!(Rgb::parse("#GG4DF0"), None);
        assert_eq!(
            Rgb::from_unit(1.0, 0.0, 0.5),
            Some(Rgb {
                r: 255,
                g: 0,
                b: 128
            })
        );
        assert_eq!(Rgb::from_unit(1.5, 0.0, 0.0), None);
    }

    #[test]
    fn the_chrome_uses_the_brand_colour_when_nothing_is_stored() {
        let prefs = Preferences::default();
        assert_eq!(prefs.accent, Accent::StoryArc);
        assert_eq!(
            chrome_accent(prefs.accent, Some(SYSTEM_BLUE)),
            brand_accent()
        );
        assert_eq!(chrome_accent(prefs.accent, None), brand_accent());
    }

    #[test]
    fn the_chrome_takes_the_system_accent_once_the_reader_chooses_it() {
        assert_eq!(
            chrome_accent(Accent::System, Some(SYSTEM_BLUE)),
            SYSTEM_BLUE
        );
    }

    #[test]
    fn a_later_change_of_the_system_accent_reaches_the_chrome() {
        let changed = Rgb {
            r: 0xE6,
            g: 0x61,
            b: 0x00,
        };
        assert_eq!(
            chrome_accent(Accent::System, Some(SYSTEM_BLUE)),
            SYSTEM_BLUE
        );
        assert_eq!(chrome_accent(Accent::System, Some(changed)), changed);
    }

    #[test]
    fn a_system_with_no_accent_hides_the_choice_and_keeps_the_brand_colour() {
        assert!(!offers_system_accent(None));
        assert!(offers_system_accent(Some(SYSTEM_BLUE)));
        assert_eq!(chrome_accent(Accent::System, None), brand_accent());
    }

    #[test]
    fn the_colour_taken_from_a_cover_is_the_same_under_both_choices() {
        let cover = Rgb {
            r: 0xC8,
            g: 0x7C,
            b: 0x5E,
        };
        assert_eq!(
            reader_accent(Some(cover), Accent::StoryArc, Some(SYSTEM_BLUE)),
            cover
        );
        assert_eq!(
            reader_accent(Some(cover), Accent::System, Some(SYSTEM_BLUE)),
            cover
        );
        assert_eq!(
            reader_accent(None, Accent::System, Some(SYSTEM_BLUE)),
            SYSTEM_BLUE
        );
        assert_eq!(
            reader_accent(None, Accent::StoryArc, Some(SYSTEM_BLUE)),
            brand_accent()
        );
    }

    #[test]
    fn preferences_save_then_restore_round_trip() {
        let prefs = Preferences {
            appearance: Appearance::OledDark,
            accent: Accent::System,
            cover_size: CoverSize::Large,
            layout: Layout::TwoPages,
            fit: Fit::Width,
            click_zones: false,
        };
        assert_eq!(Preferences::restore(&prefs.save()), prefs);
    }

    #[test]
    fn the_defaults_are_system_appearance_brand_accent_and_zones_on() {
        let prefs = Preferences::restore("");
        assert_eq!(prefs, Preferences::default());
        assert_eq!(prefs.appearance, Appearance::System);
        assert!(prefs.click_zones, "the zones are on when nothing is stored");
        assert_eq!(prefs.layout, Layout::Auto);
    }

    #[test]
    fn restore_takes_the_default_for_what_it_cannot_read() {
        let text =
            "appearance=neon\naccent=rainbow\nclick-zones=sometimes\nlayout=auto\nfuture=1\n";
        assert_eq!(Preferences::restore(text), Preferences::default());
        let text = "# saved\nappearance = dark\nclick-zones=false\n";
        let prefs = Preferences::restore(text);
        assert_eq!(prefs.appearance, Appearance::Dark);
        assert!(!prefs.click_zones);
    }

    #[test]
    fn each_appearance_says_whether_it_forces_dark() {
        assert_eq!(Appearance::System.forces_dark(), None);
        assert_eq!(Appearance::Light.forces_dark(), Some(false));
        assert_eq!(Appearance::Dark.forces_dark(), Some(true));
        assert_eq!(Appearance::OledDark.forces_dark(), Some(true));
        assert_eq!(
            Appearance::Natural.forces_dark(),
            None,
            "Natural has a light and a dark ramp"
        );
    }
}
