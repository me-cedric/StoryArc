//! What the app does with paths it is handed (task 2.30): by the file manager, on the
//! command line, by a drop on a window, or from the Open File dialog. Pure, so the rules
//! test on any host; `launch.rs` hands GTK's files to it.
//!
//! `desktop-experience`, Dropping files and folders on the app and File associations and
//! Open With: each file opens in its own reader window up to a limit the app names, the
//! rest are listed, a folder is offered as a folder library, and a file that cannot be
//! reached is named with its reason while the others still open.

use std::path::{Path, PathBuf};

/// The most reader windows one drop or one launch opens.
pub const OPEN_LIMIT: usize = 10;

/// What is at a path, as far as opening it goes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    File,
    Folder,
    Missing,
}

impl Kind {
    pub fn of(path: &Path) -> Self {
        if path.is_dir() {
            Self::Folder
        } else if path.exists() {
            Self::File
        } else {
            Self::Missing
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct OpenPlan {
    /// Each opens in its own reader window, in the order given.
    pub open: Vec<PathBuf>,
    /// Offered as folder libraries, each only when the reader agrees.
    pub folders: Vec<PathBuf>,
    /// Named in grey: the file's name and that it cannot be reached.
    pub unreachable: Vec<String>,
    /// Past the limit: listed so the reader can open them from the library.
    pub left_over: Vec<PathBuf>,
}

impl OpenPlan {
    /// Sorts what was handed over. A path given twice opens once.
    pub fn of(paths: &[PathBuf], kind: impl Fn(&Path) -> Kind) -> Self {
        let mut plan = Self::default();
        let mut seen: Vec<&PathBuf> = Vec::new();
        for path in paths {
            if seen.contains(&path) {
                continue;
            }
            seen.push(path);
            match kind(path) {
                Kind::Folder => plan.folders.push(path.clone()),
                Kind::Missing => plan
                    .unreachable
                    .push(format!("{}: the file cannot be reached", name(path))),
                Kind::File if plan.open.len() < OPEN_LIMIT => plan.open.push(path.clone()),
                Kind::File => plan.left_over.push(path.clone()),
            }
        }
        plan
    }

    /// The grey line that lists what was past the limit, or nothing.
    pub fn left_over_note(&self) -> Option<String> {
        if self.left_over.is_empty() {
            return None;
        }
        let names: Vec<String> = self.left_over.iter().map(|path| name(path)).collect();
        Some(format!(
            "{OPEN_LIMIT} files open at once at most. Not opened: {}",
            names.join(", ")
        ))
    }
}

/// The file's name as the reader knows it.
pub fn name(path: &Path) -> String {
    path.file_name().map_or_else(
        || path.display().to_string(),
        |name| name.to_string_lossy().into_owned(),
    )
}

/// The static actions of the desktop entry (`desktop-experience`, Recent items in the
/// system's launcher): each is a command-line option the entry's `Exec` passes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LaunchAction {
    ContinueReading,
    Library,
    Downloads,
}

impl LaunchAction {
    pub const ALL: [Self; 3] = [Self::ContinueReading, Self::Library, Self::Downloads];

    /// The option name, which is also the application action it runs.
    pub fn name(self) -> &'static str {
        match self {
            Self::ContinueReading => "continue-reading",
            Self::Library => "library",
            Self::Downloads => "downloads",
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::ContinueReading => "Open the publication read last",
            Self::Library => "Show the library",
            Self::Downloads => "Show the downloads",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kind(path: &Path) -> Kind {
        let text = path.to_string_lossy();
        if text.ends_with('/') || !text.contains('.') {
            Kind::Folder
        } else if text.contains("gone") {
            Kind::Missing
        } else {
            Kind::File
        }
    }

    fn paths(names: &[&str]) -> Vec<PathBuf> {
        names.iter().map(PathBuf::from).collect()
    }

    #[test]
    fn each_file_opens_once_in_order_and_a_folder_is_offered() {
        let plan = OpenPlan::of(&paths(&["/a.cbz", "/Comics", "/b.cbr", "/a.cbz"]), kind);
        assert_eq!(plan.open, paths(&["/a.cbz", "/b.cbr"]));
        assert_eq!(plan.folders, paths(&["/Comics"]));
        assert!(plan.unreachable.is_empty() && plan.left_over.is_empty());
        assert_eq!(plan.left_over_note(), None);
    }

    #[test]
    fn a_file_that_cannot_be_reached_is_named_and_the_others_still_open() {
        let plan = OpenPlan::of(&paths(&["/gone.cbz", "/b.cbz"]), kind);
        assert_eq!(plan.open, paths(&["/b.cbz"]));
        assert_eq!(plan.unreachable, ["gone.cbz: the file cannot be reached"]);
    }

    #[test]
    fn past_the_limit_the_rest_are_listed_by_name() {
        let names: Vec<String> = (0..OPEN_LIMIT + 2).map(|i| format!("/{i}.cbz")).collect();
        let names: Vec<&str> = names.iter().map(String::as_str).collect();
        let plan = OpenPlan::of(&paths(&names), kind);
        assert_eq!(plan.open.len(), OPEN_LIMIT);
        assert_eq!(plan.left_over, paths(&["/10.cbz", "/11.cbz"]));
        assert_eq!(
            plan.left_over_note().as_deref(),
            Some("10 files open at once at most. Not opened: 10.cbz, 11.cbz")
        );
    }

    #[test]
    fn nothing_handed_over_plans_nothing() {
        assert_eq!(OpenPlan::of(&[], kind), OpenPlan::default());
    }

    #[test]
    fn the_desktop_entry_actions_are_the_three_the_spec_names() {
        let names: Vec<&str> = LaunchAction::ALL.iter().map(|a| a.name()).collect();
        assert_eq!(names, ["continue-reading", "library", "downloads"]);
        let entry = include_str!("../data/com.mecedric.StoryArc.desktop");
        for action in LaunchAction::ALL {
            assert!(
                entry.contains(&format!("Exec=storyarc --{}", action.name())),
                "{}",
                action.name()
            );
        }
        // `%U`, not `%F`: a `storyarc://` link (task 5.8) is a URI the entry must pass on.
        assert!(entry.contains("Exec=storyarc %U"));
        assert!(entry.contains("MimeType="));
        assert!(entry.contains("x-scheme-handler/storyarc;"));
        assert!(!entry.contains("application/x-cb7"));
    }

    #[test]
    fn the_real_file_system_answers_kind() {
        assert_eq!(
            Kind::of(Path::new(env!("CARGO_MANIFEST_DIR"))),
            Kind::Folder
        );
        let this_file = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
        assert_eq!(Kind::of(&this_file), Kind::File);
        assert_eq!(Kind::of(Path::new("/nonexistent/x.cbz")), Kind::Missing);
    }
}
