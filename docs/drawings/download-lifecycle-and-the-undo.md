# The download lifecycle, and the ten-second undo

Companion to
[`download-lifecycle-and-the-undo.mmd`](download-lifecycle-and-the-undo.mmd).

## Why this one exists

`offline-downloads` is the capability a reader notices when it misbehaves and
never when it works, and its states are not the ones you would guess. Every
pause reason and the failure threshold are quoted from the spec inside the
source, so the model is unusually easy to verify — and unusually easy to
misremember, because there is no "transferring" or "verifying" state despite
both words appearing in conversation about it.

## Read from

| File | What it settled |
| --- | --- |
| `apps/android/core/model/src/main/kotlin/app/storyarc/core/model/Download.kt` | `Download.State`, `Download.Pause`, `isFinished`, `isActive`, the restart-to-`Queued` rule |
| `apps/ios/Packages/StoryArcKit/Sources/StoryArcCore/Download.swift` | the same five states and three pause reasons on the other platform |
| `apps/ios/App/FinishedDownloadSweep.swift` | the sweep, the ten-second window, and `settle()` |
| `apps/android/feature/library/src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt` | the Android undo, held by the app layer |

Both platforms were checked and they agree: five states, three pause reasons,
the same names in each language's idiom.

## The states are not the ones people quote

There is no `transferring` and no `verified`. The five states are **Queued**,
**Running**, **Paused** (carrying a reason), **Failed** (carrying a
plain-language reason and an attempt count) and **Finished**. Verification is not
a state but a property of Finished: `isFinished` is documented as "the file on
disk is complete and verified", so a download that has not verified has not
finished.

`isActive` is `Running || Queued` — the two states in which the app should be
moving bytes.

## Why the pause reason is part of the state

`Download.Pause` is written in the reader's terms rather than the system's, and
each case is a spec requirement rather than an implementation detail:

- **`byReader`** — the reader asked.
- **`waitingForWiFi`** — on a metered connection with Wi-Fi-only on, downloads
  "pause and state that they are waiting for Wi-Fi". The reason has to survive
  into the UI or that sentence cannot be shown.
- **`outOfSpace`** — never resolved by deleting something silently, because the
  spec says the app "never deletes a download without asking". That is why the
  edge out of it is the reader freeing space, and there is no automatic one.

`Failed` carries both a reason and a count for the same kind of reason: after
three attempts a download is "marked failed with a plain-language reason and a
retry action", so neither can be logged and forgotten.

## Why Running can go back to Queued

A process death does not preserve a transfer. On restart, any download still
marked `Running` whose transfer was not carried over is marked `Queued` again,
so the queue re-drives it rather than leaving a row that claims to be moving
bytes nobody is moving.

## What the sweep is, and what removal takes

`Swept` is **not** a `Download.State`. The sweep is held by the app layer, which
is where the ten seconds are counted — `FinishedDownloadSweep` on iOS, the
snackbar on Android. It is drawn as a state anyway because it is the only way to
show the undo, and calling that out here is cheaper than a picture that omits
the behaviour.

The sweep fires when the reader **finishes reading** a publication, not when they
delete something: it asks the progress store whether each finished download's
record `isFinished`, and takes the first one that is. Until `settle()` is called
the bytes are still there, which is what makes the undo real rather than a
re-download.

**Removal takes the bytes and nothing else.** The reading position is keyed
independently and survives — indeed the sweep *reads* the progress record to
decide, so progress necessarily outlives the download it describes. This is the
same principle the source-removal board draws at a larger scale, where a
tombstone holds progress for thirty days after its source is gone.

One incidental cross-check worth recording: the sweep looks a record up with
`PublicationIdentity(normalizedPath:)` — identity rule 3, the last resort. That
is consistent with what
[`reading-position-identity-and-merge.md`](reading-position-identity-and-merge.md)
records about identity in practice.
