# A source, in every state it can be in — Android, 2026-09-11

The Android half of `source-lifecycle` tasks 4.1, 4.3, 4.5 and 4.6, and the two defects the
capture found.

Every state here needs a **registered** source, which the corpus alone cannot give: its
publications carry `origin: EMBEDDED` and belong to no library the reader added.
`scripts/seed-android-sources.mjs` writes the registry the app reads at launch — three OPDS
catalogues, two answering and one pointed at a port nothing listens on. The routes that reach
these screens are in `scripts/android-routes.mjs` under *Settings > …* and *Search > …*.

```bash
node scripts/opds-server.mjs <corpus> --port 4444
node scripts/opds-server.mjs <corpus> --port 4445
node scripts/seed-android-sources.mjs --device emulator-5554
```

## The frames

Taken on `emulator-5554` (1080 × 2400, Android 16) with `node scripts/capture-android.mjs`.
Every row was read from a `uiautomator` dump, not from the picture.

| Frame | Screen | What it shows |
| --- | --- | --- |
| `android-sources-pair-{light,dark}` | *Your libraries* | *Attic Catalogue · Available · At least 10 titles* above *Cellar Catalogue · Not answering · 0 titles* — the reachable control and the unreachable source in **one** frame, at one moment |
| `android-detail-reachable-{light,dark}` and `-large-{light,dark}` | source detail | Status *Available*, *Last updated*, *In your library · At least 10 titles*, *Downloaded · 1.47 kB*, and five actions |
| `android-detail-unreachable-{light,dark}` and `-large-{light,dark}` | source detail | Status *Not answering*, *Last updated · Never*, *Last error · No answer since …*, *0 titles* |
| `android-removal-{light,dark}` and `-large-{light,dark}` | removal confirmation | *Remove Attic Catalogue? · This removes 10 titles and 1 download (1.47 kB).* |
| `android-remove-downloads-{light,dark}` and `-large-{light,dark}` | downloads confirmation | *Remove downloads from Attic Catalogue? · This deletes 1.47 kB of files downloaded from this library. The library stays, and so do your reading positions.* |
| `android-two-sources-{light,dark}` and `-large-{light,dark}` | search results | One title held by two catalogues: *Slow Transfer · From Attic Catalogue* above *Slow Transfer · From Loft Catalogue* |
| `android-two-sources-page-{light,dark}` and `-large-{light,dark}` | publication page | The copy that row opens, after it was fetched: *Read*, and *On this device · also elsewhere in your library* |
| `android-metered-ask-light` | metered confirmation | *Use mobile data? · Downloading "Slow Transfer" now will use mobile data. The catalogue does not state its size.* |
| `android-four-marks-{light,dark}` | the shelf, sorted by *Last read* | all four combinations of progress and availability in one screen — for `one-library-three-destinations` task 3.3 |
| `android-filter-libraries-{light,dark}` | the filter sheet | the *Which library* section, which is drawn only when more than one source has put something on the shelf |
| `android-filtered-to-one-{light,dark}` | the shelf | narrowed to *Attic Catalogue*, the control reading **1 filter active** |
| `android-clear-filters-{light,dark}` | the filter menu | *Clear filters*, offered while the shelf is narrowed — the way out |

## What the frames establish

1. **All five actions a source can offer are photographed, minus the one no reachable source
   can offer.** The reachable detail frames show *Test connection · Refresh · Free up space ·
   Remove downloads · Remove*. `SourceDiagnosis.of` withholds *Remove downloads* until the
   source holds a finished download — which is why the earlier version of this frame had four
   rows and why a download was made for it. *Reconnect* is absent because it needs a refused
   credential, and a source cannot be both refused and answering. That is task 4.1's own
   point, not a gap in the capture.

2. **The unreachable source is grey, never red, and the control proves it.** Both sources are
   in `android-sources-pair-*` at the same moment, in the same appearance, which is what makes
   the grey a choice rather than the absence of red from the palette.

3. **The precedence rule is the order, not a merge.** *Attic Catalogue* is first in the
   registry and its row is listed first. Both rows stay: `sources` defers de-duplication in
   writing — its Open Questions say "Current requirement orders by source priority;
   de-duplication is deferred" — so two rows is the specified behaviour, and each names the
   library it came from.

4. **Removing a library and removing its downloads are two different promises**, and the two
   dialogs say so. The thirty-day sentence lives under the source list —
   *Removing a library deletes what you downloaded from it and keeps your reading positions
   for 30 days* — and is in `android-sources-pair-*`.

## The two defects this capture found, both fixed

**A publication from a catalogue could not be fetched from its own page.** The page drew
*This one has to be on your device before it opens* and offered nothing that could put it
there — no primary action, nothing in the overflow. The screen computes one verb for
obtaining a copy, `obtain = copy.start ?: onCopyFromLocation`, and then handed both controls
`onCopyFromLocation` alone, which is null for every catalogue row. Instrumented on the device
before the fix: the copy route had resolved, the entry was found, and its acquisition was in
hand — `chosen=http://…/files/Ashfall%202.cbz?slow=45` — while the page showed no control.
Both controls now take `obtain`, and the parameter is named for the route rather than for the
button so the mistake reads as one. `android-metered-ask-light` and the *Read* page are the
proof it works end to end.

**A source nobody had asked was said not to answer.** The provenance line chose between *not
downloaded* and *not answering right now* on `canFetch`, which is `Connected` alone.
Connection state is never persisted, so every source loads as *connecting*, and nothing probes
on the path from the shelf to a publication's page. The page read *From Attic Catalogue — not
answering right now* about a catalogue that `curl` answered with 200 and that the shelf had
just read nine titles from, while *Your libraries* read *Available* for it at the same moment.
The line now asks the one state that means it, which is what iOS always asked. Beside it, a
successful catalogue read marks the source *connected*, so the two screens agree.

## What the four-marks frame measures

The state was built rather than found: a copy was fetched from *Attic Catalogue*, read, then
deleted while its reading position stayed, and the catalogue was stopped. So the shelf holds a
part-read book on the device, a read book whose library is away, an unread local file, and an
unread book whose library is away.

The accessibility labels carry the fact, which is what the task asks: *Ashfall, Ada Lovelace,
CBZ, Needs its library to be reachable* against *Ashfall, Ada Lovelace, CBZ*.

**The dim does not.** Sampled from `android-four-marks-light.png`: the available well is
`rgb(233, 230, 227)` and the away well `rgb(236, 233, 230)` — about one percent apart, and the
away one lighter. `AWAY_ALPHA` is 0.45 and does what it says; it is applied to a **coverless
well**, because a row from an OPDS catalogue draws no cover at all. That second finding is
recorded as task 3.6 of `one-library-three-destinations`.

## One thing the fixture cannot show

Both mock catalogues serve one corpus, so an entry carries the same `urn:` id on both, and a
download is recorded against that id. After fetching the *Attic* copy, the *Loft* row's page
reads as already on the device. That is the fixture speaking rather than the app — two mirrors
of one catalogue really do hold one publication — but it means **no frame here shows two
distinct copies of one title**. That needs two catalogues serving different ids for the same
title, which `scripts/opds-server.mjs` does not offer.
