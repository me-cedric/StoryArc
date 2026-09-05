# A failed download's row offers Retry and Remove, not Stop — 2026-09-05

One finding of the 2026-09-05 design review, answered on iOS the day Android answered it.
Every frame here is an iPhone 17 Pro (`StoryArc-iPhone17Pro`, iOS 26.5), taken with
`scripts/capture-ios.mjs` from `UITests/SweepDownloads.swift`, and the queue in every one of
them is the sweep's injected record — three transfers, the third failed after three attempts
— so each frame is repeatable and leaves nothing on the device.

The device's locale writes a decimal comma, which is why sizes read `3,1 MB`. It is the same
device every earlier Downloads capture used.

## The failed row

`ios-downloads-queue.png`, `ios-downloads-queue-dark.png`.

Until today *The Peregrine*'s only control was **Stop**, under a line reading "Failed after 3
attempts: The server did not answer in time." A transfer that has already stopped cannot be
stopped, and `offline-downloads`' Failure scenario asks a failed download for "a plain-language
reason and a retry action" — the reason was there and the action was not. The row's own
comment admitted it: the retry "belongs to the running queue, which is why the count is shown
rather than hidden behind a button that cannot reach it".

The row now offers **Retry** first and **Remove download** beside it, on their own line under
the title at every text size. The two moving rows above it keep their chevrons and **Stop**;
`testCaptureDownloadDiscardConfirmation` counts one *Retry* and two *Stop*s on this screen
before it photographs anything.

**What Retry does.** It marks the record `queued` in the download store and hands the pump to
whichever `DownloadQueue` is alive through `DownloadQueue.retry(_:)`; when none is, the next
queue built reads the record and starts it, exactly as it starts every transfer the app died
during. `DownloadQueueRetryTests` proves both ends on the host. No frame here shows a tap on
it, on purpose: the walks tap nothing that writes the standard defaults domain, so an ordinary
launch on this simulator never shows a transfer of *The Peregrine* from `example.invalid` that
nobody queued.

## The row at the largest accessibility text size

`ios-downloads-failed-ax5.png`, `ios-downloads-failed-ax5-dark.png`, `ios-downloads-failed-ax5-de.png`.

At AccessibilityXXXL one row fills the screen, so `ios-downloads-queue-ax5.png` — the queue's
top, as the earlier sweeps framed it — shows two Stops and no Retry at all; the failed row is a
screen and a half below the heading. The `-failed-ax5` walks scroll down to it.

The two buttons stop sharing a line here. *Download entfernen* alone is wider than the row at
this size in German, the longest of the four languages, so the pair goes one under the other
and the label wraps to two lines. Nothing is truncated: a `lineLimit` would have made
*Download entfernen* into *Downlo…*, a verb with no object.

## Removing the one that gave up

`ios-downloads-discard-confirm.png`, `ios-downloads-discard-confirm-dark.png`.

Removing a failed transfer is a fourth confirmation. "This stops the transfer" is as untrue of
a download that stopped by itself three attempts ago as the removal sentence was of a running
one, so it asks **Remove this download?** and says "Nothing of The Peregrine reached this
device. It leaves the queue, and it can be downloaded again." — the sentence Android's
`downloads_remove_body_unfinished` uses, in the same four languages. The destructive action is
**Remove download**. `LibraryFeature/DownloadQueueRemoval` decides which of the four questions
is asked, in the order landed → failed → where it came from, and its tests pin that order; the
two ordering tests were watched failing with the questions swapped before the order was
restored.

## Found here and not changed

`ios-downloads-failed-ax5-de.png` also shows the row above the failed one, and its **Stoppen**
truncates to **Stopp…** at this size — the moving row's *Stop* carries a `lineLimit(1)`, and
German is the one language whose word does not fit inside it at AccessibilityXXXL. No earlier
capture had photographed a German queue at this size. It is outside this change's brief, which
kept *Stop* on every row that has not failed; it is one line in `DownloadQueueSection.swift`
and a decision about whether *Stoppen* may wrap.

## A note on the device

The first capture of this set waited for another agent's `SweepSettingsTests` run to leave
`StoryArc-iPhone17Pro`; `pgrep xcodebuild` showed it and nothing else would have. Wait for the
device; a failure that arrives while it is held is not a defect in the screen under test.
