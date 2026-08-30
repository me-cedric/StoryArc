# Slice K2 — Android tablets and the five breakpoints

Captured on a booted emulator (`storyarc-api36`, API 36), from the debug APK built at the
commit these shots are committed with. The window width was varied with `wm density` on a
2400 x 1080 panel rather than with several AVDs, because the only thing the layout reads is
the width of the window.

| Shot | Window | What it shows |
| --- | --- | --- |
| `android-compact-library-bar.png` | 360 x 800 dp | `ShortNavigationBar`, and Shelves and Settings back in the library's own top bar. |
| `android-compact-reader-strip.png` | 360 x 800 dp | The page browser as the strip over the foot of the page. Captured by rotating out of the shot below without leaving the reader — the same reader, reflowed. |
| `android-medium-library-bar.png` | 800 x 360 dp | The window that used to lose both toolbar entries: a bar, and both entries present. |
| `android-large-library-rail-collapsed.png` | 1280 x 576 dp | `WideNavigationRail`, collapsed: the three destinations `navigation-shell` fixes. |
| `android-large-library-rail-open.png` | 1280 x 576 dp | The same rail opened from its menu button, revealing Shelves and Settings. |
| `android-large-library-rail-open-dark.png` | 1280 x 576 dp | The same, dark. |
| `android-large-library-largest-text.png` | 1280 x 576 dp | The same, at the largest system text size. Nothing clips. |
| `android-large-reader-supporting-pane.png` | 1280 x 576 dp | `SupportingPaneScaffold`: every page beside the artwork instead of over it, with the reading controls inside the reading pane. |
| `android-large-list-detail-panes.png` | 1280 x 576 dp | `ListDetailPaneScaffold`: the shelf and a publication page at once. |
| `android-large-list-detail-back.png` | 1280 x 576 dp | Back from the shot above — the page popped off the path, so the pane closed and the shelf took the width. One back rule. |

**The two list-detail shots were taken from a build carrying one extra line**, replacing the
library grid's `onOpen` so that a cover led to the publication page rather than straight to
the reader. Nothing in `main` navigates to `Screen.PublicationPage` yet — the wiring is the
library slice's — so without that line the two-pane layout is correct code with no way in.
The line is not in any commit; the pane code in the shots is exactly the pane code that
ships.
