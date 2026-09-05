# The source detail screen — iOS, 2026-09-05

`source-lifecycle` §4.1's, §4.3's and §4.6's iOS halves. Twelve frames from `StoryArc-iPhone17Pro`
(402 pt), taken with `scripts/capture-ios.mjs`.

| Frame | Task | Appearance | Text size |
| --- | --- | --- | --- |
| `ios-settings-source-detail.png` | §4.1 | light | default |
| `ios-settings-source-detail-dark.png` | §4.1 | dark | default |
| `ios-settings-source-detail-ax5.png` | §4.1 | light | `AccessibilityXXXL` |
| `ios-settings-source-detail-ax5-dark.png` | §4.1 | dark | `AccessibilityXXXL` |
| `ios-source-unreachable-detail.png` | §4.3 | light | default |
| `ios-source-unreachable-detail-dark.png` | §4.3 | dark | default |
| `ios-settings-source-remove.png` | §4.6 | light | default |
| `ios-settings-source-remove-dark.png` | §4.6 | dark | default |
| `ios-settings-source-remove-ax5.png` | §4.6 | light | `AccessibilityXXXL` |
| `ios-settings-source-remove-ax5-scrolled.png` | §4.6 | light | `AccessibilityXXXL`, after a swipe |
| `ios-settings-source-remove-ax5-dark.png` | §4.6 | dark | `AccessibilityXXXL` |
| `ios-settings-source-remove-ax5-scrolled-dark.png` | §4.6 | dark | `AccessibilityXXXL`, after a swipe |

Surface: *Settings › Your libraries › one source*. The walk opens `StoryArc Test Catalogue`
and falls back to `Attic NAS`; **which of the two it lands on varies between runs**, so the
default-size frames show the catalogue and the accessibility ones show the NAS. That is a
property of the walk rather than of the screen, and it is worth knowing before comparing two
frames closely.

## Four actions, not five, and that is the screen being right

The task asked for a frame showing all five fields **and** all five actions. That frame cannot
exist: `SourceDiagnosis.of` withholds *Remove downloads* unless the source holds a finished
download and *Reconnect* unless a credential was refused, and one source cannot be both at
once. The task was reworded on 2026-09-05 to ask for whichever actions the state offers, and
for the frame to say which were withheld.

These frames show **Test connection · Refresh · Free up space · Remove**. *Reconnect* is absent
because this catalogue's credential has not been refused — it is not answering at all, which is
a different state and the one *Test connection* is for.

## What the frames settled

**The zero-byte spelling is fixed, and this is the screen it was found on.** *Downloaded* reads
`0 bytes`. It read `Zero kB` here until earlier the same day, because `ByteCountFormatStyle`
spells zero out unless told not to and this call site had not been converted. Every source a
reader has just added has nothing downloaded, so that was the first thing the screen said about
most of them.

**A defect the accessibility frames found, and it is fixed here.** Before the fix, the status
read `Not an-swering` — broken across three lines of a value column a few characters wide, with
the label sitting alone in the other half of an otherwise empty row. Two of the five values are
a date and a sentence (*No answer since Sep 5, 2026 at 15:14*), so the value column is always
the one that loses.

The rows now stack at the accessibility sizes, label above value, both leading-aligned, which is
what the system's own Settings does with a long value at those sizes. Four fields fit where two
and a bit did before. `SourceDetailSizeTests` pins the branch; these frames are what prove the
fit, and the suite's own header already drew that division.

It is the second instance of the same shape found on one day — the reader's theme presets
hyphenated *Original* into `Origi-nal` at the same text size, for the same reason: a fixed
layout whose narrow half holds the text that grows.

## §4.3, and the "grey, never red" claim is now measured

`ios-source-unreachable-detail.png` and its dark twin are the unreachable source's detail
screen — *Attic NAS*, status **Not answering**, *Last error: No answer since Sep 5, 2026 at
15:20*.

`AGENTS.md`'s second non-negotiable is that an unreachable source is **grey, never red**. The
task asked for a reachable source photographed beside it as the control, on the argument that a
grey row proves nothing without one. **The better control turned out to be inside the frame.**
Sampling the most saturated pixel of each region:

| Region | Most saturated pixel | Saturation |
| --- | --- | --- |
| Status value, *Not answering* | `rgb(89,84,79)` | **0.112** |
| Action, *Test connection* | `rgb(138,77,240)` | 0.679 |
| Action, *Remove* | `rgb(255,56,60)` | **0.780** |

Red is present in the same frame at 0.78, the brand accent at 0.68, and the away status sits at
0.11 — so the grey is a **choice**, not the absence of red from the palette. A second frame of a
reachable source could not have shown that; it would only have shown a different grey.

*Remove* being the one red thing is also right: it is the destructive action, and it is the only
one.

## §4.6, and the truncation the task predicted

Six more frames: `ios-settings-source-remove{,-dark}.png` at the default size, and
`ios-settings-source-remove-ax5{,-dark}.png` with `-scrolled` twins at `AccessibilityXXXL`.

At the default size the confirmation reads in full: *"This removes 0 titles from your library.
No files on your device are deleted, and nothing was downloaded. Your reading positions are kept
for 30 days."*

**At the largest text size it stops at "No files".** The thirty-day sentence — what happens to a
reader's reading positions — is not on screen at all, on a destructive action. The task said in
its own words that *a confirmation dialog is where truncation costs a reader their library*, and
this is that.

**The `-scrolled` frames are the point.** A still cannot tell a scrollable clip from a hard
truncation, so the walk swipes and shoots again. **The two frames are identical.** A
`confirmationDialog`'s message does not scroll, so the sentence is unreachable rather than
merely off-screen.

An `alert` was tried and reverted. It fixes two smaller things — the title and the destructive
button stop hyphenating into *Re-move*, and a *Cancel* becomes visible — but its message does
not scroll either. Presentation is not the lever.

**What a test would have said.** The walk asserts the sentence with `staticTexts … CONTAINS "30
days"`, and that assertion **passes at AX5**: the message is one label in the accessibility
tree, so VoiceOver reads it in full. A guard asserting existence would have called this screen
correct while a sighted reader could not see the sentence at all.

### Fixed the same day: the thirty days moved onto the screen

The frames named above are now the **retaken** set, shot after the fix. The retention
sentence left the dialog and became a footer under the actions — `sources.remove.footer`,
*"Removing a library keeps your reading positions for 30 days."*, in four languages — shown
whenever *Remove* is offered. `ios-settings-source-detail.png` shows it under the red row at
the default size, and `SourceDetailSizeTests/retentionIsAFooter` pins that it is there.

Why a footer and not a shorter dialog: a footer wraps freely at every text size, and it is read
*before* the reader taps Remove, which is when the fact is useful. The dialog keeps the sentences
that answer "what does this do right now"; the footer answers "and what about my place", which
is a fact about removal rather than about this press of the button.

**What the AX5 frame shows now, honestly.** `ios-settings-source-remove-ax5.png` reads *"This
removes 0 titles from your library. No files"* — the body is two sentences instead of three and
still stops at the same word, because a `confirmationDialog` at that size holds about seven
short lines and the first sentence is six of them. What is cut is now the reassurance that no
files are deleted, not the retention; the retention is on the screen beneath. The `-scrolled`
twin is still identical, for the reason given above.

**A finding the fix turned up, and it is bigger than the wording.** `sources`' scenario
*Removing a source* says the app "states how many downloaded files and how much disk space will
be freed before asking" and "on confirmation removes the source, its cached metadata, its stored
credentials, **and its downloads**". Neither platform does: `LibraryModel.remove` and
`LibraryViewModel.removeSource` both say in their own comments that files on disk are never
touched, and the dialog's *"nothing was downloaded"* is a sentence that is only true at zero.
Worse, both Downloads screens list *shelf publications* that are on the device — so a removed
source's downloads leave the shelf, leave the Downloads screen, and stay on disk as bytes nothing
lists and only the total counts. That is a spec-versus-implementation gap on a destructive
action, owned by the removal path rather than by this dialog, and it is recorded here so the
dialog is not rewritten twice.

## Two walks that could not run, and why

**`SweepSourcesTests/testCaptureAwayNotice` skips on this device, honestly.** The library-wide
sentence — *"None of the places you added can be reached right now. Anything already on this
device is still here to read."* — appears only when **nothing** a reader added can be reached,
and the simulator's shelf is full of local files, so the library is never away. It reported `1
test case(s): 0 passed, 0 failed, 1 skipped` twice. Worth stating plainly because a skipped walk
exits 0: **read the run summary, not the exit code.** The state it needs is a device whose only
sources are remote and all unreachable.

**The "reachable source" control does not exist on this device either.** Both
`ios-settings-source-detail.png` and the unreachable frames show a source that is *Not
answering* — `StoryArc Test Catalogue` points at nothing running, exactly as `Attic NAS` does.
So the two frames are two unreachable sources rather than a contrast pair, and the measurement
above is what carries §4.3 instead.

## Still owed

**The Android half of §4.1**: `pnpm capture:android "Settings > source detail" --out <file> [--dark]
[--font-scale 2.0]`. The route exists and needs a non-empty source list, which the corpus alone
does not give — the 17 generated publications carry `origin: EMBEDDED` and belong to no source,
so *Your libraries* is legitimately empty until one is added.

**A source holding a finished download**, on either platform, so *Free up space* is offered
against a non-zero figure rather than against `0 bytes`.

## How to retake them

```bash
O=docs/designs/screenshots/source-lifecycle-2026-09-05
for appearance in light dark; do
  for walk in SweepSettingsTests/testCaptureSettingsSourceDetail \
              SweepSettingsTests/testCaptureSettingsSourceDetailAtLargestText \
              SweepSourcesTests/testCaptureUnreachableSourceDetail; do
    node scripts/capture-ios.mjs --out $O --only "$walk" --appearance $appearance
  done
done
```

Read the run summary rather than the exit code: `xcodebuild` exits 0 when a `-only-testing:`
filter matches nothing, so each run must report `1 test case(s): 1 passed, 0 failed, 0 skipped`.
A `0 skipped` matters as much as the `1 passed` — a walk that skips passes and photographs
nothing.
