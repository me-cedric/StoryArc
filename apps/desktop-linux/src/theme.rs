//! How the chosen appearance and accent reach GTK: three style providers over the
//! display (the generated tokens, the ramp with the four StoryArc classes, the chrome
//! accent) and the style manager's colour scheme.
//!
//! Light and dark follow the settings portal through `AdwStyleManager`; where no
//! portal answers, libadwaita reports no system scheme and draws light, which is the
//! spec's default (`desktop-experience`, A system that does not state its appearance).
//! High contrast drops every token override so libadwaita's own style wins
//! (`linux.md` section 10).

use adw::prelude::*;
use gtk::gdk;

use crate::settings::{self, Accent, Preferences, Rgb};
use crate::style::{self, Ramp};

#[derive(Clone, Debug)]
pub struct Theme {
    tokens: gtk::CssProvider,
    ramp: gtk::CssProvider,
    accent: gtk::CssProvider,
    custom_properties: bool,
}

impl Theme {
    /// Installs the three providers on the display, the tokens loaded once.
    pub fn install(display: &gdk::Display) -> Self {
        let custom_properties =
            style::supports_custom_properties(gtk::major_version(), gtk::minor_version());
        let tokens = gtk::CssProvider::new();
        tokens.load_from_string(&style::tokens_stylesheet(custom_properties));
        let ramp = gtk::CssProvider::new();
        let accent = gtk::CssProvider::new();
        for provider in [&tokens, &ramp, &accent] {
            gtk::style_context_add_provider_for_display(
                display,
                provider,
                gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
        Self {
            tokens,
            ramp,
            accent,
            custom_properties,
        }
    }

    /// Applies the appearance and the accent the preferences ask for, given what the
    /// system offers. Called at launch, on each preference change, when the style
    /// manager's dark or high-contrast answer changes, and when the system accent does.
    pub fn apply(&self, preferences: &Preferences, system_accent: Option<Rgb>) {
        let manager = adw::StyleManager::default();
        manager.set_color_scheme(match preferences.appearance.forces_dark() {
            None => adw::ColorScheme::Default,
            Some(true) => adw::ColorScheme::ForceDark,
            Some(false) => adw::ColorScheme::ForceLight,
        });
        if manager.is_high_contrast() {
            self.ramp.load_from_string(&style::ramp_stylesheet(Ramp::for_appearance(
                settings::Appearance::System,
                manager.is_dark(),
            )));
            self.accent.load_from_string("");
            return;
        }
        let dark = manager.is_dark();
        self.ramp
            .load_from_string(&style::ramp_stylesheet(Ramp::for_appearance(preferences.appearance, dark)));

        let accent = settings::chrome_accent(preferences.accent, system_accent);
        let brand = preferences.accent == Accent::StoryArc || system_accent.is_none();
        // The brand accent has a contrast-checked text colour per ramp in the tokens; a
        // system accent is drawn as it comes, which is what the system's own apps do.
        let as_text = if brand {
            let name = if dark { "storyarc_dark_accent_text" } else { "storyarc_light_accent_text" };
            style::token_colour(name).unwrap_or(accent)
        } else {
            accent
        };
        let on_accent = style::token_colour("storyarc_brand_on_accent").unwrap_or(Rgb {
            r: 255,
            g: 255,
            b: 255,
        });
        self.accent
            .load_from_string(&style::accent_stylesheet(accent, on_accent, as_text, self.custom_properties));
    }

    /// Whether the session states its appearance: false where no settings portal
    /// answers, which the preferences name in grey.
    pub fn system_states_appearance() -> bool {
        adw::StyleManager::default().system_supports_color_schemes()
    }

    pub fn tokens_provider(&self) -> &gtk::CssProvider {
        &self.tokens
    }
}
