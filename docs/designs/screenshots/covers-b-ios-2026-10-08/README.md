# covers-b, iOS frames, 2026-10-08

Device: iPhone 17 Pro Max simulator, iOS 26.4. Branch wave-3. Light, dark, and the largest text size (`-ax5`) where a layout can wrap.

Tasks proved: cover-for-every-publication 6.2, 4.1, 3.3 (the way in), 6.4, 5.1 and 5.3 (against the mock), and close-the-audited-gaps 7.8.

## Frames

| Frame | What it proves |
| --- | --- |
| `ios-detail-no-cover-lookup-off` (+ dark, ax5) | Lookup switch off: the publication page shows "Choose a cover", "Find a cover on the web" and its note. No "Find a cover". |
| `ios-detail-no-cover-lookup-on` (+ dark, ax5) | Lookup switch on: "Find a cover" also shows (task 6.2), and the web hand-off stays (task 4.1). |
| `ios-candidate-sheet-none-found` (+ dark, ax5) | "Find a cover" opens the candidate sheet (task 3.3). For "Sea Room" the lookup found nothing, so the sheet says so and points to the web search. |
| `ios-kavita-list-no-cover` (+ dark, ax5) | Kavita reading list "Start here": a blank thumbnail and "Choose a cover". No send button (task 6.4). |
| `ios-kavita-list-cover-chosen` (+ dark, ax5) | After a cover is chosen: "Change cover", "Remove cover" and "Send this cover to the server". |
| `ios-kavita-list-send-dialog` (+ dark) | The confirmation: "This changes the cover for everyone who can see that list." (task 5.1). |
| `ios-kavita-list-menu` (+ dark) | The whole-shelf menu holds "Mark as read" and "Download" (task 7.8). |
| `ios-kavita-list-download-dialog` (+ dark) | "Keep 3 titles on this device?" with the size sentence (task 7.8). |
| `ios-kavita-collection-menu` (+ dark) | The same menu on the collection "Staff picks". |
| `ios-kavita-collection-mark-read-undo` (+ dark) | After "Mark as read" the capsule "1 title changed" with "Undo". |
| `ios-kavita-download-server-down` (+ dark) | With the mock stopped, Download says "ada · 127.0.0.1 did not answer, so nothing was started." |

## Task 5.3, the drive against the mock

`node scripts/kavita-server.mjs <corpus> --port 5001`, the app added as a Kavita library (address `http://127.0.0.1:5001`, the mock's test key), then the cover was chosen from the Photos picker and "Send" was confirmed. The mock log shows `POST /api/Upload/reading-list` answered 200. The mock then served the list cover (`GET /api/Image/readinglist-cover?readingListId=1`: 200, image/jpeg, 800 by 1200). The live Kavita was not called.

## Not framed

- The candidate sheet with real candidates. The one coverless book on this device ("Sea Room") finds none. A coverless book whose title matches an Open Library record is needed.
- The generic books glyph on a server shelf with no artwork (task 5b.2, iOS frame 5). The mock serves covers at once, so the shelf never showed the glyph. The Shelves screen without the mock (the first frame of the walk) drew the glyph for the two empty shelves, but it was not kept as a frame.

## How to repeat

Build, install and seed as in the library-portability README. Start the mock with the corpus, add it through Settings > Your libraries > Add a library > Kavita library, and open Library > Shelves. Set the look with `xcrun simctl ui`. Pass `"lookUpMissingCovers":true` in the settings launch argument, or switch it on in Settings > Privacy.
