# Source removal confirmations, iOS (wave 4)

Tasks: one-vocabulary-in-four-languages 4.2 and close-the-audited-gaps 15.11. Both dialogs name the source. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it proves |
| --- | --- |
| ios-settings-source-remove | The dialog "Remove <source>?" |
| ios-settings-source-remove-downloads | The dialog "Remove <source>?" with the sentence that names the titles and the download size. |

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SweepSourceRemovalTests/<test> --device <id> --appearance light|dark`.

Owed from the same task: the "Remove downloads from <source>?" dialog was not taken as its own frame. No walk reaches it by that name.
