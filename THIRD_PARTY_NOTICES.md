# Third-party notices

Everything StoryArc ships that someone else wrote. Generated from
[`packages/licences/notices.json`](packages/licences/notices.json), which is the source
of truth — edit that and regenerate rather than editing this file.

Both apps stage the same inventory and show it in Settings › About ›
Acknowledgements, because BSD and Apache require the notice to travel with the binary
and the SIL Open Font Licence requires its text to accompany the fonts.

<!-- generated:notices -->
| Component | Licence | Platform | Copyright | Why it is in the app |
| --- | --- | --- | --- | --- |
| [Readium Swift Toolkit 3.11](https://github.com/readium/swift-toolkit) | `BSD-3-Clause` | iOS | Copyright (c) 2017, Readium | Reflowable EPUB rendering. ADR-0005. |
| [Readium Kotlin Toolkit 3.3](https://github.com/readium/kotlin-toolkit) | `BSD-3-Clause` | Android | Copyright (c) 2017, Readium | Reflowable EPUB rendering. ADR-0005. |
| [libarchive 3.8.9](https://github.com/libarchive/libarchive) | `BSD-2-Clause` | iOS, Android | The libarchive distribution as a whole is Copyright by Tim Kientzle | Decompressing RAR entries. 26 of 132 sources vendored; see third_party/libarchive/VENDORING.md. |
| [AndroidX and Jetpack Compose](https://developer.android.com/jetpack/androidx) | `Apache-2.0` | Android | Copyright (C) The Android Open Source Project | The UI toolkit, lifecycle, Room and the activity host. |
| [Kotlin and kotlinx](https://github.com/JetBrains/kotlin) | `Apache-2.0` | Android | Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors. | The language, coroutines and serialization. |
| [Literata](https://fonts.google.com/specimen/Literata) | `OFL-1.1` | iOS, Android | Copyright 2017 The Literata Project Authors (https://github.com/googlefonts/literata) | A bundled reading typeface. Designed for screen reading. |
| [Source Serif 4](https://fonts.google.com/specimen/Source+Serif+4) | `OFL-1.1` | iOS, Android | Copyright 2014 The Source Serif 4 Project Authors (https://github.com/adobe-fonts/source-serif) | A bundled reading typeface. |
| [EB Garamond](https://fonts.google.com/specimen/EB+Garamond) | `OFL-1.1` | iOS, Android | Copyright 2017 The EB Garamond Project Authors (https://github.com/octaviopardo/EBGaramond12) | A bundled reading typeface. |
| [Bitter](https://fonts.google.com/specimen/Bitter) | `OFL-1.1` | iOS, Android | Copyright 2011 The Bitter Project Authors (https://github.com/solmatas/BitterPro) | A bundled reading typeface. |
| [Atkinson Hyperlegible](https://fonts.google.com/specimen/Atkinson+Hyperlegible) | `OFL-1.1` | iOS, Android | Copyright 2020 Braille Institute of America, Inc. | A bundled reading typeface, designed for low vision. |
<!-- /generated:notices -->

Licence texts are in [`packages/licences/texts`](packages/licences/texts), taken from
[SPDX's own list](https://github.com/spdx/license-list-data) rather than transcribed.

## Not covered

Platform SDKs. Apple's frameworks and the Android platform are not redistributed by
this app and carry their own terms with the operating system.

## libarchive, specifically

libarchive's own `COPYING` warns that "some files have different licensing terms", so
the audit is per file rather than per project: **every one of the 26 vendored sources
is BSD-2-Clause**, and none of the three RAR readers references the UnRAR licence —
which is the whole reason libarchive was chosen over UnrarKit, Unrar.swift or junrar.
See [ADR-0005](docs/decisions/0005-format-and-rendering-libraries.md) and
[`third_party/libarchive/VENDORING.md`](third_party/libarchive/VENDORING.md).

Re-check the per-file headers on every refresh. Upstream has changed them before.

The vendored version, the tarball digest, the key the release was signed with and a
digest over every copied source are in
[`third_party/libarchive/pin.json`](third_party/libarchive/pin.json), and
`pnpm libarchive:pin` fails when any of the places that state a version disagree. Nothing
else would notice: copied sources have no package manifest, so this table said 3.7.7
while the tree was at 3.8.1.
