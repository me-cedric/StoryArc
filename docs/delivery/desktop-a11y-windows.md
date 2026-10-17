# Windows screen reader walk: Narrator over the library, the readers and the player

**Task 4.21 of `desktop-clients`. Written 2026-10-17 on a Mac, from the XAML and the code; Narrator
has not run.** The desktop-experience requirement "Screen readers on each system" and the
audio-playback requirement "Reaching the player without sight" give the scenarios. Each row names
what the automation properties in the XAML give a UI Automation client today, and what only
Narrator on a Windows 11 24H2 desktop can confirm. The walk at the end of the waves fills the last
column with what was heard, verbatim, and the date.

How to read the states: **given** means the XAML sets the name, role or value and a UI Automation
client reads it without the app running; **inferred** means the control is a stock WinUI control
whose automation peer supplies it; **owed** means only a Windows desktop can tell.

## The library (`MainWindow.xaml`)

| Scenario | What the XAML gives | Narrator still owes |
| --- | --- | --- |
| Controls in the library: each toolbar control with its name and role, never a raw identifier | The search box has a placeholder and `AutomationId` `LibrarySearch`; the navigation items carry their localised `Content` (Home, Library, Downloads, Sources, Shelves); the menu is a stock `MenuBar` whose items are the command names of `CommandTable` (given) | That no item is read by its `AutomationId`, and that the title bar search is reached in the Tab order after the navigation |
| Each publication announced with its title, its progress and its source | `CoverCell` sets `AutomationProperties.Name` to the title and the progress sentence (given, wave 2); the source is not in the name (owed as a gap: add the source name to the cell's automation name) | The order of the three parts as spoken, and that the grid is announced as a list with its count |
| Tabbing through the library in reading order with a visible ring | Stock `NavigationView`, `ItemsView` and `Button` controls: focus visuals and Tab order are theirs (inferred) | That focus never lands on a collapsed view (`HomeView`, `LibraryView` are `Visibility.Collapsed` when hidden, which removes them from the tree) |
| What could not be opened is announced with the named reason | The refusal sentence of `LibraryService.Refuse` is the same text the screen shows, in a `TextBlock` with `LiveSetting="Polite"` (given, wave 2) | That the live region fires once per refusal and not once per redraw |

## The comic and PDF reader (`ReaderWindow.xaml`)

| Scenario | What the XAML gives | Narrator still owes |
| --- | --- | --- |
| A page turn announces the new position, "page 12 of 180" | `PageLabel` has `LiveSetting="Polite"` and the window raises `LiveRegionChanged` after every move (given, wave 2); each page `Image` is named "Page n of m" (given) | The wording and timing of the announcement, and that two live regions (the label and the position) are not both spoken |
| A page with no text is announced by its position and the alternative text, nothing invented | A comic page has no alternative text in the container, so the image's name is its position only (given) | Nothing beyond the position is spoken |
| A PDF page with a text layer: the page's text | **Not given.** The rendered page is an image; the text layer the core reads (`storyarc_pdf_page_text`) is not yet set as the page's `HelpText` or exposed through a text pattern. Gap for the next wave: set `AutomationProperties.HelpText` from `PdfDocument.PageText` on the page image | The announcement once the gap is closed |
| The contents pane (task 4.17): the outline and the search by page | `ContentsPane` has `AutomationId` `PdfContents`; every row is a `ListViewItem` whose `AutomationProperties.Name` is "title, Page n" or "Page n, k matches" (given); the search box is a stock `AutoSuggestBox` named by its placeholder (inferred); an entry that points nowhere is disabled (given) | That Show Contents moves focus into the pane and Escape returns it to the page (the code focuses the search box when there is one, else nothing) |
| Full keyboard navigation: everything by keyboard, focus visible and never trapped | Every command is in the menu with its accelerator (given, wave 2); the `ScrollViewer` is a tab stop (given) | That the page view's focus ring is visible on a dark page |

## The EPUB reader (`EpubReaderWindow.xaml`)

| Scenario | What the XAML gives | Narrator still owes |
| --- | --- | --- |
| The book's text is exposed through the web engine, keeping the publication's own markup and language | The `WebView2` is in the tree with `AutomationId` `EpubText`; WebView2 exposes its document to UI Automation through Chromium's accessibility tree (inferred, from the WebView2 documentation) | That Narrator's scan mode reads the chapter in reading order, honours `lang`, and that the toolkit's `blob:` frames are reachable |
| Leaving a book's text: Escape or Tab moves focus to the chrome and back | **Owed.** Focus handoff between the web content and the XAML chrome is WebView2's own (`Tab` leaves the web view at its last focusable element); Escape is not wired. Gap for the next wave: handle `CoreWebView2Controller.MoveFocusRequested` and an Escape accelerator on `Web` that focuses the menu | The sequence as heard, and that focus never stays inside the text |
| The position announced after a move | `PositionLabel` has `LiveSetting="Polite"` and raises `LiveRegionChanged` on each `locator` message (given) | That a page turn inside the web view also moves Narrator's reading cursor, or that the label's announcement suffices |
| A renderer that cannot load (no WebView2 runtime) is announced with the same named reason the screen shows | `UnavailableText` is a `TextBlock` in the tree; it has no live setting (gap: give it `LiveSetting="Polite"`) | The announcement |

## The player (`PlayerWindow.xaml`) and the compact bar (`MainWindow.xaml`)

| Scenario | What the XAML gives | Narrator still owes |
| --- | --- | --- |
| Labels and values: speed, the remaining sleep time, the position | Play or pause is named by its state (`player_play`, `player_pause`); the skips are named "0:15 back" and "0:30 forward"; the speed and sleep `ComboBox` are named and their selected item is their value; `SleepText` is a polite live region (given) | That a `ComboBox` value is spoken as "Speed, 1.5×" and not as the item index |
| The scrub control announced as an adjustable with its position in time, not a percentage | The `Slider` is named "Position"; its `HelpText` is set to the clock each redraw (given). A `Slider`'s value pattern speaks the numeric value, which is seconds (gap: a `RangeValue` in seconds is not a time; the next wave gives the slider an automation peer whose value is `PlayerModel.Clock`) | What is heard: the seconds, the help text, or both |
| The chapter list: chapter, duration, mark and remaining time as one control | Each row's `AutomationProperties.Name` is "title, duration · mark · remaining" (given) | That the middle dot is read as a pause and not as "middle dot" |
| The compact bar as one element naming what is playing, with play/pause and open reachable separately | `PlayerBar` is named "Now playing: title, chapter"; its two buttons are named "Play" or "Pause" and "Open the player" (given) | That the grid is announced as one element, which depends on Narrator's grouping of a `Grid` with a name |
| The bar does not steal focus when it appears | The bar changes `Visibility` only; nothing calls `Focus` (given) | That Narrator does not move its cursor to a newly visible region |
| At the largest text size the publication, the chapter and every value are readable and no control is pushed off | The player's content is in a `ScrollViewer`; the texts wrap; the bar trims its text with an ellipsis and keeps its two buttons at their natural size (given) | The screens at 225 per cent text scale, captured |
| The transport reachable in reading order without touch | The bar is the last row of the library window's grid, so it is last in the Tab order (given) | That it is announced after the content and before the window's end |

## Gaps found by reading, for the next wave

1. The library cell's automation name lacks the source (desktop-experience, "Controls in the library").
2. A PDF page's text layer is not exposed on the page image.
3. Escape does not hand focus from the EPUB text to the chrome; `MoveFocusRequested` is not handled.
4. The scrub control speaks seconds, not a clock.
5. `UnavailableText` in the EPUB window is not a live region.

Each is a few lines of XAML or code and none needs a design decision; they wait for the walk so the
fix matches what Narrator actually says.
