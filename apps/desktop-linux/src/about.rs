//! About StoryArc and what changed in this version (`settings-and-about`, About and What
//! changed in this version).
//!
//! The About dialog names the author by the handle, as the one control that opens the
//! profile; links the repository; states that the app is free with an optional link to
//! support it; names the components the app is built on; and offers to report a problem
//! on the issue tracker with the version, the platform and the device class filled in and
//! nothing personal. Its legal section carries the generated third-party notices (task 6.3),
//! shipped inside the binary so a Flatpak and a source build show the same file.
//!
//! What changed is shown once, after an update, and never on a first launch. A version
//! with nothing a reader would notice shows nothing and is still recorded as seen. The
//! notes ship with the app, so an update installed offline shows them in full, and About
//! lists them again without changing what is seen.

use adw::prelude::*;
use gtk::glib;

use crate::strings::tr;

pub const REPOSITORY: &str = "https://github.com/me-cedric/StoryArc";
/// `THIRD_PARTY_NOTICES.md` as `scripts/notices.mjs` generates it; `pnpm notices:check` keeps
/// it in step with the manifests, so nothing is listed here by hand.
pub const NOTICES: &str = include_str!("../../../THIRD_PARTY_NOTICES.md");
const PROFILE: &str = "https://github.com/me-cedric";
const SUPPORT: &str = "https://ko-fi.com/mecedric";

/// What changed in each desktop version, newest first, as catalogue keys and English.
/// The first desktop version has nothing to catch a reader up on: there was no earlier
/// desktop app to compare with.
pub const NOTES: &[(&str, &[(&str, &str)])] = &[];

/// Whether to show what changed now, and the version to record as seen afterwards.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Decision {
    pub show: bool,
    pub record: String,
}

/// `last_seen` is the version recorded on the previous launch, `None` on a first ever
/// launch; `has_notes` is whether the current version has anything to say.
pub fn decide(last_seen: Option<&str>, current: &str, has_notes: bool) -> Decision {
    let updated = last_seen.is_some_and(|seen| seen != current);
    Decision {
        show: updated && has_notes,
        record: current.to_owned(),
    }
}

/// The notes of `version`, when it has any.
pub fn notes_for(version: &str) -> Option<&'static [(&'static str, &'static str)]> {
    NOTES
        .iter()
        .find(|(candidate, _)| *candidate == version)
        .map(|(_, notes)| *notes)
        .filter(|notes| !notes.is_empty())
}

/// The issue tracker's new-issue address with the version, the platform and the device
/// class filled in. Nothing personal: no path, no user name, no library.
pub fn problem_report_url(version: &str, platform: &str) -> String {
    let body =
        format!("StoryArc {version}\nPlatform: {platform}\nDevice: desktop\n\nWhat happened:\n");
    format!(
        "{REPOSITORY}/issues/new?body={}",
        glib::Uri::escape_string(&body, None, false)
    )
}

/// The platform line: the toolkit versions the app runs on.
pub fn platform() -> String {
    format!(
        "Linux, GTK {}.{}.{}, libadwaita {}.{}.{}",
        gtk::major_version(),
        gtk::minor_version(),
        gtk::micro_version(),
        adw::major_version(),
        adw::minor_version(),
        adw::micro_version()
    )
}

/// The notes as the markup `AdwAboutDialog` reads for its release notes.
fn release_notes(notes: &[(&str, &str)]) -> String {
    let items: String = notes
        .iter()
        .map(|(key, english)| format!("<li>{}</li>", glib::markup_escape_text(&tr(key, english))))
        .collect();
    format!("<ul>{items}</ul>")
}

pub fn dialog(version: &str) -> adw::AboutDialog {
    let dialog = adw::AboutDialog::builder()
        .application_name("StoryArc")
        .application_icon(crate::APP_ID)
        .developer_name("@me-cedric")
        .version(version)
        .comments(tr(
            "about.free",
            "Completely free and open source. No paid tier, no advertising.",
        ))
        .website(REPOSITORY)
        .support_url(SUPPORT)
        .issue_url(problem_report_url(version, &platform()))
        .license_type(gtk::License::MitX11)
        .build();
    dialog.add_credit_section(
        Some(&tr("about.author", "By @me-cedric")),
        &[&format!("@me-cedric {PROFILE}")],
    );
    dialog.add_acknowledgement_section(
        Some(&tr("about.acknowledgements", "Acknowledgements")),
        &[
            "GTK https://gtk.org",
            "libadwaita https://gnome.pages.gitlab.gnome.org/libadwaita/",
            "gtk-rs https://gtk-rs.org",
            "libarchive https://libarchive.org",
            "ICU4X https://github.com/unicode-org/icu4x",
            "SQLite https://sqlite.org",
        ],
    );
    dialog.add_legal_section("GTK", None, gtk::License::Lgpl21, None);
    dialog.add_legal_section("libadwaita", None, gtk::License::Lgpl21, None);
    dialog.add_legal_section("gtk-rs", None, gtk::License::MitX11, None);
    dialog.add_legal_section("libarchive", None, gtk::License::Bsd, None);
    dialog.add_legal_section(
        "ICU4X",
        None,
        gtk::License::Custom,
        Some("Unicode License v3"),
    );
    dialog.add_legal_section("SQLite", None, gtk::License::Custom, Some("Public domain"));
    dialog.add_legal_section(
        &tr("about.acknowledgements", "Acknowledgements"),
        None,
        gtk::License::Custom,
        Some(NOTICES),
    );
    if let Some(notes) = NOTES.iter().find(|(_, notes)| !notes.is_empty()) {
        dialog.set_release_notes_version(notes.0);
        dialog.set_release_notes(&release_notes(notes.1));
    }
    dialog
}

/// After an update with something to say, the About dialog opens on its notes once.
/// One action dismisses it; the version is recorded either way.
pub fn after_launch(parent: Option<&impl IsA<gtk::Widget>>, last_seen: Option<&str>) -> String {
    let version = storyarc_core::version();
    let decision = decide(last_seen, version, notes_for(version).is_some());
    if decision.show {
        dialog(version).present(parent);
    }
    decision.record
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_first_ever_launch_shows_nothing_and_records_the_version() {
        assert_eq!(
            decide(None, "0.2.0", true),
            Decision {
                show: false,
                record: "0.2.0".into()
            }
        );
    }

    #[test]
    fn an_update_with_something_to_say_shows_it_once() {
        assert!(decide(Some("0.1.0"), "0.2.0", true).show);
        assert!(!decide(Some("0.2.0"), "0.2.0", true).show, "not again");
    }

    #[test]
    fn a_version_with_nothing_worth_saying_shows_nothing_and_is_still_seen() {
        let decision = decide(Some("0.1.0"), "0.2.0", false);
        assert!(!decision.show);
        assert_eq!(decision.record, "0.2.0");
        assert_eq!(notes_for("0.1.0"), None);
    }

    /// The components the notices list: the name between the brackets of each table row.
    fn components(notices: &str) -> Vec<String> {
        notices
            .lines()
            .filter_map(|line| line.trim().strip_prefix("| [")?.split_once("]("))
            .map(|(name, _)| name.to_owned())
            .collect()
    }

    #[test]
    fn the_generated_notices_list_pdfium_and_libarchive() {
        let listed = components(NOTICES);
        assert!(listed.iter().any(|name| name.starts_with("PDFium")));
        assert!(listed.iter().any(|name| name.starts_with("libarchive")));
        assert!(listed.iter().any(|name| name.starts_with("Rust ")));
        assert_eq!(
            components("| [Foo 1.0](https://x) | `MIT` |\n  | [Bar](https://y) | `ISC` |\n| --- |"),
            ["Foo 1.0", "Bar"]
        );
    }

    #[test]
    fn a_problem_report_carries_the_version_and_platform_and_nothing_personal() {
        let url = problem_report_url("0.1.0", "Linux, GTK 4.14.5, libadwaita 1.5.0");
        assert!(url.starts_with("https://github.com/me-cedric/StoryArc/issues/new?body="));
        assert!(url.contains("StoryArc%200.1.0"));
        assert!(url.contains("GTK%204.14.5"));
        assert!(url.contains("Device%3A%20desktop"));
        let home = std::env::var("HOME").unwrap_or_default();
        assert!(home.is_empty() || !url.contains(&home));
        assert!(!url.contains('\n'));
    }
}
