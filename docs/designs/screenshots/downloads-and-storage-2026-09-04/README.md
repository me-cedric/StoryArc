# The queue, the stop, and what storage is about — 2026-09-04

Three of the September sweep's findings, answered. Every frame here is an iPhone 17 Pro
(`StoryArc-iPhone17Pro`, iOS 26.5), taken with `scripts/capture-ios.mjs`, and every one has a
counterpart in [`../ios-sweep-2026-09-02/`](../ios-sweep-2026-09-02/README.md) under the same
name — so each pair is a before and an after of the same walk on the same device.

The device's locale writes a decimal comma, which is why sizes read `3,1 MB`. It is the same
device the sweep used and the same formatter; nothing here changed it.

## Stopping a transfer is no longer confirmed with the words for deleting one

`ios-downloads-stop-confirm.png`, `ios-downloads-stop-confirm-dark.png`.

*Stop* on a row still arriving used to put up **Remove this download?** — "This deletes the
copy of Harbour Lights 03 on this device. Your reading position is kept, and it can be
downloaded again." — over a transfer with no copy on the device and no reading position to
keep, and offered **Remove download** as the destructive action.

It now asks **Stop this download?**, says "This stops the transfer of Harbour Lights 03.
Nothing of it is kept on this device, and it can be downloaded again", and the button says
**Stop download**. Removing a finished download and removing an imported copy are unchanged;
the three are decided in one place, `LibraryFeature/DownloadQueueRemoval`, and its tests pin
the order they are asked in.

**Android has the same defect and is untouched** — `DownloadsParts.kt`'s
`RemoveDownloadDialog` and the four `downloads_remove_*` strings. This work was iOS-only.

## A transfer states its size and how far through it is

`ios-downloads-queue.png`, `ios-downloads-queue-dark.png`, and the two `-ax5` frames.

The row was a title, two reorder chevrons, *Stop* and a bare bar. `offline-downloads` asks a
queued publication to have "its size shown, and progress visible", and only the second half
was there. Under the bar now:

| Row | Says |
| --- | --- |
| Harbour Lights 03, part-way | `37% · 3,1 MB of 8,4 MB` |
| Tidal Reach 04, not started | `0% · 0 bytes of 41 MB` |
| The Peregrine, failed | nothing — the red reason is the sentence that matters there |

A server that states no total gets `3,1 MB so far` rather than a fabricated percentage, which
is the same rule `Download.fraction` already follows for the bar. The percentage is held at
99 until every byte is through: a row that reads 100% and then sits there says the app is
stuck.

The `-ax5` frames are the accessibility branch, where the row is already two lines; the new
line is a third and wraps rather than truncating.

## Storage says what it is about

`ios-settings-root.png`, `ios-settings-downloads.png`, `ios-settings-privacy.png`, and the
`-dark` pair of the first two.

The sweep found Settings' root saying *Downloads and storage — Nothing on this device* and its
own screen *Space used — Zero kB*, while the Downloads destination listed nine publications
under *On this device*. Both were right, and that was the problem.

**What a reader is told now.** The figure is what StoryArc's own files weigh — the downloads
directory, walked — so it counts what was fetched from a source and what the reader imported.
The Downloads destination's shelf is a different set: everything readable with no network,
which `offline-downloads` asks for "whatever source it came from and however it got there",
a folder the reader picked included. Those bytes are not the app's to count and *Clear
downloads* would not free them, so folding them into the total would be a promise nothing
keeps. Neither number moved; every line that states one now names downloads:

| Screen | Was | Is |
| --- | --- | --- |
| Settings root | Nothing on this device | Nothing downloaded |
| Settings root, with files | `129 kB` on this device | `129 kB` downloaded |
| Downloads and storage | Space used · Zero kB | Space used by downloads · 0 bytes |
| Downloads destination | Space used · Zero kB | Space used by downloads · 0 bytes |
| Privacy | Downloads · 0 bytes | unchanged — it was already right |

The Downloads settings screen also carries a footer saying what the figure leaves out, which
is the sentence a reader needs when the destination next door shows nine covers.

`Zero kB` is gone because all four call one helper now, `DownloadStore.formatted(_:)`, with
`spellsOutZero` off. `PrivacySettings` had made that argument in a comment claiming the other
screens followed it; they did not.

**One figure is left spelling its zero out**: the per-source total on the source-detail
screen, `SettingsFeature/SourceDetail.swift:41`. That file belonged to another agent this
wave.

## What is not here

`ios-settings-privacy-dark.png`. Three attempts crashed with `signal kill` while another
agent's UI test held the same simulator — the interference `AGENTS.md` §6 and the sweep both
warn about, not anything about this screen. The light frame is above and the dark row is
unchanged by this work: `privacy.downloads` already used the helper's formatting.
