---
name: storyarc-gnome-design
description: Design rules for the StoryArc Linux client (GTK4, libadwaita, gtk4-rs). Use before any UI work in apps/desktop-linux, when choosing a libadwaita widget, laying out a window, or reviewing GNOME HIG compliance. Written for StoryArc from the GNOME HIG and the libadwaita docs. Pair with developing-gtk-apps for plumbing.
---

# StoryArc GNOME design

Written for StoryArc (not third-party). Sources: GNOME HIG, libadwaita docs, gtk4-rs docs.
Companion: `developing-gtk-apps` covers architecture, threading, GSettings and packaging.
This skill covers widget choice, layout and look.

Sources to open when unsure:
- HIG: https://developer.gnome.org/hig/
- Adaptive: https://developer.gnome.org/hig/guidelines/adaptive.html
- Keyboard: https://developer.gnome.org/hig/guidelines/keyboard.html
- UI styling: https://developer.gnome.org/hig/guidelines/ui-styling.html
- libadwaita: https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/
- gtk4-rs: https://gtk-rs.org/gtk4-rs/stable/latest/docs/
- GNOME Circle review rules: https://gitlab.gnome.org/Teams/Circle

## Floor and version gates

Floor is GTK 4.14 and libadwaita 1.5 (Ubuntu 24.04, Pop!_OS 24.04). Use gtk4-rs feature `v4_14` and libadwaita feature `v1_5`.
Newer widgets need a runtime check or a fallback. Never enable a higher crate feature than the floor.

| Need | Floor 1.5 | Newer (guard it) |
| --- | --- | --- |
| Window chrome | `AdwApplicationWindow` + `AdwToolbarView` (1.4) | same |
| Adaptive layout | `AdwBreakpoint` (1.4) | same |
| Split layout | `AdwNavigationSplitView`, `AdwOverlaySplitView` (1.4) | same |
| Dialogs | `AdwDialog`, `AdwAlertDialog`, `AdwPreferencesDialog`, `AdwAboutDialog` (1.5) | same |
| Accent colour | system default | `AdwStyleManager::accent_color` (1.6) |
| Spinner | `GtkSpinner` | `AdwSpinner` (1.6) |
| Shortcuts overview | `GtkShortcutsWindow` | `AdwShortcutsDialog` (1.8) |
| Wrapping box | `GtkFlowBox` | `AdwWrapBox` (1.7) |

## StoryArc rules that override defaults

1. The artwork is the interface. Covers and pages fill the window. Chrome stays thin and hides in the reader.
2. Offline is normal. Use `dim-label`-class grey (`.dimmed` on 1.7+) and a status page. Never red, never a blocking dialog.
3. Red (`.error`, `destructive-action`) only for a real destructive choice, such as removing a source.
4. Secrets live in the Secret Service (libsecret). Never in GSettings, files or logs.
5. No cross-platform UI code. All widgets are native GTK. The EPUB view is the one sanctioned web view (WebKitGTK).
6. Mobile-only features do not exist here: no haptics, no orientation lock, no volume-key page turns.

## Window and layout

- Use `AdwApplicationWindow`, `AdwToolbarView`, `AdwHeaderBar`. Client-side decorations, no custom title bar.
- Minimum size 360 x 294 so the window works when tiled narrow (Hyprland, COSMIC, GNOME tiling). Default size about 1100 x 720.
- Design narrow first. Add `AdwBreakpoint` rules for wider layouts.
- Library shell: `AdwNavigationSplitView`. Sidebar lists destinations, library filters and shelves. Content shows the cover grid.
- Cover grid: `GtkGridView` with a `GtkSignalListItemFactory` over a `gio::ListModel`. Never a hand-built grid of widgets in a `GtkScrolledWindow`.
- Wrap wide text in `AdwClamp` so lines stay readable on big monitors.
- Remember window size, sidebar state and last view in GSettings. Never position windows: Wayland forbids it.
- Several reader windows are allowed. Each is its own `AdwApplicationWindow` on the same `AdwApplication`.

## Header bar

- Start: back or sidebar toggle and the one primary action. Centre: title. End: search toggle, then the primary menu (`open-menu-symbolic`).
- Few controls. Keep blank space so the bar can drag the window.
- Icon buttons carry tooltips. No text-only buttons, no linked buttons, no suggested or destructive style in the bar.
- Primary menu holds: Preferences, Keyboard Shortcuts, About StoryArc. Nothing else.

## Navigation

- Fewer than about five top-level views: `AdwViewSwitcher`. More, or dynamic places such as library filters and shelves: sidebar.
- Drill-down (series, then book): `AdwNavigationView` push and pop. Back is always available (Alt+Left, header bar back button).
- Search: `GtkSearchBar` with `GtkSearchEntry`. Ctrl+F opens it. Type-to-search is on in the library.

## Reader

- Full screen on F11. Escape leaves full screen. Chrome auto-hides and returns on pointer move or tap.
- The reader uses `AdwToolbarView` and toggles `reveal-top-bars` and `reveal-bottom-bars` to hide chrome. No custom overlay.
- Page turn keys: Left, Right, Space, Shift+Space, Page Up, Page Down. Home and End jump to first and last page.
- Two-page spread is a reader setting. Respect reading direction (RTL for manga) in key and click zones.
- Respect `gtk-enable-animations`. Reduced motion means instant page changes.
- Audiobooks: expose MPRIS so media keys, GNOME's media controls and KDE's media widget work.

## Dialogs, feedback, empty states

| Need | Widget |
| --- | --- |
| Confirm or choose (short) | `AdwAlertDialog`. Verb-labelled buttons. Destructive button uses the destructive appearance. Cancel is the default close |
| Settings | `AdwPreferencesDialog` with `AdwPreferencesPage` and `AdwPreferencesGroup`. Rows: `AdwSwitchRow`, `AdwComboRow`, `AdwEntryRow`, `AdwActionRow` |
| About | `AdwAboutDialog` |
| Event feedback ("Added to library") | `AdwToast` on `AdwToastOverlay`. One action at most, such as Undo |
| Ongoing state ("Offline, showing downloads") | `AdwBanner`, grey |
| Nothing here yet, or error that blocks one view | `AdwStatusPage` with icon, title, short description, one action |
| File and folder pick | `GtkFileDialog` (portal aware). Never a raw path entry |

Dialog text: sentence case, no "Are you sure". State the consequence. Name the item.

## Style

- Use `AdwStyleManager`. Follow the system light or dark choice. Offer System, Light, Dark only if the reader needs it.
- Test High Contrast and dark with GTK Inspector (`GTK_DEBUG=interactive`).
- Colour never carries meaning alone. Pair it with an icon or text.
- Custom CSS is a last resort. Use libadwaita style classes (`card`, `boxed-list`, `title-1`, `heading`, `caption`, `dimmed`, `osd`) and named CSS variables (`@accent_bg_color`, `@window_bg_color`).
- Cover cards: `card` class or a rounded `GtkPicture` clip. No drop shadows added by hand.
- Icons: symbolic icons from the Adwaita set. App icon is full colour at 128 px with a symbolic variant. App id `com.mecedric.StoryArc`.
- Spacing uses multiples of 6 px (6, 12, 18, 24). Do not invent odd margins.

## Keyboard

Every action is reachable by keyboard. Register accelerators on actions, not on widgets.

| Keys | Action |
| --- | --- |
| Ctrl+Q | Quit |
| Ctrl+W | Close window |
| Ctrl+N | New reader or window |
| Ctrl+, | Preferences |
| Ctrl+? | Keyboard shortcuts |
| Ctrl+F | Search |
| F10 | Primary menu |
| F11 | Full screen |
| Alt+Left | Back |
| Esc | Close transient UI, then leave full screen |

## Accessibility

- Every icon-only control has an accessible label (`accessible-label` property) and a tooltip.
- Cover tiles announce title, author and read state.
- Focus order is logical. Test Tab and Shift+Tab through the whole window with Orca running.
- Text honours the system text scaling factor. Never set fixed pixel font sizes.

## Platform integration

- Wayland first. X11 works through XWayland. Never rely on global shortcuts, window placement or window raising.
- Target GNOME, KDE Plasma, Hyprland and COSMIC. Do not use GNOME Shell-only APIs. Do not assume a system tray exists.
- Desktop file with actions for recent items. AppStream metainfo with screenshots. MIME types for CBZ, CBR, CBT, CB7, EPUB, PDF.
- Flatpak first. Ask for the narrowest permissions: Wayland socket, fallback X11, DRI, network, and portal file access. No `--filesystem=home`.

## Review checklist

- [ ] Works at 360 px width and at 1920 px width
- [ ] Only libadwaita widgets from the floor table, or guarded newer ones
- [ ] Header bar has three zones, no text-only buttons
- [ ] Offline path is grey, no red
- [ ] No custom CSS beyond style classes and variables
- [ ] Keyboard-only run passes; Orca reads every control
- [ ] Light, dark and High Contrast checked
- [ ] No window positioning, no global shortcut, no tray dependency
- [ ] No secret outside libsecret
