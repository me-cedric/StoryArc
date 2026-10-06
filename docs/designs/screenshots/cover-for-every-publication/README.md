# A cover for every publication — the frames task 2.6 asks for

Task 2.6 of `cover-for-every-publication`: "the coverless well before, and a publication with a
chosen cover after, on both platforms, light and dark, default and largest text".

The subject is **Sea Room**, the corpus's chaptered audiobook. It is the one publication in
`scripts/corpus.mjs` that carries no artwork of any kind — no embedded picture, no loose image
beside it — so its page is where the well is drawn, and where the reader's own picture is drawn
once they have chosen one.

| Frame | What it shows |
| --- | --- |
| `android-coverless-well-*.png` | The well is the entry point, with the same offer in words under the hero |
| `android-chosen-cover-*.png` | The chosen picture, *Change cover* and *Remove cover* |
| `ios-detail-coverless-well*.png` | The same before state on iOS |
| `ios-detail-chosen-cover*.png` | The same after state on iOS |

> **Not all of these are evidence yet.** The wave 11 review found that five of the eight
> Android frames do not show the state their names claim: the emulator was failing under the
> capture harness when they were taken. Task 2.6 is partial again, and task 6.5 retakes them.
> The iOS frames stand.

`-dark` is the dark appearance. `-largest` on Android and `-ax5` on iOS are the largest
accessibility text size; the two platforms' capture harnesses name that condition differently
and each keeps its own convention.

## How the *after* state was staged, and why it is not a lie

**The picker cannot be driven from a test.** `PHPickerViewController` and Android's photo
picker both run in another process, by design — that is the whole reason this change uses them,
since neither needs a permission — and they show the device's own photo library, which is empty
on a fresh simulator and emulator and which no test may fill.

So the chosen cover was written straight into the app's own override store before the run, under
the key the app itself would use: the FNV-1a hash of `sha:<contentDigest>`, in
`Library/Application Support/cover-overrides` on iOS and `files/cover-overrides` on Android. The
digest is the one `PublicationIndexer` computes — the file's length, its first 512 KiB and its
last — so the app resolved the file by the same key it would have written.

What these frames therefore prove is the ladder: that a cover in the override store is the one
the page draws, that the controls change with it, and that both hold in four conditions. What
they do **not** prove is the picker itself. `CoverLadderTests` and `CoverLadderTest` assert the
storing, the cropping and the removal; `CoverlessWellOffersAChoiceTest` presses the well under
Robolectric and asserts the chooser is asked.

The picture used as the reader's choice is a screenshot of the app, cropped to 2:3. It is
deliberately something no publication could carry, so a reader of these frames cannot mistake
the chosen cover for artwork the file already held.

## Reproducing them

```bash
# Android
node scripts/capture-android.mjs "Publication page > no cover" --out <file> [--dark] [--font-scale 2.0]

# iOS
node scripts/capture-ios.mjs --out <directory> --only SweepCoverChoiceTests [--appearance dark]
```

Both walks need a seeded device: `node scripts/corpus.mjs --simulator <udid>` for iOS, and the
corpus pushed into `/sdcard/Android/data/com.mecedric.storyarc.debug/files` for Android.
