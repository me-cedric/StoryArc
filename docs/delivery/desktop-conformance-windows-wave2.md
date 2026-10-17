# Windows wave 2 conformance walk (task 2.48)

Status: a walk by a reader of the code, written without a .NET SDK and without Windows. Nothing
here has compiled or run. The `Desktop Windows` workflow is the first compiler, the interop jobs
on the Linux and macOS runners are the first run of the tests named below, and a walk on a
Windows 11 24H2 machine is the only proof of a screen.

Each row names the code, the test that pins the pure part, and one of four states:

- **tested**: a pure rule in `StoryArc.Interop` with a test in `StoryArc.Interop.Tests`, or a seam
  call exercised against `packages/test-fixtures`. Passing awaits the first CI run.
- **wired, not proved**: the WinUI code calls the tested rule; proving it needs a Windows desktop.
- **not proved (needs Windows)**: the scenario is only visible on a Windows desktop and nothing on
  this host can stand in for it.
- **not started**: no code yet.

No scenario here is marked passed. No capture has been made: every screen task also owes captures
in light and dark, at default and at the largest text size, which need a Windows desktop.

## The seam (task 2.1 as bound by lane W)

| What | Where | Test | State |
| --- | --- | --- | --- |
| Every status code has its name | `StoryArcStatus` | `NativeCoreSeamTests.Every_status_the_header_defines_has_its_name_here` | tested |
| A folder lists its publications | `ComicFolder` | `A_folder_lists_its_publications_as_records` | tested |
| A refused or locked file is left out of a folder | `ComicFolder` | `A_refused_or_locked_file_is_left_out_of_the_folder_and_the_rest_still_lists` | tested |
| A missing folder is `NotFound` and named | `ComicFolder` | `A_folder_that_is_not_there_is_not_found_and_named` | tested |
| A raised token cancels a scan | `ComicFolder`, `CancelToken` | `A_raised_cancel_token_stops_the_scan_and_hands_back_nothing` | tested |
| Page count and metadata as the manifest says | `ComicPublication` | `A_publication_answers_its_page_count_and_metadata_as_the_manifest_says` | tested |
| A page decodes to RGBA at the asked size | `ComicPublication.DecodePage` | `A_page_decodes_to_rgba_at_the_size_asked_and_at_its_own_size` | tested |
| A refused codec is named; a page past the end is refused | `DecodePage` | `A_page_in_a_codec_the_build_refuses_names_the_codec_and_an_index_past_the_end_is_refused` | tested |
| CB7 refused by name; a password is unreadable | `ComicPublication.Open` | `A_CB7_archive_is_refused_by_name`, `A_password_protected_archive_is_unreadable` | tested |
| CBR, CBT and CBZ open with the manifest page counts | `ComicPublication.Open` | `Each_container_opens_with_the_manifest_page_count` (CBR skipped on Windows until the MSVC libarchive header) | tested |
| A disposed handle never reaches the core | `CoreHandle` | `A_handle_used_after_dispose_throws_instead_of_reaching_the_core` | tested |
| Progress written and read back by digest | `ProgressStore` | `A_progress_record_is_written_and_read_back_by_its_digest` | tested |
| A bad record is refused and the store keeps working | `ProgressStore` | `A_record_that_is_not_one_is_refused_and_the_store_keeps_working` | tested |

## desktop-experience

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| The window model: opening a publication | `AppHost.OpenReaderAsync`, `ReaderWindow` | `WindowRegistryTests` | wired, not proved |
| Opening a publication that is already open | `WindowRegistry`, `AppHost.OpenReaderAsync` | `WindowRegistryTests` | wired, not proved |
| Two publications side by side | one `PageNavigator` per window | `PageNavigatorTests` | wired, not proved |
| A reader window whose publication disappears | `ReaderPageView` keeps decoded pages, `ShowUnavailable` in grey | none | wired, not proved |
| Relaunch after a quit; the app ended without warning | `SessionRecorder`, `RestorationPlan` | `SessionRecorderTests`, `WindowStateTests` | wired, not proved |
| A display that is gone | `WindowFrame.FitTo` | `WindowStateTests` | wired, not proved |
| A publication that cannot be reopened | `RestorationPlan.From(saved, File.Exists)`, named in the library | `WindowStateTests` | wired, not proved |
| Progress while reading; closing a reader window; quitting | `ProgressWriter` over `CoreProgressStore` | `ProgressWriterTests`, `CoreProgressStoreTests` | wired, not proved |
| A write that fails | `ProgressWriter.Failures` | `A_publication_the_store_does_not_know_is_a_named_failure_and_stays_unsaved` | tested; the diagnostic that names it is not started |
| Closing the last window on Windows | `WindowRegistry.LastWindowClosed`, `AppHost.Exit` | `WindowRegistryTests` | wired, not proved |
| Every command is in a menu; a command that does not apply | `CommandTable`, `CommandRouting`, `MenuBuilder` | `CommandTableTests`, `CommandRoutingTests` | wired, not proved |
| The standard shortcuts | `CommandTable` | `CommandRoutingTests` | wired, not proved |
| A shortcut while typing | plain keys are never accelerators; the reader leaves keys in its chrome to the chrome | by construction | not proved (needs Windows) |
| Keys that turn pages: left-to-right, right-to-left, a key at the end | `PageKeyMapper`, `PageNavigator`, `ReaderWindow.OnKeyDown` on `PreviewKeyDown` | `PageKeyMapperTests`, `PageNavigatorTests.A_turn_at_either_end_does_nothing` | wired, not proved |
| A key held down | system key repeat, one turn per repeat | none | not proved (needs Windows) |
| Search on a desktop: opening and leaving search | `AutoSuggestBox` in `TitleBar.Content`, `LibraryQueryState` | `LibraryQueryStateTests` | wired, not proved |
| Pointer reading: revealing chrome, edge click zones | `HoverChrome`, `EdgeClickZones`, `CursorHider`, a click held back 250 ms for a double click | `PointerReadingTests` | wired, not proved |
| A context menu | the library cells' Open and Show details | none | wired, not proved; the reader's page has none yet |
| Zoom: pinch and wheel, double click, zoom keys and limits | `ScrollViewer` zoom 1 to 6, `PageZoom`, `ReaderPageView.ZoomTo` | `PageZoomTests` | wired, not proved |
| Plain wheel on a fitted page turns it | `ReaderWindow.OnPageWheel`, one turn per 120 units | none | wired, not proved |
| Dragging to turn a page, past and short of the threshold | `DragTurn`, the page follows the pointer | `DragTurnTests` | wired, not proved |
| The curl follows the pointer; the curl where it is not available | | | not started (task 1.19, wave 5) |
| Two-page spreads: wide, narrow, odd last page, a page not loaded | `PageNavigator`, `SpreadLayout`, placeholders in `ReaderPageView` | `PageNavigatorTests`, `SpreadLayoutTests` | wired, not proved |
| Full screen: entering and leaving, chrome, a system that refuses | `FullScreenState`, `AppWindow.SetPresenter` | `FullScreenStateTests` | wired, not proved; the grey sentence on refusal is not shown |
| Dropping a publication, several files, what cannot be opened, a drop that is not a file | `Drops`, `OpenRequest.Plan`, `AppHost.OpenPaths` | `OpeningTests` | wired, not proved |
| Dropping a folder | `MainWindow.OfferFolderAsync` asks first | `A_dropped_folder_is_offered_as_a_library_and_not_opened` | wired, not proved |
| Double click while the app is not running | `Package.appxmanifest` `windows.fileTypeAssociation` (ProgID `storyarc.comicarchive`), `Activations.Read` | `The_package_claims_only_what_the_core_opens_page_by_page_and_never_cb7` | not proved (needs Windows) |
| Double click while the app is running | `Program.Main`, `AppInstance.FindOrRegisterForKey`, `RedirectActivationToAsync` | none | not proved (needs Windows) |
| The command line | `storyarc.exe` execution alias, `LaunchArguments` | `The_command_line_splits_as_windows_splits_it`, `A_launch_argument_string_gives_its_paths_with_or_without_the_executable` | not proved (needs Windows) |
| A file that cannot be reached | `OpenRequest` `NotFound`, named in the library | `A_file_that_cannot_be_reached_is_named_and_nothing_else_opens_for_it` | wired, not proved |
| Recently opened files; recent publications in the Jump List; a publication that is gone | `RecentItems`, `JumpLists.UpdateAsync` | `The_recent_list_is_newest_first_one_entry_per_file_and_capped`, `A_recent_file_that_is_gone_drops_out_without_an_error` | not proved (needs Windows; no Jump List capture) |
| Clearing the history | `LibraryService.ClearRecent` | none | wired, nothing in the interface calls it yet |
| Adding a folder; access across relaunches | `FolderPicker`, `FolderSourceList` in `sources.json` | `A_chosen_folder_is_stored_once_and_survives_a_relaunch` | wired, not proved |
| Access withdrawn; a folder on an unmounted volume | `FolderSourceList.Classify`, grey source buttons, choose again | `A_scan_leaves_the_source_available_offline_or_needing_access`, `An_unplugged_folder_is_not_found_by_the_core_and_classified_offline` | wired, not proved (no walk with a disconnected volume) |
| A file added while the app is open | `FileSystemWatcher` schedules, `RescanSchedule`, the rescan is the core's folder scan | `A_burst_of_changes_is_one_rescan_after_a_quiet_moment`, `A_file_added_to_a_folder_appears_in_the_next_scan_through_the_core` | wired, not proved |
| The system cannot watch more | a share or a failed watcher polls every 10 s and on focus, with one grey note | `A_folder_that_cannot_be_watched_is_polled_and_scanned_on_focus` | wired, not proved |
| Changes while the app was not running | the core reconciles by modification time and size | lane C's tests | wired, not proved |
| A burst of changes | `RescanSchedule` | `A_folder_that_never_goes_quiet_is_still_scanned_within_ten_seconds` | wired, not proved |
| Keeping the display awake | `DisplayKeepAwake` | `DisplayKeepAwakeTests` | tested; not yet called from the reader window |
| Screen readers: a page turn, what could not be opened | page label `LiveSetting`, `RaiseAutomationEvent`; the refusals `InfoBar` | none | not proved (needs Windows, Narrator) |
| Text size, contrast and motion | | | not started in this part (task 2.45) |
| Any window size | `NavigationView` Auto, the menu's overflow under 720 | none | not proved (needs Windows) |
| Preferences in their own window: opening, searching, while a reader is open | `PreferencesPage`, `PreferencesIndex` | `PreferencesIndexTests` | wired, not proved |
| The same formats on every desktop; a CB7 archive; an image the system cannot decode | the core's decoder, named refusals | the seam tests above | tested through the seam; EPUB, PDF and audio are later waves |

## Other capabilities walked

| Capability | What holds | State |
| --- | --- | --- |
| `comic-reader` | page order, pairs, keys, zoom, drag over the core's decoder | wired, not proved |
| `page-transitions` (not the curl) | a turn is a cut; the slide of the settings is not drawn yet | not started beyond the setting |
| `library-browsing` | `ItemsView` grid and list, filters, sorts, search in the title bar | wired, not proved; grouping by series is in the view model only |
| `local-library` | folder sources through the core | wired, not proved |
| `publication-formats` | CBZ, CBR, CBT through the core; CB7 refused | tested through the seam |
| `reading-progress` | the cadence and the core's store | tested; not proved on Windows |
| `reading-themes` | appearance choice through `AppearanceTheme` | wired, not proved; OLED Dark and Natural fall back to the nearest theme |
| `localization` | every new label reads the generated `.resw` through `Strings.Get` | wired; see the missing keys below |
| `native-experience` | WinUI controls only, Mica, `TitleBar` | not proved (needs Windows) |
| `settings-and-about` | the preferences page of part one | wired, not proved |
| `home-screen` | `HomeShelves`: Continue reading and Up next, an empty shelf absent | tested; the view is wired, not proved |
| `navigation-shell` | Home, Library, Downloads in the pane, search in the title bar, settings in the pane | wired, not proved |
| `publication-detail` | `PublicationDetail`: cover wash or placeholder, one primary action, the location line | tested; the page is wired, not proved |
| `cover-art` | the first page decoded at 480 px when a cell is realised | wired, not proved; the cover is page one, not the record's `coverPath` |

## Not done in this part

- The cover is the first page: the seam names a cover by its entry path (`coverPath`) and decodes by
  index, so a comic whose cover is not its first page (the manga fixture) shows the wrong cover.
- The seam has no watch export. Live watching is a `FileSystemWatcher` in the app that schedules a
  rescan through the core's folder scan; the scan and its reconcile are the core's.
- The seam's record carries no declared spreads; a spread stands alone once it decodes landscape.
- A file that could not be opened is listed in the library's What couldn't be opened bar, not as a
  cell in the grid: a folder scan leaves those files out of its records.
- Strings the catalogue lacks show English fallbacks: `detail_readAgain`, `detail_showInFolder`,
  `sources_add_folder_ask___`, `source_unauthorized_choose`, `library_notWatched`,
  `library_search_results___`, `open_overflow___`. They need iOS catalogue keys and `pnpm strings:desktop`.
- Clearing the reading history has no control yet; `LibraryService.ClearRecent` is ready.
- The library's list is rebuilt on each rescan, so the selection and the scroll position reset then.
- Grouping by series, the cover size commands, the sidebar toggle, Open Recent as a submenu, Go to Page,
  bookmarks and the reader's context menu are not wired; their menu entries show disabled.
