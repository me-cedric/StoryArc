# The cover's edit button and menu, iOS (wave 4)

Tasks: close-the-audited-gaps 24.1 (one menu behind an edit button), 24.2 (removal asks first), 24.5 (hit-region audit reaches these screens). These frames replace the wave 3 frames of the old stacked buttons. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it proves |
| --- | --- |
| ios-cover-edit-closed | A comic page with artwork: the round glass edit button sits on the bottom trailing corner of the cover. No stacked text buttons remain below the hero. |
| ios-cover-menu-open | The menu from that button, with no chosen picture: "Change cover" and "Find a cover on the web". |
| ios-cover-chosen | The page after a picture is chosen through the real photo picker. |
| ios-cover-chosen-menu-open | The menu with a chosen cover: the destructive "Remove cover" is the last row, in its own group. |
| ios-cover-remove-dialog | "Remove this cover?" with the sentence "The picture you chose is deleted from this device." and the button "Remove cover". |
| ios-cover-add | The audiobook page Sea Room has no artwork. The well keeps the visible label "Add a cover". |
| ios-cover-add-menu-open | "Add a cover" opens the menu: "Choose a cover" and "Find a cover on the web". |
| ios-kavita-cover-add | Kavita reading list "Start here" with no cover: the label "Add a cover". |
| ios-kavita-cover-chosen | The list with a chosen cover and its edit control. |
| ios-kavita-cover-menu-open | The list menu: "Change cover", "Send this cover to the server", then "Remove cover" last. There is no find row and no web row on a list (owner decision pending, parent choice O24). |
| ios-kavita-cover-send-dialog | The send row asks first: "This changes the cover for everyone who can see that list." |

Repeat: `node scripts/seed-simulator.mjs --device <id>` and `node scripts/corpus.mjs --simulator <id>`. For the Kavita frames, run `node scripts/kavita-server.mjs <corpus> --port 5001` and add it in Settings > Your libraries > Add a library > Kavita library (address http://127.0.0.1:5001, the key the server prints). Then
`node scripts/capture-ios.mjs --out <dir> --only SweepCoverMenuTests/<test> --device <id> --appearance light|dark`.
Tests: testCaptureEditButtonAndMenuOnAnArtworkCover, testCaptureChosenCoverMenuAndRemoveDialog, testCaptureCoverlessAddACoverAndMenu, testCaptureKavitaListCover. Each walk removes the picture it chose.

The hit-region audit test for the Kavita cover (testKavitaListCoverPassesTheHitRegionAudit) opens the list through Home, where it skipped; this set's walk finds the list by its title on Home. That skip is a finding for the audit file, not fixed here.

Supersedes: the wave 3 frames of the stacked cover buttons in `covers-b-ios-2026-10-08` (the Kavita list rows "Change cover", "Remove cover" and "Send this cover to the server", and the chosen-cover page). Those frames show the old layout. This set is the record of the cover screens.
