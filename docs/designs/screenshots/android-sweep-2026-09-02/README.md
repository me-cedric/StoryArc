# Android sweep — 2026-09-02

A complete visual inventory of the Android app as it stands, for design review. Not a
before/after: nothing in this folder argues for a change. It is the app, photographed
everywhere it goes.

**236 PNGs.** Every destination, every menu, sheet and dialog either of them opens, both
readers and everything inside them, the player, all seven settings groups, the empty and
failure states, three window widths, both appearances, the largest text size on every
dense surface, and Material You both on and off.

---

## How to read a filename

```
android-<surface>-<state>[-scale2][-dark][-nodynamic].png
```

| Token | Means |
| --- | --- |
| *(none)* | Phone, 411 × 914 dp, light, system text size, **Material You on** |
| `-dark` | The same surface with the system in dark mode |
| `-scale2` | `font_scale 2.0` — the largest text size the system offers |
| `-nodynamic` | **Material You off**, so StoryArc's own palette is drawn |
| `android-compact-*` | 360 × 800 dp |
| `android-medium-*` | 800 × 360 dp |
| `android-large-*` | 1280 × 576 dp |

**Dynamic colour: every file without `-nodynamic` has it ON**, because that is the app's
default — Appearance says so in as many words ("On by default"). The emulator's wallpaper
gives a lavender-purple scheme, and that purple is the wallpaper, not the brand. The 25
`-nodynamic` files are the same surfaces with the switch off, which is the only way to see
the brand palette. §4 of *What the pictures show* is about the difference, and it is not
what you would expect.

## How they were taken

Emulator `storyarc-j6` (API 36, 1080 × 2400, 420 dpi), started with `-gpu host`. Every
frame came from `pnpm capture:android <route>`, which walks to a named route in
`scripts/android-routes.mjs`, sets the appearance and the text size, waits until the screen
has actually drawn, photographs, and puts the device back. The route table went from 18
routes to 73 for this sweep; a route is repeatable, and the coordinates a person would use
by hand are not.

**The build in these pictures is the build that was made for them.** The debug APK was
built at `56db4aed`, and its SHA-256 was compared against the installed `base.apk` on the
device before the first frame and after the last:

```
a2ed12fe0c1b3e312bcb3b7e34dc50645678acbe37fd2e8c542894e280e4ff77
```

Byte-identical both times, `lastUpdateTime` unchanged throughout. No other agent's build
landed over it mid-sweep.

## What was on the device

Three data conditions. Each group below says which one it belongs to.

| Condition | The shelf held | Which files |
| --- | --- | --- |
| **A — the corpus** | The 17 publications `scripts/corpus.mjs` generates, in the app's own external files directory. They carry `origin: EMBEDDED` and **belong to no source**, which is why Settings › Your libraries is legitimately empty in condition A and why the filter menu offers no "Which library" section. Two of them cannot be opened, which is the failure notice you see on every Library frame. | Everything not named below |
| **B — one folder source** | `/sdcard/Audiobooks` added through the system picker. See §1: adding it emptied the shelf. | `android-library-one-source*`, `android-library-empty-on-device*`, `android-settings-sources-one*`, `android-settings-source-detail*`, `android-settings-source-remove-dialog`, `android-home-one-source`, `android-search-one-source`, `android-downloads-empty*` |
| **C — nothing at all** | `pm clear`, so a genuine first launch | `*-first-run*`, `android-search-nothing-to-suggest*`, `android-search-add-source-menu`, `android-settings-sources-empty`, `android-settings-downloads-empty` |
| **A + one audiobook** | Condition A with `sea-room.m4b` copied in, because nothing else in the corpus reaches the player | `android-player-*`, `android-audiobook-page*` |

---

# The index

## Home

| Surface | File | State |
| --- | --- | --- |
| Home | `android-home-default.png` · `-dark` · `-nodynamic` · `-nodynamic-dark` | Populated shelf. **Only "Recently added" renders** — see §2 |
| Home, first launch | `android-home-first-run.png` · `-dark` · `-scale2` | `HomeFirstRun`: "Nothing here yet", Open a comic, Add a folder |
| Home, one source | `android-home-one-source.png` | Condition B |
| Home, compact | `android-compact-home.png` | 360 × 800 dp |
| Home, medium | `android-medium-home.png` | 800 × 360 dp |
| Home, large | `android-large-home.png` | 1280 × 576 dp, wide rail |

## Library — the shelf

| Surface | File | State |
| --- | --- | --- |
| Cover grid | `android-library-grid.png` · `-dark` · `-scale2` · `-scale2-dark` · `-nodynamic` · `-nodynamic-dark` | Default: narrowed to *On this device*, sorted by Title |
| Compact list | `android-library-list.png` · `-dark` | Layout toggled to list |
| Widened | `android-library-everywhere.png` · `-dark` | *On this device* chip turned off |
| Nothing matches | `android-library-nothing-matches.png` · `-dark` | Filtered to *Not downloaded*, which nothing in the corpus is |
| Nothing readable offline | `android-library-empty-on-device.png` · `-dark` | Condition B — `library_empty_on_device` |
| First launch | `android-library-first-run.png` · `-dark` | `EmptyLibrary` |
| First launch, add menu | `android-library-first-run-add-menu.png` | The five source kinds from the empty state |
| Failure notice → its list | `android-library-skipped-list.png` · `-dark` | The sheet behind "What couldn't be opened" |
| One source only | `android-library-one-source.png` · `-dark` | Condition B — see §1 |
| Compact / medium / large | `android-compact-library.png` · `android-medium-library.png` · `-dark` · `android-large-library-rail.png` · `-dark` · `-scale2` | Short bar, bar, expanded rail |

## Library — the chip row and its menus

| Surface | File | State |
| --- | --- | --- |
| Sort menu | `android-library-sort-menu.png` · `-dark` · `-scale2` · `-nodynamic` | Seven orderings, then Ascending/Descending |
| Filter menu, level 1 | `android-library-filter-menu.png` · `-dark` · `-scale2` · `-nodynamic` | Sections offered by this data |
| Filter menu, level 2 | `android-library-filter-values.png` · `-dark` | *Read or unread* opened |
| Filter applied | `android-library-filter-active.png` · `-dark` | *In progress* ticked, menu closed |
| Overflow | `android-library-overflow-menu.png` · `-dark` · `-scale2` | Select · Shelves · Settings |
| Add a source | `android-library-add-source-menu.png` · `-dark` · `-scale2` | The five kinds |

## Library — selection mode

**Superseded on 2026-09-03 — these seven are the *before*.** They photograph the full-bleed
bottom slab, and `named-failures-and-quieter-chrome` §3b replaced it with a contextual
`TopAppBar`: close at the start, the plural count as the title, download and mark-as-read as
actions, *Add to…* named in words in the overflow, and the navigation bar left alone for the
whole mode. `BulkActionBar.kt` is deleted. So the "four actions, Done" row below describes a
bar that no longer exists — kept as the before, not as an inventory of the shipped app, and
labelled because this table said "Current" for a day after it stopped being true.

| Surface | File | State |
| --- | --- | --- |
| Nothing selected | `android-library-selection-none.png` · `-dark` · `-scale2` | The bar as selection mode opens |
| Two selected | `android-library-selection-two.png` · `-dark` · `-nodynamic` · `-nodynamic-dark` | "2 selected", four actions, Done |
| Add to a shelf | `android-library-add-to-shelf.png` · `-dark` · `-nodynamic` | Long-press sheet on one cover |

## Shelves

| Surface | File | State |
| --- | --- | --- |
| Shelves | `android-shelves.png` · `-dark` · `-scale2` · `-nodynamic` | Collections and reading lists, both empty |
| New menu | `android-shelves-new-menu.png` · `-dark` | New collection / New reading list |
| Create dialog | `android-shelves-create-dialog.png` · `-dark` | Name field, "Stored on this device" |

## Publication page

| Surface | File | State |
| --- | --- | --- |
| With a cover | `android-publication-cover.png` · `-dark` · `-scale2` · `-nodynamic` · `-nodynamic-dark` | CBZ, part-read, *Continue* |
| PDF | `android-publication-pdf.png` · `-dark` | A cover rendered from page one |
| In a series | `android-publication-series.png` · `-dark` | `Tidal Reach #2`, with the series shelf |
| Overflow | `android-publication-overflow.png` · `-dark` · `-scale2` | Add to a shelf, Mark as read, … |
| Add to a shelf | `android-publication-add-to-shelf.png` · `-dark` · `-scale2` | From the overflow |
| Audiobook | `android-audiobook-page.png` · `-dark` | `sea-room.m4b` |
| Medium | `android-medium-publication.png` | 800 × 360 dp — **see §5** |
| Large, two panes | `android-large-list-detail.png` | `ListDetailPaneScaffold` |

## Comic reader

| Surface | File | State |
| --- | --- | --- |
| Page | `android-comic-page.png` · `-dark` | Chrome already auto-hidden |
| Chrome | `android-comic-chrome.png` · `-dark` | Revealed by a centre tap, photographed inside its 4 s life |
| Menu sheet | `android-comic-menu.png` · `-dark` · `-scale2` · `-scale2-dark` · `-nodynamic` · `-nodynamic-dark` | Contents, page slider, Appearance, Settings |
| Page strip | `android-comic-pages.png` · `-dark` | Contents row opened |
| Adjustments | `android-comic-adjustments.png` · `-dark` · `-scale2` | Brightness, contrast, greyscale, invert, trim |
| End of publication | `android-comic-end.png` · `-dark` | Turned past the last page |
| A page it cannot decode | `android-comic-bad-page.png` · `-dark` | `Foreign Codec`, every page in an unsupported codec |
| Large, supporting pane | `android-large-comic-supporting-pane.png` | Pages beside the page rather than over it |

## EPUB reader

Reflowable EPUB (`Harbour Lights 01`). **The EPUB reader opens with its chrome up and
keeps it**, which is the opposite of the comic reader — so `-chrome` here is the plain
arrival and `-page` is the one that needed a tap to clear it.

| Surface | File | State |
| --- | --- | --- |
| Chrome | `android-epub-chrome.png` · `-dark` | As the book opens |
| Page | `android-epub-page.png` · `-dark` | Chrome dismissed |
| Menu sheet | `android-epub-menu.png` · `-dark` · `-scale2` | Contents, bookmarks, search, notes, themes |
| Theme sheet, presets | `android-epub-themes.png` · `-dark` · `-scale2` · `-nodynamic` | First detent |
| Theme sheet, expanded | `android-epub-themes-expanded.png` · `-dark` | Dragged to the second detent |
| Theme axes | `android-epub-axes.png` · `-dark` · `-scale2` · `-scale2-dark` · `-nodynamic` | The full-screen customise level |
| Contents | `android-epub-contents.png` · `-dark` | Table of contents tab |
| Bookmarks | `android-epub-bookmarks.png` · `-dark` | Empty state |
| Search in book | `android-epub-search.png` · `-dark` | Field at rest |
| Search, mid-query | `android-epub-search-typed.png` · `-dark` | "the" typed |
| Notes | `android-epub-notes.png` · `-dark` | Empty state |

## Search

| Surface | File | State |
| --- | --- | --- |
| At rest | `android-search-rest.png` · `-dark` · `-scale2` · `-nodynamic` · `-nodynamic-dark` | Scope chips plus the suggestion shelves |
| Expanded | `android-search-expanded.png` · `-dark` | Field focused |
| Mid-query | `android-search-mid-query.png` · `-dark` · `-scale2` | "harb" |
| No results | `android-search-no-results.png` · `-dark` | "zzzqqq" |
| Scoped to this device | `android-search-on-device.png` · `-dark` | *On this device* chip |
| Nothing to suggest | `android-search-nothing-to-suggest.png` · `-dark` | Condition C |
| Add a source | `android-search-add-source-menu.png` | Condition C — only offered from the empty state |
| One source | `android-search-one-source.png` | Condition B |
| Large | `android-large-search.png` | Docked bar beside the rail |

## Downloads

| Surface | File | State |
| --- | --- | --- |
| On this device | `android-downloads-queue.png` · `-dark` · `-scale2` · `-nodynamic` · `-nodynamic-dark` | The whole corpus, no transfers in flight |
| Empty | `android-downloads-empty.png` · `-dark` · `android-downloads-first-run.png` | `EmptyDestination` + "Go to your library" |
| Large | `android-large-downloads.png` | 1280 × 576 dp |

## Player

Android's player is a **destination, not a sheet** — a deliberate divergence from Apple,
recorded in `named-failures-and-quieter-chrome` §3.3. It is not a defect.

| Surface | File | State |
| --- | --- | --- |
| Player | `android-player-full.png` · `-dark` · `-scale2` | **See §3 — it says "Nothing is playing"** |
| Scrolled | `android-player-chapters.png` · `-dark` | Same screen |
| Compact bar | `android-player-compact-bar.png` · `-dark` | Home after starting playback — **no bar** |
| The session, meanwhile | `android-player-session-playing.png` | The system media control, playing, at the same moment |

## Settings

| Surface | File | State |
| --- | --- | --- |
| Root | `android-settings-root.png` · `-dark` · `-scale2` · `-nodynamic` · `-nodynamic-dark` | Seven groups, search field, Reset |
| Root, first launch | `android-settings-root-first-run.png` | Condition C summaries |
| Search results | `android-settings-search-results.png` · `-dark` | "icon" — anchor rows |
| Search, no match | `android-settings-search-empty.png` · `-dark` | "zzzqqq" |
| Reset dialog | `android-settings-reset-dialog.png` · `-dark` · `-scale2` | |
| Appearance | `android-settings-appearance.png` · `-dark` · `-scale2` · `-scale2-dark` · `-nodynamic` · `-nodynamic-dark` | Four appearances, Natural, Material You, link theme |
| App-icon chooser | `android-settings-app-icon.png` · `-dark` · `-scale2` · `-nodynamic` | Five faces, scrolled to |
| Reading | `android-settings-reading.png` · `-dark` | Volume buttons |
| Reading defaults | `android-settings-reading-defaults.png` · `-dark` · `-scale2` | Presets per scope, comic matte swatches |
| Privacy | `android-settings-privacy.png` · `-dark` | Statements and the three clearables |
| Privacy, diagnostic open | `android-settings-privacy-diagnostic.png` · `-dark` | The report expanded |
| Privacy, clear history | `android-settings-privacy-clear-history.png` · `-dark` | Confirmation dialog |
| Downloads and storage | `android-settings-downloads.png` · `-dark` · `-scale2` | Wi-Fi only, remove after finishing, limit chips |
| Downloads, empty | `android-settings-downloads-empty.png` | Condition C |
| Language | `android-settings-language.png` · `-dark` | System + four languages |
| About | `android-settings-about.png` · `-dark` | Version, links |
| About, acknowledgements | `android-settings-about-acknowledgements.png` · `-dark` | Scrolled |
| A licence in full | `android-settings-about-licence.png` · `-dark` | Readium Kotlin Toolkit |
| What's new | `android-settings-whats-new.png` · `-dark` · `-scale2` | Reached from About |
| Your libraries, none | `android-settings-sources.png` · `-dark` · `android-settings-sources-empty.png` | Conditions A and C |
| Your libraries, one | `android-settings-sources-one.png` · `-dark` | Condition B |
| A source's detail | `android-settings-source-detail.png` · `-dark` | Status, counts, six actions |
| Removing a source | `android-settings-source-remove-dialog.png` | Confirmation |
| Medium / large | `android-medium-settings.png` · `android-large-settings.png` | |

---

# What the pictures show

Nine things a reviewer should not have to find for themselves. **Nothing here was fixed** —
this sweep changed no app code.

### §1 Adding a folder source empties the shelf

`android-library-grid.png` → `android-library-one-source.png`.

Before: 17 publications. After adding `/sdcard/Audiobooks` through Add books › Add a folder:
one. The cached index was rewritten to hold only the new source's contents; every
publication with `origin: EMBEDDED` disappeared from the shelf, from Home
(`android-home-one-source.png`) and from Search (`android-search-one-source.png`). Removing
the source brought all 17 back, so nothing was destroyed — but a reader who adds a second
library loses the first until they undo it.

The same frames show two smaller things: the audiobook's title renders as the raw
document-tree id **`primary:Audiobooks`** (`android-settings-source-detail.png` puts it in
the top bar), and a folder of audio is presented as one publication rather than the book
inside it.

### §2 Home has one shelf out of five

`android-home-default.png`.

`HomeScreen` can draw a *Keep reading* hero, *Up next*, *Recently added* and *Finished*.
Only Recently added appears — yet the cells in it carry the accessibility labels
"Salt and Iron. Part-read", "Bright Panels. Part-read" and "Broken Transfer. 2 pages left",
so the app knows three publications are in progress. Two-thirds of the destination is empty
cream, and it is the first screen the app opens on.

### §3 The player says "Nothing is playing" while it is playing

`android-player-full.png` beside `android-player-session-playing.png`, taken seconds apart.

Opening the audiobook pushes the player destination, which renders `PlayerFinishedScreen`:
"Nothing is playing." and a *Go back* link. At that same moment the system media control
shows **sea-room — Adam Nicolson**, playing, with StoryArc's own *Back 15 seconds* and
*Forward 30 seconds* actions, and `dumpsys media_session` reports `state=PLAYING(3)` with
the position advancing, owned by the app's own process. The compact bar does not appear on
Home either (`android-player-compact-bar.png`). Audio works; the playback UI does not
observe it.

Consequence for this sweep: the full player, its chapter list, the speed slider and the
sleep timer **have no picture in this folder**, because the screen that holds them never
rendered.

### §4 Turning Material You off changes less than it should

`android-library-selection-two.png` (on) beside `android-library-selection-two-nodynamic.png`
(off).

With the switch off the navigation bar does move to the brand — a deep indigo pill under a
crimson label. But the `+` and `⋮` in the top bar, the *What couldn't be opened* and
*Dismiss* text buttons, the selection ticks, the three bulk-action icons and *Done* are the
**same purple in both frames**. They read as Material's baseline rather than either scheme.
Worth checking against `android-accent-2026-09-01/`, which addressed four controls in this
area — these are not the same four.

The nav bar itself is also worth a look: an indigo pill with a crimson label is two brand
colours on one item, and that label is the only coloured one in the row.

### §5 The publication page is unusable at 800 × 360 dp

`android-medium-publication.png`.

Half the height is the top bar. Below it the cover is a full-bleed slab clipped after about
a third of its height, and **the primary action is not on screen and cannot be scrolled
to** — six scroll attempts moved nothing, and the accessibility tree at that width holds
only Back, More actions and the title. There is no way to open a book from its own page in
that window. The comic-reader route could not be walked at this width for the same reason,
which is why `android-medium-comic-chrome.png` is missing.

### §6 The reader chrome sits on the text with nothing behind it

`android-epub-page.png` — the chrome pill in `android-epub-chrome.png` is a translucent
lavender lozenge laid directly over running body text, with sentences visible through and
around it and no scrim, gap or elevation. In the comic reader the same pill sits over
artwork against a black field and reads correctly (`android-comic-chrome.png`). The
difference is only that a book has text where a comic has a margin.

### §7 The page slider's handle is detached from its track

`android-comic-menu.png`, `android-epub-menu.png`. The slider under *Contents* draws its
thumb as a tall vertical bar at the far left, outside and above the rounded track that
starts about 17 px to its right. It reads as a rendering fault rather than a control.

The same sheet uses three different left insets in four consecutive rows — the Contents and
Appearance icons at one, the *Settings* section header at another, *Page turn* at a third.

### §8 The one-column grid in a 380 dp pane

`android-large-list-detail.png`. The two-pane layout is correct and the rail expands
properly, but the list pane draws the cover grid one cover per row across its full width,
leaving most of it empty. The detail pane beside it draws the cover as a small rectangle
centred in a much larger tinted well.

### §9 Small things worth a glance

- **The failure notice is body copy.** "2 couldn't be opened" with two bare text buttons
  under it, no container, no tonal surface, no icon — on every Library frame in condition A.
- **The layout toggle is orphaned.** It sits alone on its own row under the chip row, left
  aligned, one icon in a full-width band. `android-library-grid.png`.
- **The subtitle repeats the title** on `android-publication-cover.png` and
  `android-medium-publication.png` ("Broken Transfer" over "Broken Transfer"). The corpus
  gives that publication a series equal to its title, so this is partly the fixture — but
  the page draws the repetition rather than suppressing it.
- **A source that is a local folder reports "Connecting", forever**, and "Last updated:
  Never" after it has scanned. `android-settings-source-detail.png`.
- **The theme sheet's preview card is half the sheet** and shows the same paragraph as the
  page behind it, clipped mid-line with no fade; only three of the six theme cards fit, and
  the middle one's label runs under the gesture bar. `android-epub-themes.png`.
- **Status-bar icons are near-invisible in the EPUB reader** — light icons on the cream
  page. `android-epub-page.png`.

---

# What is not covered, and why

| Not here | Why |
| --- | --- |
| **The full player, chapter list, speed control, sleep timer** | §3. The screen renders its empty state while audio plays, so those controls never drew. |
| The comic reader at 800 × 360 dp | §5. The publication page offers no way into the reader at that width. |
| The EPUB reader at 1280 × 576 dp | The route could not find the book in the list pane at that width; not investigated further. |
| Downloads: remove-download dialog, undo bar | Both hang off a long-press menu that only appears for a publication with a *download record*. Everything in the corpus is a local file that was never downloaded, so the menu never opens. Needs an OPDS or Kavita source. |
| Every OPDS, Kavita and SMB surface | The add-source sheets, their sign-in, certificate-warning and failure states, the three source browsers, the reconnect sheet, facets, acquisition banners, metered-data dialogs, sync-conflict dialog. All need a live server or share; `scripts/opds-server.mjs` and `scripts/kavita-server.mjs` exist and would make this reachable in a follow-up. |
| Selection mode with two selected at `font_scale 2.0` | The walk could not reach the second cover at that text size. `android-library-selection-none-scale2.png` covers the bar itself; `android-library-selection-two.png` covers two-selected at default size. |
| PDF text selection, highlights, notes, in-PDF search | Reached by pressing and holding a word in a text PDF — a gesture the route table does not have. |
| EPUB text selection, the selection menu, the note dialog, read-aloud | Same reason, plus TTS. |
| The what's-new sheet as it appears on its own | It is shown once after an *update*, never on a first launch. `android-settings-whats-new.png` is the same content reached from About. |
| Shelf detail screens, the cover picker, the promote-to-server sheet | No collection or reading list exists to open. Creating one is one dialog away — `android-shelves-create-dialog.png`. |
| Search's add-source menu in dark | It only exists in the empty-library state, and the device had been refilled before the dark pass. The light one is here. |
| Every screen in German, Spanish or French | Out of scope for this sweep. The route table resolves its step names from all four languages, so a localised pass costs only the device's language setting. |
| The five launcher icons | Already photographed, in `app-icon-chooser-2026-09-01/`. |
