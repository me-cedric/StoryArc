# ADR-0008 — Ranged reads over a random-access source, with our own ZIP reader

- **Status:** Accepted
- **Date:** 2026-08-24
- **Deciders:** Cédric Meyer
- **Supersedes:** the ZIP rows of [ADR-0005](0005-format-and-rendering-libraries.md)

## Context

[`network-share`](../../openspec/specs/network-share/spec.md) requires the first
page of a 400 MB archive on an SMB share to render *without transferring
400 MB*. When the ZIP layer was first built, both platforms used a library that
wants a local file — `ZIPFoundation` on iOS, `java.util.zip.ZipFile` on Android —
and ADR-0005 recorded, honestly, that neither does ranged reads and that the
requirement was unmet.

The fix turns out to be cheap, because of how ZIP is shaped:

- The **central directory** — the index of every entry, with its offset and
  compressed size — sits at the **end** of the file, located via the
  End of Central Directory record and its `0x06054B50` signature.
- Every entry is compressed **independently**. There is no solid block.

So reading one page out of an arbitrarily large archive is three ranged reads:
the last ~64 KB to find and usually also contain the central directory, the
central directory itself if it did not fit, and the entry's own bytes. For a
400 MB comic with 45 pages that is **about 9 MB to first page**, and often two
requests rather than three.

SMB2's `READ` takes an offset and a length as a first-class operation. HTTP has
`Range`. Every source type StoryArc targets supports this natively — the missing
piece was never the transport.

## Decision

### A `RandomAccessSource` abstraction

One interface, three implementations, on both platforms:

```
length: Int64
read(offset: Int64, count: Int) -> Bytes
```

| Implementation | Backed by |
| --- | --- |
| Local file | a seeking file handle |
| Network share | an SMB2 `READ` at offset |
| HTTP | a `Range` request |

Everything above this line — the ZIP reader, the page decoder, the reader UI —
is unaware of where the bytes came from. That is the point: streaming stops
being a special case.

### Our own ZIP reader, replacing both libraries — everywhere

Not only for remote sources. **`ZIPFoundation` is removed from the iOS app and
`java.util.zip.ZipFile` is no longer used on Android.**

Two code paths — a library for local files and our reader for remote ones —
would mean the fixture corpus exercises one implementation while users hit the
other, on a layer that has already produced one silent cross-platform
divergence (the digit-run overflow in natural sort). One path, tested once, is
worth more than two paths where one is battle-tested.

It also removes an asymmetry: iOS needed a dependency because Apple ships no ZIP
container reader; Android did not. Now both platforms are the same hand-written
reader over the same abstraction, which is what makes a shared corpus meaningful.

**We are only parsing the container, not implementing compression.** Inflate
comes from the platform — `Compression` on Apple, `java.util.zip.Inflater` on
Android. The ZIP container format is stable, documented, and about 350 lines to
read correctly including Zip64.

### What we now own, and how it is covered

| Edge case | Covered by |
| --- | --- |
| Zip64 (archives or entries over 4 GB, or over 65,535 entries) | corpus fixture |
| Data descriptors (sizes written *after* the data, so the local header lies) | corpus fixture — the central directory is authoritative, always |
| `STORED` entries (no compression) | corpus fixture |
| Archive comment pushing the EOCD away from the tail | corpus fixture |
| Encrypted entries | detected from the general-purpose bit flag and refused per `publication-formats`, which forbids prompting for archive passwords |

The rule that makes most of these harmless: **the central directory is the only
authority.** Local headers are read for their extra fields and never trusted for
sizes.

## Streaming behaviour that sits on top

Specified in the `streaming-reads-and-prefetch` change, implemented when the
remote connectors land:

- **Adaptive prefetch** — the window is sized from measured throughput and page
  size, not from a page count a user has to guess at. A coarse
  Minimal / Balanced / Aggressive control expresses intent, and a metered
  connection forces Minimal.
- **Sparse cache** — fetched byte ranges are kept, so a page read once never
  refetches.
- **Background fill** — the remainder is fetched sequentially at low priority, so
  a comic you finish reading is simply local, without anyone having waited for a
  download. Counted against the **cache** budget, so it stays evictable and
  visible in the storage screen.

## Where ranged reads do not save you

Worth writing down, because it has a product consequence rather than being a
mere caveat.

| Format | Ranged reads | Why |
| --- | --- | --- |
| **CBZ**, **EPUB** | Excellent | Index at end, entries independent |
| **PDF** | Excellent | `xref` at end; byte-serving is what linearized PDF exists for |
| **CBT** (TAR) | Workable | No index at all, but headers can be hopped while skipping data — N small reads build one, then access is direct |
| **CB7** (7-Zip) | Usually not | Solid blocks: one page can require decompressing everything in its block |
| **CBR** (RAR) | Only if non-solid | **Solid RAR requires every file before the target.** Streaming is not possible |

For solid RAR and 7-Zip, *download first* is the honest answer, and the app must
say so rather than stream badly. That behaviour is specified rather than left to
be discovered on someone's NAS.

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Library for local, our reader for remote** | Two behaviours, one tested. The divergence shape that natural sort already demonstrated. |
| **Download the whole file first** | Simple and reliable, and it fails the `network-share` requirement outright — minutes of waiting before page one on a slow link. |
| **Patch ranged reads into ZIPFoundation** | Upstream work on someone else's schedule, and it fixes only one of the two platforms. |
| **A shared C library via FFI** (libzip, minizip) | Two FFI boundaries to buy a container parser we can write in 350 lines, and it re-opens the question [ADR-0001](0001-independent-native-cores.md) closed. |

## Consequences

**Gained**

- The `network-share` streaming requirement becomes achievable rather than
  aspirational: ~9 MB to first page instead of 400 MB.
- iOS loses a third-party dependency. Both platforms become symmetric.
- Prefetch depth is ours to control, which is a prerequisite for tuning it.
- The same abstraction serves OPDS and Kavita over HTTP with no new work.

**Accepted costs**

- ~350 lines per platform that we maintain, plus the Zip64 and data-descriptor
  edge cases. The corpus is the mitigation, and the fixtures for them land with
  the reader rather than after it.
- A hand-written parser on untrusted input is a security surface.
  [SECURITY.md](../../SECURITY.md) already names archive parsing as the largest
  one in the app; every read is bounds-checked against the source length, and no
  length field from the file is trusted to allocate.

## Revisit when

- A platform ships a ranged-read-capable ZIP container reader in its standard
  library, which would make this code deletable.
- The corpus catches a container bug our reader gets wrong that a library would
  have got right — which would be evidence the trade was misjudged.
