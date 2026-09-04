# iOS, photographed end to end — 2026-09-02

A complete visual inventory of the iOS app as it stands: every destination, every menu and
sheet opened, both readers with everything behind their menus, the player's sheets, all seven
settings groups, and the four forms a library is added through. Light and dark for each, and
the largest accessibility text size for every surface that is dense or has a control row.

It exists to be read by someone who has never seen the code. Every row below says what the
file is a picture of and what state the app was in; the last two sections say what is **not**
here, and what looked wrong to the person taking it.

244 frames, covering 130 surfaces: an iPhone 17 Pro in light and dark, an iPad Pro 11-inch in
landscape, and a simulator created bare for the first-run states a development device can
never show.

## How to read a filename

```
ios-<surface>-<state>[-ax5][-dark].png
```

`-ax5` is `UICTContentSizeCategoryAccessibilityXXXL`, the largest Dynamic Type size iOS
offers. `-dark` is the dark appearance. No suffix means the default text size and the light
appearance.

**The tables below name the light frame only.** Every row has a `-dark` twin under the same
name unless this file says otherwise, so a table of two hundred rows is a table of a hundred
saying the same thing twice. Where a dark frame is missing, the last section says so.

## How these were taken, and why that matters

Every frame is a real UI-test walk on a booted simulator — `StoryArc-iPhone17Pro`, iPhone 17
Pro, iOS 26.5 — driven by `scripts/capture-ios.mjs`. Nothing here is a `#Preview`, a mockup,
or a hand-driven screenshot.

Two things about the method are worth knowing before you trust a filename:

**The appearance is set by the launch, not by the device.** The simulator carried
`appearance: "oledDark"` in the app's own stored settings, so `--appearance light` set the
*device* to light and the app drew true black over it. Every walk in `Sweep*.swift` now passes
`appearance: system` as a launch argument, which is what makes the harness's flag
authoritative. See `apps/ios/UITests/SweepWalk.swift`.

**Every shelf choice is pinned by the launch too.** The layout, the availability axis, the
download filter, the sort and the query all persist between launches, because
`library-browsing` requires them to. So a walk that chose *List* left the next walk in a list:
the first run of this sweep produced a `library-grid` frame that is a picture of a list. Every
key is now stated on every launch.

**Pinning has one cost, and it is worth knowing before reading a frame.** The availability
axis and the download filter are `@AppStorage`, read through `UserDefaults` on every access —
and the argument domain outranks the standard one, which is what makes the pinning work. A
walk that then *taps* one of those pickers writes to the standard domain and reads the launch
argument straight back, so the choice appears never to take. It looked like two defects before
it was understood, so: those two frames are launched into their state rather than tapped into
it, and no frame here proves that either picker works. `LibraryToolbarTests` proves that on
the host side. Everything else — the layout, the sort, the query, the filters — is a stored
property on the model, changes in memory, and is tapped for real.

## Home

| Surface | File | State |
| --- | --- | --- |
| Home, top | `ios-home-top.png` | The hero and the first section under it |
| Home, top | `ios-home-top-ax5.png` | Largest text size |
| Home, lower | `ios-home-lower.png` | Scrolled past the hero to the rows |
| Home, end | `ios-home-end.png` | Scrolled to the foot, where the tab bar's inset is decided |
| See-all grid | `ios-home-see-all.png` | *Recently added* opened as a screen of its own |
| Shelves | `ios-shelves.png` | Collections and reading lists, both empty |
| Shelves | `ios-shelves-ax5.png` | Largest text size |
| New collection | `ios-shelves-new-collection.png` | The naming sheet |

## Library

| Surface | File | State |
| --- | --- | --- |
| Cover grid | `ios-library-grid.png` | Default layout, no filter, sorted by title |
| Compact list | `ios-library-list.png` | Chosen through the View menu |
| Compact list | `ios-library-list-ax5.png` | Largest text size |
| View menu | `ios-library-view-menu.png` | Open: availability, layout, sort, direction |
| View menu | `ios-library-view-menu-ax5.png` | Open, largest text size |
| Filter menu | `ios-library-filter-menu.png` | Open, nothing set — no *Clear filters* row |
| Filter menu | `ios-library-filter-menu-ax5.png` | Open, largest text size |
| Filtered shelf | `ios-library-filtered.png` | One filter set (unread); the control states it |
| Filter menu | `ios-library-filter-menu-active.png` | Re-opened over that filter |
| Narrowed to nothing | `ios-library-narrowed-to-nothing.png` | Two filters that cannot both hold |
| On this device | `ios-library-on-this-device.png` | The availability axis narrowed |
| Add books | `ios-library-add-books.png` | The menu open: five ways in |
| Add books | `ios-library-add-books-ax5.png` | Open, largest text size |

## Search

| Surface | File | State |
| --- | --- | --- |
| At rest | `ios-search-at-rest.png` | Scope, recent searches, three suggestion shelves |
| At rest | `ios-search-at-rest-ax5.png` | Largest text size |
| At rest, narrowed | `ios-search-at-rest-on-this-device.png` | The scope set to this device |
| Mid-query | `ios-search-results.png` | `harbour` — results grouped by match kind |
| Mid-query | `ios-search-results-ax5.png` | Largest text size |
| No results | `ios-search-no-results.png` | `vermillion`, with two silent servers beside it |
| Scoped to this device | `ios-search-on-this-device.png` | The same term, nothing waited for |

## Downloads

| Surface | File | State |
| --- | --- | --- |
| The readable shelf | `ios-downloads-shelf.png` | Nothing in flight |
| The readable shelf | `ios-downloads-shelf-ax5.png` | Largest text size |
| Transfer queue | `ios-downloads-queue.png` | One part-way, one waiting, one failed |
| Transfer queue | `ios-downloads-queue-ax5.png` | Largest text size — the two-line row |
| Stop confirmation | `ios-downloads-stop-confirm.png` | Naming the title and what it frees |
| With a session running | `ios-downloads-with-player.png` | The docked transport over shelf and queue |

## Publication detail

| Surface | File | State |
| --- | --- | --- |
| With a cover | `ios-detail-with-cover.png` | Real artwork in the hero |
| With a cover | `ios-detail-with-cover-ax5.png` | Largest text size |
| Without a cover | `ios-detail-no-cover.png` | The coverless well as the hero |
| In a series | `ios-detail-series-shelf.png` | Scrolled to *Other issues in this series* |
| Bare | `ios-detail-bare.png` | No series, no description, no other issue |
| An audiobook | `ios-detail-audiobook.png` | The primary action reads *Listen* |
| Overflow menu | `ios-detail-more-actions.png` | Everything that is not *open it* |

## The comic reader

| Surface | File | State |
| --- | --- | --- |
| The page | `ios-comic-reader-page.png` | Six seconds in, chrome faded out |
| Chrome, on arrival | `ios-comic-reader-chrome.png` | The two controls the reader draws itself |
| Chrome, revealed | `ios-comic-reader-chrome-revealed.png` | Brought back by a centre tap after the countdown |
| Menu | `ios-comic-reader-menu.png` | The medium detent, page visible behind |
| Menu | `ios-comic-reader-menu-ax5.png` | Largest text size |
| Menu, expanded | `ios-comic-reader-menu-expanded.png` | The large detent |
| Transition picker | `ios-comic-reader-transition-picker.png` | With the reasons under refused modes |
| Thumbnails | `ios-comic-reader-thumbnails.png` | Every page, current one marked |
| Image adjustments | `ios-comic-reader-adjustments.png` | The one surface that changes the artwork |
| PDF *Find* | `ios-pdf-find-sheet.png` | A reader surface only a PDF has |

## The EPUB reader

| Surface | File | State |
| --- | --- | --- |
| The page | `ios-epub-reader-page.png` | Chrome faded out |
| Menu | `ios-epub-reader-menu.png` | Five doors and read-aloud |
| Menu | `ios-epub-reader-menu-ax5.png` | Largest text size |
| Theme sheet, presets | `ios-epub-theme-presets.png` | Six presets, each in its own colours and typeface |
| Theme sheet, axes | `ios-epub-theme-axes.png` | Nine typographic controls behind *Customise* |
| Theme sheet, axes | `ios-epub-theme-axes-ax5.png` | Largest text size |
| Page colour | `ios-epub-theme-page-colour.png` | The reader's own colour, and the contrast gate |
| Contents | `ios-epub-contents.png` | The book's declared table of contents |
| Search in book | `ios-epub-search.png` | At rest, with its prompt |
| Bookmarks | `ios-epub-bookmarks.png` | Empty, with the instruction |
| Notes | `ios-epub-notes.png` | Empty, with the instruction |
| A note | `ios-epub-note-dialog.png` | Being written over a selected passage |

## The player

| Surface | File | State |
| --- | --- | --- |
| Compact bar | `ios-player-compact-on-home.png` | Over Home |
| Compact bar | `ios-player-compact-on-search.png` | Over Search |
| Compact bar | `ios-player-compact-ax5.png` | Largest text size |
| Full player | `ios-player-full.png` | Cover, transport, scrub, three settings |
| Chapters | `ios-player-chapters.png` | Each with its length, the current one marked |
| Chapters | `ios-player-chapters-ax5.png` | Largest text size |
| Speed | `ios-player-speed.png` | The stops, current one ticked |
| Sleep timer | `ios-player-sleep-sheet.png` | The picker, including *End of chapter* |

## Settings

| Surface | File | State |
| --- | --- | --- |
| Root | `ios-settings-root.png` | Seven groups, each summarising what it holds |
| Root | `ios-settings-root-ax5.png` | Largest text size |
| Root, French | `ios-settings-root-french.png` | The app's own language override, applied |
| Appearance | `ios-settings-appearance.png` | Four modes, Natural, the reading-theme link |
| Appearance | `ios-settings-appearance-ax5.png` | Largest text size |
| Appearance, Natural on | `ios-settings-appearance-natural.png` | The axis that crosses the four modes |
| Reading | `ios-settings-reading.png` | The volume-buttons sentence, and the defaults |
| Reading | `ios-settings-reading-ax5.png` | Largest text size |
| Reading, matte | `ios-settings-reading-matte.png` | The colour behind a comic page |
| Privacy | `ios-settings-privacy.png` | The group with nothing to opt out of |
| Privacy, diagnostic | `ios-settings-privacy-diagnostic.png` | The redacted export, shown |
| Downloads and storage | `ios-settings-downloads.png` | The limit, the Wi-Fi rule, what is here |
| Language | `ios-settings-language.png` | The four StoryArc speaks, and System |
| Your libraries | `ios-settings-sources.png` | Five sources with their states |
| One source | `ios-settings-source-detail.png` | An OPDS catalogue: status, last sync, actions |
| The same, from Sources | `ios-source-catalogue-detail.png` | Reached through *Your libraries* |
| An unreachable source | `ios-source-unreachable-detail.png` | *Not answering* — grey, never red |
| About | `ios-settings-about.png` | Version, licence, acknowledgements |
| Reset | `ios-settings-reset-confirm.png` | Naming what survives |

## Adding a library

| Surface | File | State |
| --- | --- | --- |
| Online library | `ios-add-catalogue-sheet.png` | Address, the hint, Connect |
| Online library | `ios-add-catalogue-sheet-ax5.png` | Largest text size |
| Kavita server | `ios-add-kavita-sheet.png` | Address, API key, where the key is kept |
| Shared folder | `ios-add-share-sheet.png` | Host, share, credentials, what is on this network |
| A file | `ios-add-file-picker.png` | The system's own document browser |

*Add a folder* has no frame. It presented no picker — see the last section.

## iPad, landscape

Sixteen iPad frames already exist in `../after-2026-08-30/` and every one of them is portrait.
These are the landscape pass, on an iPad Pro 11-inch (iOS 26.5), with the phone's corpus copied
into it.

**They are letterboxed, and that is the screenshot rather than the app.** `XCUIScreenshot`
returns the device's own canvas, which stays portrait while the interface is landscape — so
each frame is the landscape window with black above and below it. Crop before showing one to
anybody; nothing about the bands is the app's.

| Surface | File | State |
| --- | --- | --- |
| Home | `ios-ipad-home.png` | Landscape, sidebar-adaptable shell |
| Library | `ios-ipad-library.png` | The 158 pt cover tier a wide window takes |
| Library | `ios-ipad-library-ax5.png` | Largest text size |
| Library, list | `ios-ipad-library-list.png` | A row with an iPad's width to fill |
| Downloads | `ios-ipad-downloads.png` | Landscape |
| Search | `ios-ipad-search.png` | Landscape, at rest |
| Sidebar | `ios-ipad-sidebar-dark.png` | The four destinations, then the rows a phone never draws — **dark only** |
| Detail column | `ios-ipad-detail.png` | A publication page beside the shelf |
| Comic reader | `ios-ipad-comic-reader.png` | A page filling a landscape iPad |

## First run

A development device cannot show these: this simulator has carried a corpus, an audiobook and
five sources since August. They are taken on a simulator created for them —
`StoryArc-Sweep-Empty` — with nothing added.

| Surface | File | State |
| --- | --- | --- |
| Library | `ios-empty-library.png` | *Nothing here yet*, and the two actions that change it |
| Library | `ios-empty-library-ax5.png` | Largest text size |
| Home | `ios-empty-home.png` | Nothing open yet |
| Downloads | `ios-empty-downloads.png` | One sentence and the way to the library |
| Search | `ios-empty-search.png` | Nothing to suggest — the five ways in instead |
| Your libraries | `ios-empty-sources.png` | No libraries yet |
| Settings root | `ios-empty-settings-root.png` | Five of seven summaries saying *nothing yet* |

## The frames the older suites contribute

`ScreenshotTests`, `PlayerScreenshotTests` and `AppIconCaptureTests` were already in the
repository and were run into this folder too, under their own names. Several are a second view
of a surface the sweep also photographs; the ones below are the surfaces only they reach.

| Surface | File | State |
| --- | --- | --- |
| Home | `ios-home.png` | The destination at rest |
| Library | `ios-library.png` | The shelf at rest |
| Library | `ios-library-ax5.png` | Largest text size |
| Search | `ios-search.png` | At rest |
| Search | `ios-search-ax5.png` | Largest text size |
| Downloads | `ios-downloads.png` | The destination at rest |
| Comic reader | `ios-comic-reader-chrome.png` | The chrome over a saturated page |
| Skipped notice | `ios-skipped-notice.png` | Two publications that could not be opened |
| Skipped notice | `ios-skipped-notice-ax5.png` | Largest text size |
| What could not be opened | `ios-skipped-list.png` | The list behind it, with a reason each |
| About | `ios-about.png` | Version, licence, acknowledgements |
| Compact player | `ios-compact-player.png` | Over the library |
| Full player | `ios-full-player.png` | Cover, transport, scrub, three settings |
| Full player | `ios-full-player-largest-text.png` | Largest text size |
| Sleep timer | `ios-sleep-timer-set.png` | Set to five minutes |
| Sleep timer | `ios-sleep-timer-counting.png` | Three seconds of playback later — it moved |
| The control | `ios-library-nothing-playing.png` | The same shelf with no session |
| What's new | `ios-whats-new.png` | The sheet, on the launch after an update |
| What's new | `ios-whats-new-ax5.png` | Largest text size |
| What's new | `ios-whats-new-from-about.png` | Reached from About, which does not mark it seen |

## What is not here, and why

**The selection chrome.** It was rebuilt while this sweep was being taken — the tab bar hides,
the actions float as a glass capsule where it was, the count moves into the navigation title
and *Done* into the toolbar. The walks for it landed with it, in
`apps/ios/UITests/LibrarySelectionCapture.swift`, and writing a third and fourth walk for the
same surface is how two of them come to disagree. Produce those frames into this folder with:

```
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-sweep-2026-09-02 \
  --only ScreenshotTests/testCaptureLibrarySelectingWithPicks --appearance light
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-sweep-2026-09-02 \
  --only ScreenshotTests/testCaptureLibrarySelectingAtLargestText --appearance light
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-sweep-2026-09-02 \
  --only ScreenshotTests/testCaptureLibrarySelectingAtTheEnd --appearance light
```

The `Add to…` menu a selection opens is uncaptured for the same reason: it belongs with
whichever walk owns the new capsule.

**A running or paused download.** `StoredDownload` records `finished`, `failed` and everything
else as `queued`, so *running*, *paused for Wi-Fi*, *paused by the reader* and *paused for
space* cannot be produced by injecting a record. They need a real transfer against a live
server, which is a different kind of test.

**The Downloads destination's undo bar.** Removing a *queued* transfer takes the branch with
nothing on disk to move aside, so no undo is offered — correctly. The undoable path needs a
*finished* download whose id matches a publication's stable id, and that id is
`path:<the file's absolute path inside the app container>`, which a UI test cannot know: the
container path is assigned at install time and the test process cannot read it. It needs
either a real download from `pnpm opds` or a harness that computes the path from the host.

**A source that needs signing in again.** `SourceReconnectSheet` is reached from a source whose
credential was *refused*, and none of this device's five sources is in that state — the two
that are unreachable are unreachable, which is a different row and a different action.

**A note being written in the EPUB reader.** Selection over reflowable text is WebKit's own
gesture; a long press that lands between words selects nothing and puts up no menu. The walk
is `SweepEpubReaderTests.testCaptureEpubNoteDialog` and it skips with what it saw.

**Settings' own search results.** The query is view state with no launch argument behind it,
and typing into the simulator garbles ASCII — a French keyboard layout, recorded in this
repository twice. The empty-query root is here; a search result page is not.

**The app-icon chooser, the theme sheet's preset grid under its own name, and the reflowable
reader's arrival trio.** All five come from `ScreenshotTests` and `AppIconCaptureTests`, whose
runs were stopped: their walk to the reflowable reader is `EpubWalk.openTheEpubReader(in:)`,
which on this corpus opens two fixed-layout books and waits fifteen seconds for each before
finding a reflowable one — twenty-five minutes a suite, twice for light and dark. The sweep's
own `epub-theme-presets` is the same sheet, and the icon chooser has a folder of its own at
`../app-icon-chooser-2026-09-01/`. To take them anyway:

```
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-sweep-2026-09-02 \
  --only ScreenshotTests --appearance light
node scripts/capture-ios.mjs --out docs/designs/screenshots/ios-sweep-2026-09-02 \
  --only AppIconCaptureTests/testCaptureAppIconChooser --appearance light
```

**The comic reader's fit picker.** Tapping the row opens nothing — see the last section. There
is no frame because there was nothing to photograph.

**Two iPad frames have one appearance rather than two.** `ios-ipad-comic-reader.png` is light
only — the dark walk found no CBZ cover in the screenful it looked at — and
`ios-ipad-sidebar-dark.png` is dark only, the light walk having opened on a window whose
sidebar was already out, which its own guard treats as nothing to reveal. Both are one re-run
away; neither shows anything the other appearance would contradict.

**The EPUB reader's read-aloud bar.** `SweepEpubReaderTests.testCaptureEpubReadAloud` finds no
read-aloud row in the menu on this publication and skips saying so.

**Starting again from page one.** The confirmation exists and is worth a frame, but the
control that opens it is only offered on a publication with a recorded position, and this sweep
pins the query and the settings rather than reading anything. `detail-restart-confirm` skips
with that reason. Open any publication by hand first and the walk takes it.

**The library-wide *nothing can be reached* notice.** `library-browsing`'s *None of the places
you added can be reached right now* needs every source unreachable **and** the library not
already browsable from local files. This device's shelf is local files, so the notice never
appears; `SweepSourcesTests.testCaptureAwayNotice` skips saying so. It would take a device
whose only sources are servers.

**The end of a publication**, the offline notice over a page from an unreachable share, and the
metered-data confirmations. All three need a state that takes either a real network or reading
a publication to its last page.

## What looked wrong

Nothing here was fixed. Each item names the frame that shows it. They are ordered by how
likely they are to be a defect rather than a decision.

**Home has no hero on an iPad.** The phone opens on *Continue reading* with a full-width
cover; the iPad opens straight into *Recently added*, with no hero at all, on the same device
state and the same publication with a recorded position. `ios-ipad-home.png` against
`ios-home-top.png`. The widest window in the app is the one that drops the largest thing on
the screen.

**A horizontal shelf on an iPad stretches its covers.** In *Recently added* on the iPad the
cells are wider than they are tall, while the same artwork in the iPad's own library grid is
the portrait 2:3 the fixtures actually are. `ios-ipad-home.png` against `ios-ipad-library.png`.
`design.md` says letterbox rather than crop, and neither is happening here.

**An audiobook's progress is measured in pages.** Home's *Continue reading* hero says
`2 pages left` for `Sea Room`, which is an M4B. `ios-home-top.png`. `home.pagesLeft` is the
string; an audiobook has a duration, not a page count.

**Tapping the *Fit* row in the reader's menu opens nothing.** Twice, in the light and the dark
run: after the tap the sheet still reads *Fit — Screen*, at the same detent, with the same
rows. The *Transition* row directly beneath it — reached by the same lookup and tapped the
same way — opens its menu and offers *Slide*, which is why there is a
`ios-comic-reader-transition-picker.png` and no `ios-comic-reader-fit-picker.png`. The
difference between the two rows is the control: `Transition` is a `Menu` and `Fit` is a
`Picker`. **Worth a finger before it is called a defect** — a UI test's tap on a picker row is
not identical to a touch — but the pair of frames is the evidence either way.

**Every row in the reader's menu is drawn in the accent colour, on glass tinted by the page.**
*Contents*, *Appearance*, *Transition*, *Done* — all purple, because they are `Button`s in a
`List` and nothing sets their foreground. The sheet's material picks up the artwork behind it,
so over the salmon page in `ios-comic-reader-menu.png` the menu is warm brown and the purple
labels sit on it at low contrast; the page position, *1 of 3*, is grey on the same brown. This
is the surface `quiet-reader` moved eleven controls **into**, so it is where a reader now goes
to change anything about how a comic is drawn. It is the first thing in this sweep a design
reviewer should look at.

**Three different fallbacks for one missing cover.** A publication with no artwork is drawn as
its own title on the shelf, as a book glyph with the format under it on the publication page,
and as a flat grey square with the title in the middle in the player — and an *audiobook* gets
the book glyph too. `ios-library-grid.png`, `ios-detail-audiobook.png`,
`ios-player-sleep-sheet.png`. The app says the artwork is the interface; this is what it does
when there is none, in three unrelated ways.

**A cover-less cell says the title twice.** On every shelf, a publication with no artwork
draws its title *inside* the well and again as the caption underneath — `Foreign Codec`,
`Harbour Lights 01`, `Sea Room`. `ios-library-grid.png`, `ios-downloads-shelf.png`,
`ios-home-lower.png`. The publication *page*'s well does not do this: it draws a book glyph
and the format instead (`ios-detail-no-cover.png`), which reads better. The shelf's cell and
the page's hero disagree about the same problem.

**Settings and Downloads disagree about what is on the device.** Settings' root says
*Downloads and storage — Nothing on this device*, its own screen says *Space used — Zero kB*,
and the Privacy screen says *Downloads · 0 bytes* with its *Clear* greyed out — while the
Downloads destination shows nine publications under *On this device*.
`ios-settings-root.png`, `ios-settings-downloads.png`, `ios-settings-privacy.png` against
`ios-downloads-shelf.png`. Both readings are defensible — one counts download *records*, the
other counts local files — and a reader cannot see which. *Zero kB* is also an odd way to
write nothing; the same number is *0 bytes* one screen away.

**Narrowing to one library is answered with a sentence about the device.** Filter → *Which
library* → `Attic NAS` empties the shelf and says *Nothing from Attic NAS is on this device
yet.* `ios-library-narrowed-to-nothing.png`. The reader narrowed by library and is told the
problem is the device; those are the two axes `library-browsing` is careful to keep apart, and
the string that answers one of them names the other. `library.empty.scope`.

**A successful search is mostly failure.** Two results under *Titles*, then three separate
*didn't answer* lines — one per unreachable source, each with its own *Try again*.
`ios-search-results.png`. On a device with three servers configured and none running, which is
every train journey, the notices outnumber the answers.

**The results screen states no scope.** The segmented *Everywhere · On this device* control is
on the at-rest screen and in the field's own bar while the field is active, and nowhere on the
results. `library-browsing` asks the screen to state its scope "when the search screen is
open"; a reader looking at two results cannot see which half of their library was asked.
`ios-search-at-rest.png` against `ios-search-results.png`.

**The add-a-library forms give their action the same shape as their empty fields.** *Connect*
on the shared-folder sheet is a full-width grey capsule, identical in colour, height and corner
to the *Host*, *Share*, *User name* and *Password* fields above it — so the one thing on the
screen that does something looks like a fifth thing to type into.
`ios-add-share-sheet.png`, `ios-add-catalogue-sheet.png`, `ios-add-kavita-sheet.png`.

**Add a folder opens nothing.** *Open a file*, one row below it in the same menu, puts up the
system's document browser within three seconds — `ios-add-file-picker.png` is a picture of it.
*Add a folder* leaves the library's own toolbar reachable and presents no picker at all, which
is why there is no `ios-add-folder-picker.png` in this folder. On iOS the folder picker is the
*whole* of adding a local library, so if this is what it looks like on a device then a reader
cannot add one. `SweepSourcesTests.testCaptureFolderPicker` polls for ten seconds before saying
so, and it said so in both the light and the dark run — the file picker beside it passed in
both.

**Every source says it holds nothing, and every source says it is still connecting.**
*Your libraries* lists four sources; all four read `0 titles`, while the shelf next door holds
fourteen publications, and all four sit on *Connecting* — including `Comics on this iPhone`,
which is a local folder with nothing to connect to. `ios-settings-sources.png`,
`ios-settings-source-detail.png`. The publications on the shelf are scanned from the app's own
Documents folder and attributed to no source, so the per-source count can never agree with the
shelf; the *Connecting* state on a local folder is a separate thing and looks like a probe that
never resolves.

**Stopping a transfer is confirmed with the words for deleting a finished download.** *Stop*
on a row that is still arriving asks *Remove this download?* — "This deletes the copy of
Harbour Lights 03 on this device. Your reading position is kept, and it can be downloaded
again." — and the destructive button says *Remove download*. `ios-downloads-stop-confirm.png`.
There is no copy on the device yet and no reading position to keep; the reader is cancelling
something in flight. One string is doing two jobs.

**A transfer states no size and no percentage.** A queue row is a title, two reorder
chevrons, *Stop*, and a bare progress bar. `offline-downloads` asks for the size to be shown,
and the bar is the only thing that says a transfer is 37% of the way through.
`ios-downloads-queue.png`, `ios-downloads-queue-ax5.png`.

**The View menu's icon is an ellipsis.** The menu that decides availability, layout, sort and
direction is drawn as `ellipsis.circle` — "…" in a circle — beside the filter funnel.
`library-browsing` asks the availability choice to be "visible while it is active", and the
only thing that carries it is that glyph changing to `arrow.down.circle`; the count of active
filters is spoken and never drawn. `ios-library-grid.png`, `ios-library-filtered.png`.

**The publication page is mostly empty space, and its provenance line collides with the tab
bar.** Between the author and the *Read* button there is a band of about eighty points of
nothing, and *On this device, readable with no network* sits on the very bottom edge, half
under the glass. `ios-detail-bare.png`. The corpus has no descriptions, so this is what the
page looks like for most of a folder library.

**Home's Shelves link is a list row wedged between two shelves.** It sits after *Recently
added* and before *Finished*, with no section header, an icon and a chevron — the only row of
its kind on a screen otherwise made of horizontal cover shelves. `ios-home-lower.png`.

**The hero's title is legible through the navigation bar.** Scrolling Home puts the inline
title *Home* over the hero, and the hero's own large title stays readable behind it, colliding
with the status-bar clock. `ios-home-lower.png`, top edge.

**The shelves screen is two sentences and two pills in a screen and a half of void.** Both
sections are empty on a clean device, and their empty state is a heading, a line of
explanation and a *New …* pill — after which two-thirds of the screen is nothing.
`ios-shelves.png`, `ios-shelves-dark.png`. It is the emptiest surface in the app and the one a
reader most likely lands on by accident, from the row wedged into the middle of Home.

**The filter menu is taller than it shows.** Six of its nine groups are visible and there is
no affordance saying the rest are below. `ios-library-filter-menu.png`.
