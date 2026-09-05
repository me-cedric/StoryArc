# The source detail screen — iOS, 2026-09-05

`source-lifecycle` §4.1's iOS half. Four frames from `StoryArc-iPhone17Pro` (402 pt), taken
with `scripts/capture-ios.mjs` against `SweepSettingsTests`.

| Frame | Appearance | Text size |
| --- | --- | --- |
| `ios-settings-source-detail.png` | light | default |
| `ios-settings-source-detail-dark.png` | dark | default |
| `ios-settings-source-detail-ax5.png` | light | `AccessibilityXXXL` |
| `ios-settings-source-detail-ax5-dark.png` | dark | `AccessibilityXXXL` |

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

## Still owed for §4.1

**The Android half**: `pnpm capture:android "Settings > source detail" --out <file> [--dark]
[--font-scale 2.0]`. The route exists and needs a non-empty source list, which the corpus alone
does not give — the 17 generated publications carry `origin: EMBEDDED` and belong to no source,
so *Your libraries* is legitimately empty until one is added.

**A source holding a finished download**, on either platform, so *Free up space* is offered
against a non-zero figure rather than against `0 bytes`.

## How to retake them

```bash
for appearance in light dark; do
  for walk in testCaptureSettingsSourceDetail testCaptureSettingsSourceDetailAtLargestText; do
    node scripts/capture-ios.mjs --out docs/designs/screenshots/source-lifecycle-2026-09-05 \
      --only "SweepSettingsTests/$walk" --appearance $appearance
  done
done
```

Read the run summary rather than the exit code: `xcodebuild` exits 0 when a `-only-testing:`
filter matches nothing, so each run must report `1 test case(s): 1 passed, 0 failed, 0 skipped`.
A `0 skipped` matters as much as the `1 passed` — a walk that skips passes and photographs
nothing.
