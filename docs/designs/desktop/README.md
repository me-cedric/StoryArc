# StoryArc desktop design

Status: proposal for wave 0 of the `desktop-clients` change. Date: 2026-10-07.
Scope: macOS, Windows and Linux clients. Presentation layer only.

This folder is the product design for the three desktop apps. It sits on top of
[`docs/design.md`](../../design.md), which stays the contract for tokens and
materials. It follows [`ui-revamp-2026-08.md`](../ui-revamp-2026-08.md) for the
information architecture. It does not change either file.

| File | Covers |
|---|---|
| `README.md` | Shared principles, shared rules, the cross-platform shortcut table |
| [`macos.md`](macos.md) | SwiftUI on macOS 26, Liquid Glass |
| [`windows.md`](windows.md) | WinUI 3 on Windows 11, Mica and Acrylic |
| [`linux.md`](linux.md) | GTK4 and libadwaita, Wayland first |

Inputs read: [`design.md`](../../design.md), the
[`native-experience`](../../openspec/specs/native-experience/spec.md) spec, the
[parity audit](../../delivery/desktop-parity-2026-10-07.md), the one-library
change, and the vendored design skills. Items marked **Proposed** need an owner
decision or a spike in a later wave.

## 1. Shared principles

The three apps are one product on three platforms. They look alike in
direction and different in material.

| Principle | Desktop meaning |
|---|---|
| The artwork is the interface | Covers and pages fill the window. A cover is never smaller than 104 pt. Titles sit below the cover, never over it. |
| Chrome recedes | Platform chrome (sidebar, title bar, header bar) is stock. StoryArc adds no frame, no gradient, no decoration. In the reader, floating bars fade after 3 s. |
| Offline is grey | An offline source is dimmed with `status/offline`. No red, no blocking dialog. Red means a real failure or a destructive choice. |
| One accent | `brand/accent` marks what is interactive or what is your progress. Inside a publication, the accent comes from the cover. |
| One serif moment | Platform sans for all chrome. `editorial` serif on publication titles only, at most twice per screen. |
| Depth comes from the platform | Liquid Glass on macOS. Mica and Acrylic on Windows. Flat Adwaita on Linux. No invented shadow system. |
| Platform text, platform icons | SF Symbols, Segoe Fluent Icons, Adwaita symbolic icons. No custom icon set. |

What the three platforms share, and what they must not share:

- Shared: the destinations, the command set, the shortcut logic, the spread rules,
  the empty states, the cover ladder and the tokens.
- Not shared: any widget code. No cross-platform UI. The EPUB page is the one web
  view (ADR-0018, D6).
- Rule of surfaces: chrome belongs to the platform. The canvas under covers
  (`surfaceCanvas`), the reader (`surfaceReader`) and the letterbox
  (`surfaceSunken`) belong to the tokens.

## 2. What desktop changes

| Area | Mobile | Desktop |
|---|---|---|
| Windows | One window. The reader covers it. | Many windows. A library window plus one reader window per publication. The library stays open. |
| Pointer | Touch. Swipe, pinch, long press. | Hover, click, double-click, right-click, wheel, trackpad pinch. Hover reveals chrome. |
| Keyboard | Optional. | Complete. Every command has a menu item or a key. Focus is always visible. |
| Density | One cover tier by width. | A cover ladder by shelf width, plus a user size step and a list view. A larger window shows more covers, not larger ones. |
| Navigation | Tab bar. | Persistent sidebar. Back and forward in the toolbar. |
| System bridges | Quick actions, Handoff, widgets. | Dock menu, Jump List, `.desktop` actions, file associations, media keys, system media controls. |
| Dropped | CarPlay, volume keys, haptics, orientation lock, app icon chooser. | Not designed. Cellular becomes a metered link. |

Pointer rules:

1. A click selects. A double-click or Return reads. Right-click opens the context menu.
2. Hover never hides information. It reveals chrome only.
3. The cursor hides after 3 s of idle time, together with the reader chrome.
4. Edge click zones are **off by default** on desktop. They fight window drag and
   text selection. The setting exists in Reading. This answers parity question 2 as a proposal.
5. Pointer targets are at least 24 by 24 px (WCAG 2.5.8). Toolbar controls aim at 32.
   A touch-capable Windows device gets 40.

## 3. Information architecture

The sidebar replaces the tab bar. The structure follows the iPad sidebar of the
UI revamp. **No section lists servers.** Sources live in Settings.

| Sidebar section | Items | Mobile origin |
|---|---|---|
| (top) | Search | Search tab |
| Destinations | Home, Library, Downloads | Home, Library, Downloads tabs |
| Library | All Books, Series, Recently Added, Downloaded | Library section of the iPad sidebar |
| Shelves | Collections and reading lists. Pinned first. | Shelves section |
| (footer) | Settings, on Windows only. macOS and Linux open it from the menu. | Settings button |

Rules:

- Search is a field in the toolbar or header that stays in place and never changes shape.
  Activating it shows a results view that takes over the content column, so search is a
  place a reader arrives at (navigation-shell, Reaching search; the spec requirement
  Search on a desktop records this reading). It scopes to the current destination and
  offers to widen to everything.
- Home shows Keep reading, Up next and shelves. A shelf with nothing in it is absent.
- Publication detail is a pushed page in the content column. It is never a sheet.
  Layout: cover-derived wash, large cover, `editorial` title, a tight metadata stack,
  one primary action (Continue or Read), everything else in a menu, and one line
  that says where the file lives. At 1024 wide or more, the cover and the text sit
  side by side. Text width is capped at `maxContentWidth` (720).
- The library window has no inspector. The detail page does that job. The reader
  window has a trailing panel for contents, page thumbnails and bookmarks.
- The mini player sits at the foot of the sidebar when audio plays. The full player
  is its own compact window.

## 4. Windows, sizes and breakpoints

| Window | Default size | Minimum | Notes |
|---|---|---|---|
| Library | 1100 x 720 | macOS 520 x 400, Windows 480 x 360, Linux 360 x 294 | Restores size, sidebar state and last view. |
| Reader, comic or PDF | Fits 90 percent of the display height, width by page shape | 360 x 360 | Remembers size per format. Clamped to the work area. |
| Reader, EPUB | 760 x 900 | 360 x 360 | Remembers size. |
| Player, audiobook | 420 x 640 | 320 x 360 | One per app. A new book replaces the current one. |
| Settings | Platform default | Platform default | One window, one instance. |

Linux never positions a window (Wayland forbids it). macOS and Windows restore position
on the display that still exists.

**Layout classes** by content width of the library window. Platforms add their own
thresholds in their file.

| Class | Width | Layout |
|---|---|---|
| Compact | under 600 | Sidebar becomes an overlay or a drill-down page. One column of content. |
| Regular | 600 to 1023 | Sidebar and content. |
| Wide | 1024 and up | Sidebar and content. Detail page uses two columns. |

**Cover ladder.** One rule, from `design.md`: the shelf asks for its own measured
width, never the window's.

| Shelf width | Minimum cover width | Maximum cover width |
|---|---|---|
| under 600 | 104 pt | 168 pt |
| 600 to 839 | 132 pt | 168 pt |
| 840 and up | 158 pt | 168 pt |

The user can pick **Small, Medium or Large** (104, 132, 158) with Larger and Smaller
Covers. Automatic is the default. A very wide window adds columns. It never stretches
one cover. The grid is a virtualised list. Rows hold 10,000 publications at the
display refresh rate.

**List view.** Columns: cover thumbnail, Title, Series, Issue, Format, Progress, Added.
The header sorts. The list is the fallback when the system text size leaves no room
for legible titles under covers.

**Cover cell.** Art edge to edge, `cover` radius 4, letterbox onto `surfaceSunken`.
A thin progress rail on the bottom edge. A small filled mark in one corner when
downloaded. Title below. Never a progress ring over the art.

## 5. Chrome accent (Proposed)

Parity audit question 1 asked whether chrome follows the OS accent or the StoryArc accent.

Proposal: **StoryArc violet by default on all three**, with a setting in Appearance:
*Accent: StoryArc or System*. This keeps one accent to reason about
(`design.md`, section 2). The proposal needs an owner answer.

| Platform | How the default is applied | What the OS still draws |
|---|---|---|
| macOS | `AccentColor` asset set to `brand/accent`. | A person who picked a fixed accent in System Settings keeps it in sidebar selection and text selection. This follows Apple. |
| Windows | Override `SystemAccentColor` and its shades in app resources. | High Contrast ignores the override. |
| Linux | Override `accent_bg_color`, `accent_color` and `accent_fg_color` with named colours on 1.5. From 1.6 use `AdwStyleManager::accent_color` for the System choice. | High Contrast. |

Cover-derived accent applies inside a publication (detail page and reader) on all three,
after the lightness adjustment from `design.md`. Raw extracted colour is never used.

## 6. The reader window

### 6.1 Chrome

- Two floating bars sit over the page. Top cluster: contents, appearance, layout,
  bookmark. Bottom bar: page slider with a thumbnail that follows the drag, and the
  page count.
- The page never moves or resizes when chrome appears. The bars overlay it.
- Chrome shows on pointer move, on Tab, on Esc when hidden and on a click in the
  centre third. It fades after 3 s of pointer idle time (`chromeFade` 220 ms).
  It stays while a popover is open, while a key is held and while the pointer is over it.
- The native title bar (or header bar) stays outside the page in windowed mode.
  Full screen hides it.
- Reduce Motion: the fade becomes instant.
- Reduce Transparency: bars use `surfaceOverlay` with `borderStrong`.

### 6.2 Full screen

F11, or the platform key. Chrome and the menu bar hide. The pointer at the top edge
reveals the platform title strip where the OS offers one. Esc closes a popover first,
then leaves full screen. The display stays awake while a publication is open and the
window is visible (sleep assertion on macOS, `SetThreadExecutionState` on Windows,
`Application::inhibit` on Linux).

### 6.3 Two-page spreads

Pairing is a layout of the reader, not of the file. The rules are the same on
all platforms.

1. Layout setting: **Auto**, Single, Two Pages, Scroll. Auto is the default.
2. Auto shows two pages when the content area is at least 1.3 times wider than tall
   **and** the pages are portrait. Otherwise it shows one.
3. The cover (page 1) is shown alone. A pairing offset of one page moves the pairing.
   The offset is a per-publication setting in the layout popover.
4. A page detected as a wide spread is shown alone and is never split across two turns.
5. A turn moves two pages. The last page of an odd count is shown alone.
6. **Right-to-left**: the first page of a pair sits on the **right**. Page N is on the
   right, N+1 on the left. The slider fills from right to left. ← means next. Space and
   Page Down still mean next. The curl starts from the opposite edge.
7. Scroll mode ignores spreads. Webtoons and long strips scroll vertically.
8. Zoom keeps both pages as one unit. Pan moves the pair.
9. Resizing the window changes the layout live and keeps the current page.
10. EPUB uses two columns when the content area is 1000 pt or wider and the measure
    allows it. The reading theme sets the measure (Focus is narrow).
11. A page needs `PageDecoder.isSpread` to be wired to production. The audit found
    no caller on 2026-09-28. Wave 1 must check this first.

### 6.4 Pointer reading

- Wheel scrolls in Scroll mode. In paged modes the wheel turns pages after a short
  accumulation threshold, so a trackpad does not skip pages.
- Pinch zooms. Ctrl+wheel (Cmd+wheel on macOS) zooms. Double-click toggles Fit Page and 200 percent.
- Drag pans when zoomed. At the edge of the pan area, a further turn key advances.
- Drag at Fit Page turns the page with the curl. The curl follows the pointer, as on
  mobile (`design.md`, section 6). It is absent where it cannot be honest: Reduce Motion,
  X11 until the Linux spike shows it holds the frame budget there, or a failed frame budget.
  Under Reduce Motion the fallback is Fast fade, as in `page-transitions`: nothing slides.
  Slide is the fallback only where the curl is missing (X11, a failed frame budget), with the reason stated.
- Text selection works in EPUB and PDF. A drag on a page image never selects.

### 6.5 Formats

| Format | Surface | Notes |
|---|---|---|
| Comic (CBZ, CBR, CBT) | Native image view | Spread rules above. Image adjustments in the layout popover. |
| EPUB | One system web view with the pinned renderer | Chrome, themes and menus stay native. The page is the only web content. |
| PDF | Native page view | Same page rules as comics, plus selection, search and outline. |
| Audiobook | Player window | Cover, chapter, scrubber, 15 s back, 30 s forward, speed 0.5 to 3, sleep timer, chapter list. |

## 7. Empty, offline and failed states

| State | What the window shows |
|---|---|
| No sources yet | Home is a status page: one sentence, one action, **Add a Source**. Library shows the same page. |
| Nothing in progress | Keep reading is absent. |
| Offline | A grey banner: "Offline. Showing what is on this computer." No red. Offline sources are dimmed in Settings. Downloaded covers keep their mark. |
| Source needs sign-in | An inline row with a **Reconnect** action. Not a dialog. |
| A file will not open | The cover shows an icon and a label. Red `status/danger` plus text, never colour alone. The reader says why and offers one action. |
| No keyring on Linux | The password field stays active. One grey line names the missing service and links to the fix. The secret is held in memory for the session only, and the app never stores a secret in a file. |
| Search with no match | Names what was searched. Offers to widen the scope. |

Every empty state names what would be here and offers the one action that fills it.
No illustration without an action.

## 8. Accessibility floor

| Area | Rule |
|---|---|
| Names | Every control has a name. A cover cell says: title, series, issue, percent read, downloaded or not. |
| Reader | Each turn announces "Page 12 of 32" or "Pages 12 and 13 of 32". The chapter shows for EPUB. |
| Focus order | Sidebar, toolbar or header, content, trailing panel. In the reader: page, then chrome. |
| Keyboard | Every command is reachable without a pointer. Focus is always visible. |
| Contrast | The five ramps and six reading themes pass `pnpm tokens:check`. |
| Transparency | Reduce Transparency and Increase Contrast give the opaque fallback with strong borders. |
| Motion | Reduce Motion gives a cross-dissolve. No decorative animation. |
| Text size | The library follows the OS text size. At the largest size it becomes a list. EPUB has its own size control on every platform. |
| Colour | Never the only signal. |
| Screen readers | VoiceOver on macOS. Narrator and NVDA on Windows. Orca on Linux. Each platform file lists the checks. |

## 9. Cross-platform shortcut table

One command set. One logic: the first key is Cmd on macOS and Ctrl on Windows and
Linux. A cell differs only where the operating system owns the key. The deviations:

- macOS keeps `⌃⌘S` for the sidebar and `⌃⌘F` for full screen. These are Apple standards.
- Windows and Linux use Alt+Left and Alt+Right for Back and Forward.
- macOS reserves `⇧⌘1` to `⇧⌘4` for screenshots, so layout keys use `⌥⌘`.
- Linux uses F9 for the sidebar (GNOME HIG). Windows uses Ctrl+B.
- Windows has no app Quit key. The File menu holds Quit with no accelerator, and Alt+F4 closes the window. Linux uses Ctrl+Q.

| Command | macOS | Windows | Linux | Note |
|---|---|---|---|---|
| Open File… | ⌘O | Ctrl+O | Ctrl+O | Opens one publication in a reader window. Reads in place; never imports. |
| Open Recent | none | none | none | Submenu of the last 10 publications. |
| Add Source… | ⇧⌘A | Ctrl+Shift+A | Ctrl+Shift+A | Folder, SMB share, OPDS catalogue, Kavita server. |
| Refresh Sources | ⌘R | Ctrl+R (also F5) | Ctrl+R (also F5) | Never raises a notification. Progress shows in the window. |
| Close Window | ⌘W | Ctrl+W | Ctrl+W | Closing the last library window quits on Windows and Linux. macOS stays running. |
| Settings… | ⌘, | Ctrl+, | Ctrl+, | Opens the settings surface of the platform. |
| Quit StoryArc | ⌘Q | none (menu item; Alt+F4 closes the window) | Ctrl+Q | Flushes reading progress before exit. |
| Copy | ⌘C | Ctrl+C | Ctrl+C | Selected text, or the page image when nothing is selected. |
| Select All | ⌘A | Ctrl+A | Ctrl+A | Library: all covers in view. EPUB and PDF: all text. |
| Find | ⌘F | Ctrl+F | Ctrl+F | Library: focuses search. Reader: find in publication. |
| Find Next | ⌘G | Ctrl+G (also F3) | Ctrl+G (also F3) | Reader only. |
| Find Previous | ⇧⌘G | Ctrl+Shift+G | Ctrl+Shift+G | Reader only. |
| View as Grid | ⌥⌘1 | Ctrl+Shift+1 | Ctrl+Shift+1 | Library window. |
| View as List | ⌥⌘2 | Ctrl+Shift+2 | Ctrl+Shift+2 | Library window. Sortable columns. |
| Larger Covers | ⌘+ | Ctrl++ | Ctrl++ | One step: Small 104, Medium 132, Large 158. Library window. |
| Smaller Covers | ⌘− | Ctrl+− | Ctrl+− | Library window. |
| Automatic Cover Size | ⌘0 | Ctrl+0 | Ctrl+0 | Returns to the width-driven ladder. Library window. |
| Show or Hide Sidebar | ⌃⌘S | Ctrl+B | F9 | OS standard key on each platform. |
| Enter or Exit Full Screen | ⌃⌘F | F11 | F11 | Esc exits full screen after it closes any transient UI. |
| Back | ⌘[ | Alt+← | Alt+← | Pops the detail page or shelf. |
| Forward | ⌘] | Alt+→ | Alt+→ |  |
| Home | ⌘1 | Ctrl+1 | Ctrl+1 | Destination. |
| Library | ⌘2 | Ctrl+2 | Ctrl+2 | Destination. |
| Downloads | ⌘3 | Ctrl+3 | Ctrl+3 | Destination. |
| Continue Reading | ⇧⌘C | Ctrl+Shift+C | Ctrl+Shift+C | Opens the most recent publication at its resume point. |
| Show Details | ⌘I | Ctrl+I | Ctrl+I | Pushes the publication detail page for the selected cover. |
| Next Page | → | → | → | Also Space and Page Down. Right-to-left: ← is next, Space and Page Down stay next. |
| Previous Page | ← | ← | ← | Also Shift+Space and Page Up. Right-to-left: → is previous. |
| First Page | Home or ⌘↑ | Home | Home |  |
| Last Page | End or ⌘↓ | End | End |  |
| Go to Page… | ⌥⌘G | Ctrl+L | Ctrl+L | Page number, or percent for EPUB. |
| Next Chapter or Issue | ⌘→ | Ctrl+→ | Ctrl+→ | Comic: next issue of the series. EPUB and audiobook: next chapter. Follows reading direction. |
| Previous Chapter or Issue | ⌘← | Ctrl+← | Ctrl+← | Same rule. |
| Single Page | ⌥⌘1 | Ctrl+Shift+1 | Ctrl+Shift+1 | Reader window. |
| Two Pages | ⌥⌘2 | Ctrl+Shift+2 | Ctrl+Shift+2 | Spread rules in README section 6. |
| Scroll | ⌥⌘3 | Ctrl+Shift+3 | Ctrl+Shift+3 | Continuous. Vertical by default. |
| Zoom In or Larger Text | ⌘+ | Ctrl++ | Ctrl++ | Comic and PDF: zoom. EPUB: text size. |
| Zoom Out or Smaller Text | ⌘− | Ctrl+− | Ctrl+− |  |
| Fit Page | ⌘0 | Ctrl+0 | Ctrl+0 | Resets zoom. |
| Fit Width | ⌘9 | Ctrl+9 | Ctrl+9 |  |
| Original Size | ⌥⌘0 | Ctrl+Shift+0 | Ctrl+Shift+0 | One image pixel per screen pixel. |
| Show Contents | ⌘T | Ctrl+T | Ctrl+T | Chapters, page thumbnails, bookmarks. |
| Appearance | ⇧⌘T | Ctrl+Shift+T | Ctrl+Shift+T | Reading theme popover. The page stays visible and updates live. |
| Bookmark This Page | ⌘D | Ctrl+D | Ctrl+D |  |
| Show or Hide Controls | ⇧⌘H | Ctrl+Shift+H | Ctrl+Shift+H | Tab also reveals controls and moves focus into them. |
| Read Aloud | ⇧⌘L | Ctrl+Shift+L | Ctrl+Shift+L | Absent where the OS has no speech engine. |
| Play or Pause | Space | Space | Space | Audiobook window only. Media keys work from any window. |
| Skip Back 15 s | ← | ← | ← | Audiobook window only. |
| Skip Forward 30 s | → | → | → | Audiobook window only. |
| Minimize | ⌘M | none (OS) | none (OS) | macOS Window menu. |
| Keyboard Shortcuts | ⌘? | Ctrl+? | Ctrl+? | Opens the platform shortcut overview. |
| What's New… | none | none | none |  |
| Acknowledgements… | none | none | none |  |
| Report a Problem… | none | none | none | Opens a prefilled mail or issue page. Sends nothing by itself. |

A key may serve two commands when each is enabled in its own window type only. Larger
Covers and Zoom In share a key. So do Grid and Single Page. The disabled one never fires.

Single-key commands (arrows, Space, Home, End) work only when the reader or player
has focus and no text field is active.

## 10. Proof

A visible change owes a capture from a running app, as on mobile.

| Platform | Capture | Matrix |
|---|---|---|
| macOS | `screencapture` of a running build | Light and dark. Increase Contrast. Reduce Transparency. |
| Windows | Screenshot of a packaged or `winapp run` build | Light, dark, High Contrast, 100 and 200 percent scale. |
| Linux | Screenshot on each target compositor | GNOME, KDE Plasma, Hyprland, COSMIC. Light, dark, High Contrast. 360 and 1920 px wide. |

## 11. Open decisions

| # | Question | Proposed answer |
|---|---|---|
| O1 | Chrome accent: brand or OS | Brand by default, setting for System (section 5). |
| O2 | Edge click zones | Off by default (section 2). |
| O3 | Shared app shell between iOS and macOS | Later wave. Needs a change under `apps/ios`. |
| O4 | Linux accent on the 1.5 floor | CSS named-colour override. Re-check on 1.6 and newer. |
| O5 | Curl on Windows and Linux | Spike in wave 1. Slide is the honest fallback for a missing curl. Reduce Motion gives Fast fade. |
