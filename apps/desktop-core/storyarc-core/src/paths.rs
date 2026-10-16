//! Where the app keeps its data on each system (task 2.4 of `desktop-clients`; design.md,
//! Decision 8).
//!
//! `desktop-experience`, *Storage on a desktop*: the app keeps its data in the system's
//! per-user locations, keeps downloads and the cover cache out of any roaming or
//! synchronised folder, and shows what it uses. So:
//!
//! | System | Data | Cache and downloads |
//! | --- | --- | --- |
//! | Windows | `%LOCALAPPDATA%\StoryArc` (never `%APPDATA%`, which roams; MSIX redirects `%LOCALAPPDATA%` into the package on its own) | the same root |
//! | Linux | `$XDG_DATA_HOME/com.mecedric.StoryArc` (Flatpak sets `XDG_DATA_HOME` to `~/.var/app/com.mecedric.StoryArc/data`) | `$XDG_CACHE_HOME/com.mecedric.StoryArc` |
//! | macOS host | `~/Library/Application Support/com.mecedric.storyarc` (the Mac app itself uses its container through StoryArcKit; this is for the core's own tests and tools on a Mac) | `~/Library/Caches/com.mecedric.storyarc` |
//!
//! Resolved from an environment the caller hands over, so the three systems' rules are
//! tested on any host; `StorageLocations::current()` reads the real one.

use std::path::{Path, PathBuf};

/// The system whose rules apply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Windows,
    Linux,
    MacOs,
}

impl Platform {
    /// The system this binary runs on.
    pub fn host() -> Self {
        if cfg!(target_os = "windows") {
            Self::Windows
        } else if cfg!(target_os = "macos") {
            Self::MacOs
        } else {
            Self::Linux
        }
    }
}

/// The folder names the app files itself under: the Windows app's package name and the
/// Linux and macOS app ids.
pub const WINDOWS_FOLDER: &str = "StoryArc";
pub const LINUX_APP_ID: &str = "com.mecedric.StoryArc";
pub const MACOS_BUNDLE_ID: &str = "com.mecedric.storyarc";

/// The app's per-user folders.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageLocations {
    /// The library's records: the SQLite store, preferences.
    pub data: PathBuf,
    /// Covers and other things the app can rebuild.
    pub cache: PathBuf,
    /// Publications the reader kept for offline reading. Never in a roaming folder.
    pub downloads: PathBuf,
    /// Whether the app is running inside a Flatpak sandbox, where folders arrive through
    /// the document portal and the paths above are the sandbox's own.
    pub is_flatpak: bool,
}

impl StorageLocations {
    /// The locations for the host system, read from the process environment. Costs a
    /// handful of environment reads and one `stat` of `/.flatpak-info`.
    pub fn current() -> Self {
        let platform = Platform::host();
        let is_flatpak = platform == Platform::Linux && Path::new("/.flatpak-info").is_file();
        Self::resolve(platform, |name| std::env::var(name).ok(), is_flatpak)
    }

    /// The locations under one system's rules, given its environment. Pure.
    ///
    /// `env` answers the variables the system defines; a variable it does not answer is
    /// unset. `is_flatpak` says whether the Linux process is sandboxed: a Flatpak already
    /// sets `XDG_DATA_HOME` and `XDG_CACHE_HOME` to its `~/.var/app/<id>/…` folders, and
    /// when it has not — a broken launch — the app derives them from `HOME` so it never
    /// writes beside the host's own data by mistake.
    pub fn resolve(platform: Platform, env: impl Fn(&str) -> Option<String>, is_flatpak: bool) -> Self {
        match platform {
            Platform::Windows => {
                // %LOCALAPPDATA% and never %APPDATA%: the latter roams with the profile.
                // MSIX redirects %LOCALAPPDATA% writes into the package's own folder, so
                // the same path serves a packaged and an unpackaged app.
                let local = env("LOCALAPPDATA")
                    .map(PathBuf::from)
                    .or_else(|| env("USERPROFILE").map(|home| Path::new(&home).join("AppData").join("Local")))
                    .unwrap_or_else(|| PathBuf::from(r"C:\Users\Default\AppData\Local"));
                let root = local.join(WINDOWS_FOLDER);
                Self {
                    data: root.join("Data"),
                    cache: root.join("Cache"),
                    downloads: root.join("Downloads"),
                    is_flatpak: false,
                }
            }
            Platform::Linux => {
                let home = env("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
                let (data_home, cache_home) = if is_flatpak {
                    let sandbox = home.join(".var").join("app").join(LINUX_APP_ID);
                    (
                        env("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| sandbox.join("data")),
                        env("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|| sandbox.join("cache")),
                    )
                } else {
                    (
                        env("XDG_DATA_HOME")
                            .filter(|value| !value.is_empty())
                            .map(PathBuf::from)
                            .unwrap_or_else(|| home.join(".local").join("share")),
                        env("XDG_CACHE_HOME")
                            .filter(|value| !value.is_empty())
                            .map(PathBuf::from)
                            .unwrap_or_else(|| home.join(".cache")),
                    )
                };
                let data = data_home.join(LINUX_APP_ID);
                Self {
                    cache: cache_home.join(LINUX_APP_ID),
                    downloads: data.join("downloads"),
                    data,
                    is_flatpak,
                }
            }
            Platform::MacOs => {
                let home = env("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
                let library = home.join("Library");
                let data = library.join("Application Support").join(MACOS_BUNDLE_ID);
                Self {
                    cache: library.join("Caches").join(MACOS_BUNDLE_ID),
                    downloads: data.join("Downloads"),
                    data,
                    is_flatpak: false,
                }
            }
        }
    }

    /// The SQLite file the store opens.
    pub fn store_file(&self) -> PathBuf {
        self.data.join("library.sqlite")
    }

    /// Whether any of the folders is one the system synchronises between machines: a
    /// Windows roaming profile folder, or a cloud-synced home folder named as such.
    /// `desktop-experience` forbids writing there.
    pub fn is_roaming(path: &Path) -> bool {
        path.components().any(|component| {
            let name = component.as_os_str().to_string_lossy();
            name.eq_ignore_ascii_case("Roaming") || name.eq_ignore_ascii_case("OneDrive")
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        move |name: &str| map.get(name).cloned()
    }

    fn none_roam(locations: &StorageLocations) {
        for path in [&locations.data, &locations.cache, &locations.downloads] {
            assert!(!StorageLocations::is_roaming(path), "{} roams", path.display());
        }
    }

    #[test]
    fn windows_uses_local_app_data_and_never_the_roaming_profile() {
        let locations = StorageLocations::resolve(
            Platform::Windows,
            env(&[
                ("LOCALAPPDATA", r"C:\Users\Reader\AppData\Local"),
                ("APPDATA", r"C:\Users\Reader\AppData\Roaming"),
            ]),
            false,
        );
        assert_eq!(locations.data, PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Data"));
        assert_eq!(locations.cache, PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Cache"));
        assert_eq!(
            locations.downloads,
            PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Downloads")
        );
        assert!(!locations.is_flatpak);
        none_roam(&locations);
        // The MSIX redirect is the system's: %LOCALAPPDATA% is what a packaged app reads,
        // and the path is the same string either way.
        let packaged = StorageLocations::resolve(
            Platform::Windows,
            env(&[("LOCALAPPDATA", r"C:\Users\Reader\AppData\Local")]),
            false,
        );
        assert_eq!(packaged, locations);
    }

    #[test]
    fn windows_without_local_app_data_derives_it_from_the_profile() {
        let locations = StorageLocations::resolve(
            Platform::Windows,
            env(&[("USERPROFILE", r"C:\Users\Reader")]),
            false,
        );
        assert_eq!(locations.data, PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Data"));
    }

    #[test]
    fn linux_follows_xdg_and_falls_back_to_the_home_defaults() {
        let explicit = StorageLocations::resolve(
            Platform::Linux,
            env(&[
                ("HOME", "/home/reader"),
                ("XDG_DATA_HOME", "/data/reader/share"),
                ("XDG_CACHE_HOME", "/data/reader/cache"),
            ]),
            false,
        );
        assert_eq!(explicit.data, PathBuf::from("/data/reader/share/com.mecedric.StoryArc"));
        assert_eq!(explicit.cache, PathBuf::from("/data/reader/cache/com.mecedric.StoryArc"));
        assert_eq!(
            explicit.downloads,
            PathBuf::from("/data/reader/share/com.mecedric.StoryArc/downloads")
        );
        none_roam(&explicit);

        let defaults = StorageLocations::resolve(Platform::Linux, env(&[("HOME", "/home/reader")]), false);
        assert_eq!(defaults.data, PathBuf::from("/home/reader/.local/share/com.mecedric.StoryArc"));
        assert_eq!(defaults.cache, PathBuf::from("/home/reader/.cache/com.mecedric.StoryArc"));
        assert_eq!(defaults.store_file(), defaults.data.join("library.sqlite"));
    }

    #[test]
    fn a_flatpak_keeps_everything_under_its_own_var_app_folder() {
        // What the sandbox sets.
        let sandboxed = StorageLocations::resolve(
            Platform::Linux,
            env(&[
                ("HOME", "/home/reader"),
                ("XDG_DATA_HOME", "/home/reader/.var/app/com.mecedric.StoryArc/data"),
                ("XDG_CACHE_HOME", "/home/reader/.var/app/com.mecedric.StoryArc/cache"),
            ]),
            true,
        );
        assert_eq!(
            sandboxed.data,
            PathBuf::from("/home/reader/.var/app/com.mecedric.StoryArc/data/com.mecedric.StoryArc")
        );
        assert!(sandboxed.is_flatpak);
        // And what the app derives when the sandbox did not set them.
        let derived = StorageLocations::resolve(Platform::Linux, env(&[("HOME", "/home/reader")]), true);
        assert_eq!(
            derived.cache,
            PathBuf::from("/home/reader/.var/app/com.mecedric.StoryArc/cache/com.mecedric.StoryArc")
        );
        none_roam(&derived);
    }

    #[test]
    fn a_mac_host_uses_application_support_and_caches() {
        let locations =
            StorageLocations::resolve(Platform::MacOs, env(&[("HOME", "/Users/reader")]), false);
        assert_eq!(
            locations.data,
            PathBuf::from("/Users/reader/Library/Application Support/com.mecedric.storyarc")
        );
        assert_eq!(
            locations.cache,
            PathBuf::from("/Users/reader/Library/Caches/com.mecedric.storyarc")
        );
        none_roam(&locations);
    }

    #[test]
    fn a_roaming_folder_is_recognised_by_name() {
        assert!(StorageLocations::is_roaming(Path::new(r"C:\Users\R\AppData\Roaming\StoryArc")));
        assert!(StorageLocations::is_roaming(Path::new("/Users/r/OneDrive/StoryArc")));
        assert!(!StorageLocations::is_roaming(Path::new(r"C:\Users\R\AppData\Local\StoryArc")));
    }

    #[test]
    fn the_host_resolves_to_something_absolute_and_not_roaming() {
        let current = StorageLocations::current();
        assert!(current.data.is_absolute());
        none_roam(&current);
    }
}
