# Third-Party Notices

StoryArc bundles the third-party components below. Each entry records what it is
used for, its licence, and where the licence text lives.

`publication-formats` and `ebook-reader` both require every bundled dependency
and font family to appear here — a licence nobody wrote down is a licence nobody
checked.

## iOS

**No third-party dependencies.**

ZIPFoundation was briefly used for CBZ reading and was removed by
[ADR-0008](docs/decisions/0008-ranged-reads-and-own-zip-reader.md), which
replaced it with StoryArc's own ranged-read ZIP container reader. Inflate comes
from the system `Compression` framework.

## Android

Nothing beyond AndroidX and Jetpack Compose, which ship under Apache-2.0 as part
of the platform's own library set. ZIP container parsing is StoryArc's own code
per [ADR-0008](docs/decisions/0008-ranged-reads-and-own-zip-reader.md); inflate
comes from `java.util.zip.Inflater` in the standard library.

Test-only dependencies of `:core:format`, not shipped: `kotlinx-serialization-json`
and `kotlinx-coroutines-test`, both Apache-2.0.

## Not yet bundled, and why it matters

| Component | Status |
| --- | --- |
| **libarchive** (CBR, CBT) | **Chosen, not yet integrated.** BSD-2-Clause, with its own RAR4 and RAR5 readers rather than UnRAR-derived code. Its exact licence text is recorded here before any CBR ships. Every format reader except RAR and TAR — 7-Zip included — is compiled out. Note it parses untrusted input in C; see [SECURITY.md](SECURITY.md). |
| **Readium** (EPUB) | BSD-3-Clause on both platforms. Lands with the EPUB reader. |
| **Reading fonts** | Literata, Source Serif 4, EB Garamond, Bitter, Atkinson Hyperlegible — all OFL. Land with the theming work. |
| **UnRAR-derived decoders** | **Rejected**, not deferred. UnrarKit, Unrar.swift and junrar all carry the reference UnRAR licence, which is not OSI-approved and would sit inside an otherwise-MIT repository. libarchive exists precisely so this is unnecessary. |
| **SMB client** | Licence to confirm during the connector spike. |

## Fixture corpus

`packages/test-fixtures` contains **no third-party content.** Every page is a
procedurally generated PNG produced by `scripts/generate.py`; there is no real
artwork anywhere in this repository.
