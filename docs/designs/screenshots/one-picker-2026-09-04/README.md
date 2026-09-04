# One picker, not two — 2026-09-04

`ios-add-folder-picker.png` is the frame the 2026-09-02 sweep could not take. Its *What
looked wrong* section says so in the negative: "*Add a folder* leaves the library's own
toolbar reachable and presents no picker at all, which is why there is no
`ios-add-folder-picker.png` in this folder."

| File | What it is a picture of |
| --- | --- |
| `ios-add-folder-picker.png` | Library → *Add books* → *Add a folder*. The system browser in folder-choosing mode: directories only, an *Open* button, no files offered. |
| `ios-add-file-picker.png` | The same menu's *Open a file*, one row below. The control that always worked, photographed again on the fixed build as the control. |
| `-dark` twins | The same two in the dark appearance. |

Both walks are `SweepSourcesTests`, unchanged. The only thing that moved is the app.

## What was wrong

`LibraryView` applied **two `.fileImporter` modifiers to one view** — one for folders, one
for imports, the second wearing the name `.importingPublications` so it did not read as a
picker at the call site. SwiftUI presents only the last such modifier applied and drops the
rest silently. The folder importer was declared first, so it was the one dropped.

Nothing was wrong with the menu row, the button, or the state it set. On iOS the folder
picker is the whole of adding a local library, so the one row that was dead was the only way
in.

## How that was established

Not by reading. The MCP simulator panel had crashed, and this machine grants neither screen
recording nor accessibility control, so a literal finger was not available — what follows is
a controlled pair of runs on `StoryArc-iPhone17Pro`, which is the same instrument the sweep
used and a stronger one than a finger for this question, because it changes one variable and
holds everything else.

| Trial | Source | `testCaptureFolderPicker` | `testCaptureFilePicker` |
| --- | --- | --- | --- |
| A (control) | unchanged | **failed** | **passed**, produced its frame |
| B | the two `fileImporter`s swapped, nothing else | **passed**, produced its frame | **failed** — *"Nothing came up over the shelf in ten seconds"* |
| C (the fix) | one presentation, chosen by `LocalPick` | **passed** | **passed** |

Trial B is the one that decides it. The failure did not go away, it *moved* — to the control
that had passed on every previous run, with the same assertion text the folder walk used to
fail with. A menu row, a button action or a dead `@State` cannot do that; only the ordering
of two presentations can.

Two further observations from the same runs, both against the sweep's own reading:

- The device log shows **no document-picker process activity at all** on the failing trial —
  `com.apple.DocumentManagerUICore` is never asked. The presentation is dropped inside
  SwiftUI, before anything is requested of the system.
- The app never crashes. The walk's "crashed with signal kill" is XCTest reaping a test that
  polled ten seconds for a sheet that was never coming, not a defect in the app.

## The same bug was in `HomeScreen`, the other way round

Found by the compiler while the shelf was being fixed. Home stacked the same two
presentations in the **opposite** order — the import first, the folder under it — so on Home
*Add a folder* worked and *Open a comic* opened nothing. Nobody had reported it because Home
only offers either when the library is empty, and the sweep photographed a device holding
fourteen publications.

That is why the fix is not an order. Two arrangements of the same mistake were already in the
tree, and no gate in this repository could see either. There is one presentation per screen
now, `LocalPick` decides what it offers, and `LocalPickerTests` counts them.

## Not photographed

Home's two rows. Reaching them needs a library with nothing in it — the `StoryArc-Sweep-Empty`
device — and the empty suite has no walk that opens either picker. The Home fix is carried by
the compiler (the modifier it called no longer exists) and by the count guard, and it is the
one thing here without a frame.
