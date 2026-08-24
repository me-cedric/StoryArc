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

## libarchive — per-file licence audit

libarchive's own `COPYING` warns that "some files have different licensing
terms… widely varying licensing terms. Please check individual files before
distributing them" — which is why GitHub reports the project as `NOASSERTION`
rather than a single SPDX identifier. A project-level answer would not have been
good enough, so the three files StoryArc actually depends on were read directly.

| File | Copyright | Licence | UnRAR-derived? |
| --- | --- | --- | --- |
| `archive_read_support_format_rar.c` | Tim Kientzle (2003–2007), Andres Mejia (2011) | BSD-2-Clause | **No** — no reference in the file |
| `archive_read_support_format_rar5.c` | Grzegorz Antoniak (2018) | BSD-2-Clause | **No** — an independent implementation |
| `archive_read_support_format_tar.c` | Tim Kientzle, Michihiro NAKAJIMA, Martin Matuska | BSD-2-Clause | n/a |

This is the whole reason libarchive was chosen over UnrarKit, Unrar.swift or
junrar: those all carry the reference UnRAR licence, which is not OSI-approved
and would sit inside an otherwise-MIT repository.

```
Copyright (c) 2003-2018 <author(s)>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer
   in this position and unchanged.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## AMSMB2 — LGPL, and the obligation it carries

`AMSMB2` wraps `libsmb2` for SMB on iOS, and both are **LGPL-2.1**. It is chosen
because the only MIT alternative, `SMBClient`, speaks SMB 2.0 only and cannot
read a file at an arbitrary offset — which ADR-0008's whole architecture depends
on.

**StoryArc must link it dynamically**, as an embedded framework. AMSMB2's own
README states this requirement for App Store distribution, and there is
precedent: VLC moved from GPL to LGPL specifically to make App Store
distribution possible. A build that silently static-links would be a licence
violation, so the iOS build gets a check for it rather than a comment.

Android uses `smbj` (Apache-2.0) instead, which needs none of this — see
[ADR-0005](docs/decisions/0005-format-and-rendering-libraries.md) for why the
two platforms differ here rather than being forced to match.

## Not yet bundled, and why it matters

| Component | Status |
| --- | --- |
| **libarchive 3.8.1** (CBR, CBT) | **Verified, not yet integrated.** See the section below for the per-file licence audit. Unused readers are dropped by the linker, not by build config. Parses untrusted input in C; see [SECURITY.md](SECURITY.md). |
| **Readium** (EPUB) | BSD-3-Clause on both platforms. Lands with the EPUB reader. |
| **Reading fonts** | Literata, Source Serif 4, EB Garamond, Bitter, Atkinson Hyperlegible — all OFL. Land with the theming work. |
| **UnRAR-derived decoders** | **Rejected**, not deferred. UnrarKit, Unrar.swift and junrar all carry the reference UnRAR licence, which is not OSI-approved and would sit inside an otherwise-MIT repository. libarchive exists precisely so this is unnecessary. |
| **AMSMB2** (iOS SMB) | Chosen. LGPL-2.1, **must be dynamically linked** — see above. |
| **smbj** (Android SMB) | Chosen. Apache-2.0, no obligations beyond attribution. |

## Fixture corpus

`packages/test-fixtures` contains **no third-party content.** Every page is a
procedurally generated PNG produced by `scripts/generate.py`; there is no real
artwork anywhere in this repository.
