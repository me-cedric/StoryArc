# Linux conformance walk, wave 2

Task 2.36 of `desktop-clients`, lane L, branch `lane/linux-wave2`. Every scenario of the capabilities wave 2
names, against the Linux app at the head of this branch on 2026-10-17, with the result it gave. The scenarios
are read from the specs by name, so a scenario added to a spec later is missing here until the walk runs again.
`desktop-experience` lists only the requirements the Linux wave 2 tasks name.

| Result | Means |
| --- | --- |
| pass | A named test in `storyarc-linux` asserts it (`cargo test -p storyarc-linux` in `container-build.sh ubuntu-24.04`), or a named core test where the rule is the core's. |
| seen | The walk under cage showed it; nothing asserts it. The evidence says what was shown. |
| **fail** | It does not hold on Linux today. Each one is a defect or a missing piece of wave 2's scope. |
| later | A later wave of `desktop-clients` builds it, as named. |
| n/a | Another platform's scenario, or dropped on a desktop. |
| not proved | Built or partly built, and it needs a Linux desktop session this lane did not have: a real compositor with a pointer, a portal, a Flatpak, X11, Orca, a resize, or a measurement. |

Totals: pass 94, seen 75, fail 106, later 69, n/a 39, not proved 101, of 484 scenarios.

**What the walk is.** The debug build ran under cage 0.1.5 (a headless wlroots compositor, `WLR_BACKENDS=headless`,
1280 by 720) in an Ubuntu 24.04 container with GTK 4.14.5 and libadwaita 1.5.0, `GDK_BACKEND=wayland`, driven by
`wtype` key presses and captured by `grim`, in the light and the dark style. The one folder library was the
fixture comics of `packages/test-fixtures/comics`, plus a second folder on a path that does not exist. The walk
opened files from the command line, turned pages by key, zoomed, closed the reader, relaunched to Home,
searched, moved by Tab to the grid, opened a publication's page beside the library, and handed the app a CB7, a
missing file and a folder. There was no pointer, no session bus, no portal and no second monitor, so nothing
that needs them is called proved. The first key of a `wtype` run was sometimes lost; the second and later keys
always arrived. The walk cannot tell whether the harness or the app lost it, so a first-key loss on a real
session is owed a check. The captures were looked at; they are not committed because `docs/designs/` belongs
to another lane.

**Defects the walk found and fixed on this branch**, each with its commit: a zoomed page drew over the header
and the bottom bar, and the first arrow moved the focus to a header button instead of turning (`7c6ab11b`); a
folder handed over with no window up ended the app (`663aada6`); covers in the grid were cropped (`a00124c5`).

**Not proved, by kind.** A Flatpak run of 2.31 (the portal grant, its withdrawal and the polled watch), a real
drop and a pointer walk (hover chrome, edge clicks, the drag, pinch), a second launch handing a file to the
first, `GtkRecentManager` seen in a file manager, X11, fractional scaling, a resize walk down to 360 pixels,
a 10,000-publication scroll on Wayland and X11, Orca, larger text, high contrast and reduced motion.

## The failures, in one list

- `comic-reader` · Page transitions in the comic reader: No transition mode on Linux: a key or a click changes the page at once; only a drag slides the page with the pointer. No continuous scroll, no scroll axis.
- `comic-reader` · Reading direction: No control on Linux overrides a publication's direction.
- `comic-reader` · Navigation within a publication: No page slider, thumbnails or chapters on Linux.
- `comic-reader` · Navigation within a publication: No end-of-publication screen: the next-page key on the last screen does nothing.
- `comic-reader` · Image adjustments: The core applies adjustments and the border trim (`storyarc_core::image::adjusted`, `cropped`); Linux has no control for them yet.
- `comic-reader` · Page browser: Not built on Linux.
- `page-transitions` · Transition modes: No mode choice on Linux; pages change at once.
- `library-browsing` · Unified library: The sidebar lists each folder and its state; choosing one to browse it is not built.
- `library-browsing` · Unified library: The query state filters by folder (`library::adapter::the_filters_narrow_by_format_reading_state_and_folder`); the filter menu has no folder section yet.
- `library-browsing` · Unified library: The detail page says *Offline* or *Needs access* and disables Read (`library::detail`); the grid cell is not dimmed.
- `library-browsing` · Search: No line states the scope and no recent searches are kept on Linux.
- `library-browsing` · Search: An empty grid, with no sentence saying nothing matched.
- `library-browsing` · What could not be opened: The notice is an `AdwToast`, which times out; the grid entry stays.
- `library-browsing` · Presentation: No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only).
- `local-library` · Imported copies: Not built on Linux: an opened file is read where it stands.
- `reading-progress` · Resuming: No *Read from the beginning* on Linux.
- `reading-progress` · Privacy of reading history: No clearing of history on Linux yet.
- `reading-themes` · Theme presets: No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones.
- `reading-themes` · Theme axes: Not built on Linux.
- `reading-themes` · Custom colour: Not built on Linux.
- `reading-themes` · Theme scope and persistence: Not built on Linux.
- `localization` · Supported languages: Strings this branch added are English only: the folder, filter, sort, detail and pane texts, and those listed under Deviations.
- `localization` · Locale-correct formatting: *6 pages* and *20%* are written in English.
- `localization` · Layout resilience: No pseudo-locale on Linux.
- `native-experience` · Dynamic colour: No colour is taken from a cover on Linux yet.
- `native-experience` · Adaptive layout: No theme sheet on Linux.
- `native-experience` · Reader chrome material: No reading theme on Linux.
- `native-experience` · Theme sheet reachability: No theme sheet on Linux.
- `native-experience` · Visual proof of interface changes: Linux has no snapshot tests.
- `native-experience` · Visual proof of interface changes: No accessibility or HIG audit runs on Linux.
- `native-experience` · Chrome for a mode a reader is in: No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen.
- `settings-and-about` · Settings organisation: No reset in the Linux preferences.
- `settings-and-about` · Privacy: No privacy screen, clearing or diagnostic on Linux yet.
- `settings-and-about` · About: `AdwAboutDialog` with the name, version and licence; no support link, acknowledgements or problem report.
- `settings-and-about` · What changed in this version: Not built on Linux.
- `home-screen` · Keep reading: A Home card on an offline folder is not dimmed.
- `home-screen` · Keep reading: The card shows the title only.
- `home-screen` · The rest of the home surface: No Recently added, pinned or Finished shelf on Linux Home.
- `navigation-shell` · Reaching search: No suggestions and no empty state.
- `navigation-shell` · Where a source can be reached: No way to narrow to one folder yet.
- `navigation-shell` · Where a source can be reached: A folder row has no configuration; Choose Again shows only when access is withdrawn.
- `publication-detail` · What the page shows: No other-issues shelf on the Linux page.
- `publication-detail` · Colour taken from the cover: No colour is taken from the cover: the wash is a plain box.
- `cover-art` · The cover ladder: The Linux ladder does not look beside the file.
- `desktop-experience` · Recent items in the system's launcher: No clearing of history on Linux yet.

## comic-reader

Source: `docs/openspec/specs/comic-reader/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Page transitions in the comic reader | Mode persistence | **fail** | No transition mode on Linux: a key or a click changes the page at once; only a drag slides the page with the pointer. No continuous scroll, no scroll axis. |
| Page transitions in the comic reader | Continuous scroll | **fail** | No transition mode on Linux: a key or a click changes the page at once; only a drag slides the page with the pointer. No continuous scroll, no scroll axis. |
| Page transitions in the comic reader | Scroll axis for webtoons | **fail** | No transition mode on Linux: a key or a click changes the page at once; only a drag slides the page with the pointer. No continuous scroll, no scroll axis. |
| Page transitions in the comic reader | Curl over image pages | later | The curl is wave 5. |
| Reading direction | Manga defaults | pass | `keys::` (right-to-left mirrors the arrows and the edge zones), `reading::spread::right_to_left_puts_the_page_read_first_on_the_right`; the direction is the core's record (`ComicInfo` manga flag). |
| Reading direction | Overriding direction | **fail** | No control on Linux overrides a publication's direction. |
| Page fitting and zoom | Fit modes | pass | `reading::zoom::each_fit_sizes_the_page_its_own_way`; Fit Page, Fit Width and Original Size are reader actions on Control and 0, 9 and Shift 0. |
| Page fitting and zoom | Double-page spreads | pass | `reading::spread` (cover alone, pairs, a wide page alone, the last of an odd count alone); walk under cage: *2 of 12* showed pages 2 and 3 side by side, *12 of 12* the last page alone and centred. |
| Page fitting and zoom | Zooming | pass | `reading::zoom` (limits, double click, pinch and wheel, pan to the edges, a turn keeps the zoom), `reading::spread`; walk under cage: Control and plus zoomed a pair, clipped under the bars. |
| Page fitting and zoom | Zoom persists across pages | pass | `reading::zoom` (limits, double click, pinch and wheel, pan to the edges, a turn keeps the zoom), `reading::spread`; walk under cage: Control and plus zoomed a pair, clipped under the bars. |
| Auto-hiding chrome | Entering the reader | pass | `keys::` chrome idle tests (shown on motion, hidden three seconds later, held by an open menu). |
| Auto-hiding chrome | Revealing controls | pass | `keys::` chrome idle tests (shown on motion, hidden three seconds later, held by an open menu). |
| Auto-hiding chrome | Everything else is in the menu, and labelled | not proved | The reader menu is built from the command table; no walk opened it. |
| Auto-hiding chrome | Edge taps turn pages | pass | `keys::` click zones, on by default (`settings::`). |
| Auto-hiding chrome | Chrome does not obscure the page | seen | walk under cage: the page sits between the header and the bottom bar, and a zoomed page is clipped to that area (fixed on this branch, `7c6ab11b`). |
| Auto-hiding chrome | Fewer controls is not fewer ways in | not proved | Every command keeps a key and a menu entry (`commands::`); no walk. |
| Navigation within a publication | Page slider with thumbnails | **fail** | No page slider, thumbnails or chapters on Linux. |
| Navigation within a publication | Where the reader is, at a glance | seen | walk under cage: the bottom bar reads *2 of 12*. |
| Navigation within a publication | Thumbnail browser | **fail** | No page slider, thumbnails or chapters on Linux. |
| Navigation within a publication | Chapter navigation | **fail** | No page slider, thumbnails or chapters on Linux. |
| Navigation within a publication | Reaching the end | **fail** | No end-of-publication screen: the next-page key on the last screen does nothing. |
| Image adjustments | Adjustments available | **fail** | The core applies adjustments and the border trim (`storyarc_core::image::adjusted`, `cropped`); Linux has no control for them yet. |
| Image adjustments | Cropping borders | **fail** | The core applies adjustments and the border trim (`storyarc_core::image::adjusted`, `cropped`); Linux has no control for them yet. |
| Image adjustments | Persisting adjustments | **fail** | The core applies adjustments and the border trim (`storyarc_core::image::adjusted`, `cropped`); Linux has no control for them yet. |
| Reader performance | Prefetching | not proved | Built, not measured: the reader decodes the screens on either side on a worker and keeps nine pages around the reader's place. |
| Reader performance | Page not yet available | not proved | A page still decoding is a quiet placeholder of a page's shape (`page_view.rs`); no walk caught one, the fixtures decode at once. |
| Reader performance | Screen stays awake | pass | `idle::tests` (held while a reader is the active window, released on focus loss and close, a refusal silent). |
| System integration | Hardware page turns | n/a | Phone hardware: volume keys, orientation lock and the screenshot flag do not exist on a Linux desktop. |
| System integration | Orientation lock | n/a | Phone hardware: volume keys, orientation lock and the screenshot flag do not exist on a Linux desktop. |
| System integration | Screenshot and recording | n/a | Phone hardware: volume keys, orientation lock and the screenshot flag do not exist on a Linux desktop. |
| Page browser | One page in the centre | **fail** | Not built on Linux. |
| Page browser | Browsing does not move the reader | **fail** | Not built on Linux. |
| Page browser | The slider moves the carousel | **fail** | Not built on Linux. |
| Page browser | Chapters in the browser | **fail** | Not built on Linux. |
| Page browser | No chapter markers | **fail** | Not built on Linux. |
| Page browser | Right-to-left reading | **fail** | Not built on Linux. |
| Page browser | Reduce Motion | **fail** | Not built on Linux. |
| Page browser | Assistive technology | **fail** | Not built on Linux. |

## page-transitions

Source: `docs/openspec/specs/page-transitions/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Transition modes | Choosing a mode | **fail** | No mode choice on Linux; pages change at once. |
| Transition modes | Scroll axis | **fail** | No mode choice on Linux; pages change at once. |
| Transition modes | A mode is unavailable for the content | **fail** | No mode choice on Linux; pages change at once. |
| The curl | The page follows the finger | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | The sheet rolls rather than folds | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Turning back | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Turning back from the first page | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Release behaviour | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | The curl is interruptible | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Curl direction respects reading direction | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Curl is not offered where it cannot be honest | later | The curl is wave 5 (spike 1.17 decides X11). |
| The curl | Every other mode stays available | later | The curl is wave 5 (spike 1.17 decides X11). |
| Reduced motion | Reduce Motion is on | not proved | No transition animates on Linux yet, so there is nothing to reduce; the drag slide follows the pointer, which is not motion the app adds. |
| Reduced motion | Reduce Motion turned off mid-session | not proved | No transition animates on Linux yet, so there is nothing to reduce; the drag slide follows the pointer, which is not motion the app adds. |
| Turn triggers | Tap zones | pass | `keys::` (zones, keys by direction, wheel notches), `reading::spread::a_turn_moves_one_screen_and_stops_at_either_end`, `reading::drag`. |
| Turn triggers | Turning the tap zones off | pass | `settings::` (click zones stored), `keys::click_action` with zones off toggles the chrome. |
| Turn triggers | The tap zones are on until a reader says otherwise | pass | `settings::` default: click zones on. |
| Turn triggers | Hardware input | pass | `keys::` (zones, keys by direction, wheel notches), `reading::spread::a_turn_moves_one_screen_and_stops_at_either_end`, `reading::drag`. |
| Turn triggers | Turning at a boundary | pass | `keys::` (zones, keys by direction, wheel notches), `reading::spread::a_turn_moves_one_screen_and_stops_at_either_end`, `reading::drag`. |
| Transition performance | The next page is not ready | not proved | Not measured on Linux. |
| Transition performance | Frame budget | not proved | Not measured on Linux. |
| Transition performance | Memory during a curl | later | The curl is wave 5. |

## library-browsing

Source: `docs/openspec/specs/library-browsing/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Unified library | Default view | seen | walk under cage: Library lists every publication of the fixture folder, covers decoded by the core. |
| Unified library | Every kind of source contributes | later | Servers and downloads are wave 3; a folder library is the only source on Linux in wave 2. |
| Unified library | Browsing a source is a second way in | **fail** | The sidebar lists each folder and its state; choosing one to browse it is not built. |
| Unified library | A source that has never been reached | later | Servers and downloads are wave 3; a folder library is the only source on Linux in wave 2. |
| Unified library | Narrowing to what can be read now | later | Servers and downloads are wave 3; a folder library is the only source on Linux in wave 2. |
| Unified library | Scoping to one source | **fail** | The query state filters by folder (`library::adapter::the_filters_narrow_by_format_reading_state_and_folder`); the filter menu has no folder section yet. |
| Unified library | A publication that is also downloaded | later | Servers and downloads are wave 3; a folder library is the only source on Linux in wave 2. |
| Unified library | A publication that cannot be opened right now | **fail** | The detail page says *Offline* or *Needs access* and disables Read (`library::detail`); the grid cell is not dimmed. |
| Unified library | More from a source than the library holds | later | Servers and downloads are wave 3; a folder library is the only source on Linux in wave 2. |
| Search | The scope is stated, and can be narrowed | **fail** | No line states the scope and no recent searches are kept on Linux. |
| Search | Searching with every source unreachable | later | Servers are wave 3. |
| Search | Typing a query | pass | `library::adapter::search_finds_by_title_through_the_core_and_clearing_shows_everything`; walk under cage: *nested* found the two nested-chapters comics. |
| Search | Mixed local and server search | later | Servers are wave 3. |
| Search | No results | **fail** | An empty grid, with no sentence saying nothing matched. |
| Search | Recent searches | **fail** | No line states the scope and no recent searches are kept on Linux. |
| Filtering | Combining filters | pass | `library::adapter::the_filters_narrow_by_format_reading_state_and_folder` over the core's `LibraryIndex::arrange`. |
| Filtering | Filter persistence | not proved | The filters live as long as the library window; they are not written between runs. |
| Filtering | Filtering offline | not proved | A folder that is offline keeps its publications listed; no walk filtered one. |
| Sorting | Default order in a reading list | later | Reading lists come from servers, wave 3. |
| Sorting | Overriding a curated order | later | Reading lists come from servers, wave 3. |
| Sorting | Alphabetical sorting across languages | pass | `library::adapter::the_sort_keys_reach_the_core_and_titles_follow_the_collation`, and the core's `tests/library_query.rs` (lane C). |
| Sorting | Sorting a series | pass | `library::adapter::the_sort_keys_reach_the_core_and_titles_follow_the_collation`, and the core's `tests/library_query.rs` (lane C). |
| What could not be opened | One publication could not be opened | seen | walk under cage: started with `refused.cb7`, the library named *refused.cb7: CB7 is not supported* in grey; the grid lists each skipped file with its reason after the publications. |
| What could not be opened | Several could not be opened | seen | walk under cage: started with `refused.cb7`, the library named *refused.cb7: CB7 is not supported* in grey; the grid lists each skipped file with its reason after the publications. |
| What could not be opened | The notice is not on a timer | **fail** | The notice is an `AdwToast`, which times out; the grid entry stays. |
| What could not be opened | Reaching it later | seen | walk under cage: started with `refused.cb7`, the library named *refused.cb7: CB7 is not supported* in grey; the grid lists each skipped file with its reason after the publications. |
| What could not be opened | A publication that later opens | not proved | A rescan replaces the skipped list (`sources.rs`); no walk fixed a file. |
| What could not be opened | Announced without sight | not proved | `library::entry` gives the cell its accessible description, *cannot be opened* included; Orca was not run. |
| Presentation | Switching layout | not proved | Grid and List in the View menu share one `GListModel`; no walk switched. |
| Presentation | Adaptive columns | seen | walk under cage: six columns in a full-width library, three with the detail pane open. |
| Presentation | Cover art is shown whole | seen | walk under cage: covers are fitted whole (fixed on this branch, `a00124c5`). |
| Presentation | Progress on covers | not proved | Each cell has a progress rail from the core's summary; no capture shows one. |
| Presentation | What is on the device | later | Downloads are wave 3. |
| Presentation | A series is one row | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | A shelf of issues | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | The choice between series and issues | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | Opening a series | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | Sectioning a long library | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | An index down the side of a long shelf | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | A sort no letter describes | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | The index without sight | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | A publication that cannot be read now | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Presentation | The controls that change the view are grouped | seen | walk under cage: Filter, Sort and View sit together at the end of the header bar. |
| Presentation | A control that stands alone carries a name | not proved | Sort and View carry tooltips and Filter a label; Orca was not run. |
| Presentation | An ordering says that it is an ordering | **fail** | No series rows, issue shelves, sections or index on Linux: the grid lists publications one by one (`library::grid` groups by series in its model only). |
| Continue reading | Home view | pass | `library::home` (keep reading first, up next offers the next issue); walk under cage: after reading nested-chapters to page 2, Home showed it under *Continue reading*. |
| Continue reading | Next in series | pass | `library::home` (keep reading first, up next offers the next issue); walk under cage: after reading nested-chapters to page 2, Home showed it under *Continue reading*. |

## local-library

Source: `docs/openspec/specs/local-library/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Folder libraries | Adding a folder on iOS | n/a | Another platform. |
| Folder libraries | Adding a folder on Android | n/a | Another platform. |
| Folder libraries | Access is revoked | pass | `folders::a_withdrawn_grant_needs_access_and_an_unmounted_volume_is_offline`; not proved in a Flatpak. |
| Folder libraries | Scanning a folder | seen | `library::adapter::every_fixture_comic_becomes_a_cell_and_the_cb7_is_named_as_skipped`; walk under cage. |
| Folder libraries | Nested folder structure becomes series | not proved | Built over the core's `FolderSource`. |
| Folder libraries | Large library | not proved | No walk of 10,000 publications. |
| Opening a single file | Open-in from another app | seen | walk under cage: `storyarc natural-sort.cbz` opened a reader window and no library window. |
| Opening a single file | Remembering an opened file on iOS | n/a | Another platform. |
| Opening a single file | Remembering an opened file on Android | n/a | Another platform. |
| Opening a single file | File type registration | pass | `opening::the_desktop_entry_actions_are_the_three_the_spec_names` (MimeType, `Exec=storyarc %F`, no CB7); `desktop-file-validate` passes in the gate. |
| Opening a single file | Unsupported file | seen | walk under cage: the CB7 was named with its reason; `publication::a_cb7_archive_is_refused_by_name_with_its_reason`. |
| Imported copies | Importing | **fail** | Not built on Linux: an opened file is read where it stands. |
| Imported copies | Deleting an imported copy | **fail** | Not built on Linux: an opened file is read where it stands. |
| Watched changes | New file appears | not proved | The core's `FolderWatcher` reports a change and the window rescans; the window also rescans when it gains focus. No walk added a file. |
| Watched changes | Change detected while backgrounded | not proved | The core's `FolderWatcher` reports a change and the window rescans; the window also rescans when it gains focus. No walk added a file. |

## publication-formats

Source: `docs/openspec/specs/publication-formats/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported formats | Detecting format | not proved | The core's indexer decides (lane C's tests); no Linux test opens each fixture. |
| Supported formats | An unsupported container is named, not merely rejected | pass | `publication::a_cb7_archive_is_refused_by_name_with_its_reason`; walk under cage. |
| Supported formats | A solid RAR4 is refused before any page is shown | not proved | The core's indexer decides (lane C's tests); no Linux test opens each fixture. |
| Supported formats | A damaged archive is not reported as an unsupported one | not proved | The core's indexer decides (lane C's tests); no Linux test opens each fixture. |
| Supported formats | Encrypted or password-protected archive | not proved | The core's indexer decides (lane C's tests); no Linux test opens each fixture. |
| Supported formats | Corrupt archive | not proved | The core's indexer decides (lane C's tests); no Linux test opens each fixture. |
| Streaming capability per format | Opening a streamable publication from a remote source | later | Remote sources are wave 3. |
| Streaming capability per format | Opening a solid archive from a remote source | later | Remote sources are wave 3. |
| Streaming capability per format | A solid archive already downloaded | later | Remote sources are wave 3. |
| Streaming capability per format | A remote publication is catalogued without being transferred | later | Remote sources are wave 3. |
| Streaming capability per format | Streaming capability is known before the first page is requested | later | Remote sources are wave 3. |
| Page ordering | Natural sort | not proved | The core orders the pages (lane C); the Linux reader shows them in that order. No Linux test. |
| Page ordering | Nested directories in an archive | not proved | The core orders the pages (lane C); the Linux reader shows them in that order. No Linux test. |
| Page ordering | Non-image entries | not proved | The core orders the pages (lane C); the Linux reader shows them in that order. No Linux test. |
| Metadata extraction | ComicInfo.xml | seen | walk under cage: *Natural Sort* and *RAR Fixture #1* are the embedded titles; files without metadata show their names. |
| Metadata extraction | EPUB package metadata | later | EPUB is wave 4. |
| Metadata extraction | No embedded metadata | seen | walk under cage: *Natural Sort* and *RAR Fixture #1* are the embedded titles; files without metadata show their names. |
| Metadata extraction | Right-to-left publication | pass | The record's direction reaches `keys::` and `reading::spread` (right-to-left tests). |
| Cover extraction | Comic cover | seen | walk under cage: each cover is the first page, decoded by the core at 360 pixels on a worker. |
| Cover extraction | EPUB cover | later | EPUB is wave 4. |
| Cover extraction | Cover generation cost | not proved | Not measured. |
| Page decoding | Very large page | pass | `publication::a_comic_opens_through_the_core_and_its_pages_decode` (bounded to 3,072 pixels), `publication::a_page_the_core_cannot_decode_names_a_reason`, `publication::a_landscape_page_is_wide_and_a_portrait_one_is_not`. |
| Page decoding | Supported image codecs | pass | `publication::a_comic_opens_through_the_core_and_its_pages_decode` (bounded to 3,072 pixels), `publication::a_page_the_core_cannot_decode_names_a_reason`, `publication::a_landscape_page_is_wide_and_a_portrait_one_is_not`. |
| Page decoding | Wide double-page image | pass | `publication::a_comic_opens_through_the_core_and_its_pages_decode` (bounded to 3,072 pixels), `publication::a_page_the_core_cannot_decode_names_a_reason`, `publication::a_landscape_page_is_wide_and_a_portrait_one_is_not`. |

## reading-progress

Source: `docs/openspec/specs/reading-progress/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Local progress store | Progress is recorded | pass | `session::a_position_reads_back_and_the_last_page_is_finished` over the core's store; `progress::tests` (written within five seconds, on close and on quit). |
| Local progress store | Position identity | not proved | The record keys on the core's identity; no Linux test moves a file. |
| Local progress store | App is terminated unexpectedly | pass | `session::a_position_reads_back_and_the_last_page_is_finished` over the core's store; `progress::tests` (written within five seconds, on close and on quit). |
| Local progress store | Finished state | pass | `session::a_position_reads_back_and_the_last_page_is_finished` over the core's store; `progress::tests` (written within five seconds, on close and on quit). |
| Resuming | Continue from a resume affordance | seen | walk under cage: the detail page offered *Continue Reading · 20%*; a reader opens on the stored page. |
| Resuming | Continue from the library | seen | walk under cage: the detail page offered *Continue Reading · 20%*; a reader opens on the stored page. |
| Resuming | Restart deliberately | **fail** | No *Read from the beginning* on Linux. |
| Synchronisation | Pushing progress | later | Wave 3. |
| Synchronisation | Pulling progress | later | Wave 3. |
| Synchronisation | Source cannot store progress | later | Wave 3. |
| Conflict resolution | Remote is further ahead | later | Wave 3; the merge is the core's (lane C). |
| Conflict resolution | Both changed since the last sync | later | Wave 3; the merge is the core's (lane C). |
| Conflict resolution | Remote is behind | later | Wave 3; the merge is the core's (lane C). |
| Conflict resolution | Conflicting finished state | later | Wave 3; the merge is the core's (lane C). |
| Progress across formats and sources | Same publication from two sources | later | Servers are wave 3 and reflowable reading is wave 4. |
| Progress across formats and sources | Reflowable position | later | Servers are wave 3 and reflowable reading is wave 4. |
| Privacy of reading history | No third-party transmission | seen | The Linux crate has no network dependency in wave 2 (`Cargo.toml`). |
| Privacy of reading history | Clearing history | **fail** | No clearing of history on Linux yet. |

## reading-themes

Source: `docs/openspec/specs/reading-themes/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Theme presets | Applying a preset | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | Original respects the publisher | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | Deviating from a preset | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | The reset names what it restores | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | Resetting the preset that is already unmodified | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | Reset does not disturb the reading position | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme presets | Presets follow the appearance polarity | **fail** | No reading theme on Linux in wave 2: the preferences hold the app's appearance, layout, fit and click zones. |
| Theme axes | Font size is stepped, not continuous | **fail** | Not built on Linux. |
| Theme axes | Every axis states its value | **fail** | Not built on Linux. |
| Theme axes | An axis requires publisher styles to be off | **fail** | Not built on Linux. |
| Theme axes | Brightness is reader-local | **fail** | Not built on Linux. |
| Theme axes | Resetting an axis | **fail** | Not built on Linux. |
| Custom colour | Choosing a background | **fail** | Not built on Linux. |
| Custom colour | Custom colour and the six presets | **fail** | Not built on Linux. |
| Custom colour | Fixed-layout and image content | **fail** | Not built on Linux. |
| Theme scope and persistence | Per-series memory | **fail** | Not built on Linux. |
| Theme scope and persistence | Separate defaults for reflowable and fixed-layout | **fail** | Not built on Linux. |
| Theme scope and persistence | Changing the global default | **fail** | Not built on Linux. |

## localization

Source: `docs/openspec/specs/localization/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported languages | Following the system | pass | `strings::` (the system's language list picks English, French, German or Spanish). |
| Supported languages | Overriding in the app | n/a | Desktops follow the system language (design, Decision 12). |
| Supported languages | Completeness | **fail** | Strings this branch added are English only: the folder, filter, sort, detail and pane texts, and those listed under Deviations. |
| Locale-correct formatting | Dates and times | not proved | No date is shown on Linux yet. |
| Locale-correct formatting | File sizes and counts | **fail** | *6 pages* and *20%* are written in English. |
| Locale-correct formatting | Plurals | **fail** | *6 pages* and *20%* are written in English. |
| Locale-correct formatting | Sorting | pass | Titles sort under the core's collation for the catalogue's language (`library::adapter` sort test). |
| Layout resilience | Long translations | not proved | Labels wrap or ellipsize; no walk in German or a pseudo-locale. |
| Layout resilience | Pseudo-locale testing | **fail** | No pseudo-locale on Linux. |
| Layout resilience | Right-to-left readiness | not proved | Labels wrap or ellipsize; no walk in German or a pseudo-locale. |
| Content language | Publication titles | seen | Titles show as the record carries them. |
| Content language | Server-provided labels | later | Servers are wave 3. |

## native-experience

Source: `docs/openspec/specs/native-experience/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Platform-native interface | iOS interface | n/a | Phone platforms. |
| Platform-native interface | Android interface | n/a | Phone platforms. |
| Platform-native interface | No cross-platform UI | seen | GTK 4 and libadwaita widgets only; walk under cage. |
| Platform-native interface | System integration | not proved | Recent files, the desktop entry and the idle inhibit are wired; no session with a file manager. |
| Platform-native interface | Home-screen quick actions | pass | The Linux reading: the desktop entry's static actions (`opening::the_desktop_entry_actions_are_the_three_the_spec_names`). |
| Platform-native interface | Continuity | n/a | Phone platforms. |
| Platform-native interface | A publication a continuity handover names is no longer there | n/a | Phone platforms. |
| Dynamic colour | Android dynamic colour | n/a | Another platform. |
| Dynamic colour | One accent on both platforms | pass | `settings::` (brand accent, chrome accent following the system, a later change, no system accent). |
| Dynamic colour | Cover-derived accent | **fail** | No colour is taken from a cover on Linux yet. |
| Dynamic colour | Chrome accent | pass | `settings::` (brand accent, chrome accent following the system, a later change, no system accent). |
| Dynamic colour | A cover that yields no usable colour | **fail** | No colour is taken from a cover on Linux yet. |
| Dynamic colour | State colour survives every scheme | not proved | Not walked. |
| Adaptive layout | Tablet and large screens | seen | walk under cage: from 1024 pixels the detail page stands beside the library (`library::detail` placement test). |
| Adaptive layout | Split View, Slide Over and multi-window | n/a | Phone and tablet shapes. |
| Adaptive layout | Theme sheet on a large screen | **fail** | No theme sheet on Linux. |
| Adaptive layout | Foldables | n/a | Phone and tablet shapes. |
| Adaptive layout | Orientation | n/a | Phone and tablet shapes. |
| Reader chrome material | iOS reader chrome | n/a | Phone platforms. |
| Reader chrome material | Android reader chrome | n/a | Phone platforms. |
| Reader chrome material | The preset grid on both platforms | **fail** | No reading theme on Linux. |
| Theme sheet reachability | Opening the sheet | **fail** | No theme sheet on Linux. |
| Theme sheet reachability | Applying a change with the sheet open | **fail** | No theme sheet on Linux. |
| Accessibility | Screen reader | not proved | Not walked with Orca, a larger text size, high contrast or reduced motion. |
| Accessibility | Dynamic Type and font scale | not proved | Not walked with Orca, a larger text size, high contrast or reduced motion. |
| Accessibility | Contrast and transparency | not proved | Not walked with Orca, a larger text size, high contrast or reduced motion. |
| Accessibility | Reduce Motion | not proved | Not walked with Orca, a larger text size, high contrast or reduced motion. |
| Accessibility | Touch targets | n/a | No touch target rule on a pointer desktop beyond the HIG's. |
| Accessibility | Keyboard and switch control | seen | walk under cage: Control and F, typing, Tab to the grid and Enter reached a publication's page; the arrows and End turned pages. |
| Accessibility | Colour is never the only signal | seen | walk under cage: an unmounted folder says *Offline* in words. |
| Performance and responsiveness | Cold launch | not proved | Not measured on Linux. |
| Performance and responsiveness | Scrolling | not proved | Not measured on Linux. |
| Performance and responsiveness | No blocking spinners | seen | No spinner anywhere: covers and pages are placeholders until they decode (walk under cage). |
| Performance and responsiveness | Memory | not proved | Not measured on Linux. |
| Visual proof of interface changes | Screen change | seen | walk under cage: light and dark captures of Home, the library, the detail page beside the library, search, the offer to add a folder and the reader. The captures were looked at and are not committed: `docs/designs/` belongs to another lane. |
| Visual proof of interface changes | Snapshot tests hold the screen states | **fail** | Linux has no snapshot tests. |
| Visual proof of interface changes | A device screenshot where only a device shows it | seen | walk under cage: light and dark captures of Home, the library, the detail page beside the library, search, the offer to add a folder and the reader. The captures were looked at and are not committed: `docs/designs/` belongs to another lane. |
| Visual proof of interface changes | Guidelines are checked by machine | **fail** | No accessibility or HIG audit runs on Linux. |
| Visual proof of interface changes | Preview is not proof | n/a | Linux has no preview mechanism; the walk ran the built app. |
| Visual proof of interface changes | Both appearances | seen | walk under cage: light and dark captures of Home, the library, the detail page beside the library, search, the offer to add a folder and the reader. The captures were looked at and are not committed: `docs/designs/` belongs to another lane. |
| The icon a reader chose | Surviving a reinstall or a restore | n/a | No alternative icons on Linux: the desktop entry names one icon. |
| The icon a reader chose | The platform refuses the change | n/a | No alternative icons on Linux: the desktop entry names one icon. |
| The icon a reader chose | The platform withdraws the ability | n/a | No alternative icons on Linux: the desktop entry names one icon. |
| The icon a reader chose | The system draws its own tinted icon | n/a | No alternative icons on Linux: the desktop entry names one icon. |
| The icon a reader chose | The platform is the only record | n/a | No alternative icons on Linux: the desktop entry names one icon. |
| Chrome for a mode a reader is in | The mode replaces its surface rather than stacking on it | **fail** | No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen. |
| Chrome for a mode a reader is in | How many are chosen, and how to leave | **fail** | No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen. |
| Chrome for a mode a reader is in | Nothing chosen yet | **fail** | No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen. |
| Chrome for a mode a reader is in | Each platform's own form | **fail** | No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen. |
| Chrome for a mode a reader is in | Every action names itself | **fail** | No selection mode on Linux: the grid selects with Control and Shift, and no bar says how many are chosen. |

## settings-and-about

Source: `docs/openspec/specs/settings-and-about/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Appearance | Choosing appearance | pass | `settings::` and `style::` (light, dark, OLED, following the system, forcing a scheme). |
| Appearance | Following the system | pass | `settings::` and `style::` (light, dark, OLED, following the system, forcing a scheme). |
| Appearance | OLED Dark is not the same as Dark | pass | `settings::` and `style::` (light, dark, OLED, following the system, forcing a scheme). |
| Appearance | Reader theme is separate | not proved | No reading theme yet; the reader follows the app's appearance. |
| Choosing the app icon | Choosing one | n/a | No alternative icons on Linux. |
| Choosing the app icon | What the platform does with it | n/a | No alternative icons on Linux. |
| Choosing the app icon | Going back to the default | n/a | No alternative icons on Linux. |
| Choosing the app icon | Where it lives | n/a | No alternative icons on Linux. |
| Choosing the app icon | The platform refuses | n/a | No alternative icons on Linux. |
| Choosing the app icon | At the largest text size | n/a | No alternative icons on Linux. |
| Choosing the app icon | Announced without sight | n/a | No alternative icons on Linux. |
| Settings organisation | Structure | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Settings organisation | Searching settings | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Settings organisation | Reading defaults | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Settings organisation | Resetting | **fail** | No reset in the Linux preferences. |
| Privacy | Privacy screen | **fail** | No privacy screen, clearing or diagnostic on Linux yet. |
| Privacy | Clearing data | **fail** | No privacy screen, clearing or diagnostic on Linux yet. |
| Privacy | Exporting a diagnostic | **fail** | No privacy screen, clearing or diagnostic on Linux yet. |
| About | About contents | not proved | The dialog exists; no walk opened it. |
| About | Support link | **fail** | `AdwAboutDialog` with the name, version and licence; no support link, acknowledgements or problem report. |
| About | Acknowledgements | **fail** | `AdwAboutDialog` with the name, version and licence; no support link, acknowledgements or problem report. |
| About | Reporting a problem | **fail** | `AdwAboutDialog` with the name, version and licence; no support link, acknowledgements or problem report. |
| What changed in this version | After an update | **fail** | Not built on Linux. |
| What changed in this version | A first ever launch | **fail** | Not built on Linux. |
| What changed in this version | Nothing worth saying | **fail** | Not built on Linux. |
| What changed in this version | Reading it again | **fail** | Not built on Linux. |
| What changed in this version | An update installed while offline | **fail** | Not built on Linux. |
| What changed in this version | At the largest text size | **fail** | Not built on Linux. |

## home-screen

Source: `docs/openspec/changes/one-library-three-destinations/specs/home-screen/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Keep reading | Resuming | seen | walk under cage: Home showed nested-chapters under *Continue reading* after it was read to page 2; a click opens it in a reader. |
| Keep reading | Order | pass | `library::home::keep_reading_comes_first_and_up_next_offers_the_next_issue` over the core's `continue_reading`. |
| Keep reading | Nothing in progress | pass | `library::home::with_no_history_both_shelves_are_absent`; walk under cage: a status page says so and offers the Library. |
| Keep reading | A publication in progress is not currently readable | **fail** | A Home card on an offline folder is not dimmed. |
| Keep reading | The card shows how far through, not only how much is left | **fail** | The card shows the title only. |
| Keep reading | Resuming is an action, not only a target | not proved | The whole card is a button that opens the reader; no walk clicked it. |
| Keep reading | A publication with nothing meaningful left | not proved | The core's rule; no Linux test. |
| Keep reading | The hero does not crowd out the rest of the surface | seen | No hero: one row of equal cards. |
| Keep reading | Every card in the row is the same size | seen | A homogeneous `GtkFlowBox` (walk under cage). |
| Keep reading | Artwork is not letterboxed | seen | Home cards fill their box (`a00124c5`). |
| Up next | The next issue of a started series | pass | `library::home` (the next issue of a started series; nothing while an issue is part-read). |
| Up next | Not the same thing as resuming | pass | `library::home` (the next issue of a started series; nothing while an issue is part-read). |
| Up next | Finishing an issue in the reader | pass | `session::a_position_reads_back_and_the_last_page_is_finished` marks the last page finished, which moves the series on (`library::home`). |
| Up next | A series with nothing after it | not proved | The core's rule (lane C); no Linux test. |
| Up next | The next issue lives on a source that is down | later | Servers are wave 3. |
| The rest of the home surface | Recently added | **fail** | No Recently added, pinned or Finished shelf on Linux Home. |
| The rest of the home surface | Pinned shelves | **fail** | No Recently added, pinned or Finished shelf on Linux Home. |
| The rest of the home surface | Finished | **fail** | No Recently added, pinned or Finished shelf on Linux Home. |
| The rest of the home surface | Every shelf leads somewhere exhaustive | **fail** | No Recently added, pinned or Finished shelf on Linux Home. |
| The rest of the home surface | A shelf that would be empty | pass | `library::home::a_shelf_with_nothing_on_it_is_absent`. |
| The home surface never waits on a source | Opening the app with every source down | seen | walk under cage: with the Manga folder offline Home and the library opened at once. |
| The home surface never waits on a source | A slow source | not proved | Scans run on a worker; no slow source walked. |
| The home surface never waits on a source | Progress recorded on another device | later | Sync is wave 3. |
| The home surface when there is little to show | A few things in progress | seen | walk under cage: one card under *Continue reading*. |
| The home surface when there is little to show | A library with nothing in it | pass | `library::home` (an empty library is the status page; no history leaves no shelf). |
| The home surface when there is little to show | A library with publications but no history | pass | `library::home` (an empty library is the status page; no history leaves no shelf). |

## navigation-shell

Source: `docs/openspec/changes/one-library-three-destinations/specs/navigation-shell/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| The destination set | Moving between destinations | seen | walk under cage: Home, Library and Downloads in the sidebar; the app opens on Home; the folders sit below and change nothing above. |
| The destination set | Each destination remembers where the reader had got to | not proved | The grid keeps its scroll while the window is open; no walk moved between destinations. |
| The destination set | Configuring sources never changes the destinations | seen | walk under cage: Home, Library and Downloads in the sidebar; the app opens on Home; the folders sit below and change nothing above. |
| The destination set | Where the app opens | seen | walk under cage: Home, Library and Downloads in the sidebar; the app opens on Home; the folders sit below and change nothing above. |
| The destination set | Every source is unreachable | not proved | Not walked. |
| Reaching search | Search is a destination, not a shape | seen | walk under cage: Control and F focuses the field in the header bar, results take over the content column, Escape returns to Home with the field in place. |
| Reaching search | What search opens onto | seen | walk under cage: Control and F focuses the field in the header bar, results take over the content column, Escape returns to Home with the field in place. |
| Reaching search | Nothing to suggest | **fail** | No suggestions and no empty state. |
| Reaching search | Leaving search | seen | walk under cage: Control and F focuses the field in the header bar, results take over the content column, Escape returns to Home with the field in place. |
| Reaching search | Searching with a source unreachable | not proved | Not walked. |
| Where a source can be reached | Narrowing to one source | **fail** | No way to narrow to one folder yet. |
| Where a source can be reached | Adding a source | seen | walk under cage: the add button in the sidebar; a folder that cannot be reached says *Offline* in its row. |
| Where a source can be reached | Reaching a source's configuration | **fail** | A folder row has no configuration; Choose Again shows only when access is withdrawn. |
| Where a source can be reached | A source stops being reachable | seen | walk under cage: the add button in the sidebar; a folder that cannot be reached says *Offline* in its row. |
| The destination set on a large screen | A wide window | seen | walk under cage: sidebar, content and the detail pane at 1280 pixels. |
| The destination set on a large screen | Resizing back down | not proved | The sidebar collapses below 600 sp; no resize walk. |
| The destination set on a large screen | More shelves than the navigation can show | n/a | Three destinations always fit the sidebar. |
| Chrome that gets out of the way | Scrolling through covers | n/a | On a desktop the header bar stays and holds the search field (`desktop-experience`, Search on a desktop). |
| Chrome that gets out of the way | The control can always be recovered | n/a | On a desktop the header bar stays and holds the search field (`desktop-experience`, Search on a desktop). |
| Chrome that gets out of the way | Reduced motion | not proved | Not walked. |

## publication-detail

Source: `docs/openspec/changes/publication-detail/specs/publication-detail/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reaching a publication's page | From a cover | seen | walk under cage: Enter on a cover opened its page. |
| Reaching a publication's page | Resuming does not come here | not proved | A Home card opens the reader directly; no walk clicked one. |
| Reaching a publication's page | The same page for every kind of publication | not proved | Only comics read on Linux in wave 2. |
| Reaching a publication's page | A publication that is no longer there | not proved | Read names *the file cannot be reached* in grey; not walked. |
| What the page shows | The cover leads | seen | walk under cage: the cover leads, then the title, the line under it, the primary action and the menu. |
| What the page shows | Other issues in this series | **fail** | No other-issues shelf on the Linux page. |
| What the page shows | Metadata the publication does not carry | pass | `library::detail` builds the line under the title only from what the record has. |
| What the page shows | No cover art | not proved | The cover's placeholder card stands in; no capture of a detail page without a cover. |
| One primary action | Reading from here | seen | walk under cage: *Continue Reading · 20%*. |
| One primary action | No copy on the device, and a library that answers | later | Servers are wave 3. |
| One primary action | A publication the app reads where it stands | pass | `library::detail` (Read, Continue Reading with its percentage, Read Again, and disabled for a folder that cannot be read). |
| One primary action | Everything else | seen | One menu beside the primary action: Show in Files. |
| One primary action | Downloading from here | later | Wave 3. |
| One primary action | The copy arrives while the page is open | later | Wave 3. |
| One primary action | The primary action cannot be honoured | pass | `library::detail` (Read, Continue Reading with its percentage, Read Again, and disabled for a folder that cannot be read). |
| Where it came from | What the line says | pass | `library::detail::a_publication_with_no_cover_and_no_history_offers_read_and_names_its_folder`; walk under cage: *In comics · /tmp/comics/nested-chapters.cbz*. |
| Where it came from | What the line never says | not proved | Not walked. |
| Where it came from | The same publication in two places | later | Servers are wave 3. |
| Where it came from | Its source has been removed | not proved | No way to remove a folder yet. |
| Colour taken from the cover | The wash | **fail** | No colour is taken from the cover: the wash is a plain box. |
| Colour taken from the cover | Contrast is not negotiable | **fail** | No colour is taken from the cover: the wash is a plain box. |
| Colour taken from the cover | Chrome does not take it | seen | The chrome keeps the app accent. |
| Colour taken from the cover | A cover that yields nothing usable | **fail** | No colour is taken from the cover: the wash is a plain box. |
| Colour taken from the cover | High contrast and reduced transparency | not proved | Not walked. |
| The page on a large screen | Two panes | seen | walk under cage: the page beside the library at 1280 pixels, the grid still visible. |
| The page on a large screen | The pane before anything is chosen | seen | walk under cage: *No Publication Chosen. Choose a cover to see its page here.* |
| The page on a large screen | The window narrows | not proved | `detail_panes.rs` moves the page between the pane and a pushed page; no resize walk. |
| The page on a large screen | Going back | not proved | The pushed page has the header bar's back button; not walked. |

## cover-art

Source: `docs/openspec/changes/cover-for-every-publication/specs/cover-art/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| The cover ladder | The publication's own bytes answer | seen | walk under cage: a placeholder card, then the first page decoded by the core. |
| The cover ladder | A cover image sits beside the file | **fail** | The Linux ladder does not look beside the file. |
| The cover ladder | The source states a cover | later | Servers are wave 3. |
| The cover ladder | Nothing answers | seen | walk under cage: a placeholder card, then the first page decoded by the core. |
| A reader may choose a cover | Choosing a picture | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| A reader may choose a cover | A chosen cover outlives a rename | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| A reader may choose a cover | A publication with no digest | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| A reader may choose a cover | Undoing the choice | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| A reader may choose a cover | The cover's actions are one menu | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| A reader may choose a cover | The chosen cover survives a cache clear | later | Not in wave 2 (`tasks.md`, coverage: the ladder only). |
| Looking a cover up is the reader's choice | The lookup is off until it is turned on | later | Not in wave 2. |
| Looking a cover up is the reader's choice | Asking by an identifier the file carries | later | Not in wave 2. |
| Looking a cover up is the reader's choice | Asking by a title, and confirming the answer | later | Not in wave 2. |
| Looking a cover up is the reader's choice | A provider refuses or rate-limits | later | Not in wave 2. |
| Looking a cover up is the reader's choice | Every answer is cached | later | Not in wave 2. |
| Finding a cover on the web is a hand-off | The hand-off | later | Not in wave 2. |
| Finding a cover on the web is a hand-off | The app downloads nothing | later | Not in wave 2. |
| Writing a cover back to a source | A Kavita reading list the reader owns | later | Servers are wave 3. |
| Writing a cover back to a source | A Kavita series, chapter, collection or library | later | Servers are wave 3. |
| Writing a cover back to a source | An OPDS catalogue | later | Servers are wave 3. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported desktop systems | A supported system | seen | Built and run on Ubuntu 24.04 with GTK 4.14.5 and libadwaita 1.5.0, the floor. |
| Supported desktop systems | A system below the floor | n/a | Other systems. |
| Supported desktop systems | A Linux build below the floor | not proved | No build below the floor was tried. |
| Supported desktop systems | A Linux system without an optional service | seen | walk under cage: no session bus and no portal; the app ran, the accent choice was absent. |
| The interface accent and the system appearance | The default accent | pass | `settings::` and `portal::tests` (part one). |
| The interface accent and the system appearance | Following the system accent | pass | `settings::` and `portal::tests` (part one). |
| The interface accent and the system appearance | A system with no accent colour | pass | `settings::` and `portal::tests` (part one). |
| The interface accent and the system appearance | The system switches appearance | not proved | Not walked; light and dark were forced per launch. |
| The interface accent and the system appearance | A system that does not state its appearance | pass | `settings::` and `portal::tests` (part one). |
| The window model | Opening a publication | seen | walk under cage: a reader window per opened file. |
| The window model | Opening a publication that is already open | pass | `windows::` (one window per publication, a second open presents the first). |
| The window model | Two publications side by side | not proved | cage shows one window at a time. |
| The window model | A reader window whose publication disappears | pass | `publication::a_publication_that_disappears_is_named_in_grey_and_one_that_returns_is_not`. |
| Windows come back after a quit or a crash | Relaunch after a quit | pass | `windows::` (round trip, a gone display, a missing publication) and `progress::tests`; no relaunch walk with readers open. |
| Windows come back after a quit or a crash | A display that is gone | pass | `windows::` (round trip, a gone display, a missing publication) and `progress::tests`; no relaunch walk with readers open. |
| Windows come back after a quit or a crash | A publication that cannot be reopened | pass | `windows::` (round trip, a gone display, a missing publication) and `progress::tests`; no relaunch walk with readers open. |
| Windows come back after a quit or a crash | The app ended without warning | pass | `windows::` (round trip, a gone display, a missing publication) and `progress::tests`; no relaunch walk with readers open. |
| Closing a window and quitting the app | Progress while reading | pass | `progress::tests` (five-second clock, close and quit writes, a failing store stops nobody). |
| Closing a window and quitting the app | Closing a reader window | seen | walk under cage: Control and W closed the reader, and the next launch's Home showed the page it was on. |
| Closing a window and quitting the app | Quitting | not proved | Control and Q not walked. |
| Closing a window and quitting the app | A write that fails | pass | `progress::tests` (five-second clock, close and quit writes, a failing store stops nobody). |
| Closing a window and quitting the app | Closing the last window on each system | seen | walk under cage: closing the last window ended the process. |
| No presence when the app is closed | After quitting | seen | walk under cage: the process ended with its last window; nothing stays resident. |
| No presence when the app is closed | A download in progress | later | Downloads and refreshes are wave 3. |
| No presence when the app is closed | A finished download or a refresh | later | Downloads and refreshes are wave 3. |
| Menus, commands and shortcuts | Every command is in a menu | pass | `commands::` (every command, its key and its window; disabled where it does not apply). |
| Menus, commands and shortcuts | The standard shortcuts | pass | `commands::` (every command, its key and its window; disabled where it does not apply). |
| Menus, commands and shortcuts | A command that does not apply | pass | `commands::` (every command, its key and its window; disabled where it does not apply). |
| Menus, commands and shortcuts | A shortcut while typing | pass | `commands::` (every command, its key and its window; disabled where it does not apply). |
| Menus, commands and shortcuts | A shortcut another application holds | not proved | Not walked. |
| Full keyboard navigation | Tabbing through the library | seen | walk under cage: Tab reached the grid from the search field and Enter opened the page. |
| Full keyboard navigation | Acting on a focused item | seen | walk under cage: Tab reached the grid from the search field and Enter opened the page. |
| Full keyboard navigation | Leaving a book's text | later | EPUB is wave 4. |
| Full keyboard navigation | A dialog | not proved | Not walked. |
| Keys that turn pages | Left-to-right | pass | `keys::` (by direction, at the end, in a text field) and `reading::spread` (a turn moves one screen); walk under cage: Right and End turned. |
| Keys that turn pages | Right-to-left | pass | `keys::` (by direction, at the end, in a text field) and `reading::spread` (a turn moves one screen); walk under cage: Right and End turned. |
| Keys that turn pages | A key at the end | pass | `keys::` (by direction, at the end, in a text field) and `reading::spread` (a turn moves one screen); walk under cage: Right and End turned. |
| Keys that turn pages | A key held down | not proved | Writes coalesce (`progress::tests`); no held-key walk. |
| Search on a desktop | Opening search | seen | walk under cage: Control and F, typing, Escape. |
| Search on a desktop | Leaving search | seen | walk under cage: Control and F, typing, Escape. |
| Pointer reading | Revealing chrome | not proved | `keys::` zone and chrome rules pass; no pointer in the walk. |
| Pointer reading | A context menu | not proved | `keys::` zone and chrome rules pass; no pointer in the walk. |
| Pointer reading | Edge click zones | pass | `keys::` click zones. |
| Pointer reading | Selecting text and moving the window | later | Text is wave 4. |
| Pointer reading | A pointer that is not there | not proved | `keys::` zone and chrome rules pass; no pointer in the walk. |
| Zoom and pan with a pointer | Pinch and wheel | pass | `reading::zoom` (pinch and wheel, double click, limits); the wheel turns a fitted page (`keys::` wheel notches) and pans a larger one. |
| Zoom and pan with a pointer | Double click | pass | `reading::zoom` (pinch and wheel, double click, limits); the wheel turns a fitted page (`keys::` wheel notches) and pans a larger one. |
| Zoom and pan with a pointer | Plain wheel on a page that fits | pass | `reading::zoom` (pinch and wheel, double click, limits); the wheel turns a fitted page (`keys::` wheel notches) and pans a larger one. |
| Zoom and pan with a pointer | Zoom keys and the limits | seen | `reading::zoom::keys_step_in_and_out_and_never_pass_the_limits_silently`; walk under cage: Control and plus. |
| Dragging to turn a page | A drag past the threshold | pass | `reading::drag` (threshold, short of it, mirrored). |
| Dragging to turn a page | A drag short of the threshold | pass | `reading::drag` (threshold, short of it, mirrored). |
| Dragging to turn a page | The curl follows the pointer | later | The curl is wave 5. |
| Dragging to turn a page | The curl where it is not available | later | The curl and its absent-in-grey note are wave 5. |
| Two-page spreads by window shape | A wide window | pass | `reading::spread`; walk under cage. |
| Two-page spreads by window shape | A narrow window | pass | `reading::spread`; walk under cage. |
| Two-page spreads by window shape | The last page of an odd count | pass | `reading::spread`; walk under cage. |
| Two-page spreads by window shape | A page that has not loaded | not proved | The other page shows and the missing one is a quiet block (`page_view.rs`); no walk caught one. |
| Full screen reading | Entering and leaving | pass | `fullscreen::tests` (part one). |
| Full screen reading | Chrome in full screen | not proved | Not walked. |
| Full screen reading | A system that refuses | pass | `fullscreen::tests` (part one). |
| Dropping files and folders on the app | Dropping a publication | not proved | A drop target on every window; no drag in the walk. |
| Dropping files and folders on the app | Dropping a folder | seen | walk under cage: a folder handed over is offered with *Add Folder?* (the drop takes the same path). |
| Dropping files and folders on the app | Dropping several files | pass | `opening::` (each file once, a folder offered, the unreachable named, past the limit listed). |
| Dropping files and folders on the app | Dropping what cannot be opened | seen | walk under cage: the CB7 named, a missing file named, nothing else lost. |
| Dropping files and folders on the app | A drop that is not a file | not proved | The target accepts only a file list; not walked. |
| File associations and Open With | Double click while the app is not running | seen | walk under cage: a path on the command line opens a reader and no library window. |
| File associations and Open With | Double click while the app is running | not proved | A second launch reaches the first through `GApplication`; cage ran one launch at a time. |
| File associations and Open With | The command line | seen | walk under cage: a path on the command line opens a reader and no library window. |
| File associations and Open With | A file that cannot be reached | pass | `opening::a_file_that_cannot_be_reached_is_named_and_the_others_still_open`. |
| File associations and Open With | Recently opened files | not proved | Each opened file is added to `GtkRecentManager`; no file manager in the walk. |
| Choosing folders and keeping access | Adding a folder | not proved | Add Folder opens `GtkFileDialog`; no portal in the container, and not proved in a Flatpak. |
| Choosing folders and keeping access | Access across relaunches | seen | walk under cage: every launch read the folder back from the sources file without a prompt. |
| Choosing folders and keeping access | Access withdrawn | pass | `folders::` (the sources file, a portal grant, withdrawn, offline). |
| Choosing folders and keeping access | A folder on an unmounted volume | seen | walk under cage: a folder that is not mounted reads *Offline* in grey and keeps its place. |
| Live folder watching | A file added while the app is open | not proved | The core's `FolderWatcher`, polled for a portal grant and named *Not watched live* once; no walk added files. |
| Live folder watching | The system cannot watch more | not proved | The core's `FolderWatcher`, polled for a portal grant and named *Not watched live* once; no walk added files. |
| Live folder watching | Changes while the app was not running | not proved | The core's `FolderWatcher`, polled for a portal grant and named *Not watched live* once; no walk added files. |
| Live folder watching | A burst of changes | not proved | The core's `FolderWatcher`, polled for a portal grant and named *Not watched live* once; no walk added files. |
| Keeping the display awake while reading | Reading in front | pass | `idle::tests`. |
| Keeping the display awake while reading | Listening | later | Audio is wave 4. |
| Keeping the display awake while reading | A system that cannot be asked | pass | `idle::tests`. |
| Text size, contrast and motion follow the system | A larger text size | not proved | Not walked. |
| Text size, contrast and motion follow the system | Increased contrast | not proved | Not walked. |
| Text size, contrast and motion follow the system | Reduced motion | not proved | Not walked. |
| Any window size | A narrow window | not proved | No resize walk; cage gives the window one size. |
| Any window size | A wide window | seen | walk under cage: 1280 pixels, two panes. |
| Any window size | A window below the minimum | pass | `window_state::` minimum size. |
| Any window size | Resizing a reader | pass | `reading::spread::a_narrow_window_keeps_the_reader_on_the_same_page_one_per_slot`. |
| Linux display servers and tiling compositors | A Wayland session | seen | walk under cage: `GDK_BACKEND=wayland` under a wlroots compositor; fractional scaling not tried. |
| Linux display servers and tiling compositors | An X11 session | not proved | Not walked. |
| Linux display servers and tiling compositors | A compositor that draws no title bar | seen | walk under cage: cage draws no decoration and the app's header shows its menu and close control; Control and W closed the window. |
| Linux display servers and tiling compositors | A stable identity | not proved | Not walked. |
| Linux display servers and tiling compositors | A tiled window of any size | not proved | Not walked. |
| Linux display servers and tiling compositors | A missing portal | pass | `portal::closing_the_chooser_is_not_a_failure_and_a_missing_portal_is`; the chooser's absence is named once. |
| Recent items in the system's launcher | Recent publications | n/a | The Dock menu and the Jump List. |
| Recent items in the system's launcher | A publication that is gone | n/a | The Dock menu and the Jump List. |
| Recent items in the system's launcher | Recent publications on Linux | pass | `opening::the_desktop_entry_actions_are_the_three_the_spec_names`; each opened file goes to `GtkRecentManager`. |
| Recent items in the system's launcher | Clearing the history | **fail** | No clearing of history on Linux yet. |
| Recent items in the system's launcher | A launcher with no menu | seen | walk under cage: Home's *Continue reading* shows the publication read last. |
| Preferences in their own window | Opening the preferences | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Preferences in their own window | Searching the preferences | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Preferences in their own window | Preferences while a reader is open | not proved | `AdwPreferencesDialog` with search (part one); no walk. |
| Language follows the system | A supported language | pass | `strings::`. |
| Language follows the system | An unsupported language | pass | `strings::`. |
| Language follows the system | A long translation | not proved | Not walked. |
| The same formats on every desktop | The formats | later | EPUB and PDF are wave 4, audio is wave 4; CBZ, CBR and CBT read. |
| The same formats on every desktop | A CB7 archive | pass | `publication::` (CB7 refused by name, a page the core cannot decode names its reason). |
| The same formats on every desktop | An image the system cannot decode | pass | `publication::` (CB7 refused by name, a page the core cannot decode names its reason). |
| The same formats on every desktop | A large publication | not proved | Remote reading is wave 3. |
| Storage on a desktop | Where the data lives | pass | The store opens where `StorageLocations::current()` says (core `paths` tests, lane C). |
| Storage on a desktop | A full disk | not proved | Not walked; a failed write is logged and holds nothing (`progress::tests`). |
| Storage on a desktop | Removing the app | not proved | Not walked. |
| Cold start and responsiveness on a desktop | Cold launch | not proved | Not measured. |
| Cold start and responsiveness on a desktop | Resizing and scrolling | not proved | Not measured. |
| Cold start and responsiveness on a desktop | A source that is slow or offline | seen | walk under cage: the offline folder delayed nothing. |
| Visual proof of interface changes on a desktop | A change to a screen | seen | walk under cage, light and dark, looked at before each commit. |
| Visual proof of interface changes on a desktop | A Linux change | seen | walk under cage, light and dark, looked at before each commit. |
| Visual proof of interface changes on a desktop | A system that cannot be captured | n/a | Linux was captured. |
## Wave 2 tasks, lane L

What each task built, what a test proves, and what a Linux host still owes. Part one (2.25 to 2.27, 2.29, 2.32 to
2.35, 2.35e) is unchanged from the first half of this wave except where named.

| Task | Built | Test proof | A Linux host still owes |
| --- | --- | --- | --- |
| 2.25 Reader windows and restoration | One window per publication, restored from the session file; the reader now opens through the core's `OpenPublication`. | `windows::`, `publication::tests`. | A walk with two readers, a quit, a relaunch and a monitor taken away. |
| 2.26 Menus and commands | Unchanged. | `commands::`. | A walk of the menus and the shortcuts dialog. |
| 2.27 Keys and pointer | The key controller now runs in the capture phase, so an arrow turns before a header button takes it (`7c6ab11b`). | `keys::`. | A pointer walk: hover chrome, edge clicks, the wheel, on Wayland and X11. |
| 2.28 Zoom, pan, spreads, drag | `reading/` holds Rust copies of lane M's `ZoomModel`, `SpreadDecision` and `DragTurn` with the same tests, over the core's `SpreadLayout`. `page_view.rs` draws the screen's decoded pages, fitted (page, width or original size), zoomed, panned and slid by a drag, clipped to its area. Pages decode on a worker through `OpenPublication::decode_page`, the screens either side are asked for ahead, and a page still decoding is a quiet block. Pinch, Control and the wheel, a double click and Control with plus, minus and 0 zoom; a drag pans a page larger than the window and turns a fitted one past the threshold. | `reading::zoom`, `reading::spread`, `reading::drag`, `page_view::tests`, `publication::tests`. | A resize walk (one page to two and back on the same page) and a pointer walk of the drag and the pinch. |
| 2.29 Full screen | Unchanged. | `fullscreen::tests`. | Captures on GNOME, KDE Plasma and COSMIC, and the grey note on Hyprland. |
| 2.30 Opening files | The desktop entry declares the comic types, `Exec=storyarc %F` and the static actions Continue Reading, Library and Downloads (`--continue-reading`, `--library`, `--downloads`); the application is built with `HANDLES_OPEN`, so a second launch hands its files and its action to the first through `GApplication`. Every window takes dropped files; Open File uses `GtkFileDialog`. Each opened file is recorded with `GtkRecentManager`. A CB7 or any refused file is named with its reason, and past ten files the rest are listed. | `opening::`, `publication::tests`; `desktop-file-validate` in the gate. | A walk opening a file from the file manager, a second launch with a file, a real drop, and the recent file seen in a file dialog. |
| 2.31 Folders through the portal | `GtkFileDialog::select_folder`, a sources file, the core's `FolderSource` scanned on a worker, the core's `FolderWatcher` (polled at the core's interval of 5 seconds for a portal grant, named *Not watched live* once), access looked at every 10 seconds: a withdrawn grant turns grey with Choose Again, an unmounted volume reads *Offline* and returns by itself. A missing file chooser is named once. A folder handed over is offered with *Add Folder?*. | `folders::`, `portal::tests`. | A Flatpak run and a source-build run, with captures of the withdrawn state. |
| 2.32 Closing and quitting | Positions now go to the core's progress store; the last page counts as finished. | `progress::tests`, `session::tests`. | A Hyprland capture of the header bar with Control and W and Control and Q. |
| 2.33 Display, appearance, any size | Unchanged. | `style::`, `settings::`. | Captures on X11, fractional scaling, a resize walk down to 360 px. |
| 2.34 Idle inhibit | Unchanged. | `idle::tests`. | Walks on Hyprland and KDE. |
| 2.35 Preferences dialog | Unchanged. | `settings::`. | A walk with a reader open. |
| 2.35a Grid and list | `GtkGridView` and `GtkListView` over one `GListModel` of the core's publications, `GtkMultiSelection` for Control and Shift clicks, the cover ladder (`covers.rs`: a placeholder card, then the first page decoded at 360 px on a worker, never blocking a scroll), covers shown whole, a progress rail, and a cell for each file a scan could not open with its reason. | `library::grid`, `library::entry`, `library::adapter`. | A scroll of a 10,000-publication library on Wayland and X11. |
| 2.35b Search, filters, sorting | A `GtkSearchEntry` in the header bar whose results take over the content column, Escape returning to the destination; a Filter menu (format, reading state) and a Sort menu, all handed to the core's `LibraryIndex::arrange` under the reader's collation. | `library::query`, `library::adapter`. | A walk that filters and sorts. |
| 2.35c Home | Keep Reading and Up Next from the core's rules, an absent shelf when empty, an `AdwStatusPage` for an empty library and another for a library with no history. | `library::home`. | A walk with and without history (done under cage, see the tables). |
| 2.35d Publication detail | A pushed `AdwNavigationPage` below 1024 pixels, a pane beside the library from 1024 (`detail_panes.rs`) with one sentence before a cover is chosen; the cover, one primary action, a menu with Show in Files, and the line naming the folder and the path. | `library::detail`. | A resize walk across 1024 pixels. |
| 2.35e Chrome accent | Unchanged. | `settings::`, `portal::tests`. | Captures on libadwaita 1.6 or newer and on 1.5. |
| 2.36 Conformance walk | This page. | The tables above. | The rows marked not proved. |

## Deviations and owed items

- The branch merged `lane/core-wave2` with one conflict, in `apps/desktop-core/storyarc-ffi/build.rs`: both sides carried
  the read-only build fix, and lane C's side added the status-code filter. The merge takes lane C's file unchanged.
- The worktree that held `lane/linux-wave2` was still registered, so this session worked on its own branch from the
  same head; the report names it.
- Preferences still live in a `key=value` file under the app's data directory, not GSettings, until the packaging lane
  installs a compiled schema.
- The folder poll is the core's default of 5 seconds, inside the 10 seconds or less the spec allows; the access look is
  every 10 seconds.
- The cover wash on the detail page is a plain box: no colour is taken from the cover yet.
- Strings this branch added are English only: the folder rows (*Folders*, *Offline*, *Needs access*, *Choose Again…*,
  *Not watched live…*), the filter and sort menus, the detail page (*Read*, *Continue Reading*, *Read Again*, *Show in
  Files*, *pages*, *In*), the pane placeholder, the Home status pages, *Add Folder?* and the chooser note. The
  catalogue's own keys are used where it has them (`home.keepReading`, `home.upNext`, `home.nothingOpen`,
  `library.addSource`, `sidebar.*`).
- The Theme parser warns that `overflow` is not a GTK property: it comes from the generated tokens stylesheet, not from
  this branch.
