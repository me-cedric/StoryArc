# macOS screen reader walk — wave 4

Task 4.9 of `desktop-clients`. What the Mac's machine accessibility audit proves on the
library, a reader and the player, and what a VoiceOver session by hand still owes, scenario by
scenario against `desktop-experience`, *Screen readers on each system* and `audio-playback`,
*Reaching the player without sight*. Written 2026-10-17 at the head of the Mac wave 4 lane
(macOS 27.0.1, Xcode 27.1).

## What the audit is

`Tests/AccessibilityAudit.swift` asks the app's own accessibility server, through the
`AXUIElement` calls VoiceOver makes, for every control of every screen of
`Tests/MacCatalogue.swift`, at the default text size and at the app's largest. A control is
every element whose role a reader acts on (buttons, check boxes, radio buttons, sliders, pop-up
and menu buttons, text fields, links, combo boxes, incrementors, disclosure triangles). The
audit fails on a control with no name and on one smaller than 20 by 20 points, Apple's floor
for macOS. The suite is `AccessibilityAuditTests`; it runs in every `xcodebuild test` and on
CI. Contrast is not read by it: the palette pairs are held to 4.5:1 by `pnpm tokens:check`.

Wave 4 added three screens to the catalogue: `epub-reader` (the web view reader over
`fixture.epub`), `pdf-selection` (`text-pages.pdf` with a selection and its menu) and `player`
(`chaptered.m4b` paused at its start). The audit reads them with the twenty screens of waves 1
to 3. On the head of this lane it reports no finding on any screen at either text size.

What the audit found on the way, and what changed because of it:

- The player's Chapters and Speed menus drew 16 points tall as borderless menu buttons, under
  the floor, and the speed menu was named after its symbol (*Gauge with a needle*). Both menus
  now take the 28-point icon target the reader's chrome uses, and the speed menu's name carries
  its value: *Speed: 1×*.

## What the audit proves, by scenario

### *Controls in the library*

- **Proved by machine.** Every toolbar control, sidebar row control, cover and list control of
  Home, the grid, the list, search, downloads, the two shelf pages and the detail page carries
  a name and meets the floor, at both text sizes. No control is announced by an identifier.
- **Owed by hand.** That each publication is announced with its title, its progress and its
  source in that order. The audit reads names, not the order VoiceOver speaks a cover's
  children in, nor the progress text a cover carries as its value.

### *A page turn* and *A page with no text*

- **Proved by machine.** The comic reader's page surface is one accessibility element named
  *Page N of M* (`ReaderCanvas`), and the foot's counter carries the same label; the slider is
  named and announces its value as the page. The PDF page draws through the same surface. The
  EPUB window's web view is named with the book's title, and its foot states *Position N of
  M* as the label of the counter.
- **Owed by hand.** That VoiceOver announces the new position after a key turn without the
  reader moving the cursor (a live announcement, not a label), and that the text of a PDF page
  with a text layer is read when the cursor enters the page. Inside the EPUB's web view the
  book's own markup is what VoiceOver reads; the handoff between the chrome and the text
  (Escape and Tab, *Leaving a book's text*) is walked by hand, as the design's accessibility
  consequence says each desktop owes.

### *What could not be opened*

- **Proved by machine.** The refusal notices of the library are buttons and text with names
  (waves 2 and 3); nothing new in wave 4.
- **Owed by hand.** The PDF-without-text sentence (*This file is images of pages*) is an
  alert; that VoiceOver reads it when it appears is the alert's own behaviour and is not
  measured here.

### *Reaching the player without sight*: *Labels and values*

- **Proved by machine.** Every transport control of the player is named (Play or Pause, Back 15
  seconds, Forward 30 seconds, Chapters, Speed with its value) and meets the floor at both text
  sizes. The position slider is named *Position* and its value is the elapsed time in words
  (`PlaybackClock.spokenTime`), not a percentage.
- **Owed by hand.** That the slider's value is spoken as time when VoiceOver adjusts it with
  the arrow keys, and that a speed change is announced.

### *The compact bar under a screen reader* and *at the largest text size*

- **Not applicable on the Mac.** The Mac draws no compact bar: the session outlives the
  window on the one player, and the way back is the player window and the system's Now Playing
  panel (`desktop-experience`, *The windows are hidden*). Nothing is reserved for a bar.

### *At the largest text size*

- **Proved by machine.** The player's controls keep their size and their names at the app's
  largest text size; the audit runs the whole catalogue at both sizes.
- **Owed by hand.** That the window scrolls rather than clips when the title wraps to three
  lines at the largest size; the fixture's one-word title does not exercise it.

### *Media keys and system media controls* (what a screen reader user reaches)

- **Proved by machine, in `NowPlayingTests`.** The Now Playing entry carries the title, the
  chapter, the elapsed time and the duration; every remote command drives the one session; the
  entry leaves when playback ends. Measured with a fake command centre and board, not the
  system's.
- **Owed by hand.** The system's Now Playing panel in the menu bar, read with VoiceOver, and a
  real keyboard's media keys with the app's windows hidden.

## The VoiceOver session by hand

Not run in this lane: an agent session has no VoiceOver and no Screen Recording grant. The
checklist for the owner, on a Mac with VoiceOver on (⌘F5), each as one scenario:

1. Library: VO-right through Home; a cover says its title, its progress and its source.
2. Comic reader: VO cursor on the page, press the right arrow; the new position is announced.
3. PDF reader: VO cursor on a `text-pages.pdf` page; the page's text is read; a drag-selected
   run, then VO on the selection menu, names the five colours by colour.
4. EPUB reader: VO into the web view reads the chapter's text; Escape returns to the chrome
   and Tab goes back into the text; the theme menu names the six presets.
5. Player: VO on the slider says the time; VO-up and VO-down adjust it by time; Speed says its
   value; the Chapters menu names each chapter.
6. Media keys: hide every window (⌘H); press play/pause on the keyboard; the Now Playing panel
   shows the book and the chapter; press next; the chapter changes.

Each finding goes in this file under the scenario it belongs to, with the macOS version.
