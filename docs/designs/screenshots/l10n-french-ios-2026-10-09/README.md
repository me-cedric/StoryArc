# French publication page, iOS (wave 4)

Task: one-vocabulary-in-four-languages 4.6 (iOS half), partial. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it shows |
| --- | --- |
| ios-detail-provenance-device-fr and -dark | The page of a comic in French. The tab bar, the title action ("Lire") and the tabs are French. **The provenance line reads in English: "From On this device, readable now".** The catalogue holds "De %@, lisible maintenant" for fr. |

This frame records a defect. It does not prove 4.6. Owed: the other four states (server title not downloaded, server unreachable, library removed with no copy, second place), the refusal under the primary action, and the gone state. They need a running Kavita mock, a stopped mock, and a stale route. Not taken in this run.

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SweepCoverMenuTests/testCaptureFrenchPublicationPage --device <id> --appearance light|dark`.
