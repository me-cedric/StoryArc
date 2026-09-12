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
| `android-refused-source-{light,dark}` and `-large-*` | source detail | *Status · Needs sign-in* with **five** actions, *Sign in again* first |
| `android-reconnect-sheet-{light,dark}` and `-large-*` | the add sheet, re-opened | the address filled, the API key empty |
| `android-metered-ask-light` | metered confirmation | *Use mobile data? · Downloading "Slow Transfer" now will use mobile data. The catalogue does not state its size.* |

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

## The refused credential, reached without a server

§4.2 needed a source whose credential a server refused, and the obvious fixture is a race: a
mock served with a rotated key answers 401 on one launch and a connection failure on the next,
and only the first offers *Sign in again*.

`SourceHealth.probe` has a second route to that state and its last line says so — "Neither page
could be built, so the secret this source needs has gone" returns `Unauthorized`. So
`scripts/seed-android-sources.mjs --refused-kavita` writes a source whose credential reference
names a secret the Keystore does not hold. Nothing is asked of the network, so nothing can
flicker, and the screen is the one a refusal reaches.

It is also where the **fifth action** appears: *Sign in again* is offered only for this state,
which is why no single source can show all five at once — the point task 4.1 was reworded
around.

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

## Frames this pass took that belong to another change

Four families — the four-marks shelf, the *Which library* sheet, the narrowed shelf and
*Clear filters* — are evidence for `one-library-three-destinations` tasks 3.2 and 3.3, so they
live in `docs/designs/screenshots/shelves-and-marks-2026-09-12/` with their own README. They
were taken here because the state this folder's seeding builds is what made them reachable.

`android-metered-ask-light.png` has no dark twin. The dialog appears only on a metered
connection, and the emulator had moved to Wi-Fi by the time the dark frame was wanted. No task
asks for this frame; it is kept because the state is otherwise hard to reach.

## What the four-marks frame measured

That frame and its measurements moved to
`docs/designs/screenshots/shelves-and-marks-2026-09-12/README.md`, which is where the dim
sampling and the coverless-row finding are written out.

## One thing the fixture cannot show

Both mock catalogues serve one corpus, so an entry carries the same `urn:` id on both, and a
download is recorded against that id. After fetching the *Attic* copy, the *Loft* row's page
reads as already on the device. That is the fixture speaking rather than the app — two mirrors
of one catalogue really do hold one publication — but it means **no frame here shows two
distinct copies of one title**. That needs two catalogues serving different ids for the same
title, which `scripts/opds-server.mjs` does not offer.
