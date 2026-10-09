# SMB share detail after a read, iOS (wave 4)

Task: close-the-audited-gaps 23.3. The source detail of a share that was added and read, with no "Test connection" run, states the negotiated protocol and encryption. Device: iPhone 17 Pro Max simulator (iOS 26.4), default text size, light and dark. Frames carry the suffix -dark for dark. Fixture: `scripts/smb-server.sh --encrypted ~/StoryArcCorpus` on port 4446 (the password is the fixture's).

| Frame | What it proves |
| --- | --- |
| ios-ios-share-detail-before-test | Detail of 127.0.0.1/Comics before any test: "StoryArc reads this share over SMB 3.1.1. The connection is encrypted." |
| ios-ios-share-detail-encrypted | The same detail after a refresh. The sentence stays. |
| ios-ios-share-detail-not-connected | The control: a share that nothing answers (port 4999) makes no claim about encryption. |

The port 4445 share (encryption offered, not required) was not photographed: the iOS walk covers 4446 only.

Repeat: `node scripts/capture-ios.mjs --out <dir> --only SmbEncryptedWalkTests/<test> --device <id> --appearance light|dark`.
