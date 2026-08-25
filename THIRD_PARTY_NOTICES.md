# Third-party notices

Everything StoryArc ships that someone else wrote. Generated from
[`packages/licences/notices.json`](packages/licences/notices.json), which is the source
of truth — edit that and regenerate rather than editing this file.

Both apps stage the same inventory and show it in Settings › About ›
Acknowledgements, because BSD and Apache require the notice to travel with the binary
and the SIL Open Font Licence requires its text to accompany the fonts.

| Component | Licence | Platform | Why it is in the app |
| --- | --- | --- | --- |
| [Readium Swift Toolkit 3.11](https://github.com/readium/swift-toolkit) | `BSD-3-Clause` | iOS | Reflowable EPUB rendering. ADR-0005. |
| [Readium Kotlin Toolkit 3.3](https://github.com/readium/kotlin-toolkit) | `BSD-3-Clause` | Android | Reflowable EPUB rendering. ADR-0005. |
| [libarchive 3.7.7](https://github.com/libarchive/libarchive) | `BSD-2-Clause` | iOS, Android | Decompressing RAR entries. 26 of 132 sources vendored; see third_party/libarchive/VENDORING.md. |
| [AndroidX and Jetpack Compose](https://developer.android.com/jetpack/androidx) | `Apache-2.0` | Android | The UI toolkit, lifecycle, Room and the activity host. |
| [Kotlin and kotlinx](https://github.com/JetBrains/kotlin) | `Apache-2.0` | Android | The language, coroutines and serialization. |
| [Literata](https://fonts.google.com/specimen/Literata) | `OFL-1.1` | iOS, Android | A bundled reading typeface. Designed for screen reading. |
| [Source Serif 4](https://fonts.google.com/specimen/Source+Serif+4) | `OFL-1.1` | iOS, Android | A bundled reading typeface. |
| [EB Garamond](https://fonts.google.com/specimen/EB+Garamond) | `OFL-1.1` | iOS, Android | A bundled reading typeface. |
| [Bitter](https://fonts.google.com/specimen/Bitter) | `OFL-1.1` | iOS, Android | A bundled reading typeface. |
| [Atkinson Hyperlegible](https://fonts.google.com/specimen/Atkinson+Hyperlegible) | `OFL-1.1` | iOS, Android | A bundled reading typeface, designed for low vision. |

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
