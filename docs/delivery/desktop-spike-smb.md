# Desktop SMB: `smb` against `smb2`, run against Samba

**Task 3.1 of `desktop-clients`. Run on 2026-10-17 on the lead's Mac (Apple silicon, Rust 1.99.0)
against Samba 4.24.7 in Docker. Winner: `smb` 0.12.1.** Confidence labels follow ADR-0005; every
row marked **Proven** below was run, and the command that ran it is at the end.

The question, from [`design.md`](../openspec/changes/desktop-clients/design.md) Decision 7: which
pure-Rust SMB client sits behind `RandomAccessSource` on Windows and Linux. The exit the task set:
the negotiated dialect and the encryption state are reported, and a server that speaks only SMB 1
is refused with a named remedy.

## The fixture

`scripts/smb-server.sh` (what `pnpm smb` runs) needs Homebrew's `samba-dot-org-smbd`, which this
Mac does not have, so the spike ran the script's own `smb.conf` inside a Fedora container with the
distribution's Samba: `security = user`, signing mandatory, SMB 2.0.2 to 3.1.1, a read-only
`Comics` share over the corpus `node scripts/corpus.mjs` writes, one account with the password
`lovelace`. Three containers, one per mode:

| Mode | Port in this run | The script's port | Difference from the plain server |
| --- | --- | --- | --- |
| Plain | 4545 | 4445 | none |
| Encryption required | 4546 | 4446 | `smb encrypt = required` |
| SMB 1 only | 4550 | none | `server min protocol = NT1`, `server max protocol = NT1`, signing `auto` |

The run used ports a hundred above the script's because two containers on 4445 and 4446 hung and
could not be killed: **the corpus was bind-mounted, and smbd reading a Docker Desktop bind mount
blocked in uninterruptible IO** once a client listed the share. The containers that ran the table
below have the corpus copied into the image instead. The core's SMB tests read their port from
`STORYARC_SMB_PORT` and `STORYARC_SMB_ENCRYPTED_PORT` (defaults 4445 and 4446, the fixture table of
`AGENTS.md` section 7), so they run against either server.

Not run: a Windows share and a NAS with encryption required. Nobody had either on the network on
the day. Both stay owed to the conformance walks of tasks 3.20 and 3.24.

## What each crate did

| Case | `smb` 0.12.1 | `smb2` 0.31.0 |
| --- | --- | --- |
| Plain server, read four bytes of a CBZ | **Proven.** SMB 3.1.1, AES-128-GCM negotiated, `PK\3\4` read, 20 ms | **Proven.** SMB 3.1.1, no cipher negotiated, read, 10 ms |
| Encryption required | **Proven.** Connects, reads; the session seals every message | **Proven to fail.** `STATUS_ACCESS_DENIED` during session setup: the crate offers no way to ask for encryption, so a share that demands it cannot be read at all |
| Encryption asked for by the client on a plain SMB 3 server | **Proven.** `EncryptionMode::Required` connects and reads, so the app can negotiate encryption whenever the server supports it, as `network-share` asks | Not offered |
| Encryption asked for on a server that cannot give it | **Proven.** Refused before any file opens: "Encryption is required by the connection config, but is not available" | Not offered |
| SMB 1 only | Fails to parse the reply (`bad magic [ff 53 4d 42]`, the SMB 1 signature) | `ConnectionLost`, "Disconnected from server" |
| Wrong password | `0xC000006D` (`STATUS_LOGON_FAILURE`) | `AuthRequired`, `STATUS_LOGON_FAILURE` |
| Missing share | `0xC00000CC` (`STATUS_BAD_NETWORK_NAME`) | `NotFound`, `STATUS_BAD_NETWORK_NAME` |
| Nothing listening | `ConnectionRefused` | `ConnectionLost` |
| Silent server (container paused) | **Proven.** The read fails at the connection's own timeout (2.00 s with `timeout` set to 2 s); after the pause ends the same handle reads again in 2 ms, and a fresh session takes 23 ms | Not measured |

Neither crate classifies SMB 1, and neither can: both refuse to speak it. The core therefore sends
its own probe after a failed handshake, as design.md Decision 7 planned: one SMB 1 `NEGOTIATE`
offering only `NT LM 0.12`. **Proven** against the three servers: the SMB 1 server answers with
word count 17 and dialect index 0, both SMB 2 servers answer with word count 1 and dialect index
`0xFFFF` (no dialect in common). Only the first is "SMB 1 only", so a server that merely failed for
another reason is not misnamed.

Neither crate reports per-share encryption through its public API in a way the source can use:
`smb` keeps the tree-connect flags private, and `smb2` reports them but cannot meet them. So the
source states encryption the way the measurement above allows: it asks for encryption first, and
a session that connected with encryption required **is** encrypted. A server that cannot encrypt
is reconnected with encryption allowed and reported as not encrypted.

## Why `smb` wins

1. **It reads a share that requires encryption, and `smb2` cannot.** That is a `network-share`
   scenario (*Encrypted transport*) and a `desktop-experience` one (*Encryption*: "on a desktop
   whose SMB client supports encryption, which is Windows and Linux, the app negotiates it where
   the server requires it"). It decides the question by itself.
2. Its connection timeout bounds a silent read, which the two-second indicator and the
   sixty-second offer of `network-share` are built on, and a paused server's session survives.
3. It is MIT, and its tree (323 crates with `smb2` beside it) holds no GPL or LGPL crate; `r-efi`
   is offered under MIT or Apache-2.0 as well as LGPL and is a UEFI-only dependency.

`smb2` stays the swap-in that design.md names. It is faster on bulk reads by its own account
(pipelined), which matters for downloads rather than for a page, and it would win if it gained an
encryption switch. The trait keeps the swap a one-file change.

Version note: design.md pinned `smb2` 0.27.x; 0.31.0 was current on the day and is what ran.
`smb` 0.12.1 is the version design.md and Open Question 5 named.

## Reproduce

```bash
# One image, the corpus copied in (scripts/smb-server.sh's smb.conf, Fedora's Samba)
docker build -t storyarc-samba:corpus <dir with Dockerfile, entry.sh and corpus/>
docker run -d --rm -p 4545:4545 storyarc-samba:corpus plain 4545
docker run -d --rm -p 4546:4546 storyarc-samba:corpus encrypted 4546
docker run -d --rm -p 4550:4550 storyarc-samba:corpus smb1 4550
STORYARC_SMB_PORT=4545 STORYARC_SMB_ENCRYPTED_PORT=4546 STORYARC_SMB_USER=reader \
  cargo test -p storyarc-core --test smb
```

The comparison program itself was a scratch binary depending on both crates; it is not kept,
because the core depends on one of them and the table above is its output.
