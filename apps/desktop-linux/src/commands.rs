//! The command table: every command the desktop spec names, where it lives and its key.
//!
//! One table feeds three things, so they cannot drift: the accelerators registered on
//! the application, the menus and popovers each window builds, and the Keyboard
//! Shortcuts dialog (`docs/designs/desktop/linux.md`, section 6). It is the Linux
//! reading of the table lane M and lane W share (tasks 2.10 and 2.38): every key is the
//! same except the sidebar (F9) and Quit (Control and Q), which GNOME has no standard
//! key for.
//!
//! Pure: no GTK type in here, so it tests on any host.

/// Which window a command applies in. A command that does not apply in a window is
/// shown disabled there, never removed, so a menu has the same shape everywhere.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Scope {
    /// Every window.
    Everywhere,
    /// The library window.
    Library,
    /// A reader window.
    Reader,
    /// The audiobook player window (wave 4).
    Player,
}

impl Scope {
    /// Whether a command of this scope can act in a window of `window`.
    pub fn applies_in(self, window: Scope) -> bool {
        self == Scope::Everywhere || self == window
    }
}

/// Where the command is reachable by pointer. `ShortcutOnly` commands still have a
/// place: the Keyboard Shortcuts dialog lists them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Place {
    AddPopover,
    ViewOptions,
    PrimaryMenu,
    SearchBar,
    HeaderStart,
    HeaderEnd,
    Sidebar,
    Home,
    ContextMenu,
    LayoutPopover,
    ReaderMenu,
    Player,
    AboutDialog,
    ShortcutOnly,
}

/// The section a command sits in, in the Keyboard Shortcuts dialog.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Group {
    General,
    Library,
    Reader,
    Player,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Command {
    /// The detailed action name the menus activate: `app.` for the application,
    /// `win.` for the window.
    pub action: &'static str,
    /// The English label. The gettext key, when the iOS catalogue has one, is looked
    /// up by `label_key`.
    pub label: &'static str,
    /// The iOS catalogue key for the label, when one exists. Desktop-only commands
    /// have none yet and fall back to `label`.
    pub label_key: Option<&'static str>,
    /// GTK accelerator spellings. Empty for a command with no key.
    pub accels: &'static [&'static str],
    pub scope: Scope,
    pub place: Place,
    pub group: Group,
}

impl Command {
    /// Keys without a modifier (the page keys, Space in the player) are not registered
    /// as application accelerators: a text field must keep them. The reader's own key
    /// controller maps them through `keys::page_action` instead.
    pub fn is_registered(&self) -> bool {
        self.accels
            .iter()
            .all(|accel| accel.starts_with('<') || accel.starts_with('F'))
    }

    /// The accelerators GTK registers for this command.
    pub fn registered_accels(&self) -> &'static [&'static str] {
        if self.is_registered() {
            self.accels
        } else {
            &[]
        }
    }
}

macro_rules! command {
    ($action:expr, $label:expr, $key:expr, [$($accel:expr),*], $scope:ident, $place:ident, $group:ident) => {
        Command {
            action: $action,
            label: $label,
            label_key: $key,
            accels: &[$($accel),*],
            scope: Scope::$scope,
            place: Place::$place,
            group: Group::$group,
        }
    };
}

/// The whole table, in the order the design lists it.
pub const COMMANDS: &[Command] = &[
    command!(
        "win.open-file",
        "Open File…",
        None,
        ["<Control>o"],
        Library,
        AddPopover,
        General
    ),
    command!(
        "win.open-recent",
        "Open Recent",
        None,
        [],
        Library,
        Home,
        General
    ),
    command!(
        "win.add-source",
        "Add Source…",
        Some("library.addSource"),
        ["<Control><Shift>a"],
        Library,
        AddPopover,
        General
    ),
    command!(
        "win.refresh-sources",
        "Refresh Sources",
        None,
        ["<Control>r", "F5"],
        Library,
        ViewOptions,
        General
    ),
    command!(
        "window.close",
        "Close Window",
        None,
        ["<Control>w"],
        Everywhere,
        ShortcutOnly,
        General
    ),
    command!(
        "app.preferences",
        "Settings…",
        Some("settings.title"),
        ["<Control>comma"],
        Everywhere,
        PrimaryMenu,
        General
    ),
    command!(
        "app.quit",
        "Quit StoryArc",
        None,
        ["<Control>q"],
        Everywhere,
        ShortcutOnly,
        General
    ),
    command!(
        "win.copy",
        "Copy",
        None,
        ["<Control>c"],
        Everywhere,
        ShortcutOnly,
        General
    ),
    command!(
        "win.select-all",
        "Select All",
        None,
        ["<Control>a"],
        Library,
        ShortcutOnly,
        Library
    ),
    command!(
        "win.find",
        "Find",
        Some("search.title"),
        ["<Control>f"],
        Everywhere,
        SearchBar,
        General
    ),
    command!(
        "win.find-next",
        "Find Next",
        None,
        ["<Control>g", "F3"],
        Everywhere,
        ShortcutOnly,
        General
    ),
    command!(
        "win.find-previous",
        "Find Previous",
        None,
        ["<Control><Shift>g"],
        Everywhere,
        ShortcutOnly,
        General
    ),
    command!(
        "win.view-grid",
        "View as Grid",
        None,
        ["<Control><Shift>1"],
        Library,
        ViewOptions,
        Library
    ),
    command!(
        "win.view-list",
        "View as List",
        None,
        ["<Control><Shift>2"],
        Library,
        ViewOptions,
        Library
    ),
    command!(
        "win.larger-covers",
        "Larger Covers",
        None,
        ["<Control>plus", "<Control>equal"],
        Library,
        ViewOptions,
        Library
    ),
    command!(
        "win.smaller-covers",
        "Smaller Covers",
        None,
        ["<Control>minus"],
        Library,
        ViewOptions,
        Library
    ),
    command!(
        "win.automatic-covers",
        "Automatic Cover Size",
        None,
        ["<Control>0"],
        Library,
        ViewOptions,
        Library
    ),
    command!(
        "win.toggle-sidebar",
        "Show or Hide Sidebar",
        None,
        ["F9"],
        Library,
        HeaderStart,
        Library
    ),
    command!(
        "win.fullscreen",
        "Enter or Exit Full Screen",
        None,
        ["F11"],
        Reader,
        ReaderMenu,
        Reader
    ),
    command!(
        "win.back",
        "Back",
        None,
        ["<Alt>Left"],
        Library,
        HeaderStart,
        Library
    ),
    command!(
        "win.forward",
        "Forward",
        None,
        ["<Alt>Right"],
        Library,
        ShortcutOnly,
        Library
    ),
    command!(
        "win.show-home",
        "Home",
        Some("home.title"),
        ["<Control>1"],
        Library,
        Sidebar,
        Library
    ),
    command!(
        "win.show-library",
        "Library",
        Some("sidebar.library"),
        ["<Control>2"],
        Library,
        Sidebar,
        Library
    ),
    command!(
        "win.show-downloads",
        "Downloads",
        Some("shortcut.downloads"),
        ["<Control>3"],
        Library,
        Sidebar,
        Library
    ),
    command!(
        "win.continue-reading",
        "Continue Reading",
        Some("shortcut.continue"),
        ["<Control><Shift>c"],
        Library,
        Home,
        Library
    ),
    command!(
        "win.show-details",
        "Show Details",
        Some("library.action.showDetails"),
        ["<Control>i"],
        Library,
        ContextMenu,
        Library
    ),
    command!(
        "win.next-page",
        "Next Page",
        None,
        ["Right"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.previous-page",
        "Previous Page",
        None,
        ["Left"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.first-page",
        "First Page",
        None,
        ["Home"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.last-page",
        "Last Page",
        None,
        ["End"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.go-to-page",
        "Go to Page…",
        None,
        ["<Control>l"],
        Reader,
        ReaderMenu,
        Reader
    ),
    command!(
        "win.next-chapter",
        "Next Chapter or Issue",
        None,
        ["<Control>Right"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.previous-chapter",
        "Previous Chapter or Issue",
        None,
        ["<Control>Left"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.layout-single",
        "Single Page",
        None,
        ["<Control><Shift>1"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.layout-two",
        "Two Pages",
        None,
        ["<Control><Shift>2"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.layout-scroll",
        "Scroll",
        None,
        ["<Control><Shift>3"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.zoom-in",
        "Zoom In or Larger Text",
        None,
        ["<Control>plus", "<Control>equal"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.zoom-out",
        "Zoom Out or Smaller Text",
        None,
        ["<Control>minus"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.fit-page",
        "Fit Page",
        Some("reader.fit.screen"),
        ["<Control>0"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.fit-width",
        "Fit Width",
        Some("reader.fit.width"),
        ["<Control>9"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.original-size",
        "Original Size",
        Some("reader.fit.original"),
        ["<Control><Shift>0"],
        Reader,
        LayoutPopover,
        Reader
    ),
    command!(
        "win.show-contents",
        "Show Contents",
        None,
        ["<Control>t"],
        Reader,
        HeaderStart,
        Reader
    ),
    command!(
        "win.appearance",
        "Appearance",
        Some("settings.appearance"),
        ["<Control><Shift>t"],
        Reader,
        HeaderEnd,
        Reader
    ),
    command!(
        "win.bookmark",
        "Bookmark This Page",
        Some("reader.bookmark.add"),
        ["<Control>d"],
        Reader,
        HeaderEnd,
        Reader
    ),
    command!(
        "win.toggle-controls",
        "Show or Hide Controls",
        None,
        ["<Control><Shift>h"],
        Reader,
        ShortcutOnly,
        Reader
    ),
    command!(
        "win.read-aloud",
        "Read Aloud",
        None,
        ["<Control><Shift>l"],
        Reader,
        ReaderMenu,
        Reader
    ),
    command!(
        "win.play-pause",
        "Play or Pause",
        None,
        ["space"],
        Player,
        Player,
        Player
    ),
    command!(
        "win.skip-back",
        "Skip Back 15 s",
        None,
        ["Left"],
        Player,
        Player,
        Player
    ),
    command!(
        "win.skip-forward",
        "Skip Forward 30 s",
        None,
        ["Right"],
        Player,
        Player,
        Player
    ),
    command!(
        "app.shortcuts",
        "Keyboard Shortcuts",
        None,
        ["<Control>question"],
        Everywhere,
        PrimaryMenu,
        General
    ),
    command!(
        "app.whats-new",
        "What's New…",
        None,
        [],
        Everywhere,
        AboutDialog,
        General
    ),
    command!(
        "app.acknowledgements",
        "Acknowledgements…",
        Some("about.acknowledgements"),
        [],
        Everywhere,
        AboutDialog,
        General
    ),
    command!(
        "app.report-problem",
        "Report a Problem…",
        Some("about.report"),
        [],
        Everywhere,
        AboutDialog,
        General
    ),
];

/// The command behind an action name, if the table has it.
pub fn find(action: &str) -> Option<&'static Command> {
    COMMANDS.iter().find(|command| command.action == action)
}

/// The commands that can act in a window of `window`, in table order.
pub fn for_window(window: Scope) -> impl Iterator<Item = &'static Command> {
    COMMANDS
        .iter()
        .filter(move |command| command.scope.applies_in(window))
}

/// The commands of one section of the Keyboard Shortcuts dialog, with a key.
pub fn in_group(group: Group) -> impl Iterator<Item = &'static Command> {
    COMMANDS
        .iter()
        .filter(move |command| command.group == group && !command.accels.is_empty())
}

/// The commands that sit at one place, in table order.
pub fn in_place(place: Place) -> impl Iterator<Item = &'static Command> {
    COMMANDS
        .iter()
        .filter(move |command| command.place == place)
}

/// The Keyboard Shortcuts dialog: each section with the commands that have a key, in
/// the order General, Library, Reader, Player. An empty section is left out.
pub fn shortcut_sections() -> Vec<(Group, Vec<&'static Command>)> {
    [Group::General, Group::Library, Group::Reader, Group::Player]
        .into_iter()
        .map(|group| (group, in_group(group).collect::<Vec<_>>()))
        .filter(|(_, commands)| !commands.is_empty())
        .collect()
}

#[cfg(test)]
mod section_tests {
    use super::*;

    #[test]
    fn the_shortcut_sections_hold_every_keyed_command_once_and_no_empty_section() {
        let sections = shortcut_sections();
        assert!(sections.iter().all(|(_, commands)| !commands.is_empty()));
        let listed: usize = sections.iter().map(|(_, commands)| commands.len()).sum();
        let keyed = COMMANDS.iter().filter(|c| !c.accels.is_empty()).count();
        assert_eq!(listed, keyed);
        assert_eq!(sections[0].0, Group::General);
    }

    #[test]
    fn a_place_lists_its_commands_in_table_order() {
        let reader: Vec<_> = in_place(Place::ReaderMenu).map(|c| c.action).collect();
        assert!(reader.contains(&"win.fullscreen"));
        let primary: Vec<_> = in_place(Place::PrimaryMenu).map(|c| c.action).collect();
        assert_eq!(primary, ["app.preferences", "app.shortcuts"]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// What the spec's "Every command is in a menu" scenario names, by action.
    const SPEC_NAMED: &[&str] = &[
        "win.open-file",
        "win.add-source",
        "win.find",
        "app.preferences",
        "window.close",
        "app.quit",
        "win.fullscreen",
        "win.next-page",
        "win.previous-page",
        "win.zoom-in",
        "win.zoom-out",
        "win.go-to-page",
        "win.read-aloud",
    ];

    #[test]
    fn every_command_the_spec_names_is_in_the_table_with_a_key() {
        for action in SPEC_NAMED {
            let command = find(action).unwrap_or_else(|| panic!("{action} is missing"));
            assert!(!command.accels.is_empty(), "{action} has no key");
        }
    }

    #[test]
    fn the_standard_shortcuts_use_control() {
        let expected = [
            ("win.open-file", "<Control>o"),
            ("win.find", "<Control>f"),
            ("app.preferences", "<Control>comma"),
            ("window.close", "<Control>w"),
            ("app.quit", "<Control>q"),
            ("win.fullscreen", "F11"),
        ];
        for (action, accel) in expected {
            assert_eq!(find(action).unwrap().accels[0], accel, "{action}");
        }
    }

    #[test]
    fn linux_quits_with_control_q_and_closes_with_control_w() {
        assert!(find("app.quit").unwrap().accels.contains(&"<Control>q"));
        assert!(find("window.close").unwrap().accels.contains(&"<Control>w"));
        assert_eq!(find("app.quit").unwrap().scope, Scope::Everywhere);
    }

    #[test]
    fn every_accelerator_is_well_formed() {
        for command in COMMANDS {
            for accel in command.accels {
                let key = accel.rsplit('>').next().unwrap_or_default();
                assert!(
                    !key.is_empty(),
                    "{}: `{accel}` names no key",
                    command.action
                );
                let modifiers = &accel[..accel.len() - key.len()];
                for modifier in modifiers.split_inclusive('>').filter(|m| !m.is_empty()) {
                    assert!(
                        ["<Control>", "<Shift>", "<Alt>"].contains(&modifier),
                        "{}: `{accel}` uses an unknown modifier",
                        command.action
                    );
                }
            }
        }
    }

    #[test]
    fn no_two_commands_that_can_act_in_one_window_share_a_key() {
        for window in [Scope::Library, Scope::Reader, Scope::Player] {
            let mut seen: HashSet<&str> = HashSet::new();
            for command in for_window(window) {
                for accel in command.accels {
                    assert!(
                        seen.insert(accel),
                        "`{accel}` is used twice in a {window:?} window ({})",
                        command.action
                    );
                }
            }
        }
    }

    #[test]
    fn every_action_name_is_an_app_or_window_action() {
        for command in COMMANDS {
            assert!(
                command.action.starts_with("app.")
                    || command.action.starts_with("win.")
                    || command.action == "window.close",
                "{} is neither app. nor win.",
                command.action
            );
            assert!(!command.label.is_empty());
        }
        let mut actions: HashSet<&str> = HashSet::new();
        for command in COMMANDS {
            assert!(
                actions.insert(command.action),
                "{} appears twice",
                command.action
            );
        }
    }

    #[test]
    fn the_page_keys_are_not_registered_as_application_accelerators() {
        for action in [
            "win.next-page",
            "win.previous-page",
            "win.first-page",
            "win.last-page",
        ] {
            let command = find(action).unwrap();
            assert!(
                !command.is_registered(),
                "{action} would steal the key from a text field"
            );
            assert!(command.registered_accels().is_empty());
        }
        assert!(!find("win.play-pause").unwrap().is_registered());
        assert!(find("win.fullscreen").unwrap().is_registered());
        assert!(find("win.open-file").unwrap().is_registered());
    }

    #[test]
    fn the_reader_keys_do_not_act_in_the_library_and_the_reverse() {
        assert!(
            !find("win.next-page")
                .unwrap()
                .scope
                .applies_in(Scope::Library)
        );
        assert!(
            !find("win.view-grid")
                .unwrap()
                .scope
                .applies_in(Scope::Reader)
        );
        assert!(find("app.quit").unwrap().scope.applies_in(Scope::Reader));
        let library: Vec<_> = for_window(Scope::Library).map(|c| c.action).collect();
        assert!(library.contains(&"win.open-file"));
        assert!(!library.contains(&"win.go-to-page"));
    }

    #[test]
    fn the_shortcuts_dialog_lists_every_command_with_a_key_once() {
        let listed: Vec<&str> = [Group::General, Group::Library, Group::Reader, Group::Player]
            .into_iter()
            .flat_map(in_group)
            .map(|c| c.action)
            .collect();
        let with_key = COMMANDS.iter().filter(|c| !c.accels.is_empty()).count();
        assert_eq!(listed.len(), with_key);
        assert_eq!(listed.iter().collect::<HashSet<_>>().len(), listed.len());
    }

    #[test]
    /// About is the third entry of the primary menu; it has no key, so it is not a
    /// command of this table. The menu builder adds it.
    fn the_primary_menu_commands_are_settings_and_keyboard_shortcuts() {
        let primary: Vec<_> = COMMANDS
            .iter()
            .filter(|c| c.place == Place::PrimaryMenu)
            .map(|c| c.action)
            .collect();
        assert_eq!(primary, ["app.preferences", "app.shortcuts"]);
    }
}
