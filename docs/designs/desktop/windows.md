# StoryArc on Windows

Status: proposal, wave 0. Stack: WinUI 3 on Windows App SDK 2.x, C# on .NET 10,
Windows 11 24H2 (build 26100) floor (ADR-0018, D3; research in
[`desktop-research-windows`](../../delivery/desktop-research-windows-2026-10-07.md)).
Shared rules are in [`README.md`](README.md). This file holds what is specific to
Windows.

**Governing skills.** `winui-design` decides layout, controls, Fluent, theming and
accessibility. Load it before any XAML. `winui-code-review` decides review.
`winui-dev-workflow` decides build and run. All three need WinApp CLI 0.7 or newer.
Run `winapp find-ui` before writing a control. The Rust core and the C# interop are
outside this document.

## 1. Direction

A Windows 11 app that follows Fluent: Mica behind the sidebar and title bar, a
`NavigationView`, standard dialogs and flyouts. The cover canvas and the reader are
the two surfaces StoryArc paints itself. The app silhouette is the **media hero**
anchor of `winui-design` for the reader, and the **hierarchical browser** for the
library.

## 2. Information architecture

| `NavigationView` item | Glyph (Segoe Fluent, proposed) | Content |
|---|---|---|
| Home | Home | Keep reading, Up next, shelves. |
| Library | Library | Cover grid or list. Expands to All Books, Series, Recently Added, Downloaded. |
| Downloads | Download | Queue, storage, downloaded books. |
| Shelves (header) | Pinned first | Collections and reading lists. Drop target. |
| Settings (footer) | Settings | Built-in settings item. |

Search is an `AutoSuggestBox` in the title bar, centred, as Fluent apps do. Sources
do not appear in the pane. `PaneDisplayMode` is `Auto`: Expanded at 1008 and wider,
Compact (icons) from 641, Minimal (hamburger) at 640 and narrower. These are the
control's own thresholds, and they win over the README classes on this platform. The
mini player sits at the foot of the pane while audio plays.

## 3. Window anatomy

`Window` with the `TitleBar` control extended into content, `MicaBackdrop` as
`SystemBackdrop`. The pane is transparent so Mica shows. The content area is painted
`surfaceCanvas`.

```
+---------------------------------------------------------------------------------+
| [S] < | File Edit View Go Reader Help |     [ Search...          ]        _ [] X|
+----------------+----------------------------------------------------------------+
|  Home          |  Keep reading                                                  |
|  Library    <  |  +----------------+ +----------------+                         |
|    All Books   |  | cover  Title   | | cover  Title   |                         |
|    Series      |  |  ====----  42% | |  ==------  18% |                         |
|    Recent      |  +----------------+ +----------------+                         |
|    Downloaded  |                                                                |
|  Downloads     |  All Books                          3,214 titles  [::|=] [v]   |
|                |  +------+ +------+ +------+ +------+ +------+ +------+         |
|  SHELVES       |  |      | |      | |      | |      | |      | |      |         |
|   Weekend      |  | art  | | art  | | art  | | art  | | art  | | art  |         |
|   Reading A    |  |=-----| |      | |v     | |      | |===---| |      |         |
|                |  +------+ +------+ +------+ +------+ +------+ +------+         |
|  (Mica)        |   Title    Title    Title    Title    Title    Title           |
|                |   Series   Series   Series   Series   Series   Series          |
|  [cover] Now   |                                                                |
|  playing |> 30s|   v = downloaded mark      === = progress rail                 |
|  Settings      |                                                                |
+----------------+----------------------------------------------------------------+
```

| Zone | Content |
|---|---|
| Title bar | App icon, Back, `MenuBar`, search box, caption buttons. Below 720 wide the `MenuBar` becomes one "..." `MenuFlyout` with the same items. |
| Pane | `NavigationView`, Mica visible. |
| Content | `surfaceCanvas`. Cover grid in `ItemsRepeater` with `UniformGridLayout`, virtualised. A toolbar row above it holds the title, count, a view `SelectorBar` (Grid, List) and a sort and size `DropDownButton`. |
| Detail | A page in a `Frame` in the content area. Back is in the title bar. |

Selection mode swaps the toolbar row for the selection actions, shows the count, and
keeps **Done**. Ctrl-click and Shift-click select many.

Window size: no `SizeToContent` in WinUI 3. Set the default in the constructor. Resize
takes physical pixels, so multiply by the monitor scale (`GetDpiForWindow`). Windows App
SDK 1.7 and later give `OverlappedPresenter` the properties `PreferredMinimumWidth` and
`PreferredMinimumHeight` (Known, Microsoft Learn). Set them to 480 x 360, multiplied by
the monitor scale as for `Resize` (the unit is Inferred; confirm in wave 1). No window
subclass is needed. Snap layouts and the maximize flyout work with
`TitleBar`. Keep 480 as the narrowest useful snap.

## 4. Reader windows

One `Window` per publication. The app tracks open windows by publication id and
focuses an existing one. The window position and size restore on relaunch.

```
+---------------------------------------------------------------------------------+
| Saga 042                                                          _ [] X        |
+---------------------------------------------------------------------------------+
|                                                          +--------------------+ |
|                                                          | [=] Aa [|] [flag]  | |  acrylic
|                                                          +--------------------+ |  bar
|          +----------------------+  +----------------------+                     |
|          |                      |  |                      |                     |
|          |       page 13        |  |       page 12        |   right-to-left     |
|          |                      |  |                      |                     |
|          +----------------------+  +----------------------+                     |
|                                                                                 |
|            +-----------------------------------------------------------+        |
|            | 12-13 / 32  <|====o----------------------------|>  [thumb]|        |  acrylic
|            +-----------------------------------------------------------+        |
+---------------------------------------------------------------------------------+
```

| Element | Behaviour |
|---|---|
| Title bar | Slim `TitleBar`, title only, caption buttons. Stays in windowed mode. No `MenuBar` here. The reader menu is the **Reader** items in the "..." menu of the top bar. |
| Bars | `Grid` overlays over the page. In-app `AcrylicBrush`. Fade after 3 s with an opacity animation (`chromeFade`). |
| Full screen | F11. `AppWindowPresenterKind.FullScreen`. The taskbar hides. |
| Contents | A `SplitView` pane on the trailing side. Chapters, thumbnails, bookmarks. Ctrl+T. |
| Appearance | A `Flyout` anchored to its button. Six preset cards in 3 by 2. The page updates live. |
| Curl | A D3D11 swap chain in a `SwapChainPanel`, ADR-0009 shader in HLSL. Win2D is not used (research). Fallback for a missing curl: Slide, reason stated. Reduce Motion gives Fast fade. **Spike in wave 1.** |
| Reading aloud | Windows speech synthesis. Absent when no voice exists. |
| Keep awake | `SetThreadExecutionState` while the window is visible. |

Comic: Rust core decodes. WinUI draws in the swap chain or an `Image`. PDF: PDFium in
the core (parity: `Windows.Data.Pdf` has no text layer). EPUB: WebView2 with the pinned
renderer. Egress denial is proved again on WebView2 (ADR-0015).

Player window (420 x 640): cover, chapter, `Slider` scrubber, back 15 s, play or pause,
forward 30 s, speed, sleep timer, chapter `ListView`. System media controls through
`SystemMediaTransportControls`, so the keyboard media keys and the volume flyout work.

## 5. Settings

A **page** in the main window, opened by the footer item or Ctrl+,. A reader window
has no settings. Ctrl+, from a reader focuses the library window and opens it.

- Layout: `ScrollViewer` with a clamp at 720. Rows are `SettingsCard` and
  `SettingsExpander` from the Community Toolkit.
- A search `AutoSuggestBox` sits at the top. Results show the group path.
- Groups: **Sources, Appearance, Reading, Downloads and storage, Language, Privacy,
  About.** Each group's row states its current value.
- Sources: a `ListView` with state glyph and last sync. Offline sources are dimmed.
  Remove asks in a `ContentDialog` with the verb "Remove source" and the source name.
- Appearance: System, Light, Dark, OLED Dark, Natural. Accent: StoryArc or System.
  The page also shows the Windows setting for transparency effects as a note, never as
  a control.
- About: version, licences (Rust and .NET dependencies included), What's New,
  Acknowledgements, Report a Problem.
- A `ContentDialog` is only for a blocking decision. Hints use `TeachingTip`. State
  uses `InfoBar`.

## 6. Menu bar

`MenuBar` with `MenuBarItem`s. Each `MenuFlyoutItem` carries a `KeyboardAccelerator`
so the key shows in the menu. Access keys: Alt+F, E, V, G, R, H open the menus.
Reader items are disabled in the library window and the reverse. Window and Minimize
belong to the OS.

| Menu | Command | Shortcut |
|---|---|---|
| File | Open File… | Ctrl+O |
| File | Open Recent | none |
| File | Add Source… | Ctrl+Shift+A |
| File | Refresh Sources | Ctrl+R (also F5) |
| File | Close Window | Ctrl+W |
| File | Settings… | Ctrl+, |
| File | Quit StoryArc | none (Alt+F4 closes the window) |
| Edit | Copy | Ctrl+C |
| Edit | Select All | Ctrl+A |
| Edit | Find | Ctrl+F |
| Edit | Find Next | Ctrl+G (also F3) |
| Edit | Find Previous | Ctrl+Shift+G |
| View | View as Grid | Ctrl+Shift+1 |
| View | View as List | Ctrl+Shift+2 |
| View | Larger Covers | Ctrl++ |
| View | Smaller Covers | Ctrl+− |
| View | Automatic Cover Size | Ctrl+0 |
| View | Show or Hide Sidebar | Ctrl+B |
| View | Enter or Exit Full Screen | F11 |
| Go | Back | Alt+← |
| Go | Forward | Alt+→ |
| Go | Home | Ctrl+1 |
| Go | Library | Ctrl+2 |
| Go | Downloads | Ctrl+3 |
| Go | Continue Reading | Ctrl+Shift+C |
| Go | Show Details | Ctrl+I |
| Reader | Next Page | → |
| Reader | Previous Page | ← |
| Reader | First Page | Home |
| Reader | Last Page | End |
| Reader | Go to Page… | Ctrl+L |
| Reader | Next Chapter or Issue | Ctrl+→ |
| Reader | Previous Chapter or Issue | Ctrl+← |
| Reader | Single Page | Ctrl+Shift+1 |
| Reader | Two Pages | Ctrl+Shift+2 |
| Reader | Scroll | Ctrl+Shift+3 |
| Reader | Zoom In or Larger Text | Ctrl++ |
| Reader | Zoom Out or Smaller Text | Ctrl+− |
| Reader | Fit Page | Ctrl+0 |
| Reader | Fit Width | Ctrl+9 |
| Reader | Original Size | Ctrl+Shift+0 |
| Reader | Show Contents | Ctrl+T |
| Reader | Appearance | Ctrl+Shift+T |
| Reader | Bookmark This Page | Ctrl+D |
| Reader | Show or Hide Controls | Ctrl+Shift+H |
| Reader | Read Aloud | Ctrl+Shift+L |
| Reader | Play or Pause | Space |
| Reader | Skip Back 15 s | ← |
| Reader | Skip Forward 30 s | → |
| Help | Keyboard Shortcuts | Ctrl+? |
| Help | What's New… | none |
| Help | Acknowledgements… | none |
| Help | Report a Problem… | none |

The Jump List has a **Keep reading** task (named), **Library**, **Downloads** and the
shell Recent category. `ICustomDestinationList` builds it. `SHAddToRecentDocs` feeds Recent.

## 7. Context menus

`MenuFlyout` on right-click and on the Menu key or Shift+F10.

| Object | Items |
|---|---|
| Cover or row | Read, Show Details, separator, Add to Shelf (sub-menu), Mark as Read or Unread, Download or Remove Download, separator, Show in File Explorer (local files only), Copy Title |
| Several covers | Add to Shelf, Mark as Read, Mark as Unread, Download, Remove Download |
| Shelf in the pane | Rename, Pin or Unpin, Delete Shelf (confirms, says the books stay) |
| Source row | Refresh, Reconnect, Edit, Remove Source |
| Comic or PDF page | Bookmark This Page, Copy Image, Fit Page, Fit Width, Reading Direction |
| EPUB text selection | Copy, Search in Book, Highlight |
| Player chapter | Play from Here |

## 8. Drag and drop

`AllowDrop` with `DragOver` and `Drop` reading `StorageItems`.

| Drag | Drop on | Result |
|---|---|---|
| Files (CBZ, CBR, CBT, EPUB, PDF) | Library window or taskbar icon | Opens each in a reader window. Reads in place. |
| A folder | Library window | `ContentDialog`: **Add as Source**. |
| A cover | A shelf in the pane | Adds to the shelf. |
| A row in a reading list | Another row | Reorders. |
| A cover | File Explorer | Copies the file when it is local. |

File associations come from the package manifest. Open With and double-click start
the app with the path as an activation argument. A running instance receives it and
opens a reader window (single-instance redirection).

## 9. Empty and offline states

Use the README table. Windows specifics: the status page is a centred `StackPanel`
with an icon, one sentence and one `AccentButtonStyle` button. The offline banner is an
`InfoBar` with `Severity="Informational"`, grey, not dismissible while offline, never
`Error`. A source that needs sign-in shows an `InfoBar` row with a **Reconnect** button.
SMB 1 hosts get a named remedy line (research).

## 10. Accessibility

| Check | Rule |
|---|---|
| Narrator and NVDA | Every control has `AutomationProperties.Name`. A cover cell name: "Title, series, issue 4, 62 percent read, downloaded". Each turn calls `RaiseNotificationEvent`: "Page 12 of 32". |
| Landmarks | Pane, content, bars carry landmark types. Headings use `HeadingLevel`. |
| Focus order | `TitleBar`, pane, toolbar row, content, trailing panel. Reader: page, top bar, bottom bar. Tab into a hidden bar reveals it. |
| Keyboard | Access keys on menus. XY focus works in the grid. Focus visuals stay on. |
| High Contrast | The token dictionary has a High Contrast branch that holds system colour brushes only. The covers keep their art. Status uses glyph plus text. |
| Transparency | When transparency effects are off, Mica becomes solid and `AcrylicBrush.FallbackColor` is `surfaceOverlay`. Borders use `borderStrong`. |
| Reduce Motion | Read `UISettings.AnimationsEnabled`. Off gives a fast fade. |
| Text size | Windows text scaling applies to all XAML text. At the largest size, the library is a list. EPUB has its own size control. |
| Scale | Test at 100, 150 and 200 percent. Covers stay sharp (`RasterizationScale`). |
| Pointer and touch | 32 epx toolbar targets. 40 epx on touch devices. |

## 11. Materials and tokens

| Surface | Material | Token |
|---|---|---|
| Title bar, pane | `MicaBackdrop` (Windows 11 build 22000 and newer) | None |
| Library content | Opaque brush, theme dictionary | `surfaceCanvas` |
| Cover letterbox | Opaque brush | `surfaceSunken` |
| Cards, list rows | Opaque brush | `surfaceRaised` |
| Reader window | Opaque brush, no backdrop | `surfaceReader` |
| Reader bars, flyout over the page | In-app `AcrylicBrush`, tint opacity 0 | Fallback `surfaceOverlay` |
| System flyouts, menus, dialogs | System | None |
| Text on token surfaces | Brush keys from the dictionary | `textPrimary`, `textSecondary`, `textTertiary` |
| Accent | `SystemAccentColor` override with its light and dark shades | `brand/accent` |
| Status | Glyph plus label plus brush | `status/*` |
| Radius | `CornerRadius` | `cover` 4, `sm` 6, `md` 10. Controls keep Fluent's 4 and 8. |
| Type | `ui` = Segoe UI Variable. `editorial` = Source Serif 4, bundled (OFL, already in the licence list). `mono` = Cascadia Mono. | Typography tokens |
| Motion | Composition animations with token durations and `standard` easing | Motion tokens |

Rules from `winui-design`: no colour literals in XAML, only `ThemeResource` keys. Token
brushes are generated into `ThemeDictionaries` for `Light`, `Dark` and `HighContrast`
from `packages/design-tokens`. Natural and OLED Dark are further dictionaries. No
custom `ControlTemplate` where a built-in control and a style fit.

## 12. Windows-only integration

- Packaged MSIX with file type associations, signed by the Store (research).
- System media controls and media keys through `SystemMediaTransportControls`.
- Credentials in Credential Manager. No secret in a file.
- Metered link: `NetworkCostType` replaces the cellular rule.
- Thumbnails of covers in File Explorer: later, needs a native shim (parity item 11).
- No tray icon, no toast for a refresh (README).

## 13. Review checklist

- [ ] `winui-design` consulted; `winapp find-ui` run before each new control.
- [ ] No colour literal. Light, Dark and High Contrast dictionaries present.
- [ ] Mica only on title bar and pane. Content and reader are opaque tokens.
- [ ] Every command in the `MenuBar` with a visible accelerator.
- [ ] Narrator and NVDA pass through library, detail, reader, player.
- [ ] Capture at 100 and 200 percent, light, dark, High Contrast, transparency off.
