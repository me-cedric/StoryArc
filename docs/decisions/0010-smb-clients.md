---
status: accepted
date: 2026-08-28
deciders: Cédric Meyer
---

# ADR-0010 — An SMB2 client per platform, both pure and permissively licensed

## Context and problem statement

[`network-share`](../openspec/specs/network-share/spec.md) requires StoryArc to
read from SMB 2 and SMB 3 shares: connect, browse a directory tree, list a
folder, and read *part* of a file.

The last of those is already designed.
[ADR-0008](0008-ranged-reads-and-own-zip-reader.md) put a `RandomAccessSource`
under the ZIP reader precisely so that a share could supply one, and named
"an SMB2 `READ` at offset" as its intended backing. Nothing above that line
needs to change. What is missing is a client that speaks the protocol.

Neither platform ships one. `URLSession` does not speak SMB, and Android has no
SMB API at all. This has to come from somewhere.

## Considered options

| Option | Why not |
| --- | --- |
| **Write SMB2 on both platforms** | NEGOTIATE, SESSION_SETUP with NTLMv2, TREE_CONNECT, CREATE, READ, QUERY_DIRECTORY, signing, and SMB 3 encryption — twice. Weeks, and every hour of it spent on a protocol two mature clients already implement. [ADR-0001](0001-independent-native-cores.md) asks for independent native cores, not for re-implementing transports. |
| **libsmb2 through an FFI on both** | One C library, two FFI boundaries, and LGPL-2.1: static linking into an App Store binary is exactly the case that licence makes contentious. Not a fight worth having for a file reader. |
| **SMB on Android, nothing on iOS** | Ships a capability on one platform. The whole point of the spec set is that both platforms answer the same promises. |
| **A permissive client per platform** | **Chosen.** |

## Decision Outcome

| Platform | Client | Licence | Why |
| --- | --- | --- | --- |
| Android | [jcifs-ng](https://github.com/AgNO3/jcifs-ng) | Apache-2.0 | SMB 2/3, the standard JVM choice, and `SmbRandomAccessFile` is a ranged read already. |
| iOS | [SMBClient](https://github.com/kishikawakatsumi/SMBClient) | MIT | Pure Swift, no C dependency, no FFI boundary, and `read(offset:length:)` on a file handle. |

Two clients rather than one shared core is the same trade ADR-0001 already made
for everything else in this app: a native library on each platform, and one
vocabulary above it. The seam is a small module per platform — `core:smb` and
`Smb` — that turns the client's types into the app's own, so that nothing above
the seam knows which library is underneath.

### Consequences

- **Good.** `RandomAccessSource` gains its third implementation, and the ZIP
  reader, the page decoder and the reader learn nothing new.
- **Good.** Both licences permit static linking into a closed binary.
- **Bad.** Two clients means two sets of bugs and two upgrade schedules. The
  seam limits the blast radius; it does not remove it.
- **Bad.** SMB 3 encryption support differs between the two, so the source
  detail screen has to report what *this* connection negotiated rather than what
  the app supports in general — which the spec asks for anyway.

### Verification

`scripts/smb-server.py` runs a real SMB2 server over the fixture corpus, so the
client work is driven against a server rather than a stub. It is the same shape
as `scripts/opds-server.mjs` and `scripts/kavita-server.mjs`, for the same
reason: a capability nobody can re-run is a capability nobody can trust.
