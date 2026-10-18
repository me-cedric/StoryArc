# Linux conformance walk, wave 4

Task 4.22 of `desktop-clients`. This record lists every scenario of the capabilities that wave 4 lane L names: the EPUB and PDF reader, the player and read-aloud. It is the Linux twin of `desktop-conformance-macos-wave4.md` and has the same 92 rows in the same order. It is dated 2026-10-18. It was written from existing evidence before the host pass: the wave 4 headless walk, the accessibility and audio notes, and the code and tests at the head of `main` (`b2d0fc35f`). No test was run and no build was made for this record. The host pass fills in the "not proved" rows on a real Linux desktop. The scenarios are read from the specs by name, so a scenario added to a spec later is missing here until the record is updated. For `desktop-experience`, only the requirements the wave 4 tasks name are listed.

| Result | Means |
| --- | --- |
| pass | A named test in `apps/desktop-linux/src` asserts it. |
| seen | A headless walk frame or dump (`docs/designs/screenshots/desktop/linux/wave4/`) shows it. Nothing asserts it. The evidence column says which. |
| not proved | It needs a real desktop session (a compositor, Orca, a sound device or media keys), or no test and no capture shows it. The evidence column says which, and what would prove it. |
| **fail** | It is not built on Linux today. The evidence column says what is missing. |
| n/a | Dropped on a desktop by `design.md` Decision 9, or another system's scenario, or the reason does not apply on Linux. |

Totals: pass 22, seen 8, fail 34, not proved 21, n/a 7, of 92 scenarios (written 2026-10-18).

**What the evidence is.**

- The walk (`apps/desktop-linux/scripts/wave4-walk.sh`, run 2026-10-17): the debug build under cage 0.1.5 (headless wlroots, 1280 by 720, pixman) in the Ubuntu 24.04 container (GTK 4.14.5, libadwaita 1.5.0, WebKitGTK 2.52.6, GStreamer 1.24.2). It had a session bus, an accessibility bus and no sound device. `wtype` and `gapplication action` drove it and `grim` captured it.
- What the walk measured: `fixture.epub` reported `ready` and the position *1 of 2*, and its view paints white because the container has no GPU. `text-pages.pdf` opened with a text pane and an outline, and a search for `chapter two` jumped to page *2 of 3*. `id3-chapters.mp3` played through `playerctl`: status, title, position, a pause and a seek to 2 seconds (`playerctl.txt`).
- Not run: Orca, GNOME, Hyprland, X11, a sound device, the media keys, a voice heard aloud (a null output stood in), the Flatpak runtime and the WebKitGTK 2.44 floor.
- Tests: the crate has 291 tests (`design.md`, Decision 5b notes). This record cites them by name and did not run them. The PDF, display and `playerctl` tests skip by name when PDFium, a display or `playerctl` is missing, and the container build supplies all three.

**Why the EPUB rows are mostly red.** The Linux EPUB window of task 4.10 is the host of Decision 6 and the egress proof. It turns pages, shows the position, reads one chapter aloud and opens links out. Its own header lists themes, search, highlights and the table of contents as later tasks of the lane. The renderer already answers those messages and the window does not send them. These rows are wave 5 and 6 work for Linux, not defects in what wave 4 built. The same holds for the player. Linux has the compact bar only. The full player, the speed, the sleep timer and the chapter list are not built (`desktop-a11y-linux.md`, `desktop-spike-audio-linux.md`).

## The failures, in one list

34 rows fail. Each one is a missing piece.

- **EPUB look and typography:** built 2026-10-18 (`epub_look.rs`, `epub_theme_ui.rs`). Eleven rows pass; three are not proved until a painted page or a larger text size exists.
- **EPUB position and navigation (9):** Moving somewhere else, A publication that declares no chapters, Table of contents, Bookmarks, Highlights and notes, Search within a publication, Following an internal link, Returning from any jump, A link inside the book.
- **PDF (1):** Text-based PDF has no highlight colours, no note and no search for the selection.
- **Read aloud and its transport (9):** Starting playback (no sentence highlight, starts at the chapter), Leaving the publication while it speaks, The same controls as a narrated book, Reaching the end of a chapter, Where the listening got to, Getting back to the book, Controlling it without going back, What it says, Opening a different publication.
- **Player (15):** The compact bar, The full player, A publication with no cover, Both sources look the same, Playback outlives the publication, Where a listening position is written, Speed, Skipping, Sleep timer, Chapters, Headphones removed, and the four *Chapters before the first minute* rows.

**Found while reading the code and the frames.**

- The skip buttons of the bar stay active for a voice and do nothing.
- `EpubReader::received` hands the `href` of a `link` message to the launcher with no scheme check. `epub_view::decide` does check.
- The shelf rows have no name, and the close button of the PDF search bar has no name (dump `a11y-pdf-search.txt` counts 3 controls with no name).
- The frame README says `epub-next.png` shows *2 of 2*. The frame has an empty foot and the same size as `epub-reader.png`. No capture shows the second position.

## ebook-reader

Source: `docs/openspec/specs/ebook-reader/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reflowable rendering | Typography controls | pass | The theme surface's second depth (`epub_theme_ui.rs`) sets size, typeface, bold, margins, line and paragraph spacing, alignment and hyphenation, and each change goes to the page as one `theme` message. `epub_look::tests::the_axes_follow_the_values_and_original_drops_the_dependent_ones` holds the mapping; `epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original` drives the controls under cage (2026-10-18). The painted page is owed to a session with a GPU. |
| Reflowable rendering | One sheet, two depths | pass | One popover: the presets first, then *Customise* to the reader's typography (`epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original`, under cage, 2026-10-18). |
| Reflowable rendering | Bundled typefaces | pass | The panel offers the publisher's own, serif, sans and the five faces of `packages/fonts`, embedded and served on the book's scheme with a `@font-face` sheet every chapter links (`epub_look::tests::the_five_faces_are_served_and_linked_from_every_chapter`, 2026-10-18). A face drawn on the page needs a session with a GPU. |
| Reflowable rendering | Publisher styles | pass | *Original* sends `publisherStyles` and no colour, spacing, alignment or hyphens (`epub_look::tests::every_preset_has_its_token_colours_and_original_keeps_the_book`, `the_axes_follow_the_values_and_original_drops_the_dependent_ones`, 2026-10-18). |
| Reflowable rendering | An axis is inert while publisher styles are on | pass | Under *Original* the spacing, alignment and hyphenation group is insensitive with the sentence that says why (`epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original`, under cage), and those axes are not sent (`the_axes_follow_the_values_and_original_drops_the_dependent_ones`, 2026-10-18). |
| Reflowable rendering | Fixed-layout EPUB | not proved | The core test `epub_positions` reads `ebooks/fixed-layout.epub`. How WebKitGTK paginates it needs a painted view. The walk view paints white because the container has no GPU. A session with a GPU would prove it. |
| Reader themes | Theme choice | pass | The six presets as swatches in their token colours, and a brightness slider that dims the page (`darkenFilter`): `epub_look::tests::every_preset_has_its_token_colours_and_original_keeps_the_book`, `the_axes_follow_the_values_and_original_drops_the_dependent_ones` (2026-10-18). |
| Reader themes | The theme surface opens on the presets | pass | The surface is built each time it opens, on the six swatches; *Customise* below them opens the axes; a swatch applies its preset and closes the surface (`epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original`, under cage, 2026-10-18). |
| Reader themes | Themes are named, not numbered | pass | Each swatch carries its name and an *Aa* specimen in its own colours, the active one is checked and outlined, and it reads *Modified* when the typography moved (`epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original`, `epub_look::tests::the_size_ladder_holds_its_ends_and_the_reset_clears_modified`, 2026-10-18). |
| Reader themes | The axes, over the reader's own text | not proved | The axes sit in a popover over the page and each change sends a `theme` message at once (`EpubReader::change_look`). The page paints white in the container; a session with a GPU, watching the text change under the popover, proves it. |
| Reader themes | Getting back to the preset | pass | *Restore {preset}* puts every axis back and is insensitive when nothing moved (`epub_theme_ui::tests::the_surface_opens_on_named_presets_and_its_second_depth_obeys_original`, under cage, 2026-10-18). |
| Reader themes | Theme follows appearance | pass | *Follow the system's appearance* with a light and a dark preset; the window applies the pair on the style manager's dark change and at open (`epub_look::tests::the_look_follows_the_appearance_only_when_asked_and_round_trips`, 2026-10-18). A real appearance switch is owed to the host pass. |
| Reader themes | Both levels at the largest text size | not proved | Both depths are `AdwPreferencesGroup` rows and a scrolled popover, so they wrap and scroll. The walk has no settings portal, so GTK draws no larger text; a capture at the largest text size on a real desktop proves it. |
| Pagination and progress | Changing type size mid-chapter | not proved | The size steps the phones' ladder (`epub_look::tests::the_size_ladder_holds_its_ends_and_the_reset_clears_modified`) and a theme message does not move the locator. A walk that changes the size mid-chapter and reads the renderer's locator back proves the place is kept. |
| Pagination and progress | Progress display | pass | The foot states the share of the book read and what is left of the chapter, never a page number (`epub_look::tests::the_progress_line_names_the_book_share_and_the_chapter_left`, 2026-10-18). |
| Pagination and progress | Moving somewhere else in a reflowable publication | fail | No table of contents exists. |
| Pagination and progress | A publication that declares no chapters | fail | No progress line and no contents menu exist. |
| Pagination and progress | Scroll mode | pass | One switch in the second depth sends `scroll` to the renderer (`epub_look::tests::the_axes_follow_the_values_and_original_drops_the_dependent_ones`, 2026-10-18). |
| Navigation and annotation | Table of contents | fail | Not built. The header of `epub_window.rs` lists it as a later task of the lane. |
| Navigation and annotation | Bookmarks | fail | Not built for the EPUB. `win.bookmark` in `commands.rs` belongs to the image reader. |
| Navigation and annotation | Highlights and notes | fail | Not built. The window draws no selection bar, no highlight and no note. |
| Navigation and annotation | Search within a publication | fail | Not built for the EPUB. A PDF has search (see the PDF rows). |
| Navigation and annotation | Following an internal link | fail | No footnote popover exists. The renderer moves the page and the window offers no way back. |
| Navigation and annotation | Returning from any jump | fail | The EPUB window offers no way back after a link. A PDF search hit does: the foot shows *Back to page 1* (frame `pdf-search-hit.png`). |
| Navigation and annotation | Following a link out of the publication | pass | `epub_view::link_tests::only_a_web_address_with_a_host_leaves_the_book`: only `http` and `https` with a host leave the book, from the renderer's `link` message and from the web view's own navigation. Both ask *Open a page on {host}?* in an `AdwAlertDialog` and launch only on *Open in Browser* (`epub_view::confirm_leaving`, 2026-10-18). The dialog is not walked. |
| Navigation and annotation | A publication reaching the network on its own | pass | `epub_view::tests::the_eight_vector_page_reaches_nothing_through_the_guarded_view`: 9 arrivals unguarded and 0 guarded on WebKitGTK 2.52.6, under cage in the container. `epub_host` tests assert the rule list and the header. The 2.44 floor and the Flatpak runtime were not run. |
| PDF rendering | Text-based PDF | fail | Search, outline and selection through the text pane are built (`pdf_ui.rs`). `the_text_pdf_reads_as_the_phones_read_it_at_the_window` asserts the text, the outline and the search hits. Frames `pdf-reader.png` and `pdf-search-hit.png` show them. A selection offers no highlight colours, no note and no search for the selection. Those are not built. |
| PDF rendering | Scanned PDF | pass | `the_image_pdf_reads_as_a_comic_with_no_text_controls` asserts no text layer, no markers and no search hits. `pdf_ui::install` then adds no text pane, no search and no read aloud, and shows the one sentence in a banner. The banner shows when the file opens and not on a press. It was not captured. |
| PDF rendering | A text layer is detected rather than assumed | pass | `the_text_pdf_reads_as_the_phones_read_it_at_the_window` and `the_image_pdf_reads_as_a_comic_with_no_text_controls` read `has_text_layer` from the two corpus files. One has text and one has none. |
| PDF rendering | A device that cannot read PDF text | n/a | The app bundles PDFium, so the text API is on every Linux build. |
| PDF rendering | Large PDF | not proved | The reader asks for a page when it shows it (`Reader::request`) and the page sizes are known before any render (`page_sizes`). No fixture of several hundred megabytes exists. The 300 MB file over a share is the host walk (task 4.4). |
| PDF rendering | A rendered page is bounded by what it is shown at | pass | `a_scale_of_two_asks_the_pdf_for_twice_the_pixels` asserts that the pixels follow the window scale and that the edge cap holds. |
| PDF rendering | Page rendering is identical across platforms | seen | Frame `pdf-reader.png` shows page 1 at its own aspect ratio. `the_text_pdf_reads_as_the_phones_read_it_at_the_window` asserts the geometry in PDF points. The comparison with the other platforms is the core corpus test, not a Linux walk. |

## ebook-reader (read-aloud delta)

Source: `docs/openspec/changes/read-aloud-beyond-the-reader/specs/ebook-reader/spec.md`. The MODIFIED *Reading aloud* block replaces the main spec's, so the main spec's six scenarios are read in their delta wording, and *The transport outside the reader* is the delta's ADDED requirement.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reading aloud | Starting playback | fail | The voice starts at the first sentence of the chapter the reader is in (`EpubReader::read_aloud`), not at the position. No sentence is highlighted and the page does not follow. The bar names the book and *Reading aloud*, not the chapter. The *Read aloud* button is named in dump `a11y-epub-reader.txt`. |
| Reading aloud | Leaving the publication while it speaks | fail | The voice runs on the app `Player`, so a closed window does not own it. The bar has no way back to the book, and a reopened book does not go to the sentence being spoken. No walk closes a speaking book. |
| Reading aloud | The same controls as a narrated book | fail | No full player, no speed, no sleep timer and no chapter list exist. The skip buttons of the bar do nothing for a voice. No page names the voice. |
| Reading aloud | Background and lock screen | not proved | `Player::show_in_controls` publishes a voice to MPRIS. The tests assert the metadata for an audiobook. The walk played an audiobook only, and the shell panel needs a real desktop. The chapter line is not shown. |
| Reading aloud | Reaching the end of a chapter | fail | The voice reads one chapter. At its last sentence `Player::tick` calls `stop`. It does not carry on into the next chapter. |
| Reading aloud | Where the listening got to | fail | `Player::write_position` writes for an audiobook only. The page does not follow the voice, so the EPUB window cannot write where the voice got to. |
| Reading aloud | Something else takes the audio | not proved | It needs a second player or a call on a real session. The audio spike records that the app does not read the cork of PipeWire (gap 4 of `desktop-spike-audio-linux.md`). |
| Reading aloud | A publication with nothing to say | not proved | A PDF with no text layer gets no read aloud control (`pdf_ui::install`). The EPUB window offers the control whenever a speech engine exists, and an empty chapter gets the toast *This page has nothing to read aloud.* No book with no text was tried. |
| The transport outside the reader | Getting back to the book | fail | The bar has no action that opens the book (`player_ui::bar`). |
| The transport outside the reader | Controlling it without going back | fail | The bar has *Play* or *Pause* and *Stop* (dump `a11y-player-bar.txt`). Sentence skip is not on the bar. Its skip buttons do nothing for a voice. Next and Previous reach a sentence only through MPRIS. |
| The transport outside the reader | What it says | fail | The bar names the book and *Reading aloud*. It does not name the chapter. |
| The transport outside the reader | It is absent when nothing is playing | seen | Frame `library.png` shows no bar before a session and no space kept for it. `Bar::show` hides the revealer when the state is stopped. The end of a session was not captured. |
| The transport outside the reader | Opening a different publication | fail | Opening another book does not end a voice. No notice says that a voice stopped. Only a new read aloud or a new audiobook calls `stop_quietly`. |
| The transport outside the reader | The transport on iOS | n/a | iOS. |
| The transport outside the reader | The transport on Android | n/a | Android. |
| The transport outside the reader | The session cannot continue | not proved | `Player::tick` and `Player::on_audio` log an engine error and call `stop`, which writes the audiobook position first. No test and no walk drives a lost engine. |
| The transport outside the reader | Reaching the transport without touch | seen | Dump `a11y-player-bar.txt` lists `Cover`, the title, `15 s back`, `Play`, `30 s forward`, `Stop` and the slider `Position`. Focus stays on the sidebar row, so the bar does not take it. The bar has no open action. |

## audio-playback (audiobooks delta)

Source: `docs/openspec/changes/audiobooks-and-playback/specs/audio-playback/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| One player for everything that speaks | The compact bar | fail | The bar shows the title and the author and has play, skip and stop (frame `player-bar.png`). It does not name the chapter and has no action that opens a full player. |
| One player for everything that speaks | Nothing is playing | seen | Frame `library.png` shows no bar and no reserved space. |
| One player for everything that speaks | The full player | fail | Not built on Linux (`desktop-a11y-linux.md`). |
| One player for everything that speaks | A publication with no cover | fail | The bar draws nothing where a cover is missing (`Bar::show` clears the paintable). The shared coverless artwork is not drawn, and MPRIS gets no art. |
| One player for everything that speaks | Both sources look the same | fail | One bar draws both sources (`Bar::show`). Its skip buttons stay active for a voice and do nothing. Its second line reads *Reading aloud*. No page names the voice. |
| One player for everything that speaks | Playback outlives the publication | fail | The sound does not depend on a window, because `Player` belongs to the app. The bar gives no way back to where the audio reads. No walk closes a window while audio plays. |
| One player for everything that speaks | Starting a second thing | not proved | `play_audiobook` and `read_aloud` call `stop_quietly` first, which writes the first position. No test starts two sessions. |
| One player for everything that speaks | Where a listening position is written | fail | `Player::write_position` runs on a stop and every 15 seconds (`WRITE_EVERY`). A pause, a skip, a seek and a change of part write nothing at once. |
| Playback controls | Speed | fail | The engine takes a rate (`AudioPlayer::set_rate`, 0.5 to 3.0). No control sets it and nothing remembers it. |
| Playback controls | Skipping | fail | The controls state *15 s back* and *30 s forward* (dump `a11y-player-bar.txt`). `AudioPlayer::skip` stops at the ends of the file and does not go on into the neighbouring part. No test asserts skip. |
| Playback controls | Sleep timer | fail | Not built. |
| Playback controls | Chapters | fail | No chapter list and no marks exist. The core reads no audiobook chapters (gap 2 of `desktop-spike-audio-linux.md`). Next and Previous step through the parts of a folder, through MPRIS only. |
| Playback controls | Lock screen and system controls | pass | `playerctl_controls_playback_and_shows_the_metadata` asserts the title, the cover address, the position, pause, seek and next through MPRIS. `the_metadata_carries_title_cover_length_and_an_object_path_track` asserts the metadata. The chapter line is not shown, because no chapter list exists. The shell panel is owed. |
| Playback controls | Something else takes the audio | not proved | As for read aloud. It needs a second player or a call on a real session. |
| Playback controls | Headphones removed | fail | No device watcher exists (gap 5 of `desktop-spike-audio-linux.md`). PipeWire moves the stream to the speakers and the book plays on. |
| Reaching the player without sight | Labels and values | seen | Dump `a11y-player-bar.txt` names every control and the slider `Position`. The slider value text is the clock (`Bar::show`). The dump prints names and not values. Speed and sleep time do not exist. |
| Reaching the player without sight | The compact bar under a screen reader | seen | As in the row *Reaching the transport without touch*. The group named *Now playing* prints as an unnamed panel in the dump. The bar has no open action. |
| Reaching the player without sight | At the largest text size | not proved | No full player exists. The walk has no settings portal, so GTK has no larger text size to show. |
| Reaching the player without sight | The compact bar at the largest text size | not proved | The bar wraps in two rows (`player_ui.rs`). No capture at a large text size exists, because the walk has no settings portal. |
| Chapters before the first minute | The chapter list on the publication's page | fail | The publication page has no audiobook section (`library/detail.rs`). |
| Chapters before the first minute | Starting from a chapter | fail | No chapter list exists to start from. |
| Chapters before the first minute | An audiobook with one part | fail | The page does not state the length of an audiobook. |
| Chapters before the first minute | The primary action says where it will resume | fail | The page offers *Read* or *Continue reading* by page progress. It names no chapter. |
| Listening in a car | Continuing in the car | n/a | CarPlay is dropped on a desktop (`design.md` Decision 9). |
| Listening in a car | Browsing audiobooks in the car | n/a | As above. |
| Listening in a car | The car's own transport controls | n/a | As above. |
| Listening in a car | Only what a car should carry | n/a | As above. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`. The requirements wave 4 names: *Keeping the display awake while reading* (the listening scenario), *Media keys and system media controls*, *Screen readers on each system*, *A book stays off the network on every desktop*.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Keeping the display awake while reading | Listening | not proved | `Player::publish` holds `app.inhibit` with the suspend and idle flags while audio plays and lets it go on a pause or a stop. The `idle` tests assert one hold, one release and a silent refusal. `inhibit.txt` shows the state change only. A session that grants the inhibit is owed (task 4.14). |
| Media keys and system media controls | Media keys | not proved | It needs a real desktop that routes the keys to MPRIS. `calls_become_commands_and_unknown_ones_are_refused` and the `playerctl` test assert the same commands. |
| Media keys and system media controls | The system overlay | pass | `playerctl_controls_playback_and_shows_the_metadata` asserts the title, the cover address, the position and a seek, and that the entry leaves when the player is dropped. `playerctl.txt` shows the status, the title, a pause and a seek during the walk. The shell panel is owed. |
| Media keys and system media controls | Another application holds the keys | not proved | The app grabs no key (`mpris.rs`). Proof needs a second player on a real desktop. |
| Media keys and system media controls | A device with no speech engine | not proved | `speech_available` gates the button in `epub_window::open` and `pdf_ui::install`. No test and no walk ran without an engine. A walk in a container with no speech-dispatcher would prove it. |
| Media keys and system media controls | The windows are hidden | not proved | `Player` belongs to the app and not to a window. No walk hid every window. It needs a real session. |
| Screen readers on each system | Controls in the library | seen | Dump `a11y-library.txt` names the header controls. The sidebar rows are named since this lane (`library_window::named_row`). The shelf rows *New collection* and *New reading list* still have no name. The order Orca speaks is owed. |
| Screen readers on each system | A page turn | not proved | The PDF page is an `image` named *1 of 3* and the text pane is a readable text object (dump `a11y-pdf-reader.txt`). The EPUB position label reads *1 of 2* (dump `a11y-epub-reader.txt`). Frame `epub-next.png` shows an empty foot, so no capture shows *2 of 2*. Whether Orca announces a turn is owed. |
| Screen readers on each system | A page with no text | not proved | `a_page_announces_its_number_its_chapter_and_that_it_is_current` asserts the page label of the image reader. No dump covers `image-pages.pdf` and Orca did not run. |
| Screen readers on each system | What could not be opened | pass | `bytes_that_are_not_a_pdf_are_refused_by_name` asserts the named refusal. The toast and the cell description carry the same sentence (wave 2). Orca speaking it is owed. |
| Screen readers on each system | Orca without an accessibility bus | seen | The walks of waves 2 and 3 ran with no accessibility bus and the app ran as usual. The wave 4 walk ran with one and the app ran the same (`desktop-a11y-linux.md`). |
| A book stays off the network on every desktop | A book that tries to load a remote resource | pass | `the_eight_vector_page_reaches_nothing_through_the_guarded_view`: 0 of the attempts arrive guarded. The renderer reported `ready`. The view paints white in the container. |
| A book stays off the network on every desktop | A link to the web | not proved | `a_web_link_opens_outside_and_the_rest_is_dropped` asserts the policy. `epub_view::decide` hands the address to the launcher and the book stays. Opening the default browser needs a real session. |
| A book stays off the network on every desktop | A link inside the book | fail | The renderer moves the page and the window offers no way back to the previous place. |
| A book stays off the network on every desktop | Proof on each desktop | pass | `the_eight_vector_page_reaches_nothing_through_the_guarded_view`: 9 arrivals unguarded and 0 guarded on WebKitGTK 2.52.6 under cage. The 2.44 floor and the Flatpak runtime are a host walk. |
