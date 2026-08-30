---
status: proposed
date: 2026-08-30
deciders:
---

# ADR-0013 — CB7: what it would actually cost, and three ways to answer it

## Context and problem statement

[`publication-formats`](../openspec/specs/publication-formats/spec.md) lists CB7
in its table of supported formats, and then contradicts itself at the foot of the
same file:

> CB7 depends on a 7-Zip decoder on both platforms. If a suitable
> permissively-licensed decoder is unavailable on one platform, CB7 will be listed
> as unsupported there rather than silently failing. To be resolved during the
> format-layer spike.

The spike happened. Every other row of that table is built and tested on both
platforms; this one is not, and today a `.cb7` is refused by name —
`FormatSniffer` recognises the `7z¼¯'\u{1C}` signature and
`ComicArchiveError.unsupportedContainer(.sevenZip)` says "7-Zip", which is
already better than a parse failure. The refusal is covered by a fixture
(`comics/refused.cb7`).

So the question is not "does CB7 work". It is whether to spend a new
decompression dependency on both platforms to make it work, and that is a
product decision rather than an engineering one — which is why this ADR states
the cost and leaves the choice open rather than making it.

**This supersedes one sentence of
[ADR-0005](0005-format-and-rendering-libraries.md).** That ADR recorded CB7 as
"dropped on product scope, not difficulty", and said enabling it "would be a
one-line format registration". The first half still stands. The second half was
written before libarchive was vendored, and vendoring changed the number — see
*What it actually costs* below.

## Decision drivers

- **Both platforms or neither.** [ADR-0001](0001-independent-native-cores.md)
  makes the two apps independent, and the spec set is what keeps them honest. A
  format that opens on Android and is refused on iOS is the exact failure the
  written contract exists to prevent. The spec already anticipates this and says
  a format missing on one platform is "listed as unsupported there rather than
  silently failing".
- **Attack surface is a stated cost, not a footnote.** `SECURITY.md` names
  archive parsing as the largest attack surface in the app, and
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) requires every read to be
  bounds-checked against the source length. A 7-Zip reader is a new parser for
  hostile bytes, and on iOS and Android alike it would be a parser written in C.
- **Streaming.** ADR-0008 already records CB7 as the worst case in the format
  set: solid blocks mean one page can require decompressing everything in its
  block, so `network-share` could not stream one. A CB7 on a NAS would have to be
  downloaded whole before its first page appeared.
- **How rare is rare.** CBZ and CBR are what comic archives are. CB7 exists,
  mostly from people who reflexively 7-Zip everything. Nobody has asked for it.
  This driver is the one with no measurement behind it, and it is the one that
  decides the answer.

## What it actually costs

The vendored libarchive at [`third_party/libarchive/`](../../third_party/libarchive/VENDORING.md)
ships **26 of libarchive's 132 sources**, and `archive_read_support_format_7zip.c`
is deliberately not among them. `archive_read_support_format_all()` is not
vendored either, so no parser but RAR4 and RAR5 is reachable even by accident.

Two things would have to change, and only the first is small:

1. **Vendor the 7-Zip reader and register it.** One source file, one
   `archive_read_support_format_7zip()` call, one branch in
   `ComicArchiveOpener`, one fixture. This is the part ADR-0005 was describing.

2. **Vendor a compression library, which that ADR did not account for.**
   `config.h` in the vendored package turns *every* optional dependency off —
   "no zlib, bzip2, lzma, lz4, zstd, OpenSSL, nettle, mbedTLS, iconv or libxml2"
   — because RAR carries its own compression and libarchive's blake2 and ppmd7
   sources are vendored alongside it. 7-Zip does not carry its own: LZMA and
   LZMA2 are its default codecs and libarchive reaches them through liblzma.

   > **Unverified.** That last claim comes from reading upstream rather than from
   > compiling: this repository does not vendor the 7-Zip reader, so nobody here
   > has built it with `HAVE_LZMA_H` off and watched what it refuses. **Before
   > accepting any option below, compile the reader against the current
   > `config.h` and record what a real LZMA2 `.cb7` does.** If it refuses the
   > common case, option A costs liblzma for two iOS slices and four Android
   > ABIs, and every one of those becomes a binary to keep patched. If it does
   > not, option A is genuinely small and this ADR's recommendation should be
   > revisited.

The vendoring note is explicit that each dependency "has to be argued for",
which is what this document is.

## Considered options

1. **A 7-Zip decoder on each platform.**
2. **Refuse CB7 by name, permanently, and say so in the spec.**
3. **Convert on import: repack a CB7 as a CBZ when the file is added.**

### Option A — a 7-Zip decoder on each platform

The seam already exists. `RarComicArchive` shows the shape: parse headers
natively, hand one entry at a time to libarchive, and nothing above
`ComicArchiveReading` learns that C is involved. A `SevenZipComicArchive` would
sit beside it.

- Good, because the spec's table becomes true, and a written promise that is not
  kept is worse than one that was never made.
- Good, because it is the same library on both platforms — one vendored copy,
  two build systems, which is the arrangement already in place and already
  verified on macOS arm64 and four Android ABIs.
- Bad, because of the liblzma question above. If the answer is yes, this is not
  one file: it is a compression library across six ABIs, a second upstream to
  track for CVEs, and a measurable increase in binary size for a format nobody
  has asked for.
- Bad, because it adds a parser for hostile input to the largest attack surface
  in the app, to open files that are rare.
- Bad, because it cannot stream. A CB7 on a share would download whole, which is
  a worse experience than the refusal it replaces — and `network-share` would
  need a sentence saying so.

### Option B — refuse CB7 by name, permanently

Delete the row from the spec's table, keep `FormatSniffer` recognising the
signature, and keep the named refusal. Say in the release notes that CB7 is not
supported and that a `.cb7` is a `.cbz` away from working.

- Good, because it is already built, tested and honest. The refusal names the
  format rather than reporting a broken file, which is what
  `publication-formats` demands of an unsupported container.
- Good, because it costs nothing: no dependency, no attack surface, no binary.
- Good, because it is reversible. The vendoring note keeps the door open by
  construction, and this ADR is the record of what walking through it costs.
- Bad, because a reader with a shelf of CB7s is told no by an app that lists
  seven formats and opens six.
- Bad, because "we support the formats people actually have" is the stated
  purpose of the capability, and this is a judgement about what people have
  rather than a measurement of it.

### Option C — convert on import

On adding a `.cb7`, unpack it once and repack the pages as a CBZ in the app's
own storage, then treat the result as any other publication.

- Good, because everything downstream — streaming, ranged reads, the page
  window, the cover cache — keeps working unchanged, and the solid-block problem
  disappears after the one conversion.
- Good, because the conversion is a visible, cancellable, one-time operation
  rather than a hidden cost on every page turn.
- Bad, because it needs the same decoder as option A. It moves *when* the
  decompression happens, not whether the dependency is added, so it inherits
  every cost of A and adds work of its own.
- Bad, because it writes a second copy of the publication to the device.
  `local-library` treats a watched folder as the user's own files and does not
  duplicate them; this would be the first format that does, and a reader who
  wonders where their disk went deserves a better answer than "CB7".
- Bad, because it changes the file the library points at, which
  `reading-progress` identifies publications by. Nothing insurmountable, and
  nothing free.

## Decision Outcome

**Open. Left to the user of this repository to decide.**

The recommendation, to be accepted or overruled: **option B**, with the
verification in *What it actually costs* run first so that the decision is made
against a compiled fact rather than against a reading of upstream.

Because the cost of A is not the file, it is the second C library, the six ABIs
it has to be built for, the CVE tracking that comes with it, and a new parser on
the app's largest attack surface — all for a format that is rare, that cannot be
streamed, and that a reader can convert in one command. And explicitly **not**
option C, because it pays A's whole price and then adds a duplicate copy of every
publication and a new identity problem on top; it would only be worth
reconsidering if A were chosen and streaming turned out to matter more than disk.

If B is chosen, the follow-up is small and should happen in the same change:
delete the CB7 row from `publication-formats`' table, delete the open question,
and add a scenario stating the named refusal — which the code and
`comics/refused.cb7` already satisfy.

If A is chosen instead, the honest sequencing is: compile the reader first,
answer the liblzma question, then decide — because a "yes" there is a different
decision from a "no", and the two should not be made at once.

## Consequences

- **Positive (either way):** the capability stops carrying an open question that
  has been open since the format-layer spike, and the spec stops promising a
  format the app refuses.
- **Negative (if B):** a reader with CB7 files is told no. The refusal names the
  format, which is the most that can be done without the decoder.
- **Negative (if A):** a second vendored C library, six more ABIs to build and
  patch, a larger attack surface, and a format that downloads whole from a share.
- **Neutral:** nothing above `ComicArchiveReading` changes under any option. The
  seam ADR-0008 put there is what makes this a contained decision rather than an
  architectural one.

## Links

- Spec: [`publication-formats`](../openspec/specs/publication-formats/spec.md) —
  the *Supported formats* table and the *Open Questions* section.
- Related decisions: supersedes the "one-line format registration" sentence in
  [ADR-0005](0005-format-and-rendering-libraries.md); relates to
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) (why CB7 cannot stream) and
  [ADR-0001](0001-independent-native-cores.md) (why it is both platforms or
  neither).
- Vendoring: [`third_party/libarchive/VENDORING.md`](../../third_party/libarchive/VENDORING.md)
  — the file list, and the rule that every optional dependency has to be argued for.
