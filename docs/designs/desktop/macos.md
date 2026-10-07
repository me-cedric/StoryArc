# StoryArc on macOS

Status: proposal, wave 0. Stack: SwiftUI, macOS 26 floor, App Sandbox on, not Mac
Catalyst (ADR-0018, D2). Shared rules are in [`README.md`](README.md). This file
holds what is specific to the Mac.

**Governing skills.** `ui-review-tahoe` decides window chrome, HIG and review.
`macos-capabilities` decides menu bar, sandbox, extensions and background work.
`swiftui-liquid-glass` decides every glass surface. `swiftui-ui-patterns` and
`swiftui-view-refactor` decide view structure. `swiftui-performance-audit` runs on
the cover grid. The Mac app consumes `StoryArcKit` by path, so tokens and
`DesignSystem` come from the same generated source as iOS.

## 1. Direction

A Mac reader that looks like a macOS 26 app: a glass sidebar, a unified toolbar, a
cover canvas. The reader is the one place where StoryArc draws its own floating
glass, because the page is the loudest thing.

## 2. Information architecture

| Sidebar item | SF Symbol (proposed) | Content |
|---|---|---|
| Search | `magnifyingglass` | Focuses the toolbar field. |
| Home | `house` | Keep reading, Up next, shelves. |
| Library | `books.vertical` | Cover grid or list. |
| Downloads | `arrow.down.circle` | Queue, storage, downloaded books. |
| Library group | All Books, Series, Recently Added, Downloaded | Filters of Library. |
| Shelves group | Collections and reading lists | Pinned first. Drop target. |
| Footer | none | Settings opens with `⌘,`, not from the sidebar. |

Sources do not appear. The sidebar is a `NavigationSplitView` (`List` with
`.sidebar` style). Sidebar width 220 to 280 pt, default 240. The mini player sits
at the foot of the sidebar while audio plays.

## 3. Window anatomy

Library window: one `Window` scene, unified toolbar, glass sidebar from the SDK.

```
+---------------------------------------------------------------------------------+
| (o)(o)(o)   [|=]  <  >   Library                    [::|=] [Size v] [Search...] |
+--------------------+------------------------------------------------------------+
|  Search            |  Keep reading                                              |
|                    |  +----------------+ +----------------+                     |
|  Home              |  | cover  Title   | | cover  Title   |   (wide cards,      |
|  Library        <  |  |  ====----  42% | |  ==------  18% |    progress)        |
|  Downloads         |  +----------------+ +----------------+                     |
|                    |                                                            |
|  LIBRARY           |  All Books                                  3,214 titles   |
|   All Books        |  +------+ +------+ +------+ +------+ +------+ +------+     |
|   Series           |  |      | |      | |      | |      | |      | |      |     |
|   Recently Added   |  | art  | | art  | | art  | | art  | | art  | | art  |     |
|   Downloaded       |  |      | |      | |      | |      | |      | |      |     |
|                    |  |=-----| |      | |v     | |      | |===---| |      |     |
|  SHELVES           |  +------+ +------+ +------+ +------+ +------+ +------+     |
|   Weekend          |   Title    Title    Title    Title    Title    Title       |
|   Reading list A   |   Series   Series   Series   Series   Series   Series      |
|                    |                                                            |
|  [cover] Now       |   v = downloaded mark      === = progress rail             |
|  playing  |> 30s   |                                                            |
+--------------------+------------------------------------------------------------+
```

Toolbar, left to right: sidebar toggle (system), Back and Forward, the destination
title, then on the trailing side the view menu (grid or list, cover size, sort,
filter) and the search field. Nothing else. Items use the system toolbar style.
Icon-only items carry help tags and accessibility labels.

Selection mode follows the Mac form of the contextual-mode rule: the toolbar swaps
to the selection actions, shows the count in the title, and keeps **Done** as the
one way out. Cmd-click and Shift-click select many.

Detail page: pushed into the content column. A `backgroundExtensionEffect()` on the
hero lets the cover wash sit under the glass sidebar. Primary action **Read** or
**Continue** as the one prominent button. Other actions in a **More** menu.

Layout classes: Compact under 600 collapses the sidebar into an overlay (the system
does this on a narrow window). Regular and Wide as in the README.

## 4. Reader windows

One `WindowGroup(for: PublicationID.self)`. A second request for an open publication
focuses its window. Windows restore on relaunch at the saved page. Quit flushes progress.

```
+---------------------------------------------------------------------------------+
| (o)(o)(o)                 Saga 042                                              |
+---------------------------------------------------------------------------------+
|                                                          +--------------------+ |
|                                                          | [=] Aa [|] [flag]  | |  glass,
|                                                          +--------------------+ |  untinted
|          +----------------------+  +----------------------+                     |
|          |                      |  |                      |                     |
|          |       page 13        |  |       page 12        |   right-to-left     |
|          |                      |  |                      |   pair: N on right  |
|          +----------------------+  +----------------------+                     |
|                                                                                 |
|            +-----------------------------------------------------------+        |
|            | 12-13 / 32  <|====o----------------------------|>  [thumb]|        |  glass
|            +-----------------------------------------------------------+        |
+---------------------------------------------------------------------------------+
```

| Element | Behaviour |
|---|---|
| Title bar | Transparent, traffic lights and title. Stays in windowed mode. |
| Top glass cluster | Contents, Appearance, Layout, Bookmark. `GlassEffectContainer` so shapes morph as one. |
| Bottom glass bar | Page slider, count, thumbnail on drag. Mirrors in right-to-left. |
| Fade | After 3 s idle. Page never reflows. |
| Full screen | `⌃⌘F`. The menu bar hides and shows on top-edge hover, as the system does. |
| Contents panel | `inspector` on the trailing edge. Chapters, thumbnails, bookmarks. `⌘T`. |
| Appearance | Popover anchored to its button. Six preset cards in 3 by 2, font-size stepper, page mode. The page updates live behind it. |
| Reduce Transparency | Both glass shapes fall back to `surfaceOverlay` with `borderStrong`. |

Comic and PDF: `ZoomablePage` compiles but is a plain image on macOS today
(parity 5.3). The Mac shell adds zoom and pan with `NSScrollView` magnification or
SwiftUI gestures, plus the curl drag. PDF uses PDFKit.

EPUB: one pinned renderer in `WKWebView` (D6). The toolbar, bars and popovers stay
SwiftUI. The web view sits under the glass. The renderer gets the six reading themes
as CSS. macOS has no Dynamic Type, so the Appearance popover holds the size control.

Audiobook: the Player window (420 x 640). Large cover, chapter title, scrubber with
elapsed and remaining time, skip back 15 s, play or pause, skip forward 30 s, speed,
sleep timer, chapter list. Media keys and the system Now Playing item work through
`MPNowPlayingInfoCenter` and the remote command centre. The `Playback` target must
split its `#if os(iOS)` guard first (parity 5.2).

Read Aloud: starts from the Reader menu. Uses the system speech engine. Control is
absent when no voice exists.

## 5. Settings

The `Settings` scene, opened with `⌘,`. One window, toolbar tabs. The tabs match the
spec groups: **Sources, Appearance, Reading, Downloads, Language, Privacy**. About is
the system panel in the StoryArc menu. What's New and Acknowledgements are Help items.

- Each tab opens on a grouped form (`Form` with `.grouped` style). Width 560 pt fixed.
- Sources: list of sources with a state dot and last sync. Offline sources are
  dimmed. Add, edit and remove sit under the list. Removing a source asks first and
  says that downloads and progress stay.
- Appearance: System, Light, Dark, OLED Dark, Natural. Accent: StoryArc or System.
  Cover size default. Reduce Motion note when the system flag is on.
- Reading: defaults for direction, layout (Auto), fit, edge click zones (off), page
  transition, reading theme. A per-series choice is never overwritten.
- Downloads: storage bar, Wi-Fi rule shown as "not on a metered link", clear cache.
- Language: the app language note with a button to open System Settings, plus the
  content language rule.
- Privacy: what is stored, clear reading history, export a diagnostic.
- Search: the spec asks for searchable settings. The `Settings` scene gives no search
  field (Inferred). **Proposed:** a search field in the Settings toolbar that lists
  matches with their tab path.

## 6. Menu bar

Every command, in the order a Mac user expects. The StoryArc menu holds About
StoryArc, Settings (`⌘,`), Services, Hide StoryArc (`⌘H`), Hide Others (`⌥⌘H`), Show
All and Quit (`⌘Q`). Edit also carries the system Start Dictation and Emoji items.
View adds the system Show Toolbar and Customize Toolbar items.

| Menu | Command | Shortcut |
|---|---|---|
| File | Open File… | ⌘O |
| File | Open Recent | none |
| File | Add Source… | ⇧⌘A |
| File | Refresh Sources | ⌘R |
| File | Close Window | ⌘W |
| File | Settings… | ⌘, |
| File | Quit StoryArc | ⌘Q |
| Edit | Copy | ⌘C |
| Edit | Select All | ⌘A |
| Edit | Find | ⌘F |
| Edit | Find Next | ⌘G |
| Edit | Find Previous | ⇧⌘G |
| View | View as Grid | ⌥⌘1 |
| View | View as List | ⌥⌘2 |
| View | Larger Covers | ⌘+ |
| View | Smaller Covers | ⌘− |
| View | Automatic Cover Size | ⌘0 |
| View | Show or Hide Sidebar | ⌃⌘S |
| View | Enter or Exit Full Screen | ⌃⌘F |
| Go | Back | ⌘[ |
| Go | Forward | ⌘] |
| Go | Home | ⌘1 |
| Go | Library | ⌘2 |
| Go | Downloads | ⌘3 |
| Go | Continue Reading | ⇧⌘C |
| Go | Show Details | ⌘I |
| Reader | Next Page | → |
| Reader | Previous Page | ← |
| Reader | First Page | Home or ⌘↑ |
| Reader | Last Page | End or ⌘↓ |
| Reader | Go to Page… | ⌥⌘G |
| Reader | Next Chapter or Issue | ⌘→ |
| Reader | Previous Chapter or Issue | ⌘← |
| Reader | Single Page | ⌥⌘1 |
| Reader | Two Pages | ⌥⌘2 |
| Reader | Scroll | ⌥⌘3 |
| Reader | Zoom In or Larger Text | ⌘+ |
| Reader | Zoom Out or Smaller Text | ⌘− |
| Reader | Fit Page | ⌘0 |
| Reader | Fit Width | ⌘9 |
| Reader | Original Size | ⌥⌘0 |
| Reader | Show Contents | ⌘T |
| Reader | Appearance | ⇧⌘T |
| Reader | Bookmark This Page | ⌘D |
| Reader | Show or Hide Controls | ⇧⌘H |
| Reader | Read Aloud | ⇧⌘L |
| Reader | Play or Pause | Space |
| Reader | Skip Back 15 s | ← |
| Reader | Skip Forward 30 s | → |
| Window | Minimize | ⌘M |
| Help | Keyboard Shortcuts | ⌘? |
| Help | What's New… | none |
| Help | Acknowledgements… | none |
| Help | Report a Problem… | none |

`CommandGroup` and `CommandMenu` build these. A command is disabled, not hidden,
when its window type is not key. Reader items are disabled in a library window and
the reverse. The Dock menu offers Keep reading (named), Library, Downloads and the
last five publications (`NSApplicationDelegate.applicationDockMenu`).

## 7. Context menus

| Object | Items |
|---|---|
| Cover or row | Read, Show Details, separator, Add to Shelf (submenu), Mark as Read or Unread, Download or Remove Download, separator, Show in Finder (local files only), Copy Title |
| Several covers | Add to Shelf, Mark as Read, Mark as Unread, Download, Remove Download |
| Shelf in sidebar | Rename, Pin or Unpin, Delete Shelf (destructive, confirms, says the books stay) |
| Source row | Refresh, Reconnect, Edit, Remove Source (destructive) |
| Comic or PDF page | Bookmark This Page, Copy Image, Fit Page, Fit Width, Reading Direction (submenu) |
| EPUB text selection | Copy, Look Up, Search in Book, Highlight |
| Player chapter | Play from Here |

## 8. Drag and drop

| Drag | Drop on | Result |
|---|---|---|
| Files (CBZ, CBR, CBT, EPUB, PDF) | Library window or Dock icon | Opens the first one in a reader window. Several: asks nothing, opens each. Reads in place. |
| A folder | Library window | Sheet: **Add as Source**. One action, one cancel. The sandbox needs a security-scoped bookmark. |
| A cover | A shelf in the sidebar | Adds to the shelf. |
| A row in a reading list | Another row | Reorders. |
| A cover | Finder or Desktop | Copies the file when it is local. Remote and Kavita items offer no drag. |

## 9. Empty and offline states

Use the README table. Mac specifics: the status page is a `ContentUnavailableView`
with one `borderedProminent` button. The offline banner is a grey strip under the
toolbar, `status/offline` text on `surfaceSunken`, with an icon. A source that needs sign-in shows one line on Home with a **Reconnect** button, and a row in Settings. Sources never appear in the sidebar.

## 10. Accessibility

| Check | Rule |
|---|---|
| VoiceOver | Cover cell label: "Title, series, issue 4, 62 percent read, downloaded". The grid is a collection with the rotor. Each turn posts `AccessibilityNotification.Announcement`: "Page 12 of 32". |
| Full Keyboard Access | Tab moves through sidebar, toolbar, content. Arrow keys move in the grid. Return reads. |
| Focus order | Sidebar, toolbar, content. Reader: page, top cluster, bottom bar. |
| Reduce Motion | Curl and slide become a fast fade. The mode picker lists them unavailable with the reason. |
| Reduce Transparency, Increase Contrast | Glass becomes `surfaceOverlay`. Borders use `borderStrong`. Natural grain turns off. |
| Contrast | `pnpm tokens:check` on all ramps. |
| Text size | macOS has no Dynamic Type. The library follows system font size where SwiftUI scales. The reader has its own size control. |
| Pointer target | Toolbar and bar controls are at least 28 pt. |

## 11. Materials and tokens

| Surface | Material | Token |
|---|---|---|
| Sidebar, toolbar, popovers, menus | System (Liquid Glass from the SDK) | None. Do not tint. |
| Library content | Opaque fill | `surfaceCanvas` |
| Cover letterbox, empty wells | Opaque fill | `surfaceSunken` |
| Cards in the detail page, list rows | Opaque fill | `surfaceRaised` |
| Reader window | Opaque fill | `surfaceReader` (never pure black) |
| Reader bars, Appearance popover | `glassEffect`, untinted (`glass.chromeTintOpacity` 0) | Fallback `surfaceOverlay` plus `borderStrong` |
| Text on glass | Semantic styles (`.primary`, `.secondary`) so vibrancy works | None |
| Text on a token surface | Token text roles | `textPrimary`, `textSecondary`, `textTertiary` |
| Accent | `AccentColor` asset, `.tint` | `brand/accent` |
| Publication context | Cover-derived accent, contrast-adjusted | Derived |
| Status | Symbol plus label plus colour | `status/offline`, `status/downloaded`, `status/danger` |
| Radius | Continuous corners | `cover` 4 on covers, `md` 10 on cards |
| Type | `ui` = system. `editorial` = New York (`.fontDesign(.serif)`). `mono` = SF Mono. | Typography tokens |
| Motion | `chromeFade` 220, `pageTurn` 450, `standard` easing | Motion tokens |

Glass lives only on reader chrome. The library uses the chrome the SDK provides.
No custom shadows.

## 12. Mac-only integration

- App Sandbox: user-selected read access, app-scope bookmarks, network client, keychain
  group. `FolderBookmarks` needs `.withSecurityScope` on create and resolve (parity 5.2).
- Document types and exported UTIs kept from iOS. The local-network text and Bonjour
  services go in the Mac `Info.plist`.
- Handoff and Spotlight reuse `ReadingContinuity`.
- No menu bar extra, no notifications, no background agent (README, parity item 17).

## 13. Review checklist

- [ ] No custom window chrome. Toolbar items use system styles.
- [ ] Glass only on reader chrome, untinted, with a declared fallback.
- [ ] Every command in the menu bar. Disabled, not hidden.
- [ ] Settings reachable with `⌘,`. About is the system panel.
- [ ] Capture in light, dark, Increase Contrast and Reduce Transparency.
- [ ] VoiceOver run through library, detail, reader and player.
