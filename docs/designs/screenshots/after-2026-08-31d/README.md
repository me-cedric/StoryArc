# The reflowable reader, before and after `quiet-reader`

**Captured 2026-08-31**, iPhone 17 Pro simulator,
`StoryArcUITests/ScreenshotTests/testCaptureReaderChrome`. Three frames per tree: on
arrival, six seconds later **untouched**, and after a centre tap.

| Frame | before | after |
| --- | --- | --- |
| On arrival | **seven** controls — close, bookmark, contents, `Aa`, read aloud, a *Chapter 1* pill, and *0% read* at the foot | **two** — a close and a menu |
| Six seconds, untouched | **unchanged, byte for byte** | gone |
| After a centre tap | gone | the two are back |

Two things are proven there, and only the first was the task.

## Seven controls became two

That is `quiet-reader` section 1's claim, and counting controls in a screenshot is
exactly the comparison the source-level tests cannot make.

## The reflowable reader never withdrew its chrome, and now does

The middle row is the one worth reading twice. In the "before" tree the arrival frame and
the six-seconds-later frame have the **same SHA-256**: `EpubReaderView` only ever
*toggled* `isChromeVisible`, so the bar it drew on arrival stayed there until the reader
tapped it away. `comic-reader`'s *Revealing controls* has required "they fade out again
after 4 seconds of no interaction" the whole time; the comic reader did it and this one
never had.

No source-level test had looked at an arrival frame, so it survived every gate the
requirement has had. The screenshot pair is what found it. `EpubReaderView` now carries
the same `.task(id:)` countdown as `ReaderView`, with the same guards for the same
reasons — a sheet over the page means the reader has not stopped interacting, and chrome
hidden four seconds after a failure leaves a page that can only be escaped by
force-quitting.

`ReaderChromeTests.chromeArrivesThenWithdraws` pins both halves on both readers, so if
either is ever changed to start hidden the requirement has to change with it.

## What was fixed in the requirement rather than the code

*Entering the reader* said "the page fills the screen, **chrome is hidden**", and **no
reader has ever done that** — all four start it visible. The delta now describes showing
the controls once and withdrawing them, because that is the better half: a reader who has
just opened a book has not yet learned that a centre tap brings the way out back, and
showing it once is the only place that can be taught. Apple Books, which this change
follows, does the same.

## How the "before" was obtained, since it matters

The change had landed before these were taken, so the "before" is **a worktree at
`5b7d42a5`** — the commit before the first reader commit — built and driven with the same
test. The capture test is harness rather than the code under test, so it was added to
both trees; its theme-sheet helper differs between them because the control it reaches
for moved.

That is weaker than photographing before you edit. §6 asks for the "before" first and on
this change it was not, and this paragraph is here so no reader has to assume otherwise.

## Two mistakes this capture made first

**One tap proved nothing.** The first version tapped the centre once and photographed.
Both trees came back with a bare page and it looked like a clean comparison — the old
reader drew its chrome on arrival, so the tap *hid* it, and before and after were
identically empty for a reason unrelated to the change.

**Order mattered more than expected.** The countdown frame was first taken *after* the
centre tap, where it proved nothing at all: the tap had already hidden the chrome. Taken
before the tap, it is the frame that carries the whole fix.

## A silently skipping walk, found on the way

`openTheEpubReader` waited on `app.buttons["Reading"]` to prove it had reached the
reflowable reader. `quiet-reader` moved that control into the menu, so the button no
longer exists over the page. The wait did not fail — it timed out, the walk recorded every
EPUB as never reaching the reader, and it **skipped with a message blaming the device's
fixtures**.

A skip passes. `pnpm check` stayed green while `testCaptureThemeSheet`, the walk's other
caller, silently stopped photographing anything. The walk now proves the reader with the
web view, which is the only landmark that distinguishes the two readers from outside —
both draw a *Menu* and a close, by design.
