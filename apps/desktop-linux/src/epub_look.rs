//! The look of a reflowable book, with no GTK in it: the six reading themes, the reader's own
//! typography over them, and what both send the renderer (`ebook-reader`, *Reflowable
//! rendering* and *Reader themes*).
//!
//! This is the Linux copy of the Mac's `EpubTypography`, `EpubFonts` and `EpubLook`, over the
//! phones' `ThemePreset`, `ThemeValues` and `ReaderTypeface`. A preset sets the colours (and the
//! weight of *Bold*); the typography is the reader's and stays when the preset changes. Under
//! *Original* the publisher's stylesheet is in force, so the axes it governs are not sent. The
//! colours come from the generated tokens, so a preset that fails the contrast gate fails the
//! build. The values are kept in a `key=value` file beside the preferences.

use serde_json::{Map, Value, json};

use crate::epub_host::{BOOK_HOST, SCHEME};
use crate::strings::{tr, tr_args};

/// The six reading themes, in the phones' order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Preset {
    Original,
    Quiet,
    Paper,
    Bold,
    Calm,
    Focus,
}

impl Preset {
    pub const ALL: [Self; 6] = [
        Self::Original,
        Self::Quiet,
        Self::Paper,
        Self::Bold,
        Self::Calm,
        Self::Focus,
    ];

    pub fn key(self) -> &'static str {
        match self {
            Self::Original => "original",
            Self::Quiet => "quiet",
            Self::Paper => "paper",
            Self::Bold => "bold",
            Self::Calm => "calm",
            Self::Focus => "focus",
        }
    }

    fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|preset| preset.key() == key)
    }

    /// The preset's name, never a number (`ebook-reader`, *Themes are named, not numbered*).
    pub fn title(self) -> String {
        match self {
            Self::Original => tr("theme.preset.original", "Original"),
            Self::Quiet => tr("theme.preset.quiet", "Quiet"),
            Self::Paper => tr("theme.preset.paper", "Paper"),
            Self::Bold => tr("theme.preset.bold", "Bold"),
            Self::Calm => tr("theme.preset.calm", "Calm"),
            Self::Focus => tr("theme.preset.focus", "Focus"),
        }
    }

    /// Only *Original* keeps the publication's own stylesheet.
    pub fn keeps_publisher_styles(self) -> bool {
        self == Self::Original
    }

    /// The background and the text colour, `#RRGGBB`, from the generated tokens.
    pub fn colours(self) -> (String, String) {
        let token = |part: &str| {
            let name = format!("@define-color storyarc_reading_themes_{}_{part} ", self.key());
            crate::style::TOKENS_CSS
                .lines()
                .find_map(|line| line.strip_prefix(&name))
                .map(|value| value.trim().trim_end_matches(';').to_owned())
                .unwrap_or_default()
        };
        (token("bg"), token("fg"))
    }

    /// The axes the preset itself sets, in the renderer's names.
    fn axes(self) -> Map<String, Value> {
        let mut axes = Map::new();
        axes.insert("publisherStyles".into(), self.keeps_publisher_styles().into());
        if self.keeps_publisher_styles() {
            return axes;
        }
        let (background, text) = self.colours();
        axes.insert("backgroundColor".into(), background.into());
        axes.insert("textColor".into(), text.into());
        if self == Self::Bold {
            axes.insert("fontWeight".into(), 1.5.into());
        }
        axes
    }
}

/// The typefaces offered: the publisher's, the system serif and sans, and the five bundled.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Typeface {
    Publisher,
    Serif,
    Sans,
    Literata,
    SourceSerif,
    EbGaramond,
    Bitter,
    Atkinson,
}

impl Typeface {
    pub const ALL: [Self; 8] = [
        Self::Publisher,
        Self::Serif,
        Self::Sans,
        Self::Literata,
        Self::SourceSerif,
        Self::EbGaramond,
        Self::Bitter,
        Self::Atkinson,
    ];

    fn key(self) -> &'static str {
        match self {
            Self::Publisher => "publisher",
            Self::Serif => "serif",
            Self::Sans => "sans",
            Self::Literata => "literata",
            Self::SourceSerif => "sourceSerif",
            Self::EbGaramond => "ebGaramond",
            Self::Bitter => "bitter",
            Self::Atkinson => "atkinsonHyperlegible",
        }
    }

    /// The CSS family, or `None` for the publication's own.
    pub fn css_family(self) -> Option<&'static str> {
        match self {
            Self::Publisher => None,
            Self::Serif => Some("serif"),
            Self::Sans => Some("sans-serif"),
            Self::Literata => Some("Literata"),
            Self::SourceSerif => Some("Source Serif 4"),
            Self::EbGaramond => Some("EB Garamond"),
            Self::Bitter => Some("Bitter"),
            Self::Atkinson => Some("Atkinson Hyperlegible"),
        }
    }

    pub fn title(self) -> String {
        match self {
            Self::Publisher => tr("theme.typeface.publisher", "Publisher"),
            Self::Serif => tr("theme.typeface.serif", "Serif"),
            Self::Sans => tr("theme.typeface.sans", "Sans"),
            Self::Literata => tr("theme.typeface.literata", "Literata"),
            Self::SourceSerif => tr("theme.typeface.sourceSerif", "Source Serif"),
            Self::EbGaramond => tr("theme.typeface.ebGaramond", "EB Garamond"),
            Self::Bitter => tr("theme.typeface.bitter", "Bitter"),
            Self::Atkinson => tr("theme.typeface.atkinson", "Atkinson Hyperlegible"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Alignment {
    Publisher,
    Left,
    Justified,
}

impl Alignment {
    pub const ALL: [Self; 3] = [Self::Publisher, Self::Left, Self::Justified];

    fn key(self) -> &'static str {
        match self {
            Self::Publisher => "publisher",
            Self::Left => "left",
            Self::Justified => "justified",
        }
    }

    pub fn title(self) -> String {
        match self {
            Self::Publisher => tr("theme.alignment.publisher", "Publisher"),
            Self::Left => tr("theme.alignment.left", "Left"),
            Self::Justified => tr("theme.alignment.justified", "Justified"),
        }
    }
}

/// The phones' size ladder, in percent of the publisher's size.
pub const SIZE_STEPS: [u32; 9] = [70, 80, 90, 100, 115, 130, 150, 175, 200];

/// The slider ranges and steps of the phones' `ThemeAxis` (ten steps an axis).
pub const LINE_HEIGHT: (f64, f64) = (1.0, 2.5);
pub const PARAGRAPH_SPACING: (f64, f64) = (0.0, 2.0);
pub const MARGINS: (f64, f64) = (0.5, 2.5);

/// The base gutter one margin step stands for, in CSS pixels.
const GUTTER_UNIT: f64 = 24.0;

/// The reader's own typography: the phones' `ThemeValues` and their defaults.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Values {
    pub typeface: Typeface,
    pub font_size: u32,
    pub bold: bool,
    pub line_height: f64,
    pub paragraph_spacing: f64,
    pub margins: f64,
    pub alignment: Alignment,
    pub hyphens: bool,
}

impl Default for Values {
    fn default() -> Self {
        Self {
            typeface: Typeface::Publisher,
            font_size: 100,
            bold: false,
            line_height: 1.4,
            paragraph_spacing: 0.5,
            margins: 1.0,
            alignment: Alignment::Publisher,
            hyphens: false,
        }
    }
}

impl Values {
    /// One step up or down the size ladder, held at its ends.
    pub fn step_size(self, up: bool) -> Self {
        let at = SIZE_STEPS
            .iter()
            .position(|&step| step >= self.font_size)
            .unwrap_or(SIZE_STEPS.len() - 1);
        let at = if up {
            (at + 1).min(SIZE_STEPS.len() - 1)
        } else {
            at.saturating_sub(1)
        };
        Self {
            font_size: SIZE_STEPS[at],
            ..self
        }
    }
}

/// Everything the reader chose about the look, kept per device.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Look {
    pub preset: Preset,
    pub values: Values,
    /// Reflowable text scrolls rather than turns pages (`ebook-reader`, *Scroll mode*).
    pub scroll: bool,
    /// 0.5 to 1; the page is dimmed by the difference.
    pub brightness: f64,
    /// The preset follows the system appearance through the light and dark pair.
    pub follows: bool,
    pub light: Preset,
    pub dark: Preset,
}

impl Default for Look {
    fn default() -> Self {
        Self {
            preset: Preset::Paper,
            values: Values::default(),
            scroll: false,
            brightness: 1.0,
            follows: false,
            light: Preset::Paper,
            dark: Preset::Focus,
        }
    }
}

impl Look {
    /// Whether the active preset shows as modified: the typography moved from its defaults.
    pub fn is_modified(&self) -> bool {
        self.values != Values::default()
    }

    /// The preset for an appearance when the page follows it, else `None`.
    pub fn preset_for(&self, dark: bool) -> Option<Preset> {
        self.follows
            .then_some(if dark { self.dark } else { self.light })
    }

    /// Every axis the renderer gets: the preset's colours with the typography over them.
    pub fn axes(&self) -> Map<String, Value> {
        let mut axes = self.preset.axes();
        let values = &self.values;
        axes.insert("fontSize".into(), (f64::from(values.font_size) / 100.0).into());
        axes.insert(
            "pageGutter".into(),
            (values.margins * GUTTER_UNIT).round().into(),
        );
        axes.insert("scroll".into(), self.scroll.into());
        if let Some(family) = values.typeface.css_family() {
            axes.insert("fontFamily".into(), family.into());
        }
        if values.bold {
            axes.insert("fontWeight".into(), 1.5.into());
        }
        let darken = ((1.0 - self.brightness) * 100.0).round();
        if darken > 0.0 {
            axes.insert("darkenFilter".into(), darken.into());
        }
        if self.preset.keeps_publisher_styles() {
            return axes;
        }
        axes.insert("lineHeight".into(), values.line_height.into());
        axes.insert(
            "paragraphSpacing".into(),
            values.paragraph_spacing.into(),
        );
        if values.hyphens {
            axes.insert("hyphens".into(), true.into());
        }
        match values.alignment {
            Alignment::Publisher => {}
            Alignment::Left => {
                axes.insert("textAlign".into(), "left".into());
            }
            Alignment::Justified => {
                axes.insert("textAlign".into(), "justify".into());
            }
        }
        axes
    }

    /// The axes as the reader page's opening preferences.
    pub fn preferences_json(&self) -> String {
        Value::Object(self.axes()).to_string()
    }

    /// The `theme` message: it replaces every axis, so the preset goes with the typography.
    pub fn theme_message(&self, seq: u64) -> String {
        json!({
            "type": "theme",
            "seq": seq,
            "theme": { "name": self.preset.key(), "axes": Value::Object(self.axes()) },
        })
        .to_string()
    }

    /// The text form, ready to write to a file.
    pub fn save(&self) -> String {
        let values = &self.values;
        format!(
            "preset={}\ntypeface={}\nsize={}\nbold={}\nline-height={}\nparagraph-spacing={}\nmargins={}\nalignment={}\nhyphens={}\nscroll={}\nbrightness={}\nfollows={}\nlight={}\ndark={}\n",
            self.preset.key(),
            values.typeface.key(),
            values.font_size,
            values.bold,
            values.line_height,
            values.paragraph_spacing,
            values.margins,
            values.alignment.key(),
            values.hyphens,
            self.scroll,
            self.brightness,
            self.follows,
            self.light.key(),
            self.dark.key(),
        )
    }

    /// Reads the text form. Anything missing, unreadable or out of range takes its default.
    pub fn restore(text: &str) -> Self {
        let mut look = Self::default();
        let within = |value: &str, (low, high): (f64, f64)| {
            value
                .parse::<f64>()
                .ok()
                .filter(|v| (low..=high).contains(v))
        };
        for (key, value) in text
            .lines()
            .filter_map(|line| line.split_once('='))
            .map(|(key, value)| (key.trim(), value.trim()))
        {
            let values = &mut look.values;
            match key {
                "preset" => look.preset = Preset::from_key(value).unwrap_or(look.preset),
                "light" => look.light = Preset::from_key(value).unwrap_or(look.light),
                "dark" => look.dark = Preset::from_key(value).unwrap_or(look.dark),
                "typeface" => {
                    values.typeface = Typeface::ALL
                        .into_iter()
                        .find(|face| face.key() == value)
                        .unwrap_or(values.typeface);
                }
                "size" => {
                    values.font_size = value
                        .parse()
                        .ok()
                        .filter(|size| SIZE_STEPS.contains(size))
                        .unwrap_or(values.font_size);
                }
                "bold" => values.bold = value.parse().unwrap_or(values.bold),
                "line-height" => {
                    values.line_height = within(value, LINE_HEIGHT).unwrap_or(values.line_height);
                }
                "paragraph-spacing" => {
                    values.paragraph_spacing =
                        within(value, PARAGRAPH_SPACING).unwrap_or(values.paragraph_spacing);
                }
                "margins" => values.margins = within(value, MARGINS).unwrap_or(values.margins),
                "alignment" => {
                    values.alignment = Alignment::ALL
                        .into_iter()
                        .find(|alignment| alignment.key() == value)
                        .unwrap_or(values.alignment);
                }
                "hyphens" => values.hyphens = value.parse().unwrap_or(values.hyphens),
                "scroll" => look.scroll = value.parse().unwrap_or(look.scroll),
                "brightness" => look.brightness = within(value, (0.5, 1.0)).unwrap_or(1.0),
                "follows" => look.follows = value.parse().unwrap_or(look.follows),
                _ => {}
            }
        }
        look
    }
}

/// How far through the book the reader is, in a sentence (`ebook-reader`, *Progress display*):
/// the share of the book and what is left of the chapter, never a page number, since pages
/// move with typography.
pub fn progress_line(total: f64, chapter: f64) -> String {
    let read = (total.clamp(0.0, 1.0) * 100.0).round() as u32;
    let left = ((1.0 - chapter.clamp(0.0, 1.0)) * 100.0).round() as u32;
    tr_args(
        "desktop.w4.epub.progress",
        "%1$@%% read · %2$@%% of this chapter left",
        &[&read, &left],
    )
}

/// The folder the reading faces are served under, on the book's own scheme.
const FONT_FOLDER: &str = "storyarc-fonts/";
const FONT_SHEET: &str = "storyarc-fonts/faces.css";

/// The five faces of `packages/fonts`, embedded because the app ships no data folder for them.
const FACES: [(&str, &[u8]); 12] = [
    ("Literata", include_bytes!("../../../packages/fonts/Literata.ttf")),
    ("Literata-Italic", include_bytes!("../../../packages/fonts/Literata-Italic.ttf")),
    ("SourceSerif4", include_bytes!("../../../packages/fonts/SourceSerif4.ttf")),
    ("SourceSerif4-Italic", include_bytes!("../../../packages/fonts/SourceSerif4-Italic.ttf")),
    ("EBGaramond", include_bytes!("../../../packages/fonts/EBGaramond.ttf")),
    ("EBGaramond-Italic", include_bytes!("../../../packages/fonts/EBGaramond-Italic.ttf")),
    ("Bitter", include_bytes!("../../../packages/fonts/Bitter.ttf")),
    ("Bitter-Italic", include_bytes!("../../../packages/fonts/Bitter-Italic.ttf")),
    ("AtkinsonHyperlegible-Regular", include_bytes!("../../../packages/fonts/AtkinsonHyperlegible-Regular.ttf")),
    ("AtkinsonHyperlegible-Italic", include_bytes!("../../../packages/fonts/AtkinsonHyperlegible-Italic.ttf")),
    ("AtkinsonHyperlegible-Bold", include_bytes!("../../../packages/fonts/AtkinsonHyperlegible-Bold.ttf")),
    ("AtkinsonHyperlegible-BoldItalic", include_bytes!("../../../packages/fonts/AtkinsonHyperlegible-BoldItalic.ttf")),
];

/// The `@font-face` rules: an upright and an italic file over the weight range the phones
/// declare for the four variable families, and Atkinson Hyperlegible's four static files.
pub fn faces_css() -> String {
    let rule = |family: &str, file: &str, style: &str, weight: &str| {
        format!(
            "@font-face{{font-family:\"{family}\";src:url(\"{file}.ttf\") format(\"truetype\");font-style:{style};font-weight:{weight};font-display:swap}}"
        )
    };
    let mut rules = Vec::new();
    for (family, stem, weight) in [
        ("Literata", "Literata", "300 700"),
        ("Source Serif 4", "SourceSerif4", "300 700"),
        ("EB Garamond", "EBGaramond", "400 700"),
        ("Bitter", "Bitter", "300 700"),
    ] {
        rules.push(rule(family, stem, "normal", weight));
        rules.push(rule(family, &format!("{stem}-Italic"), "italic", weight));
    }
    for (suffix, style, weight) in [
        ("Regular", "normal", "400"),
        ("Italic", "italic", "400"),
        ("Bold", "normal", "700"),
        ("BoldItalic", "italic", "700"),
    ] {
        rules.push(rule(
            "Atkinson Hyperlegible",
            &format!("AtkinsonHyperlegible-{suffix}"),
            style,
            weight,
        ));
    }
    rules.join("\n")
}

/// The stylesheet or a face file, by container path; `None` for any other path.
pub fn font_resource(path: &str) -> Option<(Vec<u8>, String)> {
    if path == FONT_SHEET {
        return Some((faces_css().into_bytes(), "text/css".to_owned()));
    }
    let stem = path.strip_prefix(FONT_FOLDER)?.strip_suffix(".ttf")?;
    let (_, bytes) = FACES.iter().find(|(name, _)| *name == stem)?;
    Some((bytes.to_vec(), "font/ttf".to_owned()))
}

/// A chapter with the faces' stylesheet linked before its head closes; anything else as it is.
///
/// The `rel` carries a second token on purpose, as on the Mac: the toolkit adds its default
/// stylesheet only to a chapter with no `link[rel='stylesheet']` of its own, and an exact
/// `stylesheet` here would take those defaults from every unstyled book.
pub fn linking(bytes: Vec<u8>, media_type: &str) -> Vec<u8> {
    if media_type != "application/xhtml+xml" && media_type != "text/html" {
        return bytes;
    }
    let Ok(text) = String::from_utf8(bytes) else {
        return Vec::new();
    };
    let Some(close) = text.to_ascii_lowercase().find("</head>") else {
        return text.into_bytes();
    };
    // Under the host folder: the navigator's frame policy allows the manifest's folder only,
    // and the router takes the folder off again.
    let link = format!(
        "<link rel=\"stylesheet storyarc-fonts\" type=\"text/css\" href=\"{SCHEME}://{BOOK_HOST}/.storyarc/{FONT_SHEET}\"/>"
    );
    let mut out = String::with_capacity(text.len() + link.len());
    out.push_str(&text[..close]);
    out.push_str(&link);
    out.push_str(&text[close..]);
    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `ebook-reader`, *Theme choice* and *Themes are named, not numbered*: six presets, each
    /// with its own colours from the tokens, and *Original* keeps the publisher's styles.
    #[test]
    fn every_preset_has_its_token_colours_and_original_keeps_the_book() {
        for preset in Preset::ALL {
            let (background, text) = preset.colours();
            assert!(
                crate::settings::Rgb::parse(&background).is_some()
                    && crate::settings::Rgb::parse(&text).is_some(),
                "{} has {background} on {text}",
                preset.key()
            );
            assert!(!preset.title().is_empty());
        }
        assert_eq!(Preset::Paper.colours().0, "#F5F1EC");
        let original = Look {
            preset: Preset::Original,
            ..Look::default()
        }
        .axes();
        assert_eq!(original["publisherStyles"], true);
        assert!(!original.contains_key("backgroundColor"));
    }

    /// *Typography controls* and *An axis is inert while publisher styles are on*: size, face,
    /// weight and margins reach the page under every preset; spacing, alignment and hyphens
    /// only when the publisher's stylesheet is off.
    #[test]
    fn the_axes_follow_the_values_and_original_drops_the_dependent_ones() {
        let values = Values {
            typeface: Typeface::Atkinson,
            font_size: 130,
            bold: true,
            line_height: 1.8,
            margins: 2.0,
            alignment: Alignment::Justified,
            hyphens: true,
            ..Values::default()
        };
        let look = Look {
            preset: Preset::Calm,
            values,
            scroll: true,
            brightness: 0.8,
            ..Look::default()
        };
        let axes = look.axes();
        assert_eq!(axes["fontSize"], 1.3);
        assert_eq!(axes["fontFamily"], "Atkinson Hyperlegible");
        assert_eq!(axes["fontWeight"], 1.5);
        assert_eq!(axes["pageGutter"], 48.0);
        assert_eq!(axes["scroll"], true);
        assert_eq!(axes["darkenFilter"], 20.0);
        assert_eq!(axes["lineHeight"], 1.8);
        assert_eq!(axes["textAlign"], "justify");
        assert_eq!(axes["hyphens"], true);
        let original = Look {
            preset: Preset::Original,
            ..look
        }
        .axes();
        assert_eq!(original["fontSize"], 1.3);
        assert_eq!(original["fontFamily"], "Atkinson Hyperlegible");
        for inert in ["lineHeight", "paragraphSpacing", "textAlign", "hyphens"] {
            assert!(!original.contains_key(inert), "{inert} reached the page");
        }
        let message: Value = serde_json::from_str(&look.theme_message(4)).unwrap();
        assert_eq!(message["type"], "theme");
        assert_eq!(message["theme"]["name"], "calm");
        assert_eq!(message["theme"]["axes"]["fontSize"], 1.3);
    }

    /// *Changing type size mid-chapter* steps the phones' ladder, held at both ends; *Getting
    /// back to the preset* is the defaults again, and only then is the preset unmodified.
    #[test]
    fn the_size_ladder_holds_its_ends_and_the_reset_clears_modified() {
        let mut values = Values::default();
        values = values.step_size(true);
        assert_eq!(values.font_size, 115);
        for _ in 0..20 {
            values = values.step_size(true);
        }
        assert_eq!(values.font_size, 200);
        for _ in 0..20 {
            values = values.step_size(false);
        }
        assert_eq!(values.font_size, 70);
        let look = Look {
            values,
            ..Look::default()
        };
        assert!(look.is_modified());
        assert!(!Look::default().is_modified());
    }

    /// *Theme follows appearance*: the light and dark pair, only when the reader asked for it.
    #[test]
    fn the_look_follows_the_appearance_only_when_asked_and_round_trips() {
        let mut look = Look::default();
        assert_eq!(look.preset_for(true), None);
        look.follows = true;
        assert_eq!(look.preset_for(true), Some(Preset::Focus));
        assert_eq!(look.preset_for(false), Some(Preset::Paper));
        look.values = look.values.step_size(true);
        look.values.typeface = Typeface::EbGaramond;
        look.preset = Preset::Quiet;
        look.brightness = 0.7;
        look.scroll = true;
        assert_eq!(Look::restore(&look.save()), look);
        assert_eq!(Look::restore("size=12\nmargins=9\nbrightness=0.1\n"), Look::default());
    }

    /// *Bundled typefaces*: the five faces are served on the book's scheme and every chapter
    /// links their stylesheet; nothing else is touched.
    #[test]
    fn the_five_faces_are_served_and_linked_from_every_chapter() {
        let css = faces_css();
        for typeface in [
            Typeface::Literata,
            Typeface::SourceSerif,
            Typeface::EbGaramond,
            Typeface::Bitter,
            Typeface::Atkinson,
        ] {
            let family = typeface.css_family().unwrap();
            assert!(css.contains(&format!("\"{family}\"")), "{family} has no face");
        }
        for (stem, _) in FACES {
            let (bytes, media_type) = font_resource(&format!("storyarc-fonts/{stem}.ttf")).unwrap();
            assert!(bytes.len() > 10_000 && media_type == "font/ttf", "{stem}");
            assert!(css.contains(&format!("\"{stem}.ttf\"")), "{stem} is not in the sheet");
        }
        assert!(font_resource("storyarc-fonts/../OEBPS/a.ttf").is_none());
        assert_eq!(font_resource(FONT_SHEET).unwrap().1, "text/css");
        let chapter = linking(b"<html><HEAD><title>x</title></HEAD><body/></html>".to_vec(), "application/xhtml+xml");
        let chapter = String::from_utf8(chapter).unwrap();
        assert!(chapter.contains("rel=\"stylesheet storyarc-fonts\""));
        assert!(chapter.contains("storyarc-epub://book/.storyarc/storyarc-fonts/faces.css"));
        assert!(chapter.find("storyarc-fonts").unwrap() < chapter.find("</HEAD>").unwrap());
        assert_eq!(linking(b"body{}".to_vec(), "text/css"), b"body{}");
    }

    #[test]
    fn the_progress_line_names_the_book_share_and_the_chapter_left() {
        let line = progress_line(0.426, 0.25);
        assert!(line.contains("43") && line.contains("75"), "{line}");
    }
}
