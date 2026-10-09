# SMB share on port 4445, iOS (wave 5)

Tasks: close-the-audited-gaps 23.3. Device: iPhone 17 Pro Max simulator (iOS 26.2). Frames are at the default text size. A frame with the suffix -dark is dark. Capture command: `node scripts/capture-ios.mjs --out <dir> --only <Class>/<test> --device <id> --appearance light|dark`.

| Frame | What it proves |
| --- | --- |
| ios-ios-share-detail-signed-4445 | The detail screen of the Comics share on 127.0.0.1:4445 after Test connection. It reads: StoryArc reads this share over SMB 3.1.1. The connection is encrypted. |

Repeat: Start `scripts/smb-server.sh <corpus>` (port 4445). Write 4445 into `/tmp/w5hs/smbport`. Run `SmbEncryptedWalkTests/testCaptureShareDetailEncrypted`. AGENTS.md section 7 calls this fixture signed and unencrypted, yet the client reports an encrypted session. Samba encrypts when the client asks. Decide what the sentence should say for a server that does not require encryption.
