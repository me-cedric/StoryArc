# macOS conformance walk — wave 2

Task 2.24 of `desktop-clients`. Every scenario of the capabilities wave 2 names, run against
the Mac app at the head of `lane/macos-wave2` on 2026-10-17 (macOS 27.0.1, Xcode 27.1, the
ad-hoc signed sandboxed build), with the result it gave. The scenarios are read from the
specs by name, so a scenario added to a spec later is missing here until the walk runs again.

| Result | Means |
| --- | --- |
| pass | A named test in `apps/desktop-macos/Tests` asserts it inside the running app. |
| seen | A wave 2 frame (`docs/designs/screenshots/desktop/macos/wave2/`) or the project's own files show it; nothing asserts it. The evidence column says which. |
| **fail** | It does not hold on the Mac today. Each one is a defect or a missing piece of wave 2's scope. |
| later | A later wave of `desktop-clients` builds it, as named. |
| n/a | Dropped on a desktop by `design.md` Decision 9, or another platform's scenario. |
| not walked | Built in wave 2 and not exercised here, for the reason given. |

Totals: pass 167, seen 70, fail 45, later 110, n/a 46, not walked 71, of 509 scenarios.

**What the walk is.** The walks run inside the app as `StoryArcMacTests` (`WindowWalks`):
the fixture comics of `packages/test-fixtures` are copied into the container and scanned as
the app's one folder, reader windows are opened as a click on a cover opens them, keys and
clicks are sent to the windows, and the progress store is read back. A quit and a
relaunch end the test host and are not walked; restoration is asserted on the saved
sessions instead. System settings (accent, Reduce Motion, Increase Contrast, Reduce
Transparency) were not changed. `desktop-experience` lists only the requirements the wave 2
tasks name.

**Defects the walk found and fixed on this branch**, each with its commit: a second open of a
publication opened a second window (`e6acd357`); two quick key presses turned one page
(`e6acd357`); a turn followed at once by a close or a quit could go unwritten (`5adec22a`);
the app's text size changed nothing on macOS (`7dafc706`); the preferences search showed
English titles in every language (`95d63b51`); 133 strings were missing from the catalogue
(`a344fea3`); changing destination lost the page pushed in the one before, and a turn
dropped the zoom (`c9ffe569`); the sidebar drew in the system's blue rather than the
brand colour (`eb132907`).

## The failures, in one list

Every **fail** below, by capability and requirement, so the next wave can take them as tasks.

- `comic-reader` · Page transitions in the comic reader: The Mac reader changes pages without a transition; only a drag slides the page (task 2.15). No mode choice, no continuous scroll, no scroll axis. Wave 2 builds the slide and the fade under Reduce Motion only.
- `comic-reader` · Page fitting and zoom: Fit page only; no fit width or original size on the Mac yet (the Reader menu lists Fit Page).
- `comic-reader` · Navigation within a publication: A slider without thumbnails.
- `comic-reader` · Navigation within a publication: The page slider and the *5 / 12* counter exist (frame `reader-*.png`, Go to Page in the Reader menu). No thumbnails, no thumbnail browser, no chapters, no end-of-publication screen on the Mac.
- `comic-reader` · Image adjustments: Not built on the Mac.
- `comic-reader` · Page browser: Not built on the Mac.
- `page-transitions` · Transition modes: No mode choice on the Mac: the preferences name the slide and say the curl is later (frame `settings-reading-*.png`); keys and clicks change the page without the slide.
- `library-browsing` · What could not be opened: Files handed over that cannot open are named in the library (`PointerAndFilesWalkTests`), but publications a folder scan skipped are not listed on the Mac: `LibraryModel.skipped` has no Mac view yet.
- `library-browsing` · Presentation: No sections on the Mac.
- `library-browsing` · Presentation: No index rail on the Mac.
- `reading-progress` · Resuming: No *Read from the beginning* action on the Mac page yet.
- `native-experience` · Visual proof of interface changes: The Mac has no snapshot tests; its proof is the capture suite's frames.
- `native-experience` · Visual proof of interface changes: No accessibility audit runs on the Mac yet.
- `settings-and-about` · Settings organisation: No reset on the Mac preferences.
- `settings-and-about` · About: The system About panel only; no support link, acknowledgements or problem report on the Mac yet.
- `home-screen` · Keep reading: A card whose file is gone is not dimmed or explained on the Mac Home.
- `home-screen` · The rest of the home surface: Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home.
- `publication-detail` · What the page shows: No other-issues shelf on the Mac page.

## comic-reader

Source: `docs/openspec/specs/comic-reader/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Page transitions in the comic reader | Mode persistence | **fail** | The Mac reader changes pages without a transition; only a drag slides the page (task 2.15). No mode choice, no continuous scroll, no scroll axis. Wave 2 builds the slide and the fade under Reduce Motion only. |
| Page transitions in the comic reader | Continuous scroll | **fail** | The Mac reader changes pages without a transition; only a drag slides the page (task 2.15). No mode choice, no continuous scroll, no scroll axis. Wave 2 builds the slide and the fade under Reduce Motion only. |
| Page transitions in the comic reader | Scroll axis for webtoons | **fail** | The Mac reader changes pages without a transition; only a drag slides the page (task 2.15). No mode choice, no continuous scroll, no scroll axis. Wave 2 builds the slide and the fade under Reduce Motion only. |
| Page transitions in the comic reader | Curl over image pages | later | The curl is wave 5. |
| Reading direction | Manga defaults | pass | `PageKeyMapperTests` (right-to-left mirrors the arrows), `SpreadDecisionTests` (right-to-left order), the reader's Reading Direction menu on the page |
| Reading direction | Overriding direction | pass | `PageKeyMapperTests` (right-to-left mirrors the arrows), `SpreadDecisionTests` (right-to-left order), the reader's Reading Direction menu on the page |
| Page fitting and zoom | Fit modes | **fail** | Fit page only; no fit width or original size on the Mac yet (the Reader menu lists Fit Page). |
| Page fitting and zoom | Double-page spreads | pass | `SpreadDecisionTests`, `ReaderWalkTests` |
| Page fitting and zoom | Zooming | pass | `ZoomModelTests`, `SpreadDecisionTests`, `ReaderWalkTests` *A key turns one page in a narrow window and a spread in a wide one* |
| Page fitting and zoom | Zoom persists across pages | pass | `ZoomModelTests` *A turn keeps the zoom and opens the page at its top, on the side reading starts from* (fixed on this branch; the Mac has no fit-to-width mode, so the zoom is the fit-page zoom) |
| Auto-hiding chrome | Entering the reader | pass | `PointerReadingTests` (zones on by default, chrome hides after three seconds), `PointerAndFilesWalkTests` *A click on the right edge turns the page*; frame `reader-*.png` |
| Auto-hiding chrome | Revealing controls | pass | `PointerReadingTests` (zones on by default, chrome hides after three seconds), `PointerAndFilesWalkTests` *A click on the right edge turns the page*; frame `reader-*.png` |
| Auto-hiding chrome | Everything else is in the menu, and labelled | pass | `PointerReadingTests` (zones on by default, chrome hides after three seconds), `PointerAndFilesWalkTests` *A click on the right edge turns the page*; frame `reader-*.png` |
| Auto-hiding chrome | Edge taps turn pages | pass | `PointerAndFilesWalkTests` *A click on the right edge turns the page* |
| Auto-hiding chrome | Chrome does not obscure the page | pass | `PointerReadingTests` (zones on by default, chrome hides after three seconds), `PointerAndFilesWalkTests` *A click on the right edge turns the page*; frame `reader-*.png` |
| Auto-hiding chrome | Fewer controls is not fewer ways in | pass | `PointerReadingTests` (zones on by default, chrome hides after three seconds), `PointerAndFilesWalkTests` *A click on the right edge turns the page*; frame `reader-*.png` |
| Navigation within a publication | Page slider with thumbnails | **fail** | A slider without thumbnails. |
| Navigation within a publication | Where the reader is, at a glance | seen | The *5 / 12* counter, frame `reader-*.png` |
| Navigation within a publication | Thumbnail browser | **fail** | The page slider and the *5 / 12* counter exist (frame `reader-*.png`, Go to Page in the Reader menu). No thumbnails, no thumbnail browser, no chapters, no end-of-publication screen on the Mac. |
| Navigation within a publication | Chapter navigation | **fail** | The page slider and the *5 / 12* counter exist (frame `reader-*.png`, Go to Page in the Reader menu). No thumbnails, no thumbnail browser, no chapters, no end-of-publication screen on the Mac. |
| Navigation within a publication | Reaching the end | **fail** | The page slider and the *5 / 12* counter exist (frame `reader-*.png`, Go to Page in the Reader menu). No thumbnails, no thumbnail browser, no chapters, no end-of-publication screen on the Mac. |
| Image adjustments | Adjustments available | **fail** | Not built on the Mac. |
| Image adjustments | Cropping borders | **fail** | Not built on the Mac. |
| Image adjustments | Persisting adjustments | **fail** | Not built on the Mac. |
| Reader performance | Prefetching | not walked | `ReaderModel` (StoryArcKit) warms the pages around the current one; not measured on the Mac. |
| Reader performance | Page not yet available | pass | The reader draws a quiet placeholder for an undecoded page; `SpreadDecisionTests` *A narrow window keeps the reader on the same page* |
| Reader performance | Screen stays awake | pass | `DisplayAwakeTests` |
| System integration | Hardware page turns | n/a | Hardware page turns and orientation lock are mobile (Decision 9); keys replace them, `PageKeyMapperTests` |
| System integration | Orientation lock | n/a | Hardware page turns and orientation lock are mobile (Decision 9); keys replace them, `PageKeyMapperTests` |
| System integration | Screenshot and recording | n/a | Mobile behaviour. |
| Page browser | One page in the centre | **fail** | Not built on the Mac. |
| Page browser | Browsing does not move the reader | **fail** | Not built on the Mac. |
| Page browser | The slider moves the carousel | **fail** | Not built on the Mac. |
| Page browser | Chapters in the browser | **fail** | Not built on the Mac. |
| Page browser | No chapter markers | **fail** | Not built on the Mac. |
| Page browser | Right-to-left reading | **fail** | Not built on the Mac. |
| Page browser | Reduce Motion | **fail** | Not built on the Mac. |
| Page browser | Assistive technology | **fail** | Not built on the Mac. |

## page-transitions

Source: `docs/openspec/specs/page-transitions/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Transition modes | Choosing a mode | **fail** | No mode choice on the Mac: the preferences name the slide and say the curl is later (frame `settings-reading-*.png`); keys and clicks change the page without the slide. |
| Transition modes | Scroll axis | **fail** | No mode choice on the Mac: the preferences name the slide and say the curl is later (frame `settings-reading-*.png`); keys and clicks change the page without the slide. |
| Transition modes | A mode is unavailable for the content | **fail** | No mode choice on the Mac: the preferences name the slide and say the curl is later (frame `settings-reading-*.png`); keys and clicks change the page without the slide. |
| The curl | The page follows the finger | later | Wave 5 (task list: the curl is wave 5). |
| The curl | The sheet rolls rather than folds | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Turning back | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Turning back from the first page | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Release behaviour | later | Wave 5 (task list: the curl is wave 5). |
| The curl | The curl is interruptible | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Curl direction respects reading direction | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Curl is not offered where it cannot be honest | later | Wave 5 (task list: the curl is wave 5). |
| The curl | Every other mode stays available | later | Wave 5 (task list: the curl is wave 5). |
| Reduced motion | Reduce Motion is on | not walked | The reader drops its animations when Reduce Motion is on and the preferences say pages fade (`settings-reading-*.png` shows the slide line); not walked with the system setting changed, which is a system setting this session does not touch. |
| Reduced motion | Reduce Motion turned off mid-session | not walked | The reader drops its animations when Reduce Motion is on and the preferences say pages fade (`settings-reading-*.png` shows the slide line); not walked with the system setting changed, which is a system setting this session does not touch. |
| Turn triggers | Tap zones | pass | `PointerReadingTests`, `PointerAndFilesWalkTests` |
| Turn triggers | Turning the tap zones off | pass | `PointerAndFilesWalkTests` *…turning the zones off stops it at once* |
| Turn triggers | The tap zones are on until a reader says otherwise | pass | `PointerReadingTests` *The zones are on when nothing is stored* |
| Turn triggers | Hardware input | pass | `PageKeyMapperTests` |
| Turn triggers | Turning at a boundary | pass | `PageKeyMapperTests` *A key at the end moves nothing and names no error* |
| Transition performance | The next page is not ready | not walked | No frame-time measurement on the Mac yet; the page placeholder is drawn (`SpreadDecisionTests`). |
| Transition performance | Frame budget | not walked | No frame-time measurement on the Mac yet; the page placeholder is drawn (`SpreadDecisionTests`). |
| Transition performance | Memory during a curl | not walked | No frame-time measurement on the Mac yet; the page placeholder is drawn (`SpreadDecisionTests`). |

## library-browsing

Source: `docs/openspec/specs/library-browsing/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Unified library | Default view | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | Every kind of source contributes | later | Only folders in wave 2. |
| Unified library | Browsing a source is a second way in | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | A source that has never been reached | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | Narrowing to what can be read now | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | Scoping to one source | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | A publication that is also downloaded | later | Downloads are wave 3. |
| Unified library | A publication that cannot be opened right now | seen | Frames `library-grid-*.png`, `library-list-*.png` over one folder; only folder sources exist in wave 2 |
| Unified library | More from a source than the library holds | later | Server sources are wave 3. |
| Search | The scope is stated, and can be narrowed | pass | `SearchStateTests`; frame `search-*.png`; recent searches in the empty search state |
| Search | Searching with every source unreachable | not walked | Search reads the cached model; no offline walk. |
| Search | Typing a query | pass | `SearchStateTests`; frame `search-*.png`; recent searches in the empty search state |
| Search | Mixed local and server search | later | Server sources are wave 3. |
| Search | No results | pass | `SearchStateTests`; frame `search-*.png`; recent searches in the empty search state |
| Search | Recent searches | pass | `SearchStateTests`; frame `search-*.png`; recent searches in the empty search state |
| Filtering | Combining filters | pass | `SearchStateTests` *Filters toggle by format, source and reading state*; the filter persists through `LibraryPreferences` (StoryArcKit) |
| Filtering | Filter persistence | pass | `SearchStateTests` *Filters toggle by format, source and reading state*; the filter persists through `LibraryPreferences` (StoryArcKit) |
| Filtering | Filtering offline | pass | `SearchStateTests` *Filters toggle by format, source and reading state*; the filter persists through `LibraryPreferences` (StoryArcKit) |
| Sorting | Default order in a reading list | later | Reading lists are wave 3. |
| Sorting | Overriding a curated order | later | Reading lists are wave 3. |
| Sorting | Alphabetical sorting across languages | pass | `SearchStateTests` *Sort keys apply*; collation is `LibraryIndex` with the app's language (StoryArcKit) |
| Sorting | Sorting a series | pass | `SearchStateTests` *Sort keys apply*; collation is `LibraryIndex` with the app's language (StoryArcKit) |
| What could not be opened | One publication could not be opened | pass | `PointerAndFilesWalkTests` (a CB7 handed over is named in the library) |
| What could not be opened | Several could not be opened | **fail** | Files handed over that cannot open are named in the library (`PointerAndFilesWalkTests`), but publications a folder scan skipped are not listed on the Mac: `LibraryModel.skipped` has no Mac view yet. |
| What could not be opened | The notice is not on a timer | pass | The notices stay until dismissed (`LibraryNotices`); `PointerAndFilesWalkTests` reads it after the reader opened |
| What could not be opened | Reaching it later | **fail** | Files handed over that cannot open are named in the library (`PointerAndFilesWalkTests`), but publications a folder scan skipped are not listed on the Mac: `LibraryModel.skipped` has no Mac view yet. |
| What could not be opened | A publication that later opens | **fail** | Files handed over that cannot open are named in the library (`PointerAndFilesWalkTests`), but publications a folder scan skipped are not listed on the Mac: `LibraryModel.skipped` has no Mac view yet. |
| What could not be opened | Announced without sight | **fail** | Files handed over that cannot open are named in the library (`PointerAndFilesWalkTests`), but publications a folder scan skipped are not listed on the Mac: `LibraryModel.skipped` has no Mac view yet. |
| Presentation | Switching layout | pass | View as Grid and View as List (`CommandTests`); frames |
| Presentation | Adaptive columns | pass | `LibraryViewModelTests` *The grid adds columns with the width* |
| Presentation | Cover art is shown whole | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | Progress on covers | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | What is on the device | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | A series is one row | pass | `LibraryViewModelTests` (grouping by series) |
| Presentation | A shelf of issues | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | The choice between series and issues | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | Opening a series | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | Sectioning a long library | **fail** | No sections on the Mac. |
| Presentation | An index down the side of a long shelf | **fail** | No index rail on the Mac. |
| Presentation | A sort no letter describes | **fail** | No sections on the Mac. |
| Presentation | The index without sight | **fail** | No index rail on the Mac. |
| Presentation | A publication that cannot be read now | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | The controls that change the view are grouped | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | A control that stands alone carries a name | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Presentation | An ordering says that it is an ordering | seen | `LibraryViewModelTests` (columns, series grouping, selection); frames `library-grid-*.png`, `library-list-*.png`. No index rail and no sections on the Mac. |
| Continue reading | Home view | pass | `HomePlanTests`; frame `home-*.png` |
| Continue reading | Next in series | pass | `HomePlanTests` |

## local-library

Source: `docs/openspec/specs/local-library/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Folder libraries | Adding a folder on iOS | n/a | iOS. The Mac's is Add Source in the File menu, `MacFolderBookmarksTests`. |
| Folder libraries | Adding a folder on Android | n/a | Android. |
| Folder libraries | Access is revoked | pass | `FolderSourceTests`, `MacFolderBookmarksTests` *Access the system refuses is reported stale by name* |
| Folder libraries | Scanning a folder | pass | `MacFolderBookmarksTests`, `FolderSourceTests`; the walks read a scanned folder |
| Folder libraries | Nested folder structure becomes series | not walked | StoryArcKit's scan; the fixture folder is flat. |
| Folder libraries | Large library | pass | `LibraryViewModelTests` (10,000 under a second), `FolderWatcherTests` (2,000 files) |
| Opening a single file | Open-in from another app | pass | `OpenRequestTests`, `PointerAndFilesWalkTests` *Files handed over open in readers, and a CB7 archive beside them is named*; document types in `project.yml` |
| Opening a single file | Remembering an opened file on iOS | n/a | iOS. The Mac keeps it in Open Recent and the Dock menu, `OpenRequestTests`. |
| Opening a single file | Remembering an opened file on Android | n/a | Android. |
| Opening a single file | File type registration | pass | `OpenRequestTests`, `PointerAndFilesWalkTests` *Files handed over open in readers, and a CB7 archive beside them is named*; document types in `project.yml` |
| Opening a single file | Unsupported file | pass | `OpenRequestTests`, `PointerAndFilesWalkTests` *Files handed over open in readers, and a CB7 archive beside them is named*; document types in `project.yml` |
| Imported copies | Importing | later | No import on the Mac: a file opens where it is. Wave 3 with downloads. |
| Imported copies | Deleting an imported copy | later | No import on the Mac: a file opens where it is. Wave 3 with downloads. |
| Watched changes | New file appears | pass | `FolderWatcherTests` *A file copied into a watched folder is seen inside ten seconds, and 2,000 arrive in batches* |
| Watched changes | Change detected while backgrounded | pass | The watched folders are reconciled at launch (`LibraryModel.reconcileWatchedFolders`); `FolderWatcherTests` for the live case |

## publication-formats

Source: `docs/openspec/specs/publication-formats/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported formats | Detecting format | pass | `OpenRequestTests` and `PointerAndFilesWalkTests` (CB7 refused by name); the format layer is StoryArcKit's `Formats`, tested against the corpus on macOS by `ios.yml` |
| Supported formats | An unsupported container is named, not merely rejected | pass | `OpenRequestTests` and `PointerAndFilesWalkTests` (CB7 refused by name); the format layer is StoryArcKit's `Formats`, tested against the corpus on macOS by `ios.yml` |
| Supported formats | A solid RAR4 is refused before any page is shown | pass | `OpenRequestTests` and `PointerAndFilesWalkTests` (CB7 refused by name); the format layer is StoryArcKit's `Formats`, tested against the corpus on macOS by `ios.yml` |
| Supported formats | A damaged archive is not reported as an unsupported one | pass | `OpenRequestTests` and `PointerAndFilesWalkTests` (CB7 refused by name); the format layer is StoryArcKit's `Formats`, tested against the corpus on macOS by `ios.yml` |
| Supported formats | Encrypted or password-protected archive | not walked | `password-protected.cbz` is in the walk folder and named by the refusal sentence; no walk opens it. |
| Supported formats | Corrupt archive | pass | `OpenRequestTests` and `PointerAndFilesWalkTests` (CB7 refused by name); the format layer is StoryArcKit's `Formats`, tested against the corpus on macOS by `ios.yml` |
| Streaming capability per format | Opening a streamable publication from a remote source | later | Remote sources are wave 3. |
| Streaming capability per format | Opening a solid archive from a remote source | later | Remote sources are wave 3. |
| Streaming capability per format | A solid archive already downloaded | later | Remote sources are wave 3. |
| Streaming capability per format | A remote publication is catalogued without being transferred | later | Remote sources are wave 3. |
| Streaming capability per format | Streaming capability is known before the first page is requested | later | Remote sources are wave 3. |
| Page ordering | Natural sort | pass | StoryArcKit `Formats` against the corpus; the walks read `natural-sort.cbz` in its 12-page order |
| Page ordering | Nested directories in an archive | pass | StoryArcKit `Formats` against the corpus; the walks read `natural-sort.cbz` in its 12-page order |
| Page ordering | Non-image entries | pass | StoryArcKit `Formats` against the corpus; the walks read `natural-sort.cbz` in its 12-page order |
| Metadata extraction | ComicInfo.xml | seen | Frame `library-list-*.png`: *Natural Sort, Fixture Series · #1* from ComicInfo; StoryArcKit `Formats` |
| Metadata extraction | EPUB package metadata | seen | Frame `library-list-*.png`: *Natural Sort, Fixture Series · #1* from ComicInfo; StoryArcKit `Formats` |
| Metadata extraction | No embedded metadata | seen | Frame `library-list-*.png`: *Natural Sort, Fixture Series · #1* from ComicInfo; StoryArcKit `Formats` |
| Metadata extraction | Right-to-left publication | seen | Frame `library-list-*.png`: *Natural Sort, Fixture Series · #1* from ComicInfo; StoryArcKit `Formats` |
| Cover extraction | Comic cover | seen | Frames `library-grid-*.png`; StoryArcKit's cover ladder |
| Cover extraction | EPUB cover | seen | Frames `library-grid-*.png`; StoryArcKit's cover ladder |
| Cover extraction | Cover generation cost | seen | Frames `library-grid-*.png`; StoryArcKit's cover ladder |
| Page decoding | Very large page | seen | Frame `reader-*.png`; `large-page.cbz` decodes in the grid; the undecodable-page sentence names the codec (catalogue key `desktop.reader.pageUndecodable`) |
| Page decoding | Supported image codecs | seen | Frame `reader-*.png`; `large-page.cbz` decodes in the grid; the undecodable-page sentence names the codec (catalogue key `desktop.reader.pageUndecodable`) |
| Page decoding | Wide double-page image | seen | Frame `reader-*.png`; `large-page.cbz` decodes in the grid; the undecodable-page sentence names the codec (catalogue key `desktop.reader.pageUndecodable`) |

## reading-progress

Source: `docs/openspec/specs/reading-progress/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Local progress store | Progress is recorded | pass | `ProgressWriterTests`, `ReaderWalkTests` *…and closing writes it* |
| Local progress store | Position identity | pass | `ProgressWriterTests`, `ReaderWalkTests` *…and closing writes it* |
| Local progress store | App is terminated unexpectedly | pass | Every turn is written by `ReaderModel` at once, and a failed write is kept and retried at launch (`ProgressWriterTests`) |
| Local progress store | Finished state | pass | `ProgressWriterTests`, `ReaderWalkTests` *…and closing writes it* |
| Resuming | Continue from a resume affordance | pass | `DetailPresentationTests` (Continue at the page); frames `detail-*.png`, `reader-*.png` (opens on page 5) |
| Resuming | Continue from the library | pass | `DetailPresentationTests` (Continue at the page); frames `detail-*.png`, `reader-*.png` (opens on page 5) |
| Resuming | Restart deliberately | **fail** | No *Read from the beginning* action on the Mac page yet. |
| Synchronisation | Pushing progress | later | Wave 3. |
| Synchronisation | Pulling progress | later | Wave 3. |
| Synchronisation | Source cannot store progress | later | Wave 3. |
| Conflict resolution | Remote is further ahead | later | Wave 3 (the merge is lane C's task 2.1 for Windows and Linux; StoryArcKit's on the Mac). |
| Conflict resolution | Both changed since the last sync | later | Wave 3 (the merge is lane C's task 2.1 for Windows and Linux; StoryArcKit's on the Mac). |
| Conflict resolution | Remote is behind | later | Wave 3 (the merge is lane C's task 2.1 for Windows and Linux; StoryArcKit's on the Mac). |
| Conflict resolution | Conflicting finished state | later | Wave 3 (the merge is lane C's task 2.1 for Windows and Linux; StoryArcKit's on the Mac). |
| Progress across formats and sources | Same publication from two sources | not walked | One source kind in wave 2; identity matching is StoryArcKit's. |
| Progress across formats and sources | Reflowable position | not walked | One source kind in wave 2; identity matching is StoryArcKit's. |
| Privacy of reading history | No third-party transmission | pass | The entitlements allow only the network client, and the app makes no request in wave 2 (`EntitlementsTests`) |
| Privacy of reading history | Clearing history | not walked | Settings > Privacy clears the store and both recent lists; not driven by a test. |

## reading-themes

Source: `docs/openspec/specs/reading-themes/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Theme presets | Applying a preset | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | Original respects the publisher | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | Deviating from a preset | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | The reset names what it restores | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | Resetting the preset that is already unmodified | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | Reset does not disturb the reading position | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme presets | Presets follow the appearance polarity | later | The presets are the EPUB reader's (wave 4); the comic page sits on the app's own surface. |
| Theme axes | Font size is stepped, not continuous | later | Wave 4. |
| Theme axes | Every axis states its value | later | Wave 4. |
| Theme axes | An axis requires publisher styles to be off | later | Wave 4. |
| Theme axes | Brightness is reader-local | later | Wave 4. |
| Theme axes | Resetting an axis | later | Wave 4. |
| Custom colour | Choosing a background | later | Wave 4. |
| Custom colour | Custom colour and the six presets | later | Wave 4. |
| Custom colour | Fixed-layout and image content | later | Wave 4. |
| Theme scope and persistence | Per-series memory | later | Wave 4. |
| Theme scope and persistence | Separate defaults for reflowable and fixed-layout | later | Wave 4. |
| Theme scope and persistence | Changing the global default | later | Wave 4. |

## localization

Source: `docs/openspec/specs/localization/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported languages | Following the system | pass | `LocalizationTests` reads every menu, notice, Home and accent key in en, fr, de and es from the built app; Settings > Language overrides the system |
| Supported languages | Overriding in the app | seen | Settings > Language; the choice is the shared `AppSettings.language` |
| Supported languages | Completeness | pass | `LocalizationTests` |
| Locale-correct formatting | Dates and times | not walked | Percentages and page counts use the system formatters; no walk in another language. |
| Locale-correct formatting | File sizes and counts | not walked | Percentages and page counts use the system formatters; no walk in another language. |
| Locale-correct formatting | Plurals | not walked | Percentages and page counts use the system formatters; no walk in another language. |
| Locale-correct formatting | Sorting | pass | `LibraryIndex` collation in the app's language (StoryArcKit) |
| Layout resilience | Long translations | not walked | No pseudo-locale walk on the Mac yet. |
| Layout resilience | Pseudo-locale testing | not walked | No pseudo-locale walk on the Mac yet. |
| Layout resilience | Right-to-left readiness | not walked | No pseudo-locale walk on the Mac yet. |
| Content language | Publication titles | seen | Titles and series are shown as the file carries them (frames). |
| Content language | Server-provided labels | seen | Titles and series are shown as the file carries them (frames). |

## native-experience

Source: `docs/openspec/specs/native-experience/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Platform-native interface | iOS interface | n/a | iOS. |
| Platform-native interface | Android interface | n/a | Android. |
| Platform-native interface | No cross-platform UI | seen | SwiftUI and AppKit only; frames. Quick actions and Continuity are mobile or later (Decision 10). |
| Platform-native interface | System integration | seen | SwiftUI and AppKit only; frames. Quick actions and Continuity are mobile or later (Decision 10). |
| Platform-native interface | Home-screen quick actions | n/a | Mobile; the Dock menu stands in (`MacAppDelegate`). |
| Platform-native interface | Continuity | later | Handoff is LATER in Decision 10. |
| Platform-native interface | A publication a continuity handover names is no longer there | later | Handoff is LATER in Decision 10. |
| Dynamic colour | Android dynamic colour | n/a | Android. |
| Dynamic colour | One accent on both platforms | pass | `ChromeAccentTests` *The brand colour when nothing is stored* |
| Dynamic colour | Cover-derived accent | seen | Frames `detail-*.png` |
| Dynamic colour | Chrome accent | pass | Settings, sources and the empty library use the single brand colour (`ChromeAccentTests`, frames); the sidebar takes it under the default Multicolor system accent since `eb132907` |
| Dynamic colour | A cover that yields no usable colour | pass | `ChromeAccentTests` (brand by default, system once chosen, a later system change reaching the chrome, the cover colour unchanged); frames `detail-*.png` (cover wash) |
| Dynamic colour | State colour survives every scheme | pass | `ChromeAccentTests` (brand by default, system once chosen, a later system change reaching the chrome, the cover colour unchanged); frames `detail-*.png` (cover wash) |
| Adaptive layout | Tablet and large screens | n/a | Mobile. |
| Adaptive layout | Split View, Slide Over and multi-window | n/a | Mobile; multiple reader windows are the Mac's (`ReaderWalkTests`). |
| Adaptive layout | Theme sheet on a large screen | later | Wave 4. |
| Adaptive layout | Foldables | n/a | Android. |
| Adaptive layout | Orientation | n/a | Mobile. |
| Reader chrome material | iOS reader chrome | n/a | iOS. |
| Reader chrome material | Android reader chrome | n/a | Android. |
| Reader chrome material | The preset grid on both platforms | later | Wave 4. |
| Theme sheet reachability | Opening the sheet | later | The theme sheet is the EPUB reader's, wave 4. |
| Theme sheet reachability | Applying a change with the sheet open | later | The theme sheet is the EPUB reader's, wave 4. |
| Accessibility | Screen reader | not walked | Covers and pages carry labels (`CoverCell.label`, the reader's page label); no VoiceOver or Accessibility Inspector walk on the Mac yet. The text size is the app's own (frames `*-largest.png`). |
| Accessibility | Dynamic Type and font scale | pass | The app's own text size reaches every window (frames `*-largest.png`, `ChromeAccentTests`); the picker values in Preferences keep the control size |
| Accessibility | Contrast and transparency | not walked | Covers and pages carry labels (`CoverCell.label`, the reader's page label); no VoiceOver or Accessibility Inspector walk on the Mac yet. The text size is the app's own (frames `*-largest.png`). |
| Accessibility | Reduce Motion | not walked | The reader drops its animations under Reduce Motion; not walked. |
| Accessibility | Touch targets | n/a | Pointer targets on a Mac; controls are system controls. |
| Accessibility | Keyboard and switch control | not walked | Covers and pages carry labels (`CoverCell.label`, the reader's page label); no VoiceOver or Accessibility Inspector walk on the Mac yet. The text size is the app's own (frames `*-largest.png`). |
| Accessibility | Colour is never the only signal | not walked | Covers and pages carry labels (`CoverCell.label`, the reader's page label); no VoiceOver or Accessibility Inspector walk on the Mac yet. The text size is the app's own (frames `*-largest.png`). |
| Performance and responsiveness | Cold launch | not walked | Task 5.11 measures it. |
| Performance and responsiveness | Scrolling | not walked | `LibraryViewModelTests` arranges 10,000 publications under a second and `FolderWatcherTests` measures the main actor under a 2,000-file burst; cold launch is not measured (task 5.11). |
| Performance and responsiveness | No blocking spinners | not walked | `LibraryViewModelTests` arranges 10,000 publications under a second and `FolderWatcherTests` measures the main actor under a 2,000-file burst; cold launch is not measured (task 5.11). |
| Performance and responsiveness | Memory | not walked | `LibraryViewModelTests` arranges 10,000 publications under a second and `FolderWatcherTests` measures the main actor under a 2,000-file burst; cold launch is not measured (task 5.11). |
| Visual proof of interface changes | Screen change | seen | `docs/designs/screenshots/desktop/macos/wave2/`, 32 frames from inside the app |
| Visual proof of interface changes | Snapshot tests hold the screen states | **fail** | The Mac has no snapshot tests; its proof is the capture suite's frames. |
| Visual proof of interface changes | A device screenshot where only a device shows it | seen | `docs/designs/screenshots/desktop/macos/wave2/`, 32 frames from inside the app |
| Visual proof of interface changes | Guidelines are checked by machine | **fail** | No accessibility audit runs on the Mac yet. |
| Visual proof of interface changes | Preview is not proof | seen | `docs/designs/screenshots/desktop/macos/wave2/`, 32 frames from inside the app |
| Visual proof of interface changes | Both appearances | seen | `docs/designs/screenshots/desktop/macos/wave2/`, 32 frames from inside the app |
| The icon a reader chose | Surviving a reinstall or a restore | n/a | The icon chooser drops on desktops (Decision 9). |
| The icon a reader chose | The platform refuses the change | n/a | The icon chooser drops on desktops (Decision 9). |
| The icon a reader chose | The platform withdraws the ability | n/a | The icon chooser drops on desktops (Decision 9). |
| The icon a reader chose | The system draws its own tinted icon | n/a | The icon chooser drops on desktops (Decision 9). |
| The icon a reader chose | The platform is the only record | n/a | The icon chooser drops on desktops (Decision 9). |
| Chrome for a mode a reader is in | The mode replaces its surface rather than stacking on it | not walked | Multi-selection exists in the grid (`LibraryViewModelTests`); no bulk actions on the Mac yet, so no mode chrome. |
| Chrome for a mode a reader is in | How many are chosen, and how to leave | not walked | Multi-selection exists in the grid (`LibraryViewModelTests`); no bulk actions on the Mac yet, so no mode chrome. |
| Chrome for a mode a reader is in | Nothing chosen yet | not walked | Multi-selection exists in the grid (`LibraryViewModelTests`); no bulk actions on the Mac yet, so no mode chrome. |
| Chrome for a mode a reader is in | Each platform's own form | not walked | Multi-selection exists in the grid (`LibraryViewModelTests`); no bulk actions on the Mac yet, so no mode chrome. |
| Chrome for a mode a reader is in | Every action names itself | not walked | Multi-selection exists in the grid (`LibraryViewModelTests`); no bulk actions on the Mac yet, so no mode chrome. |

## settings-and-about

Source: `docs/openspec/specs/settings-and-about/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Appearance | Choosing appearance | pass | `ChromeAccentTests`; frames `settings-appearance-*.png`; light and dark switch live in every frame pair |
| Appearance | Following the system | pass | `ChromeAccentTests`; frames `settings-appearance-*.png`; light and dark switch live in every frame pair |
| Appearance | OLED Dark is not the same as Dark | pass | `ChromeAccentTests`; frames `settings-appearance-*.png`; light and dark switch live in every frame pair |
| Appearance | Reader theme is separate | later | Reading themes are wave 4. |
| Choosing the app icon | Choosing one | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | What the platform does with it | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | Going back to the default | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | Where it lives | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | The platform refuses | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | At the largest text size | n/a | Dropped on desktops (Decision 9). |
| Choosing the app icon | Announced without sight | n/a | Dropped on desktops (Decision 9). |
| Settings organisation | Structure | pass | `SettingsSearchTests`; frames `settings-*.png`; a reading setting applies to an open reader (`PointerAndFilesWalkTests`) |
| Settings organisation | Searching settings | pass | `SettingsSearchTests` |
| Settings organisation | Reading defaults | pass | `PointerAndFilesWalkTests` (a reading setting reaches an open reader at once) |
| Settings organisation | Resetting | **fail** | No reset on the Mac preferences. |
| Privacy | Privacy screen | not walked | Settings > Privacy states what is kept and where (`SettingsTabs.swift`); no frame of that tab. |
| Privacy | Clearing data | not walked | Clear Reading History exists with a confirmation; not driven by a test. |
| Privacy | Exporting a diagnostic | later | Wave 3; the Privacy tab says so. |
| About | About contents | **fail** | The system About panel only; no support link, acknowledgements or problem report on the Mac yet. |
| About | Support link | **fail** | The system About panel only; no support link, acknowledgements or problem report on the Mac yet. |
| About | Acknowledgements | **fail** | The system About panel only; no support link, acknowledgements or problem report on the Mac yet. |
| About | Reporting a problem | **fail** | The system About panel only; no support link, acknowledgements or problem report on the Mac yet. |
| What changed in this version | After an update | later | Not built on the Mac. |
| What changed in this version | A first ever launch | later | Not built on the Mac. |
| What changed in this version | Nothing worth saying | later | Not built on the Mac. |
| What changed in this version | Reading it again | later | Not built on the Mac. |
| What changed in this version | An update installed while offline | later | Not built on the Mac. |
| What changed in this version | At the largest text size | later | Not built on the Mac. |

## home-screen

Source: `docs/openspec/changes/one-library-three-destinations/specs/home-screen/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Keep reading | Resuming | seen | A Keep reading card opens the reader at its page (frames `home-*.png`, `reader-*.png`) |
| Keep reading | Order | pass | `HomePlanTests` |
| Keep reading | Nothing in progress | pass | `HomePlanTests` *An empty shelf is absent* |
| Keep reading | A publication in progress is not currently readable | **fail** | A card whose file is gone is not dimmed or explained on the Mac Home. |
| Keep reading | The card shows how far through, not only how much is left | seen | Progress rail and percentage, frames `home-*.png` |
| Keep reading | Resuming is an action, not only a target | seen | The card is a button with a context menu (frames) |
| Keep reading | A publication with nothing meaningful left | not walked | No fixture is at its last page. |
| Keep reading | The hero does not crowd out the rest of the surface | n/a | No hero on the Mac Home; cards only. |
| Keep reading | Every card in the row is the same size | seen | Fixed card size in `HomeView.swift`; the frames hold one card |
| Keep reading | Artwork is not letterboxed | seen | Cover fills its frame (frames) |
| Up next | The next issue of a started series | pass | `HomePlanTests` *Only an unread next issue is Up next*; the fixtures have no finished series, so no frame shows the shelf |
| Up next | Not the same thing as resuming | pass | `HomePlanTests` *Only an unread next issue is Up next*; the fixtures have no finished series, so no frame shows the shelf |
| Up next | Finishing an issue in the reader | pass | `HomePlanTests` (a finished issue offers the next one) |
| Up next | A series with nothing after it | pass | `HomePlanTests` |
| Up next | The next issue lives on a source that is down | later | Remote sources are wave 3. |
| The rest of the home surface | Recently added | **fail** | Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home. |
| The rest of the home surface | Pinned shelves | **fail** | Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home. |
| The rest of the home surface | Finished | **fail** | Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home. |
| The rest of the home surface | Every shelf leads somewhere exhaustive | **fail** | Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home. |
| The rest of the home surface | A shelf that would be empty | **fail** | Recently added is a sidebar filter, not a Home shelf; no Finished or pinned shelves on the Mac Home. |
| The home surface never waits on a source | Opening the app with every source down | not walked | Home reads only the local store and the model; no unreachable-source walk. |
| The home surface never waits on a source | A slow source | later | Remote sources are wave 3. |
| The home surface never waits on a source | Progress recorded on another device | later | Sync is wave 3. |
| The home surface when there is little to show | A few things in progress | pass | `HomePlanTests` *An empty shelf is absent*; the empty Home names what to do (`desktop.home.nothing.*`) |
| The home surface when there is little to show | A library with nothing in it | seen | Wave 1 frames: the no-sources page with its one action |
| The home surface when there is little to show | A library with publications but no history | pass | `HomePlanTests`; Home says nothing is in progress |

## navigation-shell

Source: `docs/openspec/changes/one-library-three-destinations/specs/navigation-shell/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| The destination set | Moving between destinations | seen | The sidebar's four destinations (frames), Home first; `ShellTests` |
| The destination set | Each destination remembers where the reader had got to | pass | `LibraryWalkTests` *A publication's page pushed in Library is still there after a visit to Home* (fixed on this branch) |
| The destination set | Configuring sources never changes the destinations | pass | The sidebar lists `LibraryDestination.allCases` whatever the sources (`LibraryWindow`); wave 1 `ShellTests` |
| The destination set | Where the app opens | seen | Home is selected at launch (frames) |
| The destination set | Every source is unreachable | not walked | An offline folder is grey (`FolderSourceTests`); the destinations stay, not walked. |
| Reaching search | Search is a destination, not a shape | pass | `SearchStateTests` *Typing takes the content column; clearing returns to where the reader came from*; frame `search-*.png` |
| Reaching search | What search opens onto | pass | `SearchStateTests` *Typing takes the content column; clearing returns to where the reader came from*; frame `search-*.png` |
| Reaching search | Nothing to suggest | pass | `SearchStateTests` *Typing takes the content column; clearing returns to where the reader came from*; frame `search-*.png` |
| Reaching search | Leaving search | pass | `SearchStateTests` *Typing takes the content column; clearing returns to where the reader came from*; frame `search-*.png` |
| Reaching search | Searching with a source unreachable | pass | `SearchStateTests` *Typing takes the content column; clearing returns to where the reader came from*; frame `search-*.png` |
| Where a source can be reached | Narrowing to one source | seen | Folders are added from File > Add Source and listed in Settings > Sources with their state; no per-source browsing in wave 2. |
| Where a source can be reached | Adding a source | not walked | File > Add Source…, Settings > Sources, and a folder dropped on the library offers to add it; the system's folder chooser is not driven by a walk. |
| Where a source can be reached | Reaching a source's configuration | seen | Folders are added from File > Add Source and listed in Settings > Sources with their state; no per-source browsing in wave 2. |
| Where a source can be reached | A source stops being reachable | pass | `FolderSourceTests` |
| The destination set on a large screen | A wide window | seen | Sidebar and content column at every size from 640 × 440 (`ShellTests`, wave 1 narrow frames) |
| The destination set on a large screen | Resizing back down | seen | Sidebar and content column at every size from 640 × 440 (`ShellTests`, wave 1 narrow frames) |
| The destination set on a large screen | More shelves than the navigation can show | later | Shelves are wave 3. |
| Chrome that gets out of the way | Scrolling through covers | not walked | The library window keeps a fixed toolbar, which is the Mac idiom; the reader's chrome hides (`PointerReadingTests`). |
| Chrome that gets out of the way | The control can always be recovered | not walked | The library window keeps a fixed toolbar, which is the Mac idiom; the reader's chrome hides (`PointerReadingTests`). |
| Chrome that gets out of the way | Reduced motion | not walked | The library window keeps a fixed toolbar, which is the Mac idiom; the reader's chrome hides (`PointerReadingTests`). |

## publication-detail

Source: `docs/openspec/changes/publication-detail/specs/publication-detail/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reaching a publication's page | From a cover | seen | Show Details (⌘I) and the context menu push the page (frames `detail-*.png`) |
| Reaching a publication's page | Resuming does not come here | seen | In `LibraryGrid.swift` a double click and Read open the reader and Show Details pushes the page; not walked |
| Reaching a publication's page | The same page for every kind of publication | seen | Show Details (⌘I) and the context menu push the page (frames `detail-*.png`) |
| Reaching a publication's page | A publication that is no longer there | pass | `DetailPresentationTests` (offline: action absent, grey, the volume named) |
| What the page shows | The cover leads | seen | Cover, title, series line, format and pages (frames); no other-issues shelf on the Mac yet |
| What the page shows | Other issues in this series | **fail** | No other-issues shelf on the Mac page. |
| What the page shows | Metadata the publication does not carry | seen | Cover, title, series line, format and pages (frames); no other-issues shelf on the Mac yet |
| What the page shows | No cover art | pass | `DetailPresentationTests` *A publication with no cover* |
| One primary action | Reading from here | pass | `DetailPresentationTests`; frames `detail-*.png` |
| One primary action | No copy on the device, and a library that answers | later | Downloads are wave 3. |
| One primary action | A publication the app reads where it stands | pass | `DetailPresentationTests`; frames `detail-*.png` |
| One primary action | Everything else | pass | `DetailPresentationTests`; frames `detail-*.png` |
| One primary action | Downloading from here | later | Wave 3. |
| One primary action | The copy arrives while the page is open | later | Wave 3. |
| One primary action | The primary action cannot be honoured | pass | `DetailPresentationTests`; frames `detail-*.png` |
| Where it came from | What the line says | pass | `DetailPresentationTests` (the folder, `~` for home, the volume when offline) |
| Where it came from | What the line never says | pass | `DetailPresentationTests` (the folder, `~` for home, the volume when offline) |
| Where it came from | The same publication in two places | later | One source kind in wave 2. |
| Where it came from | Its source has been removed | pass | `DetailPresentationTests` (no location: the action is absent) |
| Colour taken from the cover | The wash | seen | Frames `detail-*.png`: the wash from the cover, the chrome untouched (`ChromeAccentTests` *A colour taken from a cover is the same under both choices*) |
| Colour taken from the cover | Contrast is not negotiable | not walked | The wash uses StoryArcKit's `CoverAccent`, which holds the contrast floor; not measured on the Mac. |
| Colour taken from the cover | Chrome does not take it | pass | `ChromeAccentTests` *A colour taken from a cover is the same under both choices* |
| Colour taken from the cover | A cover that yields nothing usable | seen | Frames `detail-*.png`: the wash from the cover, the chrome untouched (`ChromeAccentTests` *A colour taken from a cover is the same under both choices*) |
| Colour taken from the cover | High contrast and reduced transparency | not walked | Not walked with the system settings changed. |
| The page on a large screen | Two panes | seen | Sidebar and pushed page (frames) |
| The page on a large screen | The pane before anything is chosen | n/a | The Mac pushes the page in the content column rather than a third pane. |
| The page on a large screen | The window narrows | seen | The page is pushed in the content column beside the sidebar (frames). |
| The page on a large screen | Going back | seen | The toolbar back button (frames `detail-*.png`) |

## cover-art

Source: `docs/openspec/changes/cover-for-every-publication/specs/cover-art/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| The cover ladder | The publication's own bytes answer | seen | Frames |
| The cover ladder | A cover image sits beside the file | not walked | StoryArcKit's ladder; no fixture has a sidecar image. |
| The cover ladder | The source states a cover | later | Server sources are wave 3. |
| The cover ladder | Nothing answers | seen | `no-pages.cbz` shows the coverless well with its format (frame `library-list-*.png`) |
| A reader may choose a cover | Choosing a picture | later | Not built on the Mac. |
| A reader may choose a cover | A chosen cover outlives a rename | later | Not built on the Mac. |
| A reader may choose a cover | A publication with no digest | later | Not built on the Mac. |
| A reader may choose a cover | Undoing the choice | later | Not built on the Mac. |
| A reader may choose a cover | The cover's actions are one menu | later | Not built on the Mac. |
| A reader may choose a cover | The chosen cover survives a cache clear | later | Not built on the Mac. |
| Looking a cover up is the reader's choice | The lookup is off until it is turned on | later | Not built on the Mac. |
| Looking a cover up is the reader's choice | Asking by an identifier the file carries | later | Not built on the Mac. |
| Looking a cover up is the reader's choice | Asking by a title, and confirming the answer | later | Not built on the Mac. |
| Looking a cover up is the reader's choice | A provider refuses or rate-limits | later | Not built on the Mac. |
| Looking a cover up is the reader's choice | Every answer is cached | later | Not built on the Mac. |
| Finding a cover on the web is a hand-off | The hand-off | later | Not built on the Mac. |
| Finding a cover on the web is a hand-off | The app downloads nothing | later | Not built on the Mac. |
| Writing a cover back to a source | A Kavita reading list the reader owns | later | Server sources are wave 3. |
| Writing a cover back to a source | A Kavita series, chapter, collection or library | later | Server sources are wave 3. |
| Writing a cover back to a source | An OPDS catalogue | later | Server sources are wave 3. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Supported desktop systems | A supported system | seen | macOS 26 floor in `project.yml`; built and run on macOS 27.0.1 |
| Supported desktop systems | A system below the floor | seen | `deploymentTarget: macOS 26` in `project.yml`; the system refuses to open it below |
| Supported desktop systems | A Linux build below the floor | n/a | Linux. |
| Supported desktop systems | A Linux system without an optional service | n/a | Linux. |
| A desktop interface in each system's own idiom | Native look on each system | seen | Frames; glass on the reader chrome only |
| A desktop interface in each system's own idiom | Chrome material follows the system | seen | Frames; glass on the reader chrome only |
| A desktop interface in each system's own idiom | Transparency off | not walked | Reduce Transparency is not walked. |
| A desktop interface in each system's own idiom | A system without translucent material | not walked | Reduce Transparency is not walked. |
| The interface accent and the system appearance | The default accent | pass | `ChromeAccentTests` *The brand colour when nothing is stored, whatever the system accent*; frames: the controls and, since `eb132907`, the sidebar take the brand colour. On a Mac whose system accent is a chosen colour rather than Multicolor, the sidebar keeps that colour: macOS draws a sidebar in the app's accent only under Multicolor. |
| The interface accent and the system appearance | Following the system accent | pass | `ChromeAccentTests` *A later change of the system accent recolours the chrome*; the system accent itself is not changed in this session |
| The interface accent and the system appearance | A system with no accent colour | n/a | macOS always has an accent. |
| The interface accent and the system appearance | The system switches appearance | pass | `ChromeAccentTests`; frame pairs light and dark |
| The interface accent and the system appearance | A system that does not state its appearance | n/a | macOS always states it. |
| The window model | Opening a publication | pass | `ReaderWindowModelTests`, `ReaderWalkTests` *Two readers open side by side, and a second open of one fronts it* |
| The window model | Opening a publication that is already open | pass | `ReaderWindowModelTests`, `ReaderWalkTests` *Two readers open side by side, and a second open of one fronts it* |
| The window model | Two publications side by side | pass | `ReaderWalkTests` *Two readers open side by side* |
| The window model | A reader window whose publication disappears | not walked | The reader names a failure in its window; deleting the open file is not walked. |
| Windows come back after a quit or a crash | Relaunch after a quit | pass | `ReaderWindowModelTests` (saved, read back, missing named, a gone display's frame not reused); a real quit and relaunch is not walked, because it ends the test host |
| Windows come back after a quit or a crash | A display that is gone | pass | `ReaderWindowModelTests` *A frame on a display that is gone is not reused* |
| Windows come back after a quit or a crash | A publication that cannot be reopened | pass | `ReaderWindowModelTests` *Restoration reopens reachable windows and names the missing one* |
| Windows come back after a quit or a crash | The app ended without warning | pass | Every turn is written at once by `ReaderModel`; a failed write is retried at launch (`ProgressWriterTests`) |
| Closing a window and quitting the app | Progress while reading | pass | `ProgressWriterTests`, `ReaderWalkTests` (a press then an immediate close writes the page) |
| Closing a window and quitting the app | Closing a reader window | pass | `ProgressWriterTests`, `ReaderWalkTests` (a press then an immediate close writes the page) |
| Closing a window and quitting the app | Quitting | pass | `ProgressWriterTests`, `ReaderWalkTests` (a press then an immediate close writes the page) |
| Closing a window and quitting the app | A write that fails | pass | `ProgressWriterTests` *A write that fails still lets the window close* |
| Closing a window and quitting the app | Closing the last window on each system | pass | `MacAppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns false: the app stays with its menu bar, as a Mac app does |
| No presence when the app is closed | After quitting | seen | No login item, agent or extension in the project |
| No presence when the app is closed | A download in progress | seen | No login item, agent or extension in the project |
| No presence when the app is closed | A finished download or a refresh | seen | No login item, agent or extension in the project |
| Menus, commands and shortcuts | Every command is in a menu | pass | `CommandTests` |
| Menus, commands and shortcuts | The standard shortcuts | pass | `CommandTests` |
| Menus, commands and shortcuts | A command that does not apply | pass | `CommandTests` |
| Menus, commands and shortcuts | A shortcut while typing | pass | `PageKeyMapperTests` *With a text field in focus a key edits the text and turns no page* |
| Menus, commands and shortcuts | A shortcut another application holds | not walked | No global shortcut is registered; not walked. |
| Full keyboard navigation | Tabbing through the library | not walked | Not walked. |
| Full keyboard navigation | Acting on a focused item | not walked | Not walked. |
| Full keyboard navigation | Leaving a book's text | later | EPUB, wave 4. |
| Full keyboard navigation | A dialog | not walked | The Go to Page sheet takes Return and Escape (`.defaultAction`, `.cancelAction`); not walked. |
| Keys that turn pages | Left-to-right | pass | `PageKeyMapperTests`, `ReaderWalkTests` |
| Keys that turn pages | Right-to-left | pass | `PageKeyMapperTests`, `ReaderWalkTests` |
| Keys that turn pages | A key at the end | pass | `PageKeyMapperTests`, `ReaderWalkTests` |
| Keys that turn pages | A key held down | pass | Turns count from the page last asked for, so repeats are not lost (`ReaderWalkTests`, two presses in a row) |
| Search on a desktop | Opening search | pass | Find (⌘F) is in the table (`CommandTests`); `SearchStateTests` |
| Search on a desktop | Leaving search | pass | `SearchStateTests` *clearing returns to where the reader came from* |
| Pointer reading | Revealing chrome | pass | `PointerReadingTests`, `PointerAndFilesWalkTests` |
| Pointer reading | A context menu | pass | `PointerReadingTests`, `PointerAndFilesWalkTests` |
| Pointer reading | Edge click zones | pass | `PointerReadingTests`, `PointerAndFilesWalkTests` |
| Pointer reading | Selecting text and moving the window | n/a | No text in a comic page; the title bar moves the window. |
| Pointer reading | A pointer that is not there | pass | Every reader action is in the Reader menu with a key (`CommandTests`) |
| Zoom and pan with a pointer | Pinch and wheel | pass | `ZoomModelTests`; the Zoom menu in the reader chrome |
| Zoom and pan with a pointer | Double click | pass | `ZoomModelTests`; the Zoom menu in the reader chrome |
| Zoom and pan with a pointer | Plain wheel on a page that fits | pass | `ZoomModelTests`; the Zoom menu in the reader chrome |
| Zoom and pan with a pointer | Zoom keys and the limits | pass | `ZoomModelTests`; the Zoom menu in the reader chrome |
| Dragging to turn a page | A drag past the threshold | pass | `DragTurnTests` |
| Dragging to turn a page | A drag short of the threshold | pass | `DragTurnTests` |
| Dragging to turn a page | The curl follows the pointer | later | Wave 5. |
| Dragging to turn a page | The curl where it is not available | pass | The preferences say the curl comes later, and the slide is what runs (`settings-reading-*.png`) |
| Two-page spreads by window shape | A wide window | pass | `SpreadDecisionTests`, `ReaderWalkTests` (narrow then wide) |
| Two-page spreads by window shape | A narrow window | pass | `SpreadDecisionTests`, `ReaderWalkTests` (narrow then wide) |
| Two-page spreads by window shape | The last page of an odd count | pass | `SpreadDecisionTests`, `ReaderWalkTests` (narrow then wide) |
| Two-page spreads by window shape | A page that has not loaded | pass | The reader draws a quiet placeholder; `SpreadDecisionTests` |
| Full screen reading | Entering and leaving | pass | `ReaderWalkTests` *Full screen is entered and left, and the window gets its size back* |
| Full screen reading | Chrome in full screen | not walked | The chrome hides on the same timer in full screen; not imaged. |
| Full screen reading | A system that refuses | not walked | Full screen was granted in the walk; a refusal is not produced. |
| Dropping files and folders on the app | Dropping a publication | pass | `OpenRequestTests`, `PointerAndFilesWalkTests`; a real drag from Finder is not walked |
| Dropping files and folders on the app | Dropping a folder | not walked | A folder dropped on the library offers to add it (`LibraryWindow`); not walked. |
| Dropping files and folders on the app | Dropping several files | pass | `OpenRequestTests` *Several files open up to the limit and the rest are listed* |
| Dropping files and folders on the app | Dropping what cannot be opened | pass | `PointerAndFilesWalkTests` (CB7 named) |
| Dropping files and folders on the app | A drop that is not a file | not walked | The drop destination takes file URLs only; not walked. |
| File associations and Open With | Double click while the app is not running | not walked | Document types are declared; a Finder double click is not walked. |
| File associations and Open With | Double click while the app is running | pass | `PointerAndFilesWalkTests` drives the same inbox `application(_:open:)` fills |
| File associations and Open With | The command line | not walked | `open -a StoryArc file.cbz` reaches `application(_:open:)`; not walked. |
| File associations and Open With | A file that cannot be reached | pass | `OpenRequestTests` *A file that cannot be reached is named as unreadable* |
| File associations and Open With | Recently opened files | pass | `OpenRequestTests`; the Dock menu lists them |
| Choosing folders and keeping access | Adding a folder | pass | `MacFolderBookmarksTests`, `FolderSourceTests` |
| Choosing folders and keeping access | Access across relaunches | pass | `MacFolderBookmarksTests`, `FolderSourceTests` |
| Choosing folders and keeping access | Access withdrawn | pass | `MacFolderBookmarksTests`, `FolderSourceTests` |
| Choosing folders and keeping access | A folder on an unmounted volume | pass | `MacFolderBookmarksTests`, `FolderSourceTests` |
| Live folder watching | A file added while the app is open | pass | `FolderWatcherTests` |
| Live folder watching | The system cannot watch more | not walked | FSEvents has no per-directory limit; the fallback path is the Linux and Windows lanes'. |
| Live folder watching | Changes while the app was not running | pass | The library reconciles its folders at launch (StoryArcKit), `FolderWatcherTests` for the live case |
| Live folder watching | A burst of changes | pass | `FolderWatcherTests` |
| Secrets in the system's own store | Saving a password | later | Wave 3 (wave 1 proved the store, `MacCredentialStoreTests`). |
| Secrets in the system's own store | A secure store that is not running | later | Wave 3 (wave 1 proved the store, `MacCredentialStoreTests`). |
| Secrets in the system's own store | A secret the store refuses | later | Wave 3 (wave 1 proved the store, `MacCredentialStoreTests`). |
| Secrets in the system's own store | Searching the app's files | later | Wave 3 (wave 1 proved the store, `MacCredentialStoreTests`). |
| Keeping the display awake while reading | Reading in front | pass | `DisplayAwakeTests` |
| Keeping the display awake while reading | Listening | later | Audio is wave 4. |
| Keeping the display awake while reading | A system that cannot be asked | pass | `DisplayAwakeTests` |
| Metered connections | A metered network | later | Wave 3 (downloads). |
| Metered connections | A network that is not metered | later | Wave 3 (downloads). |
| Metered connections | A network that changes mid-download | later | Wave 3 (downloads). |
| Metered connections | No connection | later | Wave 3 (downloads). |
| Exporting a diagnostic to a file | Saving the diagnostic | later | Wave 3. |
| Exporting a diagnostic to a file | A place the file cannot be written | later | Wave 3. |
| Exporting a diagnostic to a file | Cancelling | later | Wave 3. |
| Media keys and system media controls | Media keys | later | Wave 4 (audio). |
| Media keys and system media controls | The system overlay | later | Wave 4 (audio). |
| Media keys and system media controls | Another application holds the keys | later | Wave 4 (audio). |
| Media keys and system media controls | A device with no speech engine | later | Wave 4 (audio). |
| Media keys and system media controls | The windows are hidden | later | Wave 4 (audio). |
| Screen readers on each system | Controls in the library | not walked | Labels exist on covers and pages; no VoiceOver walk. |
| Screen readers on each system | A page turn | not walked | Labels exist on covers and pages; no VoiceOver walk. |
| Screen readers on each system | A page with no text | not walked | Labels exist on covers and pages; no VoiceOver walk. |
| Screen readers on each system | What could not be opened | not walked | Labels exist on covers and pages; no VoiceOver walk. |
| Screen readers on each system | Orca without an accessibility bus | not walked | Labels exist on covers and pages; no VoiceOver walk. |
| Text size, contrast and motion follow the system | A larger text size | pass | Frames `*-largest.png` |
| Text size, contrast and motion follow the system | Increased contrast | not walked | Increase Contrast is not walked. |
| Text size, contrast and motion follow the system | Reduced motion | not walked | Reduce Motion is not walked. |
| Any window size | A narrow window | pass | `ShellTests` (minimum), `ReaderWalkTests` (resizing a reader re-pairs) |
| Any window size | A wide window | pass | `ShellTests` (minimum), `ReaderWalkTests` (resizing a reader re-pairs) |
| Any window size | A window below the minimum | pass | `ShellTests` (the minimum is enforced) |
| Any window size | Resizing a reader | pass | `ShellTests` (minimum), `ReaderWalkTests` (resizing a reader re-pairs) |
| Linux display servers and tiling compositors | A Wayland session | n/a | Linux only. |
| Linux display servers and tiling compositors | An X11 session | n/a | Linux only. |
| Linux display servers and tiling compositors | A compositor that draws no title bar | n/a | Linux only. |
| Linux display servers and tiling compositors | A stable identity | n/a | Linux only. |
| Linux display servers and tiling compositors | A tiled window of any size | n/a | Linux only. |
| Linux display servers and tiling compositors | A missing portal | n/a | Linux only. |
| Covers in the system's file views | A file manager thumbnail | later | Wave 5. |
| Covers in the system's file views | A publication with no cover | later | Wave 5. |
| Covers in the system's file views | No hand-off of data | later | Wave 5. |
| Recent items in the system's launcher | Recent publications | pass | `OpenRequestTests` *A vanished file leaves the recent list silently, newest stays first, five at most*; the Dock menu lists them |
| Recent items in the system's launcher | A publication that is gone | pass | `OpenRequestTests` *A vanished file leaves the recent list silently, newest stays first, five at most*; the Dock menu lists them |
| Recent items in the system's launcher | Recent publications on Linux | n/a | Linux. |
| Recent items in the system's launcher | Clearing the history | not walked | Settings > Privacy clears both recent lists; not driven by a test. |
| Recent items in the system's launcher | A launcher with no menu | n/a | The Dock always has a menu. |
| Preferences in their own window | Opening the preferences | pass | `ShellTests` (one Settings window), `SettingsSearchTests`, `PointerAndFilesWalkTests` (a reading setting reaches an open reader) |
| Preferences in their own window | Searching the preferences | pass | `ShellTests` (one Settings window), `SettingsSearchTests`, `PointerAndFilesWalkTests` (a reading setting reaches an open reader) |
| Preferences in their own window | Preferences while a reader is open | pass | `ShellTests` (one Settings window), `SettingsSearchTests`, `PointerAndFilesWalkTests` (a reading setting reaches an open reader) |
| Language follows the system | A supported language | pass | `LocalizationTests`; the app follows the system list unless Settings > Language says otherwise |
| Language follows the system | An unsupported language | not walked | Falls back to English through the string catalogue; not walked. |
| Language follows the system | A long translation | not walked | No pseudo-locale walk yet. |
| The same formats on every desktop | The formats | pass | `OpenRequestTests`, `PointerAndFilesWalkTests`; StoryArcKit `Formats` |
| The same formats on every desktop | A CB7 archive | pass | `OpenRequestTests`, `PointerAndFilesWalkTests`; StoryArcKit `Formats` |
| The same formats on every desktop | An image the system cannot decode | seen | The page names the codec (`desktop.reader.pageUndecodable`); `unsupported-codec.cbz` is in the walk folder, not opened by a walk |
| The same formats on every desktop | A large publication | not walked | `large-page.cbz` decodes (grid frame); memory is not measured. |
| Cold start and responsiveness on a desktop | Cold launch | not walked | Task 5.11 measures the cold launch; `LibraryViewModelTests` and `FolderWatcherTests` hold the arrangement and the burst. |
| Cold start and responsiveness on a desktop | Resizing and scrolling | not walked | Task 5.11 measures the cold launch; `LibraryViewModelTests` and `FolderWatcherTests` hold the arrangement and the burst. |
| Cold start and responsiveness on a desktop | A source that is slow or offline | later | Remote sources are wave 3. |
| Visual proof of interface changes on a desktop | A change to a screen | seen | `docs/designs/screenshots/desktop/macos/wave2/`, taken from inside the app because the session has no Screen Recording grant |
| Visual proof of interface changes on a desktop | A Linux change | n/a | Linux. |
| Visual proof of interface changes on a desktop | A system that cannot be captured | pass | The capture suite images the app's own windows from inside it, and each frame records how (`method.txt`) |
