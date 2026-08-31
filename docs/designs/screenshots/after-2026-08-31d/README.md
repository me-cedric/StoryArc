# The fourth batch of 2026-08-31, after

Two changes landed in this batch and each has its own half below: **what changed in a
version** on both platforms, and **the reflowable reader's chrome**. They share a batch
letter because they were captured the same evening against the same devices; nothing else
connects them.

---

## What changed in a version

What changed in a version, on both platforms — the screen after an update, the same content
reached from About, and the About screens that now carry a way to it. Paired with
[`before-2026-08-31d`](../before-2026-08-31d/README.md), which is the same two About screens
without the row.

### How these were taken

```bash
pnpm capture:ios --out docs/designs/screenshots/after-2026-08-31d --only testCaptureWhatsNew
pnpm capture:ios … --only testCaptureWhatsNewAtLargestText
pnpm capture:ios … --only testCaptureAbout
pnpm capture:ios … --only testCaptureWhatsNewFromAbout

ANDROID_SERIAL=emulator-5554 pnpm gradle :app:assembleDebug   # then adb install -r
ANDROID_SERIAL=emulator-5554 pnpm capture:android "Settings > About"            --out …/android-about.png
ANDROID_SERIAL=emulator-5554 pnpm capture:android what                          --out …/android-whats-new-from-about.png
ANDROID_SERIAL=emulator-5554 pnpm capture:android Home                          --out …/android-whats-new.png
ANDROID_SERIAL=emulator-5554 pnpm capture:android Home --dark                   --out …/android-whats-new-dark.png
ANDROID_SERIAL=emulator-5554 pnpm capture:android Home --font-scale 2.0         --out …/android-whats-new-scale2.png
```

Devices: `StoryArc-iPhone17Pro` (11DFC984), and the `storyarc-j6` emulator started with
`-gpu host`. Two emulators were attached, so every `adb` call carried `ANDROID_SERIAL`.

### The one thing worth explaining: how the sheet was made to appear

It is shown **once, on the launch after an update**, so a device that has just installed the
build is in the first-ever-launch branch and shows nothing. Both platforms were put in the
after-an-update state by writing an older version into the store the app itself reads —
**not** by a flag or a hook in the app, which would mean the picture proved a code path no
reader takes.

- **iOS:** `-app.storyarc.whatsNewSeen 0.0.1` as a launch argument. `UserDefaults`'s argument
  domain outranks the standard one, so `WhatsNewStore` reads `0.0.1` and the shell takes the
  branch it takes on a real update. `ScreenshotTests.testCaptureWhatsNew` does this itself.
- **Android:** the `SharedPreferences` file is written with `adb shell run-as`, then the app
  is force-stopped and the `Home` route re-launches it. The sheet is over Home, which is why
  the route is `Home` rather than a route of its own — one launch, one sheet, and the walk
  reaches nothing further because the modal is over everything.

Each Android capture re-seeds first: launching records the installed version, so the second
capture of a pair would otherwise photograph Home with no sheet at all.

### What each one shows

| Shot | What is in it |
| --- | --- |
| `ios-whats-new.png` | The `.sheet` at `.presentationDetents([.large])`: heading, version, four rows, `Continue` pinned at the foot. |
| `ios-whats-new-ax5.png` | The same at `AccessibilityXXXL`. The rows have scrolled past the fold, the icon column has not grown, and `Continue` is still there at full size — which is the requirement's own sentence, photographed. |
| `ios-about.png` | About with the *What's new* row, between the free-and-open sentence and Repository. Compare with the same file in `before-2026-08-31d`. |
| `ios-whats-new-from-about.png` | The same four rows reached from About. No `Continue`, because nothing is being dismissed and nothing is being recorded. |
| `android-whats-new.png` | The `ModalBottomSheet` over Home, expanded, `Continue` pinned. Home is visible above it: capped, not full-screen. |
| `android-whats-new-dark.png` | The same, dark. |
| `android-whats-new-scale2.png` | The same at `font_scale 2.0`. The sheet scrolls, the icon column is the same dp it was, and `Continue` has not moved. |
| `android-about.png` | About with the *What's new* row at the head of the links. |
| `android-whats-new-from-about.png` | The whole log from About, with `Back` and no `Continue`. |

### What the first Android attempt got wrong, and the picture that caught it

The sheet was first built on `ModalBottomSheet`'s default state, which opens **partially
expanded** — `design.md` says "capped and expandable", and that reads like the default.

A modal sheet lays its content out at the full height and is *translated* down to the partial
offset, so a footer pinned to the bottom of the content sits below the visible edge. The first
capture showed the fourth row running off the bottom of the screen with **no action anywhere
on it**, which is precisely what `settings-and-about` forbids: "the dismissing action stays
reachable without scrolling past the content".

No unit test could have seen it. `WhatsNewLayoutTest` composes the sheet's *content* in a box
the size of a small phone — the height that hid the button belongs to the dialog, not to the
content. The sheet now opens expanded (`rememberBottomSheetState` with `Hidden` and `Expanded`
and nothing between), which is also the shape iOS's single `.large` detent has. The picture
above is the second one.

---

### The reflowable reader's chrome

**Captured 2026-08-31**, iPhone 17 Pro simulator,
`StoryArcUITests/ScreenshotTests/testCaptureReaderChrome`. Three frames per tree: on
arrival, six seconds later **untouched**, and after a centre tap.

| Frame | before | after |
| --- | --- | --- |
| On arrival | **seven** controls — close, bookmark, contents, `Aa`, read aloud, a *Chapter 1* pill, and *0% read* at the foot | **two** — a close and a menu |
| Six seconds, untouched | **unchanged, byte for byte** | gone |
| After a centre tap | gone | the two are back |

Two things are proven there, and only the first was the task.

### Seven controls became two

That is `quiet-reader` section 1's claim, and counting controls in a screenshot is
exactly the comparison the source-level tests cannot make.

### The reflowable reader never withdrew its chrome, and now does

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

### What was fixed in the requirement rather than the code

*Entering the reader* said "the page fills the screen, **chrome is hidden**", and **no
reader has ever done that** — all four start it visible. The delta now describes showing
the controls once and withdrawing them, because that is the better half: a reader who has
just opened a book has not yet learned that a centre tap brings the way out back, and
showing it once is the only place that can be taught. Apple Books, which this change
follows, does the same.

### How the "before" was obtained, since it matters

The change had landed before these were taken, so the "before" is **a worktree at
`5b7d42a5`** — the commit before the first reader commit — built and driven with the same
test. The capture test is harness rather than the code under test, so it was added to
both trees; its theme-sheet helper differs between them because the control it reaches
for moved.

That is weaker than photographing before you edit. §6 asks for the "before" first and on
this change it was not, and this paragraph is here so no reader has to assume otherwise.

### Two mistakes this capture made first

**One tap proved nothing.** The first version tapped the centre once and photographed.
Both trees came back with a bare page and it looked like a clean comparison — the old
reader drew its chrome on arrival, so the tap *hid* it, and before and after were
identically empty for a reason unrelated to the change.

**Order mattered more than expected.** The countdown frame was first taken *after* the
centre tap, where it proved nothing at all: the tap had already hidden the chrome. Taken
before the tap, it is the frame that carries the whole fix.

### A silently skipping walk, found on the way

`openTheEpubReader` waited on `app.buttons["Reading"]` to prove it had reached the
reflowable reader. `quiet-reader` moved that control into the menu, so the button no
longer exists over the page. The wait did not fail — it timed out, the walk recorded every
EPUB as never reaching the reader, and it **skipped with a message blaming the device's
fixtures**.

A skip passes. `pnpm check` stayed green while `testCaptureThemeSheet`, the walk's other
caller, silently stopped photographing anything. The walk now proves the reader with the
web view, which is the only landmark that distinguishes the two readers from outside —
both draw a *Menu* and a close, by design.
