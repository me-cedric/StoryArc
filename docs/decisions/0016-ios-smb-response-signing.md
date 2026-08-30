---
status: proposed
date: 2026-08-30
deciders:
---

# ADR-0016 — iOS SMB: an unsigned, unverified session, and four ways to stop lying about it

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
  untouched otherwise. Grepping the whole `Sources/SMBClient` tree for `verify`
  finds nothing: **no code path checks the signature on a response**, whether or
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
- [ADR-0001](0001-independent-native-cores.md) accepts two clients and two sets
  of bugs. It does not accept the two platforms making different promises to the
  reader without saying so.
- `network-share` already reserves the space: the source detail screen states
  what the connection turned out to be. Adding an honest line there costs one
  string, not a redesign.
- A reader who cannot see the difference cannot act on it. Someone reading from a
  NAS on their own home network is in a different position from someone on a
  shared office or hotel network, and only they know which.

## Considered options

### A — Say so, on the connection sheet and in `SECURITY.md`

Mirror Android's line: report `not signed` beside the existing `not encrypted`,
in the same string shape and the same four languages, and add a row to
`SECURITY.md` saying SMB integrity is not verified on iOS.

- **Good.** Honest today, costs one string pair per language, and closes the
  cross-platform asymmetry as a *disclosure* even though the capability gap
  stays.
- **Good.** It is the prerequisite for every other option: whichever fix lands
  later, the screen still has to say what this connection got.
- **Bad.** It does not stop the attack. It moves the decision to the reader, who
  can choose not to add a share on a network they do not trust.
- **Bad.** "not signed" is a phrase most readers cannot act on without a
  sentence explaining it, and the sheet is not a place for a paragraph.

### B — Fix it upstream

Open a pull request against SMBClient: verify the signature on every response
when the session is signed, and refuse a session whose negotiated security mode
was downgraded from what was requested.

- **Good.** Fixes it for everyone, and the library is MIT and small — the change
  is confined to `Session.swift`, where the signing key and `Crypto.hmacSHA256`
  already are.
- **Bad.** Unbounded schedule. StoryArc would have to pin a fork or vendor the
  patch to ship before upstream merges, and `Package.resolved` currently tracks a
  floating `from: "0.3.1"` — which the review's rank 13 already flags as its own
  problem.
- **Bad.** Verification alone is not sufficient while the server picks whether to
  sign at all; the same change has to make the client demand signing, which is a
  behaviour change for every user of the library and a harder sell upstream.

### C — Swap the client

Look again at what exists for Swift: a client that signs, verifies and speaks SMB
3.1.1 would close encryption (ADR-0010's open consequence) and integrity in one
move.

- **Good.** Would resolve two recorded gaps at once.
- **Bad.** ADR-0010 surveyed this ground and found one viable permissive Swift
  client. The realistic alternative is an FFI to libsmb2, which that ADR rejected
  on LGPL-2.1 static-linking grounds — a rejection nothing here disturbs.
- **Bad.** Re-doing the seam is a large change against a `RandomAccessSource`
  boundary that currently works, for a threat that requires an attacker on the
  reader's own network.

### D — Demand signing from the app and hope

Bypass `SMBClient.login` and drive `session.negotiate(securityMode:dialects:)`
directly — both are public — passing `[.signingEnabled, .signingRequired]`.

- **Bad, and worth writing down so it is not proposed as a quick win.** It makes
  the client sign its *requests*. Responses are still never verified, so the
  attack — rewriting what comes back — is untouched. It would produce a screen
  that could truthfully say "signed" while offering no more integrity than
  before, which is worse than saying nothing.

## Recommendation, not a decision

**A now, B next, C only if B stalls.**

Option A is the only one that can land in this security pass, it is a
prerequisite for the others, and it is what the spec already has room for. It has
deliberately **not** been implemented in the change that carries this ADR: the
Android half of rank 16 was a configuration fix with a regression test, whereas
the iOS half is a new user-facing string in four languages whose wording depends
on which of these options is chosen — "not signed" reads differently beside a
roadmap item than beside a permanent limitation.

Option B is the only one that makes the reader safer rather than better informed,
and it is small enough to be worth attempting: one file, one HMAC comparison, and
a downgrade check next to a key that is already derived.

Option C stays on the table only as an escape from B.

## Consequences

- **Until A lands, iOS and Android say different things about the same
  connection**, and only the Android one is complete: `SmbIdentity` there carries
  `isSigned` and the sheet shows it; the iOS `SmbIdentity` has no such field.
  This is a mirror the project has broken knowingly, and this ADR is where it is
  recorded.
- **`SECURITY.md`'s "Network transport" row overstates iOS.** It says SMB 1 is
  refused and SMB 3 encryption is negotiated where offered; it says nothing about
  integrity, and on iOS there is none. Amending that row is part of Option A.
- Rank 11 stays open in
  [`docs/delivery/security-review-2026-08-30.md`](../delivery/security-review-2026-08-30.md)
  and is marked as needing this decision.
- Nothing here changes ADR-0010's choice of client. If Option C is ever taken,
  that is the ADR to supersede, not this one.
