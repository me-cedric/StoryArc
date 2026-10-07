---
status: accepted
date: 2026-10-07
deciders: Cédric Meyer
---

# ADR-0018 — SMB 3 encryption on both platforms: smbj on Android, a vendored SMBClient on iOS

**This updates [ADR-0010](0010-smb-clients.md) and [ADR-0016](0016-ios-smb-response-signing.md).**
ADR-0010 chose one SMB client per platform and recorded that neither encrypts. ADR-0016
accepted the iOS integrity risk and recorded that SMB 3 is never reached on iOS. Decision
D26 of the `close-the-audited-gaps` change asks for SMB 3 encryption on both platforms.
This record says how, and what is still true of the two older records.

## Context and problem statement

[`network-share`](../openspec/specs/network-share/spec.md)'s *Encrypted transport*:

- WHEN the server supports SMB 3 encryption
- THEN the app negotiates it
- AND the source detail screen states whether the connection is encrypted

Neither client could do this:

- **Android, jcifs-ng 2.1.10.** It offers SMB 3.1.1 and carries the negotiate context for
  encryption, and it has no cipher. Against `smb encrypt = required` it answers "Server
  requires encryption, not yet supported". It is also LGPL-2.1-or-later, the one copyleft
  entry in the licence inventory.
- **iOS, SMBClient 0.3.1.** It offers SMB 2.0.2 and SMB 2.1 only. Against `smb encrypt =
  required` the session setup is refused with `ACCESS_DENIED`, which the app read as a
  refused password.

And the detail screen read one constant, `ShareTransport.isEncrypted = false`, on both
platforms.

## Decision drivers

- The spec clause, on both platforms ([ADR-0001](0001-independent-native-cores.md)).
- The ranged read stays. [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) put
  `RandomAccessSource` under the format layer so that a share could supply one.
- A permissive licence, as ADR-0010 and ADR-0016 require.
- No new dependency on iOS.

## Considered options

### Android

| Option | Verdict |
| --- | --- |
| Keep jcifs-ng | No cipher, and LGPL. |
| **smbj 0.15.0** | **Chosen.** Apache-2.0. Negotiates SMB 2.0.2 to SMB 3.1.1, encrypts with AES-128-CCM and AES-128-GCM, signs, and checks every response signature. `File.read(buffer, offset, …)` is a ranged read. |

### iOS

| Option | Verdict |
| --- | --- |
| A newer SMBClient release | There is none. The tags end at `0.3.1`. `main` (`66eafaa`, checked on 2026-10-07) still offers SMB 2.0.2 and SMB 2.1 only, with no transform header and no cipher. |
| AMSMB2 or libsmb2 | LGPL. ADR-0016 already declined both. |
| **Vendor SMBClient 0.3.1 and add SMB 3** | **Chosen.** MIT. `third_party/SMBClient`, with every change listed in its [`VENDORING.md`](../../third_party/SMBClient/VENDORING.md). CryptoKit and CommonCrypto only. |

ADR-0016 named "vendoring an SMB implementation" as the thing ADR-0010 declined, and it
priced option E (fix response verification upstream) as unbounded. This decision is
narrower than option E: it adds SMB 3 negotiation and transport encryption, which upstream
lacks entirely, and it does not add response-signature verification. The vendored copy is
small, MIT, and diffed against one tag, so a later upstream release can be compared line by
line.

## Decision Outcome

| Platform | Client | Licence | Dialects offered | Ciphers |
| --- | --- | --- | --- | --- |
| Android | smbj 0.15.0 | Apache-2.0 | 2.0.2, 2.1, 3.0, 3.0.2, 3.1.1 | AES-128-GCM, AES-128-CCM |
| iOS | SMBClient 0.3.1, vendored, with SMB 3 added | MIT | 2.0.2, 2.1, 3.0, 3.0.2, 3.1.1 | AES-128-GCM, AES-128-CCM |

Both clients **offer** encryption and **use** it whenever the two ends agree SMB 3 with a
cipher in common. Neither demands it, so an SMB 2 server and a guest share still connect,
unencrypted, and say so.

**The negotiated state is per session.** Each client reports the dialect and the encryption
it negotiated through `SmbIdentity`. Each probe of a saved share records that in
`ShareSessions`, in memory only, keyed by the source. `SourceDiagnosis.transport` carries it,
and the source detail screen draws one of three whole sentences from it: the dialect and
"encrypted", the dialect and "not encrypted", or "no connection since StoryArc started". The
constant `ShareTransport.isEncrypted` is gone on both platforms.

Android's smbj brings Bouncy Castle 1.85.2 (MIT), asn-one 0.6.0 (Apache-2.0), MBassador
1.3.2 (MIT) and the SLF4J API 2.0.18 (MIT). All four are in the licence inventory. No
component in the inventory is LGPL now.

## Consequences

- **Good.** The spec clause is met on both platforms, and measured: the detail screen states
  what this session negotiated.
- **Good.** Android verifies every response signature and every sealed message. iOS
  authenticates every sealed message through its cipher. On a server with SMB 3 and a cipher
  in common, which is every current NAS, the iOS integrity gap of ADR-0016 is closed for the
  session.
- **Good.** No LGPL component ships. The relinking duty that jcifs-ng carried is gone.
- **Bad.** StoryArc now maintains an SMB 3 implementation on iOS: the key derivation, the
  preauth hash, AES-CMAC, AES-CCM, AES-GCM and the transform header. It is tested against
  Samba and against the RFC 4493 vectors, and it is security code that needs review on every
  change.
- **Bad.** iOS still verifies no signature on a response. A session that is signed and not
  sealed (an SMB 2 server, or SMB 3 with no common cipher) is as exposed as ADR-0016 says.
  ADR-0016 stays the record of that risk, now for that narrower case.
- **Bad.** Android's R8 rules grow: MBassador finds its handlers by annotation at run time.
  `apps/android/app/proguard-rules.pro` keeps them, and `minifyReleaseWithR8` passes.
- **Neutral.** `SpnegoAsn1LimitTest` is removed. It guarded jcifs-ng's use of Bouncy
  Castle's ASN.1 parser for SPNEGO, and smbj parses SPNEGO with asn-one instead. Bouncy
  Castle 1.85.2 is past the CVE-2025-8885 fix in 1.78.

### What this changes in ADR-0010

- The Android row: smbj replaces jcifs-ng.
- The two "Bad" entries about dialects and encryption: both clients now reach SMB 3.1.1,
  both report the dialect they landed on, and both encrypt.
- The verification still holds, and grows: the suite runs against `server signing =
  mandatory` and also against `smb encrypt = required`.

### What this changes in ADR-0016

- "SMB 3 is never reached" is no longer true. The vendored client negotiates SMB 3.1.1.
- "Whether the client signs is decided by the server" is narrower: an SMB 3 session signs
  every request, and a sealed session needs no signature.
- The accepted risk stays for a session that is signed and not sealed.

## Verification

Both fixture servers come from `scripts/smb-server.sh`: the plain share on port 4445 offers
encryption and demands signing, and the `--encrypted` share on port 4446 demands encryption.

- **Android.** `EncryptionRequiredTest` connects to 4446 and gets an encrypted SMB 3.1.1
  session, a listing and a ranged read. `SmbClientTest` gets an encrypted SMB 3.1.1 session on
  4445. `ShareSessionRecordTest` proves that a probe records the session.
- **iOS.** `SmbEncryptionTests` does the same against 4446 and 4445. `SmbDialectMatrixTests`
  forces each path the client can land on: AES-128-CCM on 3.1.1 and on 3.0.2, AES-128-GCM,
  AES-CMAC signing on 3.1.1 and on 3.0.2 with no cipher, HMAC-SHA256 on 2.1, and the refusal
  of SMB 2.1 by a share that demands encryption. `SMB3CryptoTests` checks AES-CMAC against
  RFC 4493 and checks that a changed byte or another session's transform is refused.
  `ShareProbeRecordTests` proves that a probe records the session.
- **A recorded manual run, 2026-10-07.** A third encrypted Samba served one 3,500,000-byte
  random file. The iOS client read it whole with AES-128-GCM and again with AES-128-CCM, in
  frames up to the server's 8 MiB read size, and both reads matched the file's SHA-256
  (`561665f78163bc91a8a99ee50fdf68990098847af3868efb7ec43e5bee15e05b`). `SmbSource` also read 400,000 bytes from offset 3,000,000.
