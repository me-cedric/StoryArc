---
status: accepted — risk accepted
date: 2026-08-30
deciders: Cédric Meyer
---

# ADR-0016 — iOS SMB: an unsigned, unverified session, and no client that fixes it

**This extends [ADR-0010](0010-smb-clients.md) rather than contradicting it.**
That ADR chose one SMB client per platform and recorded what neither of them
does: encrypt. It was silent on *integrity*, and integrity is the gap the
security review found. Nothing about the choice of SMBClient is reopened here;
what is on the table is what to do about a property of it that was not weighed
when it was chosen.

## Context and problem statement

[`network-share`](../openspec/specs/network-share/spec.md) requires streaming
reads: every page turn on a share is a fresh SMB2 `READ`. That makes the
transport part of the app's **primary** attack surface — a malicious publication
— rather than a side channel, because whoever controls the bytes on the wire
chooses the ZIP central directory, the image data and the EPUB XHTML that the
format layer then parses.

On iOS that transport has no integrity protection at all. Established from the
resolved dependency, SMBClient 0.3.1 (`Package.resolved` revision `e636c2b`):

- **Whether the client signs is decided by the server.**
  `Sources/SMBClient/Session.swift:82` —
  `signingRequired = response.securityMode.contains(.signingRequired)`. A server
  that clears that bit gets an unsigned session, which is also what an attacker
  who can answer the NEGOTIATE gets.
- **Signing, when it happens, is outbound only.**
  `Session.swift:692-702` adds an HMAC to requests and returns the packet
  untouched otherwise. Grepping the whole `Sources/SMBClient` tree for `verif`
  finds **nothing**: no code path checks the signature on a response, whether or
  not the session is signed. Signing every request would therefore not close the
  hole — the attacker does not need to forge a request, only to rewrite an
  answer.
- **SMB 3 is never reached.** `Session.swift:70-72` defaults to
  `dialects: [.smb202, .smb210]`, so transport encryption — the other thing that
  would make responses tamper-evident — is not available either.

The app does nothing to narrow this: `Sources/Smb/SmbClient.swift` calls
`client.login(...)` and `client.connectShare(...)` with the library's defaults,
and hardcodes `isEncrypted: false` on the identity it reports.

So a reader streaming a comic from their NAS over Wi-Fi can have the archive's
bytes substituted by anyone on the same network — an ARP-spoofing guest, a
compromised IoT device — and the app will parse whatever arrives. This is the
security review's **rank 11, medium, CONFIRMED**.

**Android is not in this position.** jcifs-ng ships
`jcifs/internal/smb2/Smb2SigningDigest` with a `verify` method, so inbound
signatures are checked. Under the same review's rank 16 the Android client now
also *asks* for signing (`jcifs.smb.client.signingPreferred`) and reports what it
negotiated on the connection sheet, so a reader on Android can see whether the
session is signed. The two platforms are, for the first time, not mirrors on this
point — which is the second thing this ADR has to resolve.

## Decision drivers

- The defect is in the dependency, not in StoryArc. Nothing the app configures
  makes SMBClient verify a response.
- **The app does not talk to the reader about its own weaknesses.** Security
  posture is recorded in this repository. It is not a line on a screen, a badge,
  or a sentence a reader has to interpret, and it is not a toggle or a prompt
  that sells safety in exchange for a tap. This drops what an earlier draft of
  this ADR recommended, and the drop is the point: a disclosure is not a fix, and
  dressing one up as the other is how a known gap stops being counted.
- **A fix may not cost a feature.** Reading part of a file at an offset is not a
  nicety here; [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) put
  `RandomAccessSource` under the ZIP reader specifically so a share could supply
  one. A client that must download a file to read a page is not a smaller fix, it
  is a different app.
- [ADR-0001](0001-independent-native-cores.md) accepts two clients and two sets
  of bugs. It does not accept the two platforms making different promises without
  the difference being written down.
- Every entry in [`packages/licences/notices.json`](../../packages/licences/notices.json)
  is permissive — BSD, Apache, MIT, OFL. An LGPL or GPL dependency in an App
  Store binary is a live argument about §6 relinking rights against a signed,
  DRM'd bundle, not a footnote in an inventory.

## What a replacement has to do

Read off `Sources/Smb/`, so that "feature parity" means something checkable
rather than something asserted:

| The seam | The library call under it |
| --- | --- |
| `SmbClient.connect() -> SmbIdentity` | `login(username:password:)`, `connectShare(_:)` |
| `SmbClient.list(_:) -> [SmbEntry]` | `listDirectory(path:)` |
| `SmbClient.open(_:) -> RandomAccessSource` | `fileStat(path:)` for the length, then `fileReader(path:)` |
| `SmbSource.read(offset:count:)` | **`FileReader.read(offset:length:)`** — one SMB2 `READ` at an offset |
| Silent re-establishment after sleep | a second `SMBClient` built from the same `SmbAddress`, one retry |
| Guest, and username plus password | the `username` and `password` arguments |

Two things the survey does **not** have to carry, established rather than
assumed. Share enumeration is not used: `SMBClient.listShares()` exists and no
StoryArc code calls it — the reader types the share name. Domain accounts are not
supported today either: the library's `login` takes `domain:` and `workstation:`,
`SmbAddress` has no field for them and `SmbClient` never passes them.
`SmbDiscovery` is `NWBrowser` over `_smb._tcp` and touches no client at all.

The ranged read is the hard bar. Everything else is ordinary.

## Considered options

### A — Say so, on the connection sheet

Mirror Android's line: report `not signed` beside the existing `not encrypted`,
in four languages.

- **Rejected, and not on the ground the earlier draft argued.** It does not stop
  the attack, which was always true. It is now also against the rule: the app
  does not explain its own weaknesses to the reader, because "not signed" is a
  phrase nobody can act on and a screen is not where a security posture belongs.
  It stays recorded in [`SECURITY.md`](../../SECURITY.md), which is where a
  reader who wants to know can find it and where a maintainer cannot miss it.

### B — Swap the client

**This is the option the direction asked to exhaust, so it is the one written up
in full.** Each licence comes from that project's own `LICENSE` or `COPYING`, and
each capability claim from its own source rather than from a README.

| Candidate | Licence | Verifies a response? | Ranged read | Verdict |
| --- | --- | --- | --- | --- |
| **SMBClient 0.3.1** (current) | MIT | No — zero hits for `verif` in `Sources/SMBClient` | `read(offset:length:)` | the status quo |
| **SMBClient `main`** (`66eafaa`, 89 commits ahead) | MIT | Still no — zero hits | yes | no newer tag exists |
| **AMSMB2** | **LGPL-2.1** — its own `LICENSE`, wrapper included | Only when the attacker leaves a bit set | `pread` | licence, and it would not stop this attack anyway |
| **libsmb2** at head | **LGPL-2.1-or-later** (`COPYING`) | **Yes**, correctly, and it seals SMB 3 too | yes | licence |
| **alexiscn/SMBKit** | claims MIT, is "just a copy of AMSMB2" | as AMSMB2 | as AMSMB2 | a derivative of an LGPL work is not relicensed by copying it |
| **filmicpro/SMBClient** over libdsm | MIT wrapper, LGPL-2.1 library | — | — | **SMB 1 only.** This app refuses SMB 1 |
| **sahlberg/usmb2** | MIT | No — `usmb2.c:206`, "16 byte signature is all zero" | `usmb2_pread` | a Z80-class client; strictly behind the current one |
| **icedracon/smb2-client** | MIT, Rust | No — `client.rs:52` signs outbound only | — | one month old, one star, and a Rust FFI |
| **A platform API** | — | — | — | `iPhoneOS26.5.sdk` ships no NetFS or SMB framework. There is none |

Four findings underneath that table are worth keeping, because they are the ones
that decided it.

**The cheapest answer does not exist.** The tag list on
kishikawakatsumi/SMBClient ends at `0.3.1`, at exactly the revision
`Package.resolved` already pins. `main` is 89 commits ahead and still contains no
verification; what it *has* gained is a `requireSigning` flag
(`SMBClient.swift:38`) and a stronger derivation of `signingRequired`
(`Session.swift:82`) — which is Option D below, made official upstream, and which
leaves responses exactly as unchecked as before.

**libsmb2's verification is not where its own function names suggest.**
`smb2_pdu_check_signature()` in `lib/smb2-signing.c:274` is a stub that returns
`0` and is called from nowhere. The real check is in `lib/socket.c` and
`lib/libsmb2.c`, and at head it is right: it refuses an unsigned PDU rather than
treating a cleared flag as nothing to check, and it says why in the source — that
flag lives inside the header being authenticated, so anyone on the path could
strip it (MS-SMB2 3.2.5.1.3).

**AMSMB2 does not ship that.** Its `Dependencies/libsmb2` submodule is pinned at
`aedafb2`, and at that revision `socket.c` gates the whole check on
`smb2->hdr.flags & SMB2_FLAGS_SIGNED` — the bypass upstream later removed. So the
one candidate that would be easy to adopt would, as it ships today, verify only
those responses an attacker chooses to have verified. It would cost the project
its first copyleft dependency in exchange for that.

**There is no platform escape.** The iPhoneOS 26.5 SDK's framework directory has
no NetFS, no SMB, nothing. Routing the reader through the Files app instead would
mean losing in-app discovery, in-app credentials, the share browser and saved
sources — a fix that makes the app do less, which is not a fix.

### C — Verify above the seam, in StoryArc's own code

- **Not possible.** `Session.signingKey` is `private`, `Session.connection` is a
  `private let`, and `Session.init(_ connection:)` is `private`. There is no
  injection point and no way to obtain the key an HMAC would need. StoryArc
  cannot check what the library hands it.

### D — Demand signing from the app and hope

Drive `session.negotiate(securityMode:dialects:)` directly — it is public —
passing `[.signingEnabled, .signingRequired]`.

- **Bad, and worth writing down so it is not proposed as a quick win.** It makes
  the client sign its *requests*. Responses are still never verified, so the
  attack — rewriting what comes back — is untouched. The app reads and never
  writes, so request forgery was never the exposure. Refusing servers that do not
  require signing would additionally break every reader whose NAS merely permits
  it, which is a feature removed to buy nothing.

### E — Fix it upstream

Open a pull request against SMBClient: verify the signature on every response,
and refuse a session downgraded from what was requested.

- **Good.** The library is MIT and small, and this fixes it for everyone.
- **Bad, and the earlier draft priced it wrong.** It said "one file, one HMAC
  comparison". The source says otherwise. The raw response bytes are reassembled
  in `Connection.receive`, which also walks a compounded chain and absorbs interim
  `STATUS_PENDING` replies — while the signing key lives one layer up in
  `Session`, behind `private`. A correct patch has to push the key down, verify
  each PDU of a compound chain, handle the interim reply (which *is* signed, per
  MS-SMB2 3.2.5.1.4), exempt NEGOTIATE and the final SESSION_SETUP leg, and — the
  part that is easy to get wrong — refuse an unsigned PDU rather than skip the
  check when the flag is clear. libsmb2 shipped precisely that last bug for years.
  This is a real change across two types with four special cases, and it is not
  something to write blind against one Samba fixture and then ship to readers'
  NASes.
- **Bad.** Unbounded schedule regardless. StoryArc would have to vendor the patch
  to ship before upstream merged, and vendoring an SMB implementation is the thing
  [ADR-0010](0010-smb-clients.md) declined to do in the first place.

## Decision

**None of the above. The risk is accepted, and nothing ships.**

The survey was run to find a better client, and there is one: libsmb2 at head
verifies responses correctly, seals SMB 3, and reads at an offset. It is
LGPL-2.1-or-later. The only maintained Swift wrapper for it is LGPL-2.1 itself
and pins a revision of it whose verification an attacker can skip. Everything
permissively licensed either does not verify (SMBClient, usmb2,
icedracon/smb2-client), speaks SMB 1 (libdsm), or does not exist (a platform
API). No candidate clears the licence bar and the feature bar at once, and the
one that clears the feature bar clears it at a price this project has already
declined to pay once, for the same library, in ADR-0010.

So the answer is not that the survey found nothing. It is that the survey found
the same thing ADR-0010 found, for the same reason — and the reason is the
licence rather than the FFI. `third_party/libarchive` is already C behind an FFI
on both platforms and nobody minds.

Nothing is added to the app. No line on the connection sheet, no badge, no
toggle, no prompt. The posture is recorded here and in
[`SECURITY.md`](../../SECURITY.md), which already carries it.

### What would change this

Any one of these reopens it, and none of them needs a new ADR — this one is where
the answer goes:

1. **SMBClient gains response verification.** The pin is `exact: "0.3.1"`, so
   every bump is a reviewed diff. Grep that diff for `verif` in
   `Sources/SMBClient/Session.swift` and `Connection.swift`. This is the cheapest
   outcome by a wide margin and costs nothing to wait for.
2. **AMSMB2 bumps its libsmb2 submodule past the flag-gated check** *and* the
   project decides an LGPL-2.1 dependency is shippable on the App Store. Both
   halves, not either.
3. **Apple ships an SMB API.** iPhoneOS 26.5 has none; a later SDK might.
4. **Someone writes option E.** If it is written, it is written upstream and
   against more than one server, not vendored in a hurry.

## Consequences

- **A reader on iOS streaming from a share is not protected against an attacker
  on their own network, and the app will not tell them so.** That is the accepted
  risk, in one sentence. It is bounded by what the format layer already does with
  hostile bytes — every read bounds-checked, no length field trusted for an
  allocation ([ADR-0008](0008-ranged-reads-and-own-zip-reader.md)) — which is why
  this is a medium and not a high.
- **iOS and Android now differ in the app, deliberately.** Android's sheet shows
  `signed` or `not signed` because jcifs-ng can answer the question; the iOS sheet
  says nothing, because its client cannot and because a line reading "not signed"
  is the disclosure this decision refuses. Whether Android should keep saying it
  is a question for Android's own slice, not this one.
- **ADR-0010's choice of client stands, and is confirmed rather than merely
  untouched.** The ground was re-walked with a specific defect in hand and the
  answer came out the same.
- **`SECURITY.md` already states this correctly.** Its "Network transport" row
  says iOS signs only when the server insists and never verifies a response. An
  earlier draft of this ADR recorded that the row overstated iOS; that is no
  longer true and the note is withdrawn. Only its link was wrong — it pointed at
  `0015-ios-smb-response-signing.md`, which is not a file — and that is fixed.
- Rank 11 in
  [`docs/delivery/security-review-2026-08-30.md`](../delivery/security-review-2026-08-30.md)
  is closed as **accepted**, not as fixed.
