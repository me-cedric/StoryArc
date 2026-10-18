# macOS conformance walk — wave 4

Task 4.22 of `desktop-clients`. Every scenario of the capabilities wave 4 lane M names — the
EPUB and PDF reader, the player and read-aloud — run against the Mac app at the head of
`claude/lane-macos-wave56-7be24f` on 2026-10-18 (macOS 27.0.1, Xcode 27.1, the ad-hoc signed
sandboxed build), with the result it gave. `xcodebuild test` runs 238 tests in 62 suites; 236
pass, and the two that fail predate this lane: the quit-during-a-download walk (the resumed
download did not finish within its wait) and a 0.69% drift of the `player.dark` reference. The
capture suites are skipped, as they are unless asked for. The scenarios are read from the specs
by name, so a scenario added to a spec later is missing here until the walk runs again. For
`desktop-experience`, only the requirements the wave 4 tasks name are listed.

| Result | Means |
| --- | --- |
| pass | A named test in `apps/desktop-macos/Tests` asserts it inside the running app. |
| seen | A wave 4 frame (`docs/designs/screenshots/desktop/macos/wave4/`) or the app's code shows it; nothing asserts it. The evidence column says which. |
| **fail** | It does not hold on the Mac today. Each one is a missing piece, listed below. |
| later | Not on the Mac in wave 4, as named. |
| n/a | Dropped on a desktop by `design.md` Decision 9, or another system's scenario. |
| not walked | Built, mostly in StoryArcKit, and not exercised by a Mac walk, for the reason given. |

Totals: pass 23, seen 11, fail 42, later 0, n/a 10, not walked 6, of 92 scenarios.

**What the walk is.** The walks run inside the app as `StoryArcMacTests` (`WindowWalks`), as in
waves 2 and 3. Wave 4 adds four: the EPUB walk over the corpus `fixture.epub` in the Mac's web
view (`EpubWalkTests`), the PDF walk over `text-pages.pdf` and `image-pages.pdf`
(`PdfWalkTests`), the player walk over `chaptered.m4b` with a keyboard (`PlayerWalkTests`),
and the egress proof, whose eight-vector page is counted by the collector of
`apps/desktop-web/epub` out of process on port 4815, because the sandboxed app may not listen
(`EpubEgressTests`). The media keys and the Now Playing panel are measured against a fake
command centre and board (`NowPlayingTests`), the voice against a fake speaker and voice list
(`ReadAloudTests`): the system's own panel, keys and voices are the VoiceOver session by hand
that `docs/delivery/desktop-a11y-macos.md` lists. The OPDS and Kavita mocks ran on 4748 and
4747 for the wave 3 suites that share the run; the share walks skipped, as Samba is not on
this Mac.

**What the walks measured** (`ConformanceLog`, the container's `tmp/conformance/wave4.log`):

- egress: the control page, 8 of 8 vectors arrived; guarded, 0 of 8;
- EPUB: *Fixture Publication*, 2 positions; two right arrows reached position 2; `chapter`
  found 82 hits, each with a chapter name; the close, after the way back to position 1, wrote a
  reflowable position at progression 0.0 with a locator;
- PDF: `text-pages.pdf` opened with a text layer and 3 outline chapters; `three` had 1 hit, on
  page 2; the drag over page 2 selected 13 characters, *Chapter Three*; `image-pages.pdf`
  opened with no text layer and no markers;
- player: *Chaptered*, 3 parts; space paused and played; the right arrow moved the place from
  part 0 at 0 seconds to part 2 at 2 seconds; with the window closed the session ran on.

**Why the EPUB column is mostly red.** The wave 4 Mac EPUB is the host of design.md Decision 6
and the egress proof, with the six presets, search, the way back, keys and read-aloud: tasks
4.5 and 4.8 asked for that and no more. The typography axes, the table of contents, bookmarks,
highlights, scroll mode, the progress sentence and the footnote popover are what the renderer
already posts and the host does not yet draw; they are wave 5 and 6 work for the Mac, not
defects in what wave 4 built. The same holds for the player's sleep timer, the chapter marks and
the chapter list on the publication's page.

**The compact bar.** The Mac draws no compact bar. The a11y record of task 4.9 treated the two
bar scenarios as not applicable because the session outlives its window on the one player and
the Now Playing panel is the way back. No design decision dropped the bar on a desktop, so this
record lists the four bar rows as failures, which is the honest reading until the owner decides.

**Wave 4 on this branch**, with its commits: the EPUB host, PDF text, media keys and read-aloud
(`c53920d0f`), the a11y note and the frames (`89a634f71`), merged to main in `8a22f7231`.

## The failures, in one list

- `ebook-reader` · *Typography controls*: The Mac's theme menu offers the six presets and nothing else: no font size, family, spacing, margin, alignment or brightness axis (`EpubReaderWindow.themeMenu`).
- `ebook-reader` · *One sheet, two depths*: One level, the presets; there is no second depth because there are no axes.
- `ebook-reader` · *Bundled typefaces*: No typeface choice; the reading fonts the phone bundles are not in the Mac build (`MacAbout.linked`).
- `ebook-reader` · *Publisher styles*: Publisher styles follow the preset (*Original* keeps them, `EpubReaderModel.axes(of:)`); no control turns them off on their own.
- `ebook-reader` · *An axis is inert while publisher styles are on*: No axis is shown, so none is marked.
- `ebook-reader` · *Theme choice*: The six presets apply and the renderer confirms the theme (`EpubWalkTests` applies *Quiet* and *Paper*); no brightness control.
- `ebook-reader` · *The theme surface opens on the presets*: The menu lists the presets and nothing else; the action that opens the axes is absent with the axes.
- `ebook-reader` · *Themes are named, not numbered*: Named *Original* to *Focus* (`desktop.epub.theme.*`), as rows of a menu with a check mark; no swatch and no specimen.
- `ebook-reader` · *The axes, over the reader's own text*: No axes surface.
- `ebook-reader` · *Getting back to the preset*: Nothing deviates from a preset, so nothing restores one.
- `ebook-reader` · *Theme follows appearance*: No setting links the appearance to the reading theme; the page keeps its preset in dark mode (wave 4 frame `epub-reader-dark.png`).
- `ebook-reader` · *Changing type size mid-chapter*: No type size control.
- `ebook-reader` · *Progress display*: The foot states *Position N of M* (`EpubWalkTests` reads 1 then 2 of 2) and no slider is drawn; the sentence in words with the chapter's remainder is not there, and the position sits in the chrome, which hides.
- `ebook-reader` · *Moving somewhere else in a reflowable publication*: The manifest carries the table of contents (`EpubWebPublicationTests`); no Mac control shows it.
- `ebook-reader` · *A publication that declares no chapters*: Follows from the line above: there is no line.
- `ebook-reader` · *Scroll mode*: Paginated only; no scroll mode is sent to the renderer.
- `ebook-reader` · *Table of contents*: Built in the manifest, not shown.
- `ebook-reader` · *Bookmarks*: Not on the Mac in wave 4 (the wave 4 hand-over's owed list).
- `ebook-reader` · *Highlights and notes*: The renderer posts a selection; the Mac host ignores it. The PDF has the four actions (`PdfTextTests`), the EPUB has none.
- `ebook-reader` · *Following an internal link*: An internal link moves the reader inside the renderer and posts the new locator; no footnote popover, and no way back is kept for a link (`returnLocator` is set by `go(to:)` alone).
- `ebook-reader` · *Returning from any jump*: After a search hit the way back is offered and using it is not a place to return from (`EpubWalkTests`: `returnLocator` set, then nil after `goBack`); after a link there is none, and there is no contents entry or bookmark to jump by.
- `ebook-reader` · *Following a link out of the publication*: `http` and `https` go to the default browser and any other scheme is dropped (`EpubReaderModel.follow`, `EpubLinkOpener`); the host is not shown or confirmed first.
- `ebook-reader` · *Starting playback*: The voice starts at the first sentence of the chapter of the current position, on the one player (`EpubReaderModel.toggleReadAloud`); the sentence is stated in the foot, not highlighted in the page, and the page does not follow. The Mac draws no compact bar.
- `ebook-reader` · *Leaving the publication while it speaks*: The voice runs on `PlayerCentre.shared`, which outlives its window (`PlayerWalkTests` shows it for a narrated book); reopening the book shows the saved reading position, not the sentence being spoken.
- `ebook-reader` · *The same controls as a narrated book*: Speed and sentence skip work (`ReadAloudTests` *walks the sentences*, `NowPlayingTests` *A voice gets sentence skip*); there is no sleep timer and no full player window for the voice.
- `ebook-reader` · *Where the listening got to*: `MacPlayer.wire` writes the centre's positions for audio formats only; a voice's place is not written, and closing the book writes the reading position.
- `ebook-reader` · *Getting back to the book*: The Mac draws no compact bar; the voice's transport is the system's Now Playing panel, which offers no way to the book's window.
- `ebook-reader` · *Opening a different publication*: A second book replaces the first on the one `PlayerCentre` (StoryArcKit); nothing tells the listener that the voice stopped.
- `audio-playback` · *The compact bar*: The Mac draws no compact bar: the session outlives the window and the way back is the player window and the Now Playing panel. No design decision dropped the bar on a desktop, so it is listed as missing, where the a11y record called it not applicable.
- `audio-playback` · *The full player*: `PlayerWindow` has the cover slot, the title, the chapter, the position and duration, play and pause, skip back and forward, the scrub slider, the chapters and the speed, on the same session (`PlayerWalkTests` reopens it without a restart); no sleep timer.
- `audio-playback` · *A publication with no cover*: A headphones glyph in the cover slot (`PlayerWindow.artwork`, frame `player-light.png`); not the kind over the format's name, and the panel is given no artwork for it.
- `audio-playback` · *Both sources look the same*: A voice has no player window on the Mac; it is started and stopped from the EPUB window's Read Aloud button.
- `audio-playback` · *Sleep timer*: No sleep timer on the Mac in wave 4 (`MacPlaybackPlatform.sleepTimerChanged` is empty).
- `audio-playback` · *Chapters*: The Chapters menu lists each part by title or number and plays it (`PlayerWindow.settings`); no duration, no finished or in-progress mark, no remaining time.
- `audio-playback` · *Headphones removed*: No route observer on the Mac (`MacPlayer`); playback goes on through the speaker.
- `audio-playback` · *The compact bar under a screen reader*: No bar.
- `audio-playback` · *The compact bar at the largest text size*: No bar.
- `audio-playback` · *The chapter list on the publication's page*: The Mac's publication page lists no audiobook chapters (`DetailView`).
- `audio-playback` · *Starting from a chapter*: `MacPlayer.listen(part:)` starts at a chosen part, but no page offers the choice.
- `audio-playback` · *An audiobook with one part*: No chapter list on the page, so nothing states the duration either.
- `audio-playback` · *The primary action says where it will resume*: The page's open action names no chapter.
- `desktop-experience` · *A link inside the book*: The reader moves there; no way back is offered after a link.

## ebook-reader

Source: `docs/openspec/specs/ebook-reader/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reflowable rendering | Typography controls | **fail** | The Mac's theme menu offers the six presets and nothing else: no font size, family, spacing, margin, alignment or brightness axis (`EpubReaderWindow.themeMenu`). |
| Reflowable rendering | One sheet, two depths | **fail** | One level, the presets; there is no second depth because there are no axes. |
| Reflowable rendering | Bundled typefaces | **fail** | No typeface choice; the reading fonts the phone bundles are not in the Mac build (`MacAbout.linked`). |
| Reflowable rendering | Publisher styles | **fail** | Publisher styles follow the preset (*Original* keeps them, `EpubReaderModel.axes(of:)`); no control turns them off on their own. |
| Reflowable rendering | An axis is inert while publisher styles are on | **fail** | No axis is shown, so none is marked. |
| Reflowable rendering | Fixed-layout EPUB | seen | `EpubWebPublicationTests` *a fixed-layout book says so*: the manifest the renderer reads carries `layout: fixed`; how the bundle paginates it is the renderer's, and the Mac adds no zoom or spread over the web view. |
| Reader themes | Theme choice | **fail** | The six presets apply and the renderer confirms the theme (`EpubWalkTests` applies *Quiet* and *Paper*); no brightness control. |
| Reader themes | The theme surface opens on the presets | **fail** | The menu lists the presets and nothing else; the action that opens the axes is absent with the axes. |
| Reader themes | Themes are named, not numbered | **fail** | Named *Original* to *Focus* (`desktop.epub.theme.*`), as rows of a menu with a check mark; no swatch and no specimen. |
| Reader themes | The axes, over the reader's own text | **fail** | No axes surface. |
| Reader themes | Getting back to the preset | **fail** | Nothing deviates from a preset, so nothing restores one. |
| Reader themes | Theme follows appearance | **fail** | No setting links the appearance to the reading theme; the page keeps its preset in dark mode (wave 4 frame `epub-reader-dark.png`). |
| Reader themes | Both levels at the largest text size | seen | Frame `epub-reader-light-largest.png`: the theme menu reads in full at the app's largest size; `AccessibilityAuditTests` at both sizes. One level only. |
| Pagination and progress | Changing type size mid-chapter | **fail** | No type size control. |
| Pagination and progress | Progress display | **fail** | The foot states *Position N of M* (`EpubWalkTests` reads 1 then 2 of 2) and no slider is drawn; the sentence in words with the chapter's remainder is not there, and the position sits in the chrome, which hides. |
| Pagination and progress | Moving somewhere else in a reflowable publication | **fail** | The manifest carries the table of contents (`EpubWebPublicationTests`); no Mac control shows it. |
| Pagination and progress | A publication that declares no chapters | **fail** | Follows from the line above: there is no line. |
| Pagination and progress | Scroll mode | **fail** | Paginated only; no scroll mode is sent to the renderer. |
| Navigation and annotation | Table of contents | **fail** | Built in the manifest, not shown. |
| Navigation and annotation | Bookmarks | **fail** | Not on the Mac in wave 4 (the wave 4 hand-over's owed list). |
| Navigation and annotation | Highlights and notes | **fail** | The renderer posts a selection; the Mac host ignores it. The PDF has the four actions (`PdfTextTests`), the EPUB has none. |
| Navigation and annotation | Search within a publication | pass | `EpubWalkTests` *The fixture opens, turns, themes, searches and writes where it got to*: `chapter` lists its hits with the text before and after and the chapter, and the first hit moves the reader |
| Navigation and annotation | Following an internal link | **fail** | An internal link moves the reader inside the renderer and posts the new locator; no footnote popover, and no way back is kept for a link (`returnLocator` is set by `go(to:)` alone). |
| Navigation and annotation | Returning from any jump | **fail** | After a search hit the way back is offered and using it is not a place to return from (`EpubWalkTests`: `returnLocator` set, then nil after `goBack`); after a link there is none, and there is no contents entry or bookmark to jump by. |
| Navigation and annotation | Following a link out of the publication | **fail** | `http` and `https` go to the default browser and any other scheme is dropped (`EpubReaderModel.follow`, `EpubLinkOpener`); the host is not shown or confirmed first. |
| Navigation and annotation | A publication reaching the network on its own | pass | `EpubEgressTests`: the eight-vector page, control 8 of 8 arrivals unguarded, 0 of 8 through the rule list, the header and the scheme; *The rules are rules WebKit accepts* |
| PDF rendering | Text-based PDF | pass | `PdfWalkTests` *The text PDF searches, jumps, selects and marks*; `PdfTextTests` for selection, copy, the five colours, the note, search for the selection and the outline; frame `pdf-selection-*.png` |
| PDF rendering | Scanned PDF | pass | `PdfWalkTests`: `image-pages.pdf` gets no text model and no markers; a press on it shows the one-sentence alert (`desktop.pdf.noText.*`, `ReaderWindow`) |
| PDF rendering | A text layer is detected rather than assumed | pass | `PdfTextTests` *A text layer is detected rather than assumed: the scan gets no model* |
| PDF rendering | A device that cannot read PDF text | n/a | PDFKit's text API is on every Mac the floor allows. |
| PDF rendering | Large PDF | not walked | PDFKit renders a page when asked, through StoryArcKit's `PdfDocumentReader`; no several-hundred-megabyte fixture exists, and the 300 MB file over a share is the host walk at the end of the waves (task 4.4). |
| PDF rendering | A rendered page is bounded by what it is shown at | not walked | The bound is `PdfDocumentReader`'s, tested in StoryArcKit; no Mac walk measures a page's pixels. |
| PDF rendering | Page rendering is identical across platforms | seen | `PdfTextTests` *The page geometry maps the view and the page both ways*, in PDF points; the comparison with the other platforms is the corpus test, not a Mac walk. |

## ebook-reader (read-aloud delta)

Source: `docs/openspec/changes/read-aloud-beyond-the-reader/specs/ebook-reader/spec.md`. The MODIFIED *Reading aloud* block replaces the main spec's, so the main spec's six scenarios are read in their delta wording, and *The transport outside the reader* is the delta's ADDED requirement.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Reading aloud | Starting playback | **fail** | The voice starts at the first sentence of the chapter of the current position, on the one player (`EpubReaderModel.toggleReadAloud`); the sentence is stated in the foot, not highlighted in the page, and the page does not follow. The Mac draws no compact bar. |
| Reading aloud | Leaving the publication while it speaks | **fail** | The voice runs on `PlayerCentre.shared`, which outlives its window (`PlayerWalkTests` shows it for a narrated book); reopening the book shows the saved reading position, not the sentence being spoken. |
| Reading aloud | The same controls as a narrated book | **fail** | Speed and sentence skip work (`ReadAloudTests` *walks the sentences*, `NowPlayingTests` *A voice gets sentence skip*); there is no sleep timer and no full player window for the voice. |
| Reading aloud | Background and lock screen | pass | `NowPlayingTests` *Playback starting puts the title, the chapter and the position on the panel* and *A voice gets sentence skip in the track buttons and no scrubber*; hidden windows keep playing (`PlayerWalkTests`) |
| Reading aloud | Reaching the end of a chapter | pass | `ReadAloudTests` *The voice walks the sentences across the chapter boundary, skips by one, and ends with the book* (the last sentence reported is none, so the highlight is withdrawn); `NowPlayingTests` *The entry leaves when playback ends, and when the book runs out* |
| Reading aloud | Where the listening got to | **fail** | `MacPlayer.wire` writes the centre's positions for audio formats only; a voice's place is not written, and closing the book writes the reading position. |
| Reading aloud | Something else takes the audio | n/a | No audio session on a Mac: nothing takes an app's audio (`MacPlaybackPlatform`); a phone's scenario. |
| Reading aloud | A publication with nothing to say | pass | `ReadAloudTests` *The EPUB window offers the control only where a voice exists and the book has text*; *With no voice at all the control is absent* |
| The transport outside the reader | Getting back to the book | **fail** | The Mac draws no compact bar; the voice's transport is the system's Now Playing panel, which offers no way to the book's window. |
| The transport outside the reader | Controlling it without going back | seen | Pause, resume and sentence skip through the panel and the media keys (`NowPlayingTests` *The keys drive the one session*); ending the session needs the book's window (the Read Aloud button). |
| The transport outside the reader | What it says | pass | `NowPlayingTests`: the panel carries the title and the chapter being spoken |
| The transport outside the reader | It is absent when nothing is playing | pass | `NowPlayingTests` *The entry leaves when playback ends, and when the book runs out* |
| The transport outside the reader | Opening a different publication | **fail** | A second book replaces the first on the one `PlayerCentre` (StoryArcKit); nothing tells the listener that the voice stopped. |
| The transport outside the reader | The transport on iOS | n/a | iOS. |
| The transport outside the reader | The transport on Android | n/a | Android. |
| The transport outside the reader | The session cannot continue | not walked | The entry leaves when the source ends (`NowPlayingTests`); a voice that becomes unavailable mid-session was not driven. |
| The transport outside the reader | Reaching the transport without touch | seen | The Now Playing panel is the system's own; `docs/delivery/desktop-a11y-macos.md` owes it to a VoiceOver session by hand (item 6). |

## audio-playback (audiobooks delta)

Source: `docs/openspec/changes/audiobooks-and-playback/specs/audio-playback/spec.md`

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| One player for everything that speaks | The compact bar | **fail** | The Mac draws no compact bar: the session outlives the window and the way back is the player window and the Now Playing panel. No design decision dropped the bar on a desktop, so it is listed as missing, where the a11y record called it not applicable. |
| One player for everything that speaks | Nothing is playing | seen | No bar exists, so nothing is drawn and nothing is reserved. |
| One player for everything that speaks | The full player | **fail** | `PlayerWindow` has the cover slot, the title, the chapter, the position and duration, play and pause, skip back and forward, the scrub slider, the chapters and the speed, on the same session (`PlayerWalkTests` reopens it without a restart); no sleep timer. |
| One player for everything that speaks | A publication with no cover | **fail** | A headphones glyph in the cover slot (`PlayerWindow.artwork`, frame `player-light.png`); not the kind over the format's name, and the panel is given no artwork for it. |
| One player for everything that speaks | Both sources look the same | **fail** | A voice has no player window on the Mac; it is started and stopped from the EPUB window's Read Aloud button. |
| One player for everything that speaks | Playback outlives the publication | pass | `PlayerWalkTests` *keeps playing with its window closed*: the window goes, the session stays, and a second open fronts a window on the same session |
| One player for everything that speaks | Starting a second thing | not walked | The one-session rule is `PlayerCentre`'s, tested in StoryArcKit; `MacPlayer.listen` does not restart a book that is already playing; no Mac walk starts two. |
| One player for everything that speaks | Where a listening position is written | seen | `MacPlayer.wire` sends each position the centre reports to the progress store; the moments and the fifteen-second cadence are `PlayerCentre`'s, tested in StoryArcKit. |
| Playback controls | Speed | pass | `NowPlayingTests` *The speed is stated as a number*; `MacPlayer.wire` recalls and remembers the speed per publication and series; the stops are `PlaybackSpeed.stops` |
| Playback controls | Skipping | pass | `PlayerWalkTests`: the right arrow skips and the place moves; the controls state 15 and 30 (`gobackward.15`, `goforward.30`); crossing a part is the centre's |
| Playback controls | Sleep timer | **fail** | No sleep timer on the Mac in wave 4 (`MacPlaybackPlatform.sleepTimerChanged` is empty). |
| Playback controls | Chapters | **fail** | The Chapters menu lists each part by title or number and plays it (`PlayerWindow.settings`); no duration, no finished or in-progress mark, no remaining time. |
| Playback controls | Lock screen and system controls | pass | `NowPlayingTests`: title, chapter, elapsed and duration on the panel, play, pause, skip and seek drive the one session; artwork through `MacCoverPNG` |
| Playback controls | Something else takes the audio | n/a | No audio session on a Mac. |
| Playback controls | Headphones removed | **fail** | No route observer on the Mac (`MacPlayer`); playback goes on through the speaker. |
| Reaching the player without sight | Labels and values | pass | `AccessibilityAuditTests` on `player`: every control named, the slider's value in time (`docs/delivery/desktop-a11y-macos.md`) |
| Reaching the player without sight | The compact bar under a screen reader | **fail** | No bar. |
| Reaching the player without sight | At the largest text size | pass | `AccessibilityAuditTests` at the largest size; frame `player-light-largest.png` |
| Reaching the player without sight | The compact bar at the largest text size | **fail** | No bar. |
| Chapters before the first minute | The chapter list on the publication's page | **fail** | The Mac's publication page lists no audiobook chapters (`DetailView`). |
| Chapters before the first minute | Starting from a chapter | **fail** | `MacPlayer.listen(part:)` starts at a chosen part, but no page offers the choice. |
| Chapters before the first minute | An audiobook with one part | **fail** | No chapter list on the page, so nothing states the duration either. |
| Chapters before the first minute | The primary action says where it will resume | **fail** | The page's open action names no chapter. |
| Listening in a car | Continuing in the car | n/a | CarPlay is dropped on a desktop (`design.md` Decision 9). |
| Listening in a car | Browsing audiobooks in the car | n/a | As above. |
| Listening in a car | The car's own transport controls | n/a | As above. |
| Listening in a car | Only what a car should carry | n/a | As above. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`. The requirements wave 4 names: *Keeping the display awake while reading* (the listening scenario), *Media keys and system media controls*, *Screen readers on each system*, *A book stays off the network on every desktop*.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Keeping the display awake while reading | Listening | not walked | The app holds a display assertion for a reader window in front (`DisplayAwake`) and asks nothing for audio; macOS holds its own idle-sleep assertion while any process plays audio, which was not measured in this session. |
| Media keys and system media controls | Media keys | pass | `NowPlayingTests` *The keys drive the one session: pause, play, skip, the next chapter, a seek*, with a fake command centre; a real keyboard is owed by hand (a11y note, item 6) |
| Media keys and system media controls | The system overlay | pass | `NowPlayingTests`: the title, the chapter, the position and the artwork on the panel; a seek moves playback; *The entry leaves when playback ends* |
| Media keys and system media controls | Another application holds the keys | not walked | Who gets the keys is `MPRemoteCommandCenter`'s arbitration; not driven with a second player. |
| Media keys and system media controls | A device with no speech engine | pass | `ReadAloudTests` *With no voice at all the control is absent* |
| Media keys and system media controls | The windows are hidden | pass | `PlayerWalkTests` *keeps playing with its window closed*; `NowPlayingTests` *The targets are added once for the life of the platform* |
| Screen readers on each system | Controls in the library | pass | `AccessibilityAuditTests` over the 23 screens; the order VoiceOver speaks a cover in is owed by hand (a11y note) |
| Screen readers on each system | A page turn | seen | The page surface is one element named *Page N of M* and the EPUB foot states *Position N of M*; the live announcement is owed by hand (a11y note). |
| Screen readers on each system | A page with no text | seen | As above: named by position; nothing else is invented. |
| Screen readers on each system | What could not be opened | seen | The refusal notices are named text and buttons (waves 2 and 3); the no-text alert is the system's. |
| Screen readers on each system | Orca without an accessibility bus | n/a | Linux. |
| A book stays off the network on every desktop | A book that tries to load a remote resource | pass | `EpubEgressTests`: 0 of 8 arrivals guarded; the book renders |
| A book stays off the network on every desktop | A link to the web | seen | `EpubReaderModel.follow` hands `http` and `https` to `NSWorkspace` through `EpubLinkOpener` and drops the rest; the navigation delegate allows only the app's scheme, `blob:` and `about:` (`EpubReaderModel.navigates`); no walk clicks a link. |
| A book stays off the network on every desktop | A link inside the book | **fail** | The reader moves there; no way back is offered after a link. |
| A book stays off the network on every desktop | Proof on each desktop | pass | `EpubEgressTests` *the eight-vector page*: none of the eight arrives through the guarded view; the collector counts out of process (`pnpm egress`) |
