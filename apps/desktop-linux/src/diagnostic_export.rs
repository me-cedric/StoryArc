//! Exporting a diagnostic to a file (task 3.19; `desktop-experience`, *Exporting a
//! diagnostic to a file*). The text is shown in full first; a save dialog asks where; a file
//! is written there and nowhere else. Pure over the core's `DiagnosticReport`: every
//! credential held and every hostname is redacted by the core before the text exists.

use std::path::{Path, PathBuf};

use storyarc_core::diagnostics::DiagnosticReport;
use storyarc_core::secrets::Secret;

use crate::strings::{tr, tr_args};

/// What the reader sees and saves. `secrets` is every secret the app holds.
pub fn report(
    version: &str,
    flatpak: bool,
    sources: &[(&str, &str)],
    secrets: &[&Secret],
) -> String {
    let mut report = DiagnosticReport::new("StoryArc diagnostic");
    report.section(
        "App",
        [
            ("version", version),
            ("platform", "linux"),
            ("sandbox", if flatpak { "flatpak" } else { "none" }),
        ],
    );
    report.section("Sources", sources.iter().copied());
    report.render(secrets)
}

/// What the save came to.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Exported {
    Written(PathBuf),
    /// The dialog was cancelled: nothing was written and nothing is kept.
    Cancelled,
    /// The place cannot be written: named, and another is offered. Nothing elsewhere.
    CannotWrite {
        place: String,
        message: String,
    },
}

/// Writes `text` to what the save dialog chose. `chosen` is `None` for a cancel.
pub fn write(chosen: Option<&Path>, text: &str) -> Exported {
    let Some(path) = chosen else {
        return Exported::Cancelled;
    };
    match std::fs::write(path, text) {
        Ok(()) => Exported::Written(path.to_path_buf()),
        Err(_) => {
            let place = path
                .parent()
                .map_or_else(|| path.display().to_string(), |p| p.display().to_string());
            Exported::CannotWrite {
                message: tr_args(
                    "diagnostics.cannotWrite %s",
                    "StoryArc cannot write to %s. Choose another place.",
                    &[&place],
                ),
                place,
            }
        }
    }
}

pub fn title() -> String {
    tr("diagnostics.title", "Export diagnostics")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scratch::Scratch;

    #[test]
    fn the_report_holds_no_secret_in_any_encoding_and_no_hostname() {
        let secret = Secret::new("lovelace1815");
        let text = report(
            "0.1.0",
            false,
            &[(
                "nas",
                "smb://nas.example.org/comics lovelace1815 bG92ZWxhY2UxODE1",
            )],
            &[&secret],
        );
        assert!(!text.contains("lovelace1815"));
        assert!(!text.contains("nas.example.org"));
        assert!(text.contains("[App]") && text.contains("version = 0.1.0"));
    }

    #[test]
    fn saving_writes_the_text_to_the_chosen_file() {
        let dir = Scratch::new("diag");
        let file = dir.join("diagnostic.txt");
        assert_eq!(write(Some(&file), "x"), Exported::Written(file.clone()));
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "x");
    }

    #[test]
    fn a_place_that_cannot_be_written_is_named_and_nothing_is_written_elsewhere() {
        let dir = Scratch::new("diag");
        let missing = dir.join("no-such-folder").join("diagnostic.txt");
        let Exported::CannotWrite { place, message } = write(Some(&missing), "x") else {
            panic!("a missing folder cannot be written");
        };
        assert!(place.ends_with("no-such-folder"));
        assert!(message.contains(&place));
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
    }

    #[test]
    fn cancelling_writes_nothing() {
        assert_eq!(write(None, "x"), Exported::Cancelled);
    }
}
