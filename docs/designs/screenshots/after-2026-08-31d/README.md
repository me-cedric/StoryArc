# The reflowable reader, before and after `quiet-reader`

**Captured 2026-08-31**, iPhone 17 Pro simulator, `StoryArcUITests/ScreenshotTests/testCaptureReaderChrome`.

| | Controls over the page |
| --- | --- |
| [before](../before-2026-08-31d/ios-reader-on-arrival.png) | **seven** — close, bookmark, contents, `Aa`, read aloud, a *Chapter 1* pill, and a *0% read* pill at the foot |
| [after](ios-reader-on-arrival.png) | **two** — a close and a menu |

That is the change `quiet-reader` section 1 asks for, and counting controls in a
screenshot is exactly the comparison the source-level tests cannot make.

## How the "before" was obtained, since it matters

The change had already landed when these were taken, so the "before" is not a capture
that happened to precede it. It is a **git worktree at `5b7d42a5`** — the commit before
the first reader commit — built and driven with the same test. The capture test itself
was added to both trees; it is harness, not the code under test.

That is weaker than photographing before you edit, and it is said here rather than left
for a reader to assume. §6 asks for the "before" to be captured first, and on this change
it was not.

## Two shots each, and the reason

The first version of this capture tapped the centre once and photographed. Both trees
came back with a bare page and it looked like a clean comparison. It was not: **the old
reader drew its chrome on arrival**, so the tap *hid* it, and the before and the after
were identically empty for a reason that had nothing to do with the change.

So each tree gets two: on arrival, and after a centre tap. Whichever state carries the
chrome is in the pair, and the pair also shows *when* it is drawn — which turned out to
be worth having.

## What the pair caught that no test did

**Chrome is visible on arrival in the "after" too.** `comic-reader`'s *Entering the
reader* scenario says "the page fills the screen, chrome is hidden", and all four readers
— both platforms, both readers — start with `isChromeVisible`/`wantsChrome` **true** and
withdraw it after four seconds. That is not a regression from `quiet-reader`; it predates
it, and no source-level test looks at the arrival frame.

Recorded here rather than quietly fixed, because which of the two is wrong — the sentence
or the behaviour — is a product question and not a defect report. See
`quiet-reader/design.md`.

## A silently skipping walk, found on the way

`openTheEpubReader` waited on `app.buttons["Reading"]` to prove it had reached the
reflowable reader. `quiet-reader` moved the themes control into the menu, so that button
no longer exists over the page. The wait did not fail — it timed out, the walk recorded
every EPUB as never reaching the reader, and it **skipped with a message blaming the
device's fixtures**.

A skip passes. `pnpm check` stayed green while `testCaptureThemeSheet`, the walk's other
caller, silently stopped photographing anything. The walk now proves the reader with the
web view, which is the only landmark that distinguishes the two readers from outside —
both draw a *Menu* and a close, by design.
