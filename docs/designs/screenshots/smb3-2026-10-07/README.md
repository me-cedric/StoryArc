# SMB 3 encryption on a share — 2026-10-07

Task 18.3 of `close-the-audited-gaps`, decision D26. The share asks for encryption, and each
platform now negotiates SMB 3.1.1 and reports what it measured. These frames show that report
on the add sheet and on the source detail screen.

**Server.** `scripts/smb-server.sh --encrypted` on port 4446 (`smb encrypt = required`, signing
mandatory). The simulator reaches the Mac at `127.0.0.1`. The emulator reaches it at `10.0.2.2`.
The user name is the Mac user name. The password is the fixture password that the script prints.
Both are typed into the real add form, so the credential goes through the app's own store.

**Devices.** iOS: iPhone 17 Pro Max simulator, iOS 26.4. Android: `storyarc-ci` emulator, API 35.
Each frame is taken in light and dark. Each is taken at the default text size and at the
largest size (iOS AccessibilityXXXL, Android font scale 2.0, files ending `-ax` or `-ax5`).

| Frame | What it proves |
| --- | --- |
| `ios-add-share-encrypted*`, `android-share-add-encrypted*` | The add sheet shows the exact dialect and the state after Connect: iOS "SMB 3.1.1 · encrypted", Android "SMB 3.1.1 · encrypted · signed". Before this change iOS showed "SMB 2 · not encrypted" and Android showed "SMB 2 or later". |
| `ios-share-detail-encrypted*`, `android-share-detail-encrypted*` | The detail screen draws the whole sentence for an encrypted session: "StoryArc reads this share over SMB 3.1.1. The connection is encrypted." The frame is taken after Test connection. |
| `ios-share-detail-before-test*` | The detail screen of the same share before any probe. It says "No connection has been made since StoryArc started", although the sheet browsed the share and the row reads Available with 11 titles. See the finding below. |
| `ios-share-detail-not-connected*`, `android-share-detail-not-connected*` | The control. A share that nothing answers (port 4999) gets the third sentence, not the encrypted one. |

**Finding.** The detail sentence reads the last session that the probe recorded
(`ShareSessions`). The add sheet and the library scan use other clients and record nothing. So
a reader who adds an encrypted share sees "No connection has been made" until they press Test
connection. The reviewer traced the sentence to the probe, so the claim "the sentence is
measured" holds, but the first sight of the screen is stale. Tracked as task 23.3.

## How to repeat

1. `scripts/smb-server.sh --encrypted` (keep it running).
2. iOS: `node scripts/install-and-seed-simulator.mjs <udid>`, then
   `node scripts/capture-ios.mjs --out <dir> --only SmbEncryptedWalkTests --device <udid> --appearance light`
   and again with `dark`. Run `testCaptureShareDetailEncrypted` before the `AtLargestText`
   walk: the largest-size walk reads the share that the first one registers. The system offers
   to save the password; the walk declines.
3. Android: `adb shell pm clear com.mecedric.storyarc.debug`, then
   `node scripts/capture-android.mjs "Sources > add share encrypted" --out <file>.png [--dark] [--font-scale 2.0]`
   and the same for `"Sources > share detail encrypted"`. For the control, run
   `adb root`, then `node scripts/seed-android-sources.mjs --share --share-port 4999` (with `adb` on
   the path), then `"Sources > share detail not connected"`.
