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

/// Folder names that mean the system copies the folder between machines.
const ROAMING_FOLDERS: [&str; 3] = ["Roaming", "OneDrive", "iCloud Drive"];

/// The sandbox the app runs in, which moves where its folders really are.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Sandbox {
    /// A source build, an unpackaged Windows app, or a Mac host.
    None,
    /// A Linux Flatpak: folders arrive through the document portal and the data folders are
    /// the sandbox's own `~/.var/app/<id>/…`.
    Flatpak,
    /// A packaged Windows app. Its writes to `%LOCALAPPDATA%` land in the package's private
    /// `%LOCALAPPDATA%\Packages\<family name>\LocalCache\Local` and are merged back into the
    /// app's view, so the app opens the same path either way and only the storage view needs
    /// to know where the bytes are. The family name comes from the Windows app
    /// (`Package.Current.Id.FamilyName`): the core cannot ask WinRT.
    Msix { package_family_name: String },
}

/// The app's per-user folders.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageLocations {
    /// The library's records: the SQLite store, preferences.
    pub data: PathBuf,
    /// Covers and other things the app can rebuild.
    pub cache: PathBuf,
    /// Publications the reader kept for offline reading. Never in a roaming folder.
    pub downloads: PathBuf,
    /// The sandbox the folders above were resolved for.
    pub sandbox: Sandbox,
    /// For a packaged Windows app: `%LOCALAPPDATA%` as the app sees it, and where it is on disk.
    msix_redirect: Option<(String, String)>,
}

impl StorageLocations {
    /// The locations for the host system, read from the process environment. Costs a
    /// handful of environment reads and one `stat` of `/.flatpak-info`. A packaged Windows
    /// app calls [`StorageLocations::resolve`] with [`Sandbox::Msix`] instead, because only
    /// it knows its package family name.
    pub fn current() -> Self {
        let platform = Platform::host();
        let sandbox = if platform == Platform::Linux && Path::new("/.flatpak-info").is_file() {
            Sandbox::Flatpak
        } else {
            Sandbox::None
        };
        Self::resolve(platform, |name| std::env::var(name).ok(), sandbox)
    }

    /// The locations under one system's rules, given its environment. Pure, and the same on
    /// every host: Windows paths are built with `\` whatever system runs the tests.
    ///
    /// `env` answers the variables the system defines; a variable it does not answer, or
    /// answers empty, is unset. In a Flatpak the sandbox already sets `XDG_DATA_HOME` and
    /// `XDG_CACHE_HOME` to its `~/.var/app/<id>/…` folders, and when it has not — a broken
    /// launch — the app derives them from `HOME` so it never writes beside the host's own
    /// data by mistake. A sandbox that does not belong to `platform` is ignored.
    pub fn resolve(
        platform: Platform,
        env: impl Fn(&str) -> Option<String>,
        sandbox: Sandbox,
    ) -> Self {
        let env = |name: &str| env(name).filter(|value| !value.is_empty());
        match platform {
            Platform::Windows => Self::windows(&env, sandbox),
            Platform::Linux => Self::linux(&env, sandbox == Sandbox::Flatpak),
            Platform::MacOs => {
                let home = env("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
                let library = home.join("Library");
                let data = library.join("Application Support").join(MACOS_BUNDLE_ID);
                Self {
                    cache: library.join("Caches").join(MACOS_BUNDLE_ID),
                    downloads: data.join("Downloads"),
                    data,
                    sandbox: Sandbox::None,
                    msix_redirect: None,
                }
            }
        }
    }

    fn windows(env: &impl Fn(&str) -> Option<String>, sandbox: Sandbox) -> Self {
        // %LOCALAPPDATA% and never %APPDATA%: the latter roams with the profile.
        let local = env("LOCALAPPDATA")
            .or_else(|| env("USERPROFILE").map(|home| windows_join(&home, &["AppData", "Local"])))
            .unwrap_or_else(|| r"C:\Users\Default\AppData\Local".to_owned());
        let local = local.trim_end_matches(['\\', '/']).to_owned();
        let root = windows_join(&local, &[WINDOWS_FOLDER]);
        let (sandbox, msix_redirect) = match sandbox {
            Sandbox::Msix {
                package_family_name,
            } if !package_family_name.is_empty() => {
                let private = windows_join(
                    &local,
                    &["Packages", &package_family_name, "LocalCache", "Local"],
                );
                (
                    Sandbox::Msix {
                        package_family_name,
                    },
                    Some((local, private)),
                )
            }
            _ => (Sandbox::None, None),
        };
        Self {
            data: PathBuf::from(windows_join(&root, &["Data"])),
            cache: PathBuf::from(windows_join(&root, &["Cache"])),
            downloads: PathBuf::from(windows_join(&root, &["Downloads"])),
            sandbox,
            msix_redirect,
        }
    }

    fn linux(env: &impl Fn(&str) -> Option<String>, is_flatpak: bool) -> Self {
        let home = env("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from);
        let (data_fallback, cache_fallback) = if is_flatpak {
            let sandbox = home.join(".var").join("app").join(LINUX_APP_ID);
            (sandbox.join("data"), sandbox.join("cache"))
        } else {
            (home.join(".local").join("share"), home.join(".cache"))
        };
        let data_home = env("XDG_DATA_HOME").map_or(data_fallback, PathBuf::from);
        let cache_home = env("XDG_CACHE_HOME").map_or(cache_fallback, PathBuf::from);
        let data = data_home.join(LINUX_APP_ID);
        Self {
            cache: cache_home.join(LINUX_APP_ID),
            downloads: data.join("downloads"),
            data,
            sandbox: if is_flatpak {
                Sandbox::Flatpak
            } else {
                Sandbox::None
            },
            msix_redirect: None,
        }
    }

    /// Whether the folders are a Flatpak sandbox's own.
    pub fn is_flatpak(&self) -> bool {
        self.sandbox == Sandbox::Flatpak
    }

    /// The SQLite file the store opens.
    pub fn store_file(&self) -> PathBuf {
        self.data.join("library.sqlite")
    }

    /// Where the bytes of `path` really are, for the storage view: a packaged Windows app's
    /// `%LOCALAPPDATA%` path moved into its package folder, every other path unchanged.
    pub fn on_disk(&self, path: &Path) -> PathBuf {
        let Some((visible, private)) = &self.msix_redirect else {
            return path.to_path_buf();
        };
        let text = path.to_string_lossy();
        match text.strip_prefix(visible.as_str()) {
            Some(rest) if rest.is_empty() || rest.starts_with('\\') => {
                PathBuf::from(format!("{private}{rest}"))
            }
            _ => path.to_path_buf(),
        }
    }

    /// Whether a path lies in a folder the system synchronises between machines: a Windows
    /// roaming profile folder, or a cloud-synced home folder named as such. Reads `/` and
    /// `\` as separators on every host. `desktop-experience` forbids writing there.
    pub fn is_roaming(path: &Path) -> bool {
        path.to_string_lossy().split(['/', '\\']).any(|name| {
            ROAMING_FOLDERS
                .iter()
                .any(|roaming| name.eq_ignore_ascii_case(roaming))
        })
    }
}

/// A Windows path from a base and parts, joined with `\` on any host.
fn windows_join(base: &str, parts: &[&str]) -> String {
    let mut joined = base.trim_end_matches(['\\', '/']).to_owned();
    for part in parts {
        joined.push('\\');
        joined.push_str(part);
    }
    joined
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
            assert!(
                !StorageLocations::is_roaming(path),
                "{} roams",
                path.display()
            );
            assert!(
                !StorageLocations::is_roaming(&locations.on_disk(path)),
                "{} roams on disk",
                path.display()
            );
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
            Sandbox::None,
        );
        assert_eq!(
            locations.data,
            PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Data")
        );
        assert_eq!(
            locations.cache,
            PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Cache")
        );
        assert_eq!(
            locations.downloads,
            PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Downloads")
        );
        assert_eq!(locations.sandbox, Sandbox::None);
        assert_eq!(locations.on_disk(&locations.data), locations.data);
        none_roam(&locations);
    }

    #[test]
    fn a_packaged_windows_app_opens_the_same_paths_and_knows_where_msix_puts_them() {
        let unpackaged = StorageLocations::resolve(
            Platform::Windows,
            env(&[("LOCALAPPDATA", r"C:\Users\Reader\AppData\Local\")]),
            Sandbox::None,
        );
        let packaged = StorageLocations::resolve(
            Platform::Windows,
            env(&[("LOCALAPPDATA", r"C:\Users\Reader\AppData\Local\")]),
            Sandbox::Msix {
                package_family_name: "MeCedric.StoryArc_8wekyb3d8bbwe".to_owned(),
            },
        );
        // The redirect is the system's: the app opens the same paths either way.
        assert_eq!(packaged.data, unpackaged.data);
        assert_eq!(packaged.downloads, unpackaged.downloads);
        assert_eq!(
            packaged.on_disk(&packaged.data),
            PathBuf::from(
                r"C:\Users\Reader\AppData\Local\Packages\MeCedric.StoryArc_8wekyb3d8bbwe\LocalCache\Local\StoryArc\Data"
            )
        );
        assert_eq!(
            packaged.on_disk(Path::new(r"D:\Comics\a.cbz")),
            PathBuf::from(r"D:\Comics\a.cbz")
        );
        // A prefix that is only a prefix of a folder name is not the folder.
        assert_eq!(
            packaged.on_disk(Path::new(r"C:\Users\Reader\AppData\LocalLow\x")),
            PathBuf::from(r"C:\Users\Reader\AppData\LocalLow\x")
        );
        none_roam(&packaged);
        // An empty family name is no package.
        let empty = StorageLocations::resolve(
            Platform::Windows,
            env(&[("LOCALAPPDATA", r"C:\L")]),
            Sandbox::Msix {
                package_family_name: String::new(),
            },
        );
        assert_eq!(empty.sandbox, Sandbox::None);
    }

    #[test]
    fn windows_without_local_app_data_derives_it_from_the_profile() {
        let locations = StorageLocations::resolve(
            Platform::Windows,
            env(&[("USERPROFILE", r"C:\Users\Reader"), ("LOCALAPPDATA", "")]),
            Sandbox::None,
        );
        assert_eq!(
            locations.data,
            PathBuf::from(r"C:\Users\Reader\AppData\Local\StoryArc\Data")
        );
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
            Sandbox::None,
        );
        assert_eq!(
            explicit.data,
            PathBuf::from("/data/reader/share/com.mecedric.StoryArc")
        );
        assert_eq!(
            explicit.cache,
            PathBuf::from("/data/reader/cache/com.mecedric.StoryArc")
        );
        assert_eq!(
            explicit.downloads,
            PathBuf::from("/data/reader/share/com.mecedric.StoryArc/downloads")
        );
        assert!(!explicit.is_flatpak());
        none_roam(&explicit);

        let defaults = StorageLocations::resolve(
            Platform::Linux,
            env(&[("HOME", "/home/reader"), ("XDG_DATA_HOME", "")]),
            Sandbox::None,
        );
        assert_eq!(
            defaults.data,
            PathBuf::from("/home/reader/.local/share/com.mecedric.StoryArc")
        );
        assert_eq!(
            defaults.cache,
            PathBuf::from("/home/reader/.cache/com.mecedric.StoryArc")
        );
        assert_eq!(defaults.store_file(), defaults.data.join("library.sqlite"));
        // A Windows sandbox means nothing on Linux.
        let stray = StorageLocations::resolve(
            Platform::Linux,
            env(&[("HOME", "/home/reader")]),
            Sandbox::Msix {
                package_family_name: "x".to_owned(),
            },
        );
        assert_eq!(stray, defaults);
    }

    #[test]
    fn a_flatpak_keeps_everything_under_its_own_var_app_folder() {
        // What the sandbox sets.
        let sandboxed = StorageLocations::resolve(
            Platform::Linux,
            env(&[
                ("HOME", "/home/reader"),
                (
                    "XDG_DATA_HOME",
                    "/home/reader/.var/app/com.mecedric.StoryArc/data",
                ),
                (
                    "XDG_CACHE_HOME",
                    "/home/reader/.var/app/com.mecedric.StoryArc/cache",
                ),
            ]),
            Sandbox::Flatpak,
        );
        assert_eq!(
            sandboxed.data,
            PathBuf::from("/home/reader/.var/app/com.mecedric.StoryArc/data/com.mecedric.StoryArc")
        );
        assert!(sandboxed.is_flatpak());
        // And what the app derives when the sandbox did not set them.
        let derived = StorageLocations::resolve(
            Platform::Linux,
            env(&[("HOME", "/home/reader")]),
            Sandbox::Flatpak,
        );
        assert_eq!(
            derived.cache,
            PathBuf::from(
                "/home/reader/.var/app/com.mecedric.StoryArc/cache/com.mecedric.StoryArc"
            )
        );
        assert!(derived.downloads.starts_with("/home/reader/.var/app"));
        none_roam(&derived);
    }

    #[test]
    fn a_mac_host_uses_application_support_and_caches() {
        let locations = StorageLocations::resolve(
            Platform::MacOs,
            env(&[("HOME", "/Users/reader")]),
            Sandbox::None,
        );
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
    fn a_roaming_folder_is_recognised_by_name_on_any_host() {
        assert!(StorageLocations::is_roaming(Path::new(
            r"C:\Users\R\AppData\Roaming\StoryArc"
        )));
        assert!(StorageLocations::is_roaming(Path::new(
            "/Users/r/OneDrive/StoryArc"
        )));
        assert!(StorageLocations::is_roaming(Path::new(
            "/Users/r/iCloud Drive/StoryArc"
        )));
        assert!(!StorageLocations::is_roaming(Path::new(
            r"C:\Users\R\AppData\Local\StoryArc"
        )));
    }

    #[test]
    fn the_host_resolves_to_something_absolute_and_not_roaming() {
        let current = StorageLocations::current();
        assert!(current.data.is_absolute());
        none_roam(&current);
    }
}
