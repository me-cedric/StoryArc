# Frames re-scoped to the new rule, iOS, 2026-10-10

Owner rule of 2026-10-09 (`AGENTS.md` section 6): a snapshot reference proves a screen state. A device screenshot proves only what a snapshot cannot draw. Default text size, light and dark.
Device: iPhone 17, iOS 26.2 (`FAE72C22-8CCC-47A3-B114-1AE10BE48780`).

## Device frames in this folder

| Frame | Task | What it proves |
| --- | --- | --- |
| `ios-cover-web-handoff.png` and `-dark` | cover-for-every-publication 4.3 | On the page of *Sea Room* (no artwork), *Add a cover* then *Find a cover on the web* leaves the app for the system browser. The browser shows an image search for "Sea Room cover". |

Repeat: seed the simulator (`node scripts/install-and-seed-simulator.mjs <id>`, `node scripts/corpus.mjs --simulator <id>`). Open the Library, then the group *Sea Room*, then the M4B. Tap *Add a cover*, then *Find a cover on the web*. Take the frame with `xcrun simctl io <id> screenshot`. Set the appearance with `xcrun simctl ui <id> appearance light|dark`.
The search page is a third-party site, so its pictures change from day to day. The frame proves the hand-off, not the results.

## Snapshot references added

New entries 19a to 26 of `docs/designs/screen-catalogue.md`. Images are in `apps/ios/SnapshotTests/__Snapshots__/<Class>/`. Run `pnpm snap:ios` to compare them.

| Entry | Task | State drawn |
| --- | --- | --- |
| `LocalisedCatalogueTests/19a` to `19d` | one-vocabulary 4.6, close-the-audited-gaps 15.10 and 26.3 | The publication page in French: title not downloaded, server stopped, library removed, second place. |
| `LocalisedCatalogueTests/19e` | the same | The French sentence of a page that left the library (the alert on the shelf). |
| `LocalisedCatalogueTests/20a` and `20b` | one-vocabulary 1.7 | The skipped notice for `protected.aax` in Spanish, and in English as the control. Light, dark and largest. |
| `LocalisedCatalogueTests/21a` and `21b` | one-vocabulary 2.4 | The alert for a refused `.txt` file in French, and in English as the control. |
| `EdgeStateCatalogueTests/22` | cover-for-every-publication 3.6, 6.7 | The cover chooser with three candidates and their pictures (a stub transport serves painted covers). |
| `EdgeStateCatalogueTests/23` | one-library-three-destinations 0b.2, close-the-audited-gaps 26.3 | Home when an audiobook was read last: the hero offers Resume. |
| `EdgeStateCatalogueTests/24` | one-vocabulary 4.2, close-the-audited-gaps 26.3 | The source detail at "1 of 1 title" (singular). |
| `EdgeStateCatalogueTests/25a` and `25b` | close-the-audited-gaps 23.2 | A tall page at Fit to Width, with Slide and with Page curl stored. The page fills the width, and the two edge frames are the same width. |
| `EdgeStateCatalogueTests/26` | one-library-three-destinations 2.1 | The two pinned sections of Home built by `pinnedShelfRows` with the real covers. The reading list follows its own order. The collection follows the library order. |

Notes that a reader needs:

- The language is set through the app's own `speaking(_:)`. The hosted app sets the language back whenever it redraws, so the test asks for it again every 0.1 s while it draws.
- 25b: at rest, Page curl draws the same page body as Slide (decision D33). The frame does not draw a turn in progress.
- 22 is a list on a plain background. The sheet is drawn alone, not over the publication page.
- 26 is the two sections only. The full Home puts them below Recently added and the shelf rows, so they are below the first screen.

## Product findings

- Skipped notice at the largest text size (entries 20a and 20b, `.largest.png`): the sentence wraps one word to a line, the banner overlaps the large title, and *Show* falls below the first screen. English and Spanish both show it. Entry 18 does not, because its sentence is shorter.

## Owed, with the reason

- True Split View beside a second app on an iPad (one-library 4.1 and 4.3, publication-detail 4.1): the simulator drag between two apps has no scripted route. The device checklist holds the step (section H).
- The dark twin of the iPad resize sequence (`ipad-split-width-ios-2026-10-09`): the drag was done by hand in light only. Not repeated.
- A turn in progress for Page curl at Fit to Width (23.2): a held drag cannot be captured by a UI test.
