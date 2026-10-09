# Damaged ending in the player, iOS (wave 4)

Task: close-the-audited-gaps 23.6 (iOS half). Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark.

| Frame | What it proves |
| --- | --- |
| ios-player-damaged-before and -dark.png | After Cut Short (truncated.m4b) ends, the player shows the heading "Playback stopped", the sentence "1 part could not be played" and the button "Mark as finished". |
| ios-player-damaged-after and -dark.png | After a tap on "Mark as finished", the heading changes to "Finished". |

Repeat: `node scripts/seed-simulator.mjs --device <id>`, then
`node scripts/capture-ios.mjs --out <dir> --only PlayerDamageTests/testCaptureDamagedEndingBeforeAndAfterMarking --device <id> --appearance light|dark`.
