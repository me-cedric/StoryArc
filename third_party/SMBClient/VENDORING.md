# SMBClient, vendored

**Upstream:** <https://github.com/kishikawakatsumi/SMBClient> · **tag 0.3.1** · revision
`e636c2b2458930770932a36d311ec9d478575b90` · MIT ([`LICENSE`](LICENSE)).

The iOS app reads network shares through this client. [ADR-0010](../../docs/decisions/0010-smb-clients.md)
chose it. [ADR-0019](../../docs/decisions/0019-smb-3-encryption-clients.md) vendored it,
because no upstream release negotiates SMB 3, and SMB 3 is where transport encryption starts.

## Why it is vendored

- The tags end at `0.3.1`. Upstream `main` (`66eafaa`, checked on 2026-10-07) still offers
  SMB 2.0.2 and SMB 2.1 only, and has no transform header and no cipher.
- The change touches the receive path, the negotiate request and the session setup. None of
  those are reachable from outside the package, so the change cannot live in StoryArc's own
  code.
- No new dependency. CryptoKit gives SHA-512, HMAC-SHA256 and AES-GCM. CommonCrypto, which
  upstream already uses, gives the raw AES block that AES-CMAC and AES-CCM are built on.

## What changed against the tag

Every change carries a `StoryArc:` comment.

| File | Change |
| --- | --- |
| `Package.swift` | The test target is removed. The fixtures are not vendored. |
| `Auth/SMB3Crypto.swift` | New. The SP800-108 KDF, the 3.1.1 preauth hash step, AES-128-CMAC, AES-128-CCM, AES-128-GCM, and the SMB2 TRANSFORM_HEADER of MS-SMB2 2.2.41. |
| `Messages/Negotiate.swift` | The request carries capabilities and, when 3.1.1 is offered, the PREAUTH_INTEGRITY and ENCRYPTION negotiate contexts. The response reads the chosen cipher, with every length checked. |
| `Session.swift` | Offers SMB 2.0.2, 2.1, 3.0, 3.0.2 and 3.1.1. Keeps the preauth hash, derives the SMB 3 signing, encryption and decryption keys, signs SMB 3 with AES-CMAC, and seals every message after the session setup when a cipher was agreed. Reports `dialect`, `cipher` and `isEncrypting`. `newSession()` copies the new state, and now also copies `isAnonymous`. |
| `Session.swift`, `SMBClient.swift` (move) | `move(from:to:replacing:)` sets `ReplaceIfExists` in the rename, so a file written beside the sync document replaces it in one server step. `library-sync` task 2.2. |
| `Connection.swift` | The receive path reads one transport frame at a time and opens an SMB 3 transform before it reads the header. An interim `STATUS_PENDING` reply is replaced by the final reply that follows it. |

## What it still does not do

- **It verifies no signature on a response.** [ADR-0016](../../docs/decisions/0016-ios-smb-response-signing.md)
  records this. A sealed session is authenticated by its cipher, so the gap is now limited to
  a session that is signed and not sealed: an SMB 2 server, or an SMB 3 server with no cipher
  in common.
- AES-256, AES-GMAC signing, compression, multichannel and Kerberos are not offered.

## Refreshing

1. Diff upstream's new tag against `0.3.1` for `Session.swift`, `Connection.swift` and
   `Messages/Negotiate.swift`.
2. Carry every `StoryArc:` change across, or drop it when upstream now does the same.
3. Run `scripts/smb-server.sh` and `scripts/smb-server.sh --encrypted`, then `pnpm test:ios`.
   `SmbDialectMatrixTests` forces each dialect and cipher against Samba.
