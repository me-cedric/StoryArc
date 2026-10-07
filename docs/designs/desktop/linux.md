# StoryArc on Linux

Status: proposal, wave 0. Stack: GTK4 and libadwaita in Rust (gtk4-rs), floor GTK 4.14
and libadwaita 1.5, Wayland first, Flatpak first (ADR-0018, D4; research in
[`desktop-research-linux-macos`](../../delivery/desktop-research-linux-macos-2026-10-07.md)).
Shared rules are in [`README.md`](README.md). This file holds what is specific to Linux.

**Governing skills.** `storyarc-gnome-design` decides widget choice, layout, look and
keys. It is written for StoryArc and wins over every other Linux source here.
`developing-gtk-apps` decides plumbing: threads, GSettings, D-Bus, packaging, tests.
Use only widgets from the floor table of `storyarc-gnome-design`, or guard newer ones.

**Targets.** GNOME, KDE Plasma, Hyprland and COSMIC on Arch, Manjaro, Ubuntu,
Pop!_OS and Fedora. One layout works on all of them. The app never positions a window,
never needs a tray, never relies on a global shortcut and never uses a GNOME Shell API.

## 1. Direction

A GNOME app in the libadwaita style: client-side header bar, flat surfaces, symbolic
icons. It must also look right on a tiling compositor at 360 px wide. StoryArc adds
its accent, its cover canvas and its reader. Everything else is stock Adwaita.

## 2. Information architecture

| Sidebar row | Icon (Adwaita symbolic, proposed) | Content |
|---|---|---|
| Home | `user-home-symbolic` | Keep reading, Up next, shelves. |
| Library | `library-symbolic` | Cover grid or list. |
| Downloads | `folder-download-symbolic` | Queue, storage, downloaded books. |
| Library section | All Books, Series, Recently Added, Downloaded | Filters. |
| Shelves section | Collections and reading lists | Pinned first. Drop target. |

Search is the header search toggle plus type-to-search in the library. Sources do not
appear in the sidebar. **Note:** `storyarc-gnome-design` says the sidebar lists
"sources and shelves". The UI revamp forbids a sidebar of servers. This file follows the
revamp. The skill needs a one-line fix (see Parent edits in the report).

The sidebar is a `GtkListBox` with the `navigation-sidebar` class inside an
`AdwNavigationSplitView`. The mini player sits at its foot while audio plays.

## 3. Window anatomy

`AdwApplicationWindow` with `AdwToolbarView`. Client-side decorations only.

```
+---------------------------------------------------------------------------------+
| [|=] [+]                      Library                      [Q] [::|=] [=]       |
+--------------------+------------------------------------------------------------+
|  Home              |  Keep reading                                              |
|  Library        <  |  +----------------+ +----------------+                     |
|  Downloads         |  | cover  Title   | | cover  Title   |                     |
|                    |  |  ====----  42% | |  ==------  18% |                     |
|  LIBRARY           |  +----------------+ +----------------+                     |
|   All Books        |                                                            |
|   Series           |  All Books                                  3,214 titles   |
|   Recently Added   |  +------+ +------+ +------+ +------+ +------+ +------+     |
|   Downloaded       |  |      | |      | |      | |      | |      | |      |     |
|                    |  | art  | | art  | | art  | | art  | | art  | | art  |     |
|  SHELVES           |  |=-----| |      | |v     | |      | |===---| |      |     |
|   Weekend          |  +------+ +------+ +------+ +------+ +------+ +------+     |
|   Reading list A   |   Title    Title    Title    Title    Title    Title       |
|                    |   Series   Series   Series   Series   Series   Series      |
|  [cover] Now       |                                                            |
|  playing  |> 30s   |   v = downloaded mark      === = progress rail             |
+--------------------+------------------------------------------------------------+
```

Header bar zones (`storyarc-gnome-design`): **start** sidebar toggle (or Back in a
page) and one primary action, **Add** (`list-add-symbolic`) opening a popover with
Open File and Add Source. **Centre** `AdwWindowTitle`. **End** search toggle, View
options (`MenuButton`), primary menu (`open-menu-symbolic`). Icon buttons have
tooltips and accessible labels. No text-only buttons.

The primary menu holds Preferences, Keyboard Shortcuts and About StoryArc. Nothing
else. The About dialog carries What's New, Acknowledgements and Report a Problem.

View options popover: Grid or List, Cover size (Small, Medium, Large, Automatic),
Sort (Title, Series, Date Added, Last Read), Filter (Downloaded only), Refresh.

| Part | Widget |
|---|---|
| Shell | `AdwNavigationSplitView` |
| Drill-down (detail page, series) | `AdwNavigationView` push and pop |
| Cover grid | `GtkGridView` with `GtkSignalListItemFactory` over a `gio::ListModel` and `GtkMultiSelection` |
| List view | `GtkColumnView`. Sortable headers. |
| Search | `GtkSearchBar` with `GtkSearchEntry`. Ctrl+F. Type-to-search on. |
| Wide text | `AdwClamp`, 720 |
| Status and empty | `AdwStatusPage`, `AdwBanner`, `AdwToastOverlay` |

Cover ladder: a small controller measures the grid's own width, picks the tier (104,
132, 158 by the README ladder), sets the cell width and applies the 168 cap. A
`GtkGridView` does not do this by itself.

**Breakpoints** (`AdwBreakpoint`, `sp` units so they follow text scale):

| Condition | Change |
|---|---|
| `max-width: 600sp` | Split view collapses. Sidebar becomes a page. Detail is one column. |
| `min-width: 1024sp` | Detail page uses two columns. |
| Always | Minimum window 360 x 294. Design narrow first. |

Selection mode: the header bar swaps to selection actions, the title shows the count,
and **Cancel** is the one way out. Ctrl-click and Shift-click select many.

Spacing uses multiples of 6 px. The token steps `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24
map to 6, 6, 12, 18, 24. The grid gap is 12 (`md`).

## 4. Reader windows

One `AdwApplicationWindow` per publication on the same `AdwApplication`. The app finds
an open one by publication id and presents it. The compositor decides placement.

```
+---------------------------------------------------------------------------------+
| [|=]                   Saga 042                    [Aa] [=] [flag] [=]          |  header bar
+---------------------------------------------------------------------------------+
|                                                                                 |
|          +----------------------+  +----------------------+                     |
|          |                      |  |                      |                     |
|          |       page 13        |  |       page 12        |   right-to-left     |
|          |                      |  |                      |                     |
|          +----------------------+  +----------------------+                     |
|                                                                                 |
|            +-----------------------------------------------------------+        |
|            | 12-13 / 32  <|====o----------------------------|>  [thumb]|        |  bottom bar
|            +-----------------------------------------------------------+        |
+---------------------------------------------------------------------------------+
```

| Element | Behaviour |
|---|---|
| Header bar | Start: Contents toggle. Centre: title. End: Appearance (Aa), Layout, Bookmark, Reader menu. It stays in windowed mode. It hides in full screen and returns when the pointer moves to the top edge. |
| Bottom bar | Page slider, count, thumbnail on drag. Mirrors in right-to-left. |
| Hide and show | `AdwToolbarView` with `extend-content-to-top-edge` and `extend-content-to-bottom-edge`, so the page never shifts. Toggle `reveal-bottom-bars` and `reveal-top-bars`. No custom overlay. |
| Fade | After 3 s idle. Honour `gtk-enable-animations`. Off means instant. |
| Full screen | F11. Esc closes a popover, then leaves full screen. |
| Contents | `AdwOverlaySplitView` with the sidebar at the end. Chapters, thumbnails, bookmarks. |
| Appearance | `GtkPopover` on a `GtkMenuButton`. Six preset cards in 3 by 2. The page updates live. |
| Layout | `GtkPopover`. Single, Two Pages, Scroll, direction, fit, zoom, pairing offset. |
| Reader menu | Go to Page, Read Aloud, Full Screen, Find. |
| Curl | App-owned `GtkGLArea`. Present on Wayland. On X11 it is absent, with Slide and the reason stated (Reduce Motion gives Fast fade instead), until the wave 1 spike shows it holds the frame budget there. **Spike in wave 1.** |
| Keep awake | `Application::inhibit(IDLE)`. |

Comic and PDF: the Rust core decodes, and the core's PDF engine renders (parity risk 4).
EPUB: WebKitGTK with the pinned renderer, floor WebKitGTK 2.44. The page turn is a
raster in the curl. Egress denial is proved again on WebKitGTK (ADR-0015). The GTK
widgets stay native. The web view is only the page.

Player window (420 x 640): cover, chapter, scrubber, back 15 s, play or pause, forward
30 s, speed, sleep timer, chapter list. The app exports **MPRIS**, so media keys, the
GNOME media controls and the KDE media widget work. Read Aloud uses speech-dispatcher
and is absent without it.

## 5. Settings

`AdwPreferencesDialog` (1.5), opened with Ctrl+, or the primary menu. It has built-in
search. Pages: **Sources, Appearance, Reading, Downloads, Language, Privacy.** About is
`AdwAboutDialog`.

| Page | Rows |
|---|---|
| Sources | One `AdwActionRow` per source with a state icon and last sync. Offline rows use `dim-label`. Add and edit push a sub-page (Inferred for 1.5). Remove asks with `AdwAlertDialog`, verb "Remove", naming the source. |
| Appearance | `AdwComboRow`: System, Light, Dark, OLED Dark, Natural. Accent: StoryArc or System. Cover size. |
| Reading | `AdwComboRow` and `AdwSwitchRow` for direction, layout, fit, edge click zones (off), page transition, reading theme. |
| Downloads | Storage bar, metered-link rule, clear cache. |
| Language | Content language rule. The app follows the session locale. |
| Privacy | What is stored, clear history, export a diagnostic. |

Settings live in GSettings. **Secrets never do.** They live in the Secret Service
through libsecret. A file dialog is always `GtkFileDialog`.

## 6. Commands

GNOME has no menu bar. Every command still has a key and a place. The **Where it
lives** column gives the place. All accelerators are registered on `gio::Action`s, not
on widgets. The **Keyboard Shortcuts** window lists every row and is built from the
same action table. Linux shares every key with Windows except the sidebar (F9) and Quit (Ctrl+Q).

| Command | Where it lives | Shortcut |
|---|---|---|
| Open File… | Add popover | Ctrl+O |
| Open Recent | Home, Keep reading | none |
| Add Source… | Add popover | Ctrl+Shift+A |
| Refresh Sources | View options popover | Ctrl+R (also F5) |
| Close Window | Shortcut only | Ctrl+W |
| Settings… | Primary menu | Ctrl+, |
| Quit StoryArc | Shortcut only | Ctrl+Q |
| Copy | Shortcut only | Ctrl+C |
| Select All | Shortcut only | Ctrl+A |
| Find | Search bar | Ctrl+F |
| Find Next | Shortcut only | Ctrl+G (also F3) |
| Find Previous | Shortcut only | Ctrl+Shift+G |
| View as Grid | View options popover | Ctrl+Shift+1 |
| View as List | View options popover | Ctrl+Shift+2 |
| Larger Covers | View options popover | Ctrl++ |
| Smaller Covers | View options popover | Ctrl+− |
| Automatic Cover Size | View options popover | Ctrl+0 |
| Show or Hide Sidebar | Header bar, start | F9 |
| Enter or Exit Full Screen | Reader menu and shortcut | F11 |
| Back | Header bar, start | Alt+← |
| Forward | Shortcut only | Alt+→ |
| Home | Sidebar | Ctrl+1 |
| Library | Sidebar | Ctrl+2 |
| Downloads | Sidebar | Ctrl+3 |
| Continue Reading | Home, hero card | Ctrl+Shift+C |
| Show Details | Context menu | Ctrl+I |
| Next Page | Shortcut only | → |
| Previous Page | Shortcut only | ← |
| First Page | Shortcut only | Home |
| Last Page | Shortcut only | End |
| Go to Page… | Reader menu | Ctrl+L |
| Next Chapter or Issue | Shortcut only | Ctrl+→ |
| Previous Chapter or Issue | Shortcut only | Ctrl+← |
| Single Page | Layout popover | Ctrl+Shift+1 |
| Two Pages | Layout popover | Ctrl+Shift+2 |
| Scroll | Layout popover | Ctrl+Shift+3 |
| Zoom In or Larger Text | Layout popover | Ctrl++ |
| Zoom Out or Smaller Text | Layout popover | Ctrl+− |
| Fit Page | Layout popover | Ctrl+0 |
| Fit Width | Layout popover | Ctrl+9 |
| Original Size | Layout popover | Ctrl+Shift+0 |
| Show Contents | Reader header, start | Ctrl+T |
| Appearance | Reader header, end | Ctrl+Shift+T |
| Bookmark This Page | Reader header, end | Ctrl+D |
| Show or Hide Controls | Shortcut only | Ctrl+Shift+H |
| Read Aloud | Reader menu | Ctrl+Shift+L |
| Play or Pause | Player | Space |
| Skip Back 15 s | Player | ← |
| Skip Forward 30 s | Player | → |
| Keyboard Shortcuts | Primary menu | Ctrl+? |
| What's New… | About dialog | none |
| Acknowledgements… | About dialog | none |
| Report a Problem… | About dialog | none |

**Static desktop actions.** A `.desktop` file cannot list a publication by name. It
offers three static actions: *Continue Reading* (resolves at launch), *Library* and
*Downloads*. Opened files go to `GtkRecentManager` so file managers and file dialogs
list them.

## 7. Context menus

`GtkPopoverMenu` from a `gio::MenuModel`. Triggered by right-click, the Menu key and
Shift+F10.

| Object | Items |
|---|---|
| Cover or row | Read, Show Details, section break, Add to Shelf (sub-menu), Mark as Read or Unread, Download or Remove Download, section break, Show in Files (local files only), Copy Title |
| Several covers | Add to Shelf, Mark as Read, Mark as Unread, Download, Remove Download |
| Shelf in the sidebar | Rename, Pin or Unpin, Delete Shelf (`AdwAlertDialog`, says the books stay) |
| Source row | Refresh, Reconnect, Edit, Remove Source |
| Comic or PDF page | Bookmark This Page, Copy Image, Fit Page, Fit Width, Reading Direction |
| EPUB text selection | Copy, Search in Book, Highlight |
| Player chapter | Play from Here |

## 8. Drag and drop

`GtkDropTarget` for files. `GtkDragSource` for covers.

| Drag | Drop on | Result |
|---|---|---|
| Files (CBZ, CBR, CBT, EPUB, PDF) | Library window | Opens each in a reader window. Reads in place. In Flatpak the paths come through the document portal. |
| A folder | Library window | `AdwAlertDialog`: **Add as Source**. |
| A cover | A shelf in the sidebar | Adds to the shelf. |
| A row in a reading list | Another row | Reorders. |

Command-line and file-manager opens arrive as arguments (`GApplication` open). A running
instance opens a reader window.

## 9. Empty and offline states

Use the README table. Linux specifics:

- No sources, or a view that cannot show content: `AdwStatusPage` with icon, title, a
  short description and one suggested-action button.
- Offline: `AdwBanner`, neutral, "Offline. Showing what is on this computer." Verify in
  wave 1 that the banner is not accent-coloured at 1.5. If it is, draw a flat strip in
  `surfaceSunken`. Never `.error`.
- Sign-in needed: an `AdwActionRow` with a **Reconnect** button. Not a dialog.
- No Secret Service (Hyprland and minimal installs): the password row stays active. A
  grey subtitle names `gnome-keyring`, KeePassXC or `oo7-daemon`. The secret is held in
  memory for the session only and is asked for again at the next launch.
- Events (added to shelf, download finished): `AdwToast` with at most one action.

## 10. Accessibility

| Check | Rule |
|---|---|
| Orca | Every control has an accessible label. Icon-only buttons have `accessible-label` and a tooltip. Cover cells announce title, series, issue, percent read, downloaded. |
| Page turns | Announce "Page 12 of 32" with `gtk_accessible_announce` (GTK 4.14; Inferred, confirm). |
| Focus order | Header bar, sidebar, content. Reader: header bar, page, bottom bar. Test Tab and Shift+Tab with Orca on. |
| Keyboard | `GtkGridView` arrows move the focus. Enter reads. Every action has an accelerator. |
| High Contrast | `AdwStyleManager::high_contrast`: drop every token override. Libadwaita's style wins. |
| Reduce Motion | `gtk-enable-animations` off gives a fast fade. |
| Text size | The session text scaling factor applies. No fixed pixel font. At the largest size the library is a list. |
| Contrast | `pnpm tokens:check` for token surfaces. |
| Pointer target | Libadwaita's 34 px buttons stay. Nothing under 24 px. |
| Colour | Never the only signal. |

## 11. Materials and tokens

Libadwaita has no blur. Depth is flat. The accent is the only colour StoryArc adds to
chrome.

| Surface | Mechanism | Token |
|---|---|---|
| Window, header bar, sidebar, dialogs | Stock Adwaita for System, Light and Dark | None |
| Library content canvas | One generated class, `.storyarc-canvas` | `surfaceCanvas` |
| Cover letterbox | Same stylesheet | `surfaceSunken` |
| Cover radius | `.storyarc-cover`: 4 px radius, overflow hidden | `cover` |
| Cards in the detail page | `card` class | Stock |
| Reader | `.storyarc-reader` background | `surfaceReader` |
| Reader bottom bar and popovers over the page | `osd` class. No blur. | Fallback `surfaceOverlay` plus `borderStrong` |
| Accent | Named colours `accent_bg_color`, `accent_color`, `accent_fg_color` | `brand/accent` |
| Status | Symbolic icon plus text plus class `dimmed` or `error` | `status/*` |
| OLED Dark and Natural | Named-colour override set, only when chosen | Ramps |
| Type | `ui` = system font. `editorial` = Source Serif 4, bundled. `mono` = `monospace` class. | Typography tokens |
| Motion | Durations from tokens. | Motion tokens |

The stylesheet is **generated** from `packages/design-tokens` and is the only custom
CSS. It holds the four classes above and the accent override. Use style classes and
named colours elsewhere (`card`, `boxed-list`, `title-1`, `heading`, `caption`, `dimmed`,
`osd`; `@accent_bg_color`, `@window_bg_color`). No hand-made shadows.

**Accent colours.** On 1.5 the System choice is Adwaita blue, and StoryArc violet is the
default (README section 5). From libadwaita 1.6, guard a call to
`AdwStyleManager::accent_color` and offer **System** with the platform's accent. The
cover-derived accent inside a publication overrides both.

## 12. Compositor notes

From the research doc. IDs L9 to L16.

| Compositor | What to do |
|---|---|
| Hyprland | Always server-side mode, no title bar drawn. The header bar stays. Add Ctrl+W and Ctrl+Q. Set a minimum size. Needs `xdg-desktop-portal-gtk` for file dialogs, dark mode and settings. Window class `com.mecedric.StoryArc`. |
| Hyprland idle | `Application::inhibit(IDLE)` uses `zwp_idle_inhibit_v1`. |
| Hyprland secrets | No keyring ships. The user installs one. The app says so (section 9). |
| COSMIC | Portal has no Inhibit. `oo7-portal` or `gnome-keyring` for secrets. |
| KDE Plasma | Wayland or X11. Use `GtkFileDialog` and the Settings portal. |
| X11 and XWayland | Works. No curl until the spike shows it holds the frame budget. GTK deprecated its X11 backend in 4.17.4. |
| NVIDIA | Leave the renderer to GTK. Document `GSK_RENDERER=ngl` as the fallback. |

## 13. Linux-only integration

- App id `com.mecedric.StoryArc`. Desktop file, AppStream metainfo with screenshots,
  MIME types for CBZ, CBR, CBT, CB7, EPUB and PDF.
- Flatpak permissions: Wayland socket, X11 fallback, DRI, network, portal file access.
  No `--filesystem=home`.
- Folder watching with `inotify`. The watch limit is finite. Fall back to a rescan.
- Metered link from NetworkManager replaces the cellular rule.
- No tray, no notification for a refresh.

## 14. Review checklist

- [ ] Works at 360 px and at 1920 px.
- [ ] Only floor widgets, or guarded newer ones.
- [ ] Header bar has three zones, no text-only buttons.
- [ ] Offline path is grey. No red.
- [ ] No custom CSS beyond the generated stylesheet.
- [ ] Keyboard-only run passes. Orca reads every control.
- [ ] Light, dark and High Contrast checked. GTK Inspector (`GTK_DEBUG=interactive`).
- [ ] Captured on GNOME, KDE Plasma, Hyprland and COSMIC.
- [ ] No window positioning, no global shortcut, no tray, no secret outside libsecret.
