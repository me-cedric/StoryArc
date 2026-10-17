//! The stylesheets the app loads: the generated tokens, the four StoryArc classes, the
//! ramp for the chosen appearance and the chrome accent. Text only; `theme.rs` hands
//! the text to GTK.
//!
//! `linux.md` section 11: the generated stylesheet is the only custom CSS. It holds
//! the token colours as named colours (`@define-color`), which libadwaita 1.5 reads,
//! and a `:root` block of custom properties, which GTK parses from 4.16 only. On the
//! 4.14 floor that block is dropped before loading, so the floor logs no CSS warning.

use crate::settings::{Appearance, Rgb};

/// The generated tokens, copied from `packages/design-tokens/dist/gtk/` by the token
/// sync. Do not edit the file by hand.
pub const TOKENS_CSS: &str = include_str!("../data/style/storyarc-tokens.css");

/// The four classes the design names, over the ramp colours of `ramp_stylesheet`.
const APP_CSS: &str = "\
.storyarc-canvas { background-color: @storyarc_surface_canvas; }
.storyarc-letterbox { background-color: @storyarc_surface_sunken; }
.storyarc-cover { border-radius: 4px; overflow: hidden; }
.storyarc-reader { background-color: @storyarc_surface_reader; color: @storyarc_text_primary; }
.storyarc-reader-bar { background-color: @storyarc_surface_overlay; border: 1px solid @storyarc_border_strong; border-radius: 10px; }
";

/// The ramp an appearance draws with, once the style manager has said whether it is dark.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ramp {
    Light,
    Dark,
    OledDark,
    NaturalLight,
    NaturalDark,
}

impl Ramp {
    pub fn for_appearance(appearance: Appearance, dark: bool) -> Self {
        match (appearance, dark) {
            (Appearance::OledDark, _) => Self::OledDark,
            (Appearance::Natural, false) => Self::NaturalLight,
            (Appearance::Natural, true) => Self::NaturalDark,
            (_, false) => Self::Light,
            (_, true) => Self::Dark,
        }
    }

    /// The prefix of this ramp's tokens in the generated stylesheet.
    fn prefix(self) -> &'static str {
        match self {
            Self::Light => "storyarc_light",
            Self::Dark => "storyarc_dark",
            Self::OledDark => "storyarc_oled_dark",
            Self::NaturalLight => "storyarc_natural_light",
            Self::NaturalDark => "storyarc_natural_dark",
        }
    }

    /// Whether this ramp replaces Adwaita's own surfaces. Light and Dark are stock
    /// Adwaita (`linux.md` section 11); OLED Dark and Natural override the named colours.
    fn overrides_adwaita(self) -> bool {
        !matches!(self, Self::Light | Self::Dark)
    }
}

/// One token's colour, read from the generated stylesheet.
pub fn token_colour(name: &str) -> Option<Rgb> {
    let needle = format!("@define-color {name} ");
    TOKENS_CSS
        .lines()
        .find_map(|line| line.strip_prefix(&needle))
        .and_then(|rest| Rgb::parse(rest.trim_end_matches(';')))
}

/// The generated tokens as GTK can load them. Without custom-property support the
/// `:root` block is dropped, since GTK 4.14 would log a parse error for it.
pub fn tokens_stylesheet(custom_properties: bool) -> String {
    if custom_properties {
        return TOKENS_CSS.to_owned();
    }
    match TOKENS_CSS.find(":root {") {
        Some(start) => TOKENS_CSS[..start].trim_end().to_owned() + "\n",
        None => TOKENS_CSS.to_owned(),
    }
}

/// The ramp aliases the four classes read, and the Adwaita overrides for the ramps
/// that are themes rather than stock.
pub fn ramp_stylesheet(ramp: Ramp) -> String {
    let p = ramp.prefix();
    let mut css = format!(
        "@define-color storyarc_surface_canvas @{p}_surface_canvas;
@define-color storyarc_surface_raised @{p}_surface_raised;
@define-color storyarc_surface_overlay @{p}_surface_overlay;
@define-color storyarc_surface_reader @{p}_surface_reader;
@define-color storyarc_surface_sunken @{p}_surface_sunken;
@define-color storyarc_border_subtle @{p}_border_subtle;
@define-color storyarc_border_strong @{p}_border_strong;
@define-color storyarc_text_primary @{p}_text_primary;
@define-color storyarc_text_secondary @{p}_text_secondary;
@define-color storyarc_accent_text @{p}_accent_text;
"
    );
    if ramp.overrides_adwaita() {
        css.push_str(&format!(
            "@define-color window_bg_color @{p}_surface_canvas;
@define-color window_fg_color @{p}_text_primary;
@define-color view_bg_color @{p}_surface_raised;
@define-color view_fg_color @{p}_text_primary;
@define-color headerbar_bg_color @{p}_surface_canvas;
@define-color headerbar_fg_color @{p}_text_primary;
@define-color sidebar_bg_color @{p}_surface_sunken;
@define-color sidebar_fg_color @{p}_text_primary;
@define-color card_bg_color @{p}_surface_raised;
@define-color card_fg_color @{p}_text_primary;
@define-color popover_bg_color @{p}_surface_overlay;
@define-color popover_fg_color @{p}_text_primary;
@define-color dialog_bg_color @{p}_surface_overlay;
@define-color dialog_fg_color @{p}_text_primary;
@define-color headerbar_border_color @{p}_border_subtle;
@define-color sidebar_border_color @{p}_border_subtle;
"
        ));
    }
    css.push_str(APP_CSS);
    css
}

/// The chrome accent as libadwaita's named colours. `on_accent` is the label drawn on
/// a filled control; `as_text` the accent drawn as text on a surface. With custom
/// properties the same three go out as the variables libadwaita 1.6 reads.
pub fn accent_stylesheet(
    accent: Rgb,
    on_accent: Rgb,
    as_text: Rgb,
    custom_properties: bool,
) -> String {
    let mut css = format!(
        "@define-color accent_bg_color {};\n@define-color accent_fg_color {};\n@define-color accent_color {};\n",
        accent.hex(),
        on_accent.hex(),
        as_text.hex()
    );
    if custom_properties {
        css.push_str(&format!(
            ":root {{ --accent-bg-color: {}; --accent-fg-color: {}; --accent-color: {}; }}\n",
            accent.hex(),
            on_accent.hex(),
            as_text.hex()
        ));
    }
    css
}

/// GTK parses custom properties and `:root` from 4.16.
pub fn supports_custom_properties(gtk_major: u32, gtk_minor: u32) -> bool {
    gtk_major > 4 || (gtk_major == 4 && gtk_minor >= 16)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tokens_name_every_colour_the_classes_read() {
        for ramp in [
            Ramp::Light,
            Ramp::Dark,
            Ramp::OledDark,
            Ramp::NaturalLight,
            Ramp::NaturalDark,
        ] {
            for suffix in [
                "surface_canvas",
                "surface_raised",
                "surface_overlay",
                "surface_reader",
                "surface_sunken",
                "border_subtle",
                "border_strong",
                "text_primary",
                "text_secondary",
                "accent_text",
            ] {
                let name = format!("{}_{suffix}", ramp.prefix());
                assert!(
                    token_colour(&name).is_some(),
                    "{name} is missing from the tokens"
                );
            }
        }
        assert!(token_colour("storyarc_brand_on_accent").is_some());
        assert_eq!(token_colour("storyarc_nothing"), None);
    }

    #[test]
    fn the_floor_drops_the_root_block_and_a_newer_gtk_keeps_it() {
        assert!(
            TOKENS_CSS.contains(":root {"),
            "the generator writes a :root block"
        );
        let floor = tokens_stylesheet(false);
        assert!(!floor.contains(":root"));
        assert!(!floor.contains("--storyarc"));
        assert!(floor.contains("@define-color storyarc_brand_accent #8A4DF0;"));
        assert!(floor.ends_with(";\n"));
        assert_eq!(tokens_stylesheet(true), TOKENS_CSS);
    }

    #[test]
    fn gtk_4_16_is_where_custom_properties_begin() {
        assert!(!supports_custom_properties(4, 14));
        assert!(!supports_custom_properties(4, 15));
        assert!(supports_custom_properties(4, 16));
        assert!(supports_custom_properties(5, 0));
    }

    #[test]
    fn light_and_dark_stay_stock_adwaita_while_oled_and_natural_override_it() {
        let light = ramp_stylesheet(Ramp::Light);
        assert!(
            light.contains("@define-color storyarc_surface_canvas @storyarc_light_surface_canvas;")
        );
        assert!(!light.contains("window_bg_color"));
        assert!(light.contains(".storyarc-reader"));

        let oled = ramp_stylesheet(Ramp::OledDark);
        assert!(oled.contains("@define-color window_bg_color @storyarc_oled_dark_surface_canvas;"));
        assert!(
            oled.contains("@define-color popover_bg_color @storyarc_oled_dark_surface_overlay;")
        );
        let natural = ramp_stylesheet(Ramp::NaturalDark);
        assert!(natural.contains(
            "@define-color storyarc_surface_reader @storyarc_natural_dark_surface_reader;"
        ));
    }

    #[test]
    fn the_ramp_follows_the_appearance_and_the_style_manager() {
        assert_eq!(Ramp::for_appearance(Appearance::System, false), Ramp::Light);
        assert_eq!(Ramp::for_appearance(Appearance::System, true), Ramp::Dark);
        assert_eq!(
            Ramp::for_appearance(Appearance::Light, true),
            Ramp::Dark,
            "the manager's answer wins"
        );
        assert_eq!(
            Ramp::for_appearance(Appearance::OledDark, true),
            Ramp::OledDark
        );
        assert_eq!(
            Ramp::for_appearance(Appearance::Natural, false),
            Ramp::NaturalLight
        );
        assert_eq!(
            Ramp::for_appearance(Appearance::Natural, true),
            Ramp::NaturalDark
        );
    }

    #[test]
    fn the_accent_goes_out_as_named_colours_and_as_variables_where_gtk_reads_them() {
        let accent = Rgb {
            r: 0x8A,
            g: 0x4D,
            b: 0xF0,
        };
        let white = Rgb {
            r: 255,
            g: 255,
            b: 255,
        };
        let text = Rgb {
            r: 0x7F,
            g: 0x3F,
            b: 0xE2,
        };
        let floor = accent_stylesheet(accent, white, text, false);
        assert_eq!(
            floor,
            "@define-color accent_bg_color #8A4DF0;\n@define-color accent_fg_color #FFFFFF;\n@define-color accent_color #7F3FE2;\n"
        );
        let newer = accent_stylesheet(accent, white, text, true);
        assert!(newer.starts_with(&floor));
        assert!(newer.contains("--accent-bg-color: #8A4DF0;"));
    }
}
