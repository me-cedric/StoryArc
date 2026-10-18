# Windows conformance walk, wave 4

Task 4.22 of `desktop-clients`. This record lists every scenario of the capabilities that wave 4 lane W names: the EPUB and PDF reader, the player and read-aloud. It is the Windows twin of `desktop-conformance-macos-wave4.md` and has the same 92 rows in the same order. It is dated 2026-10-18. It was written from existing evidence before the host pass: the code in `apps/desktop-windows`, the interop tests in `apps/desktop-windows/tests/StoryArc.Interop.Tests`, `docs/delivery/desktop-a11y-windows.md` and `docs/delivery/desktop-spike-audio-windows.md`. No Windows screen has been walked, by owner decision: the host pass happens after all waves. No test was run for this record. The host pass fills in the "not proved" rows and turns each "wired, not proved" row into pass or fail. The scenarios are read from the specs by name, so a scenario added to a spec later is missing here until the record is updated. For `desktop-experience`, only the requirements the wave 4 tasks name are listed.

| Result | Means |
| --- | --- |
| wired, not proved | The code or an interop test in `apps/desktop-windows` wires it. No Windows screen showed it. The evidence column names the code or the test. |
| not proved | No code or test was found quickly. It is owed to the host pass. |
| **fail** | The feature is clearly absent in `apps/desktop-windows`. The evidence column says what is missing. |
| n/a | Dropped on a desktop by `design.md` Decision 9, or another system's scenario, or the reason does not apply on Windows. |

Totals: wired, not proved 81, not proved 3, fail 0, n/a 8, of 92 scenarios (written 2026-10-18; 33 rows turned from fail to wired, not proved the same day).

**What closed the 33 failures.** On 2026-10-18 the Windows EPUB window gained a bar of reading tools. The reading themes flyout has two levels: the six presets as swatches, the size stepper, scroll mode and brightness, then the axes over a specimen. The five bundled faces are served on the book's origin. The window has the contents to full depth, search with context, bookmarks, highlights with notes copied out as text or Markdown, footnotes in place, a way back after each jump, and a progress line in words. The rules are in `StoryArc.Interop` (`ReadingThemes`, `EpubFonts`, `EpubMarks`, `EpubJumps`, `EpubProgressLine`) with the tests `ReadingThemeTests` and `EpubMarksTests`. The spoken sentence is drawn and followed. A text PDF shows the text of the page in its contents pane, where a selection makes the same highlight record (`PdfMarks`). A scanned PDF says once that it is images of pages. The player writes each listening moment (`PlayerModel.WriteDue`) and draws the coverless well on the window and on the system's media controls. An audiobook's page lists its chapters, starts at one and names where it resumes (`AudiobookDetail`, `ListeningWritesTests`). Every row is still owed to the host pass: no Windows screen showed any of it.

## The failures, in one list

No row fails since 2026-10-18. The 33 rows that failed when this record was written are listed here so the host pass can find them.

- **EPUB look and typography (14):** Typography controls, One sheet two depths, Bundled typefaces, Publisher styles, An axis is inert, Theme choice, The theme surface opens on the presets, Themes are named, The axes over the reader's own text, Getting back to the preset, Theme follows appearance, Both levels at the largest text size, Changing type size mid-chapter, Scroll mode.
- **EPUB position and navigation (10):** Progress display, Moving somewhere else, A publication that declares no chapters, Table of contents, Bookmarks, Highlights and notes, Search within a publication, Following an internal link, Returning from any jump, A link inside the book.
- **PDF (2):** Text-based PDF, Scanned PDF.
- **Read aloud (1):** Starting playback.
- **Player (6):** A publication with no cover, Where a listening position is written, and the four *Chapters before the first minute* rows.

**Found while reading the code.**

- `AppHost` passes no cover path for a narrated book. The player and the system overlay now draw the coverless well instead; reading a cover embedded in the file is not built.
- Resolved 2026-10-18: `PlaybackService` wrote the position only when a session ended, and a skip from the window or the system's controls moved the model and not the engine. `PlayerModel.SoughtTo` now moves the engine.
- The five gaps of `desktop-a11y-windows.md` stand. Narrator has not run.

## ebook-reader

Source: `docs/openspec/specs/ebook-reader/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reflowable rendering | Typography controls | wired, not proved | The *Customise* level of the theme flyout (`EpubReaderWindow.Themes.cs`) sets size, typeface, bold, line, character, word and paragraph spacing, margins, alignment and hyphenation; brightness is on the first level, and each change posts one `theme` message at once. `ReadingThemeTests.Every_axis_reaches_the_renderer_under_a_preset_that_drops_publisher_styles` (2026-10-18). |
| Reflowable rendering | One sheet, two depths | wired, not proved | The flyout opens on the six swatches, the size stepper, *Continuous scroll* and brightness; one *Customise* button as wide as the grid opens the axes (`EpubReaderWindow.ShowPresets`, `ShowAxes`) (2026-10-18). |
| Reflowable rendering | Bundled typefaces | wired, not proved | The typeface box offers the publisher's, serif, sans and the five faces of `packages/fonts`, Atkinson Hyperlegible labelled as designed for low vision; the faces are served on the book's origin and every chapter links them. `ReadingThemeTests.The_five_bundled_faces_are_served_on_the_books_origin_and_every_chapter_links_them` (2026-10-18). |
| Reflowable rendering | Publisher styles | wired, not proved | Original keeps the publisher's stylesheet (`publisherStyles: true`); every other preset drops it, and the position is the renderer's, kept across the change. `ReadingThemeTests.Original_keeps_the_publishers_styles_and_sends_none_of_the_axes_they_govern` (2026-10-18). |
| Reflowable rendering | An axis is inert while publisher styles are on | wired, not proved | Under Original the governed axes are disabled under a one-line reason and one action, *Use StoryArc's typography*, that switches to Paper (`EpubReaderWindow.ShowAxes`); `ReadingThemes.IsEffective` decides, tested in `ReadingThemeTests.Original_keeps_the_publishers_styles_and_sends_none_of_the_axes_they_govern` (2026-10-18). |
| Reflowable rendering | Fixed-layout EPUB | not proved | Owed to the host pass. The core test `epub_positions` reads `ebooks/fixed-layout.epub` on every host. WebView2 has not rendered it. |
| Reader themes | Theme choice | wired, not proved | Six swatches and a brightness slider from one half to full (`darkenFilter`). The preset colours are held to the tokens by `ReadingThemeTests.The_preset_colours_are_the_reading_theme_tokens` (2026-10-18). |
| Reader themes | The theme surface opens on the presets | wired, not proved | *Reading themes* (the tool bar or Control+Shift+T) opens on the swatches with no axis among them; a swatch applies and closes the flyout (`EpubReaderWindow.Swatch`) (2026-10-18). |
| Reader themes | Themes are named, not numbered | wired, not proved | Each swatch shows a specimen and the name in the preset's colours, face and weight; the active one is outlined, has the item status *Selected* and says *Modified* when the typography moved (`EpubLook.IsModified`, `ReadingThemeTests.The_look_is_kept_and_follows_the_appearance_with_the_chosen_pair`) (2026-10-18). |
| Reader themes | The axes, over the reader's own text | wired, not proved | The axes level shows a specimen in the active theme, face and size, and the page behind the flyout changes with each axis; each slider states its value beside its label (`ReadingThemes.ValueText`) (2026-10-18). |
| Reader themes | Getting back to the preset | wired, not proved | *Restore <preset>* names the preset and puts the typography back (`EpubReaderWindow.ShowAxes`) (2026-10-18). |
| Reader themes | Theme follows appearance | wired, not proved | *Match the reading theme to the app* with a light and a dark preset; `Root.ActualThemeChanged` applies the pair at once. `ReadingThemeTests.The_look_is_kept_and_follows_the_appearance_with_the_chosen_pair` (2026-10-18). |
| Reader themes | Both levels at the largest text size | wired, not proved | Both levels are in a scrolling flyout, every label wraps and *Customise* is the second item (`EpubReaderWindow.xaml`). No text-size walk yet (2026-10-18). |
| Pagination and progress | Changing type size mid-chapter | wired, not proved | The size stepper, Control+Plus and Control+Minus post one `theme` message; the renderer keeps its locator across the relayout (2026-10-18). |
| Pagination and progress | Progress display | wired, not proved | The foot states the share read and the share of the chapter left, in words, and no page number (`EpubProgressLine`, `EpubMarksTests.The_progress_line_states_the_book_and_the_chapter_in_words_or_the_book_alone`) (2026-10-18). |
| Pagination and progress | Moving somewhere else in a reflowable publication | wired, not proved | *Contents* in the tool bar and the menu (Control+T) goes to a chapter, with a way back (`EpubReaderWindow.Marks.cs`) (2026-10-18). |
| Pagination and progress | A publication that declares no chapters | wired, not proved | The line states the share of the book alone and the contents say the book declares none. `EpubMarksTests.The_progress_line_states_the_book_and_the_chapter_in_words_or_the_book_alone` (2026-10-18). |
| Pagination and progress | Scroll mode | wired, not proved | *Continuous scroll* on the first level sends `scroll: true`; the renderer keeps its locator across the switch. `ReadingThemeTests.Every_axis_reaches_the_renderer_under_a_preset_that_drops_publisher_styles` (2026-10-18). |
| Navigation and annotation | Table of contents | wired, not proved | The manifest's `toc` to full depth, each entry indented and given its level, the current chapter selected. `EpubMarksTests.The_contents_are_shown_to_full_depth_with_the_current_chapter_found` (2026-10-18). |
| Navigation and annotation | Bookmarks | wired, not proved | Control+D or the tool bar toggles a bookmark with its chapter and an excerpt, listed in reading order under *Bookmarks and Highlights* beside the contents. `EpubMarksTests.A_bookmark_keeps_its_chapter_and_excerpt_toggles_off_and_lists_in_reading_order` (2026-10-18). |
| Navigation and annotation | Highlights and notes | wired, not proved | A selection offers five colours, *Note*, *Copy* and *Search for this*; the highlights and notes are listed in one place and copied as plain text or Markdown. `EpubMarksTests.A_selection_becomes_a_highlight_with_a_note_drawn_with_the_spoken_sentence_and_exported` (2026-10-18). |
| Navigation and annotation | Search within a publication | wired, not proved | The search flyout (Control+F) lists each match with its context and chapter, and a click jumps to it. `EpubMarksTests.Footnotes_activations_and_search_results_are_read_from_the_renderer` (2026-10-18). |
| Navigation and annotation | Following an internal link | wired, not proved | A footnote opens in a flyout over the page; a link into another chapter offers *Back*. `EpubMarksTests.A_jump_offers_one_way_back_that_is_not_itself_a_place_to_return_from` (2026-10-18). |
| Navigation and annotation | Returning from any jump | wired, not proved | One *Back* control after a link, a contents entry, a bookmark, a highlight or a search hit, until used or replaced. `EpubMarksTests.A_jump_offers_one_way_back_that_is_not_itself_a_place_to_return_from` (2026-10-18). |
| Navigation and annotation | Following a link out of the publication | wired, not proved | `RendererMessage.OutboundLink` keeps `http` and `https` only (`EpubHostTests`). The window asks *Open a page on {host}?* in a `ContentDialog` and launches only on *Open in Browser* (`EpubReaderWindow.ConfirmLeavingAsync`, 2026-10-18). Owed to the host pass. |
| Navigation and annotation | A publication reaching the network on its own | wired, not proved | `EpubHostTests.The_eight_vectors_arrive_nowhere` and `EpubSeamTests.Through_the_fake_web_view_the_fixture_book_renders_from_its_origin_and_nothing_leaves_it` run the eight vectors through a fake WebView2 pipeline. `StartAsync` sets the scheme, the filter and the navigation block. The egress page in the real web view is owed. |
| PDF rendering | Text-based PDF | wired, not proved | Outline and search are wired (`PdfPaneModelTests`, `ReaderWindow.ToggleContents`). The page is an image, so the contents pane shows the engine's text of the page shown; a selection there offers the five colours, a note, copy and search in the document, drawn in the text and listed by page, kept as the EPUB's highlight record and copied out by the same document (`ReaderWindow.PdfText.cs`). `PdfMarksTests.A_pdf_selection_is_the_same_highlight_record_and_is_found_again_in_its_page` (2026-10-18). |
| PDF rendering | Scanned PDF | wired, not proved | The text controls are hidden (`PdfPaneModelTests.A_scanned_file_offers_neither_search_nor_selection_and_the_engine_is_not_asked`). A press that sweeps a word or a right-click shows the one sentence, once (`PdfPaneModelTests.A_press_that_tries_to_select_in_a_scanned_file_is_told_the_file_is_images_of_pages`, `ReaderWindow.TellImagesOnly`) (2026-10-18). |
| PDF rendering | A text layer is detected rather than assumed | wired, not proved | `PdfPaneModel.HasTextLayer`. `PdfSeamTests.The_text_pdf_reads_as_the_phones_read_it` and `PdfSeamTests.The_image_pdf_reads_as_a_comic_with_no_text_layer` skip when PDFium is missing. |
| PDF rendering | A device that cannot read PDF text | n/a | The app bundles PDFium, so the text API is on every Windows build. |
| PDF rendering | Large PDF | not proved | Owed to the host pass. `PdfDocument` draws one page when asked. No large file was opened. |
| PDF rendering | A rendered page is bounded by what it is shown at | wired, not proved | `PdfDocument.RenderPageToFit` takes a size limit. `PdfSeamTests.A_page_drawn_to_fit_a_larger_view_is_enlarged_where_the_plain_render_stops_at_one_pixel_a_point`. |
| PDF rendering | Page rendering is identical across platforms | wired, not proved | `PdfSeamTests.The_text_pdf_reads_as_the_phones_read_it` mirrors the cases of the core. No Windows page was compared with another platform. |

## ebook-reader (read-aloud delta)

Source: `docs/openspec/changes/read-aloud-beyond-the-reader/specs/ebook-reader/spec.md`. The MODIFIED *Reading aloud* block replaces the main spec's, so the main spec's six scenarios are read in their delta wording, and *The transport outside the reader* is the delta's ADDED requirement.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reading aloud | Starting playback | wired, not proved | The spoken sentence is drawn as a decoration in its own tint and the page follows it (`EpubMarks.SpokenLocator`, `EpubReaderWindow.StartReadAloud`); the compact bar names the chapter (`PlayerModel.CompactLine`). `EpubMarksTests.A_selection_becomes_a_highlight_with_a_note_drawn_with_the_spoken_sentence_and_exported` (2026-10-18). |
| Reading aloud | Leaving the publication while it speaks | wired, not proved | `PlaybackService` belongs to `AppHost`, so a voice outlives its window. `AppHost.OpenPlayer` goes to the book window when it is open. Reopening at the sentence being spoken: no code found. |
| Reading aloud | The same controls as a narrated book | wired, not proved | A voice runs on the same `PlayerModel` as a narrated book (`PlaybackKind.ReadAloud`), so `PlayerWindow` offers speed, sleep and chapters for it. `PlayerModelTests.A_voice_fades_in_a_shorter_window_and_end_of_chapter_follows_the_audio`. No page names the voice. |
| Reading aloud | Background and lock screen | wired, not proved | `PlaybackService.WindowsTransport` over `SystemMediaTransportControls`. `TransportControlsTests.The_entry_shows_title_cover_and_position_while_a_session_exists_and_leaves_when_it_ends`. |
| Reading aloud | Reaching the end of a chapter | wired, not proved | `ReadAloudTests.The_voice_carries_on_into_the_next_chapter_skips_an_empty_one_and_ends_at_the_last_sentence`. |
| Reading aloud | Where the listening got to | wired, not proved | The page follows the voice by chapter, and each move reaches `AppHost.PageTurned`. No test asserts it. |
| Reading aloud | Something else takes the audio | wired, not proved | `PlaybackService` reads `AudioStateMonitor` and calls `Interrupted` and `InterruptionEnded`. `PlayerModelTests.An_interruption_resumes_by_itself_but_never_undoes_the_listeners_pause_and_audio_taken_for_good_ends_it`. |
| Reading aloud | A publication with nothing to say | not proved | Owed to the host pass. `ReadAloudTests.Starting_in_an_empty_chapter_speaks_the_next_one_that_has_words_and_a_silent_tail_ends_at_once` covers an empty chapter. No check hides the control for a book with no text. |
| The transport outside the reader | Getting back to the book | wired, not proved | `AppHost.OpenPlayer` activates the book window when it is open. When it is closed, the bar opens the player window and not the book. |
| The transport outside the reader | Controlling it without going back | wired, not proved | The bar has *Play* or *Pause* and *Open the player*. Stop and skip are in the player window, one step on. |
| The transport outside the reader | What it says | wired, not proved | `PlayerModelTests.Starting_plays_and_the_transport_names_the_title_the_chapter_and_the_position` and `PlayerModelTests.A_publication_with_no_chapters_shows_the_author_on_the_second_line`. |
| The transport outside the reader | It is absent when nothing is playing | wired, not proved | `MainWindow.DrawPlayerBar` collapses the bar when there is no line. `TransportControlsTests.The_same_state_twice_is_one_update_and_quit_takes_the_entry_down`. |
| The transport outside the reader | Opening a different publication | wired, not proved | `PlayerModelTests.Opening_a_different_publication_ends_the_session_at_its_position_and_says_so_once`. `PlaybackService.VoiceStopped` shows the notice once in the bar. |
| The transport outside the reader | The transport on iOS | n/a | iOS. |
| The transport outside the reader | The transport on Android | n/a | Android. |
| The transport outside the reader | The session cannot continue | wired, not proved | The model ends the session and records the position (`PlayerModel.End`). `PlayerModelTests.An_interruption_resumes_by_itself_but_never_undoes_the_listeners_pause_and_audio_taken_for_good_ends_it`. The bar leaves with the session. |
| The transport outside the reader | Reaching the transport without touch | wired, not proved | `PlayerBar` is named *Now playing* with the title and the chapter. It has two named buttons, sits last in the tab order and never calls `Focus` (`desktop-a11y-windows.md`). |

## audio-playback (audiobooks delta)

Source: `docs/openspec/changes/audiobooks-and-playback/specs/audio-playback/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| One player for everything that speaks | The compact bar | wired, not proved | `MainWindow.Player.cs` draws the bar with the title, the chapter, play or pause and *Open the player*. |
| One player for everything that speaks | Nothing is playing | wired, not proved | `MainWindow.DrawPlayerBar` sets the bar to `Collapsed`, so it keeps no space. |
| One player for everything that speaks | The full player | wired, not proved | `PlayerWindow` has the cover, the title, the chapter, the position, play, skip, the scrub slider, speed, sleep and the chapter list, on the same `PlaybackService`. |
| One player for everything that speaks | A publication with no cover | wired, not proved | The player draws the kind as a symbol over the format's name, never the title, and renders that well once as the artwork of the system's media controls (`PlayerWindow.DrawCoverless`, `PlaybackService.UseCoverlessArtwork`). `ListeningWritesTests.A_book_with_no_cover_shows_its_kind_over_its_format_and_never_its_title` (2026-10-18). |
| One player for everything that speaks | Both sources look the same | wired, not proved | One `PlayerModel`, one bar and one window serve both kinds. No page names the voice. |
| One player for everything that speaks | Playback outlives the publication | wired, not proved | `PlaybackService` belongs to `AppHost`, and `PlayerWindow` keeps the session when it closes. The bar opens the way back. |
| One player for everything that speaks | Starting a second thing | wired, not proved | `PlayerModelTests.Opening_a_different_publication_ends_the_session_at_its_position_and_says_so_once`. |
| One player for everything that speaks | Where a listening position is written | wired, not proved | `PlayerModel.WriteDue` at a pause, a skip, a chapter, a scrub let go, and every fifteen seconds of audio; `PlaybackService` reads the engine's own position when it writes. Skips now move the engine (`SoughtTo`). Desktops have no background moment. `ListeningWritesTests.A_pause_a_skip_a_chapter_and_a_scrub_let_go_each_write_once_and_the_engine_follows_each_move`, `ListeningWritesTests.A_book_left_playing_is_written_every_fifteen_seconds_of_audio_and_not_while_paused` (2026-10-18). |
| Playback controls | Speed | wired, not proved | `PlayerWindow.SpeedBox` over `PlaybackSpeed.Offered` (0.5 to 3.0). `PlaybackRulesTests.Speed_is_clamped_to_the_range_and_stated_as_a_number`. The default for a series: no code found. |
| Playback controls | Skipping | wired, not proved | `PlaybackRulesTests.A_skip_crosses_a_chapter_boundary_and_stops_at_the_ends_of_the_book` and `PlayerModelTests.Skips_move_by_the_fixed_intervals_and_chapter_moves_land_on_starts`. |
| Playback controls | Sleep timer | wired, not proved | `PlayerWindow.SleepBox`. `PlaybackRulesTests.The_sleep_countdown_fades_over_its_last_thirty_seconds_and_records_a_little_before_the_end`. |
| Playback controls | Chapters | wired, not proved | `PlayerWindow.ChapterList`. `PlayerModelTests.The_chapter_list_marks_finished_in_progress_with_what_is_left_and_not_reached`. |
| Playback controls | Lock screen and system controls | wired, not proved | `TransportControlsTests.The_entry_shows_title_cover_and_position_while_a_session_exists_and_leaves_when_it_ends` and `TransportControlsTests.Each_key_maps_to_the_players_action_and_next_is_nothing_at_the_last_chapter`. |
| Playback controls | Something else takes the audio | wired, not proved | `AudioStateMonitor` in `PlaybackService`. `PlayerModelTests.An_interruption_resumes_by_itself_but_never_undoes_the_listeners_pause_and_audio_taken_for_good_ends_it`. |
| Playback controls | Headphones removed | wired, not proved | `MediaDevice.DefaultAudioRenderDeviceChanged` calls `RouteLost`. `PlayerModelTests.Headphones_removed_pauses_as_the_listener_would_so_nothing_resumes_on_its_own`. |
| Reaching the player without sight | Labels and values | wired, not proved | The XAML names every control and sets the clock as the help text of the scrub slider (`desktop-a11y-windows.md`). The slider speaks seconds, not a clock (gap 4 there). |
| Reaching the player without sight | The compact bar under a screen reader | wired, not proved | `PlayerBar` is one named element with two named buttons (`desktop-a11y-windows.md`). |
| Reaching the player without sight | At the largest text size | wired, not proved | The content of the player sits in a `ScrollViewer` and the text wraps (`desktop-a11y-windows.md`). No capture at 225 per cent exists. |
| Reaching the player without sight | The compact bar at the largest text size | wired, not proved | The bar trims its text with an ellipsis and keeps its two buttons at their size (`desktop-a11y-windows.md`). |
| Chapters before the first minute | The chapter list on the publication's page | wired, not proved | An audiobook's page reads its chapters before it plays and lists each with its length and mark (`PublicationDetailPage.ShowAudiobookAsync`). `ListeningWritesTests.The_page_lists_the_chapters_with_their_marks_and_names_the_chapter_it_resumes_inside` (2026-10-18). |
| Chapters before the first minute | Starting from a chapter | wired, not proved | A chapter on the page starts the book there (`AppHost.ListenFrom`); the saved position is only read (2026-10-18). |
| Chapters before the first minute | An audiobook with one part | wired, not proved | No list; the page states the length (`AudiobookDetail.ListsChapters`). `ListeningWritesTests.A_book_of_one_part_states_its_length_and_offers_no_list` (2026-10-18). |
| Chapters before the first minute | The primary action says where it will resume | wired, not proved | *Listen*, *Continue <chapter>* or *Continue listening* (`AudiobookDetail.PrimaryLabel`). `ListeningWritesTests.The_page_lists_the_chapters_with_their_marks_and_names_the_chapter_it_resumes_inside` (2026-10-18). |
| Listening in a car | Continuing in the car | n/a | CarPlay is dropped on a desktop (`design.md` Decision 9). |
| Listening in a car | Browsing audiobooks in the car | n/a | As above. |
| Listening in a car | The car's own transport controls | n/a | As above. |
| Listening in a car | Only what a car should carry | n/a | As above. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`. The requirements wave 4 names: *Keeping the display awake while reading* (the listening scenario), *Media keys and system media controls*, *Screen readers on each system*, *A book stays off the network on every desktop*.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Keeping the display awake while reading | Listening | wired, not proved | `PlaybackKeepAwake` holds `ES_SYSTEM_REQUIRED` while a session plays. `ReadAloudTests.The_system_is_kept_from_sleeping_only_while_the_session_plays`. |
| Media keys and system media controls | Media keys | wired, not proved | `TransportControlsTests.Each_key_maps_to_the_players_action_and_next_is_nothing_at_the_last_chapter`. |
| Media keys and system media controls | The system overlay | wired, not proved | `TransportControlsTests.The_entry_shows_title_cover_and_position_while_a_session_exists_and_leaves_when_it_ends` and `A_seek_in_the_overlay_stays_inside_the_timeline`. `AppHost` passes no cover for a narrated book. |
| Media keys and system media controls | Another application holds the keys | wired, not proved | `TransportControlsTests.While_nothing_plays_the_keys_are_left_to_whoever_holds_them`. |
| Media keys and system media controls | A device with no speech engine | wired, not proved | `ReadAloudTests.Without_a_voice_the_control_is_absent_and_nothing_starts`. `PlaybackService.HasVoice` gates the command. |
| Media keys and system media controls | The windows are hidden | wired, not proved | `PlaybackService` belongs to `AppHost` and the session outlives `PlayerWindow`. No test hides every window. |
| Screen readers on each system | Controls in the library | wired, not proved | Names are given in the XAML (`desktop-a11y-windows.md`). The source is missing from the name of a cell (gap 1 there). |
| Screen readers on each system | A page turn | wired, not proved | `PageLabel` and `PositionLabel` are polite live regions (`desktop-a11y-windows.md`). The text layer of a PDF page is not exposed (gap 2 there). |
| Screen readers on each system | A page with no text | wired, not proved | The image is named by its position and nothing else is invented (`desktop-a11y-windows.md`). |
| Screen readers on each system | What could not be opened | wired, not proved | `LibraryService.Refuse` sets the same sentence in a polite live region (`desktop-a11y-windows.md`). |
| Screen readers on each system | Orca without an accessibility bus | n/a | Linux. |
| A book stays off the network on every desktop | A book that tries to load a remote resource | wired, not proved | `EpubHostTests.The_eight_vectors_arrive_nowhere` and `EpubHostTests.Each_lock_alone_stops_what_it_governs`. The real web view is owed. |
| A book stays off the network on every desktop | A link to the web | wired, not proved | `RendererMessage.OutboundLink` keeps `http` and `https`. `Launcher.LaunchUriAsync` opens the default browser. `NewWindowRequested` is handled and `EpubHost.AllowsNavigation` blocks other navigation (`EpubHostTests.A_navigation_is_allowed_only_within_the_origin_and_a_frame_also_to_its_own_blobs`). |
| A book stays off the network on every desktop | A link inside the book | wired, not proved | The renderer moves the page inside the book and the window offers *Back* to the place left. `EpubMarksTests.A_jump_offers_one_way_back_that_is_not_itself_a_place_to_return_from` (2026-10-18). |
| A book stays off the network on every desktop | Proof on each desktop | wired, not proved | `EpubHostTests.The_eight_vectors_arrive_nowhere` runs the eight vectors through a fake WebView2 pipeline. The real web view is owed. |
