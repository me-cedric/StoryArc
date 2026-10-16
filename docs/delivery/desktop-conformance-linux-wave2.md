# Linux conformance, wave 2, part one

Lane L, branch `lane/linux-wave2`. This page records, per task, what is built, what a test proves and what a Linux
host still owes. Task 2.36 (the walk) is not done: it needs 2.28, 2.30, 2.31 and 2.35a to 2.35d, which wait for the
core's library API. No window can be shown on the Mac this was written on, so every "walk" below is owed.

Proof that exists: `apps/desktop-linux/scripts/container-build.sh ubuntu-24.04 --clippy` builds the crate against GTK 4.14
and libadwaita 1.5, runs the crate's tests, runs clippy with warnings denied, and validates the desktop file and the
metainfo. It never opens a window.

| Task | Built | Test proof | A Linux host still owes |
| --- | --- | --- | --- |
| 2.25 Reader windows and restoration | `reader_window.rs` opens one window per publication; `main.rs` restores the library and each reader from the session file, names a reader that cannot reopen in the library in grey, and presents the window that already reads a publication. A reader whose file goes away keeps its pages and shows a grey banner. | `windows::` (round trip, one window per publication, gone display, missing publication, minimum size), `publication::tests` (availability, refusal by name). | A walk that opens two readers (`gapplication action com.mecedric.StoryArc open-reader "'/path/a.cbz'"`, twice with two files), quits, relaunches, and moves a monitor away. |
| 2.26 Menus and commands | `menus.rs` registers every accelerator of the table, adds a disabled action for each command a window does not implement, builds the primary menu and the reader menu from the table, and shows a custom `AdwDialog` listing every command that has a key. | `commands::` (table, keys, no clash, sections and places). | A walk that opens the menu and the dialog and presses Control and comma, Control and Q. A command nobody implements yet is grey by design. |
| 2.27 Keys and pointer | The reader maps keys, edge clicks, the wheel and a right click through `keys.rs`. Pointer motion reveals the chrome, three idle seconds hide it and the pointer, an open menu holds it. | `keys::` (page keys by direction, zones, wheel notches, chrome idle). | A walk that shows hover chrome and turns pages by key, edge click and wheel on Wayland and X11. |
| 2.29 Full screen | `win.fullscreen` on F11 asks the compositor, watches the answer for 1.5 seconds and, if none comes, greys the entry with the note "Full screen is not available". Escape leaves. | `fullscreen::tests` (grant, leave, refusal, late grant). | Captures on GNOME, KDE Plasma and COSMIC, and the grey note on Hyprland. |
| 2.32 Closing and quitting | Closing a reader flushes its position, then leaves the session; Quit saves the session, flushes every reader, closes every window and ends the process. A failing write is logged and holds nothing. The session file is also rewritten after each timed write, so a crash restores to the last written page. | `progress::tests` (the five-second clock, one write for many turns, a failing store stops nobody and the position stays in memory). | A Hyprland capture of the header bar with Control and W, Control and Q, and a kill while a book is open. |
| 2.33 Display, appearance, any size | `theme.rs` loads the generated tokens, the ramp and the accent through three `GtkCssProvider`s and follows `AdwStyleManager`, which follows the settings portal and draws light when none answers. High contrast drops the overrides. Every window requests 360 by 294. | `style::`, `settings::` (ramps, accent, appearance forcing). | Captures on Wayland and X11 in light, dark, OLED and Natural, and a resize walk down to 360 px. The X11 curl note belongs to the page-curl work, not built here. |
| 2.34 Idle inhibit | The window that is active holds `GtkApplication::inhibit` with the idle flag and releases it when it loses focus or closes. A zero cookie is a silent refusal. | `idle::tests` (granted, refused, twice). | A walk on Hyprland and one on KDE with a screen blank timeout of one minute. |
| 2.35 Preferences dialog | `preferences_dialog.rs`: `AdwPreferencesDialog` with search, an Appearance page and a Reading page. A change writes the file and reaches the theme and every open reader at once. | `settings::` (round trip, defaults, labels). | A walk that searches the dialog and changes a setting with a reader open. |
| 2.35e Chrome accent | The Accent row offers System only where the settings portal reports an accent, read over D-Bus because `AdwStyleManager::accent_color` needs libadwaita 1.6. Absent, not disabled, where there is none; the brand colour stays. | `settings::` (brand default, system choice, a later accent change, no accent, cover colour unchanged), `portal::tests`. | Captures of both choices on a session with a portal accent and the absent row on a session without one. |
| Tokens | `data/style/storyarc-tokens.css` is the output of `pnpm tokens:build`; this branch's copy is identical. | `style::` reads colours from it. | None. |

## Deviations and owed items

- Preferences live in a `key=value` file under the app's data directory, not GSettings, until the packaging lane installs a
  compiled schema (`settings.rs` says so).
- Reading positions live in a `publication=page` file until the core's progress store (task 2.1) lands.
- The reader shows the page's number and name, not its artwork: the core decodes no page yet (task 2.5).
- Opening a file from the file manager, by argv and by drop is task 2.30; the walk path for now is the `open-reader` action.
- The library shows no Continue reading shelf yet, so "the library shows that position at once" is owed to 2.35c.
- Interface strings the iOS catalogue lacks fall back to English: `shortcuts.title`, `shortcuts.general`,
  `shortcuts.library`, `shortcuts.reader`, `shortcuts.player`, `settings.accent`, `settings.layout`, `settings.fit`,
  `settings.clickZones`, `settings.appearance.noPortal`, `restore.missing`, `reader.pageOfCount`, `menu.main`,
  `library.empty.title`, `library.empty.body`, `sidebar.home`, `sidebar.library`, `sidebar.downloads`.
- Not started, by instruction: 2.28, 2.30, 2.31, 2.35a to 2.35d, 2.36.
