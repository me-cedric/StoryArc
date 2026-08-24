# Third-Party Notices

StoryArc bundles the third-party components below. Each entry records what it is
used for, its licence, and where the licence text lives.

`publication-formats` and `ebook-reader` both require every bundled dependency
and font family to appear here — a licence nobody wrote down is a licence nobody
checked.

## iOS

### ZIPFoundation — 0.9.20

- **Used for:** reading CBZ archives, and the ZIP container inside EPUB.
- **Licence:** MIT.
- **Source:** <https://github.com/weichsel/ZIPFoundation>
- **Why a dependency:** Apple platforms ship no ZIP container reader. Android
  gets `java.util.zip` from its standard library and needs nothing.
  ([ADR-0005](docs/decisions/0005-format-and-rendering-libraries.md))

```
MIT License

Copyright (c) 2017-2026 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Android

Nothing yet beyond AndroidX and Jetpack Compose, which ship under Apache-2.0 as
part of the platform's own library set. ZIP reading uses `java.util.zip` from the
standard library.

`kotlinx-serialization-json` (Apache-2.0) is a **test-only** dependency of
`:core:format`, used to read the shared fixture manifest.

## Not yet bundled, and why it matters

| Component | Status |
| --- | --- |
| **RAR decoder** (CBR) | **Blocked on a licence review.** Every practical RAR decoder derives from the reference UnRAR source, whose licence is not a standard OSI licence. Reviewed and recorded here before any CBR code ships; if it is incompatible with distributing StoryArc under MIT, CBR becomes an optional component rather than a quiet licence violation. |
| **Readium** (EPUB) | BSD-3-Clause on both platforms. Lands with the EPUB reader. |
| **Reading fonts** | Literata, Source Serif 4, EB Garamond, Bitter, Atkinson Hyperlegible — all OFL. Land with the theming work. |
| **SMB client** | Licence to confirm during the connector spike. |

## Fixture corpus

`packages/test-fixtures` contains **no third-party content.** Every page is a
procedurally generated PNG produced by `scripts/generate.py`; there is no real
artwork anywhere in this repository.
