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
| [CryptoSwift 1.10.0](https://github.com/krzyzanowskim/CryptoSwift) | `Attribution` | iOS | Copyright (C) 2014-3099 Marcin Krzyżanowski <marcin.krzyzanowski@gmail.com> | Decryption inside the Readium streamer. ADR-0005. |
| [DifferenceKit 1.3.0](https://github.com/ra1028/DifferenceKit) | `Apache-2.0` | iOS | Copyright (c) ra1028 (https://github.com/ra1028) | Collection diffing inside the Readium navigator. ADR-0005. |
| [Fuzi 4.0.1](https://github.com/readium/Fuzi) | `MIT` | iOS | Copyright (c) 2015 Ce Zheng | XML parsing inside the Readium toolkit. ADR-0005. |
| [GCDWebServer 4.0.1](https://github.com/readium/GCDWebServer) | `BSD-3-Clause` | iOS | Copyright (c) 2012-2014, Pierre-Olivier Latour | Pinned with the Readium toolkit; its adapter target is not linked. ADR-0005. |
| [SQLite.swift 0.16.0](https://github.com/stephencelis/SQLite.swift) | `MIT` | iOS | Copyright (c) 2014-2015 Stephen Celis (<stephen@stephencelis.com>) | Pinned with the Readium toolkit; its LCP adapter target is not linked. ADR-0005. |
| [SwiftSoup 2.13.9](https://github.com/scinfu/SwiftSoup) | `MIT` | iOS | Copyright (c) 2009-2025 Jonathan Hedley <https://jsoup.org/>
Copyright (c) 2016-2025 Nabil Chatbi (Swift port) | HTML parsing inside the Readium toolkit. ADR-0005. |
| [Zip 2.1.2](https://github.com/marmelroy/Zip) | `MIT` | iOS | Copyright (c) 2015 Roy Marmelstein | Its Minizip module reads EPUB entries inside Readium. Zip.unzipFile is never called; see ADR-0014. |
| [ZIPFoundation 3.0.1](https://github.com/readium/ZIPFoundation) | `MIT` | iOS | Copyright (c) 2017-2024 Thomas Zoechling (https://www.peakstep.com) | ZIP reading inside the Readium toolkit. ADR-0005. |
| [SMBClient 0.3.1](https://github.com/kishikawakatsumi/SMBClient) | `MIT` | iOS | Copyright (c) 2024 Kishikawa Katsumi | SMB 2/3, which iOS has no API for. ADR-0010. |
| [Readium Kotlin Toolkit 3.3](https://github.com/readium/kotlin-toolkit) | `BSD-3-Clause` | Android | Copyright (c) 2017, Readium | Reflowable EPUB rendering. ADR-0005. |
| [jsoup 1.22.2](https://jsoup.org) | `MIT` | Android | Copyright (c) 2009-2026 Jonathan Hedley <https://jsoup.org/> | HTML parsing inside the Readium toolkit. ADR-0005. |
| [Timber 5.0.1](https://github.com/JakeWharton/timber) | `Apache-2.0` | Android | Copyright 2013 Jake Wharton | Logging inside the Readium toolkit. ADR-0005. |
| [Koi 0.5.5](https://github.com/mcxiaoke/kotlin-koi) | `Apache-2.0` | Android | Copyright 2015, 2016 Xiaoke Zhang | Utilities inside the Readium streamer. ADR-0005. |
| [Guava 33.3.1-android](https://github.com/google/guava) | `Apache-2.0` | Android | Copyright (C) The Guava Authors | Listenable futures inside media3, the audiobook player. |
| [JSpecify 1.0.0](https://jspecify.dev) | `Apache-2.0` | Android | Copyright 2018-2020 The JSpecify Authors. | The nullness annotations jsoup and Guava carry. |
| [jcifs-ng 2.1.10](https://github.com/AgNO3/jcifs-ng) | `LGPL-2.1-or-later` | Android | Copyright (C) 2000 "Michael B. Allen" <jcifs at samba dot org>
© 2016 AgNO3 Gmbh & Co. KG | SMB 2/3, which Android has no API for. ADR-0010. The only LGPL component: it is linked unmodified and is replaceable. |
| [SLF4J API 1.7.36](https://www.slf4j.org) | `MIT` | Android | Copyright (c) 2004-2022 QOS.ch Sarl (Switzerland) | The logging facade jcifs-ng writes to. ADR-0010. |
| [Bouncy Castle 1.84](https://www.bouncycastle.org) | `MIT` | Android | Copyright (c) 2000-2026 The Legion of the Bouncy Castle Inc. (https://www.bouncycastle.org). | SPNEGO token parsing inside jcifs-ng. Raised from 1.76 for CVE-2025-8885. |
| [desugar_jdk_libs 2.1.5](https://github.com/google/desugar_jdk_libs) | `GPL-2.0-with-classpath-exception` | Android | Copyright (c) Oracle and/or its affiliates. All rights reserved. | Core library desugaring, which the Readium AAR requires. The Classpath Exception is what lets the app link it. |
| [libarchive 3.8.9](https://github.com/libarchive/libarchive) | `BSD-2-Clause` | iOS, Android | The libarchive distribution as a whole is Copyright by Tim Kientzle | Decompressing RAR entries. 26 of 132 sources vendored; see third_party/libarchive/VENDORING.md. |
| [AndroidX and Jetpack Compose](https://developer.android.com/jetpack/androidx) | `Apache-2.0` | Android | Copyright (C) The Android Open Source Project | The UI toolkit, lifecycle, Room, media3 and the activity host. |
| [Kotlin and kotlinx](https://github.com/JetBrains/kotlin) | `Apache-2.0` | Android | Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors. | The language, coroutines and serialization. |
| [Literata](https://fonts.google.com/specimen/Literata) | `OFL-1.1` | iOS, Android | Copyright 2017 The Literata Project Authors (https://github.com/googlefonts/literata) | A bundled reading typeface. Designed for screen reading. |
| [Source Serif 4](https://fonts.google.com/specimen/Source+Serif+4) | `OFL-1.1` | iOS, Android | Copyright 2014 The Source Serif 4 Project Authors (https://github.com/adobe-fonts/source-serif) | A bundled reading typeface. |
| [EB Garamond](https://fonts.google.com/specimen/EB+Garamond) | `OFL-1.1` | iOS, Android | Copyright 2017 The EB Garamond Project Authors (https://github.com/octaviopardo/EBGaramond12) | A bundled reading typeface. |
| [Bitter](https://fonts.google.com/specimen/Bitter) | `OFL-1.1` | iOS, Android | Copyright 2011 The Bitter Project Authors (https://github.com/solmatas/BitterPro) | A bundled reading typeface. |
| [Atkinson Hyperlegible](https://fonts.google.com/specimen/Atkinson+Hyperlegible) | `OFL-1.1` | iOS, Android | Copyright 2020 Braille Institute of America, Inc. | A bundled reading typeface, designed for low vision. |
<!-- /generated:notices -->

Licence texts are in [`packages/licences/texts`](packages/licences/texts), taken from
[SPDX's own list](https://github.com/spdx/license-list-data) rather than transcribed.
Two are not SPDX's. `Attribution.txt` is CryptoSwift's own licence, which SPDX has no
identifier for — its podspec calls the type "Attribution", and the text is copied from the
package. `GPL-2.0-with-classpath-exception.txt` is the `LICENSE` file that accompanies
`desugar_jdk_libs`, because SPDX publishes the GPL and the Classpath Exception as two
documents and the library ships them as one.

## Not covered

Platform SDKs. Apple's frameworks and the Android platform are not redistributed by
this app and carry their own terms with the operating system.

## jcifs-ng, the one copyleft component

`jcifs-ng` is LGPL-2.1-or-later and every other component here is permissive, so it is
the one entry whose terms reach back into this app. Section 6 of the LGPL lets a work
that merely *uses* the library ship under any terms, provided the reader can relink the
work against a modified version of that library. StoryArc meets that the plain way:
the APK links the published `eu.agno3.jcifs:jcifs-ng:2.1.10` artifact **unmodified**,
`apps/android/core/smb/build.gradle.kts` is the one place that declares it, and the whole
app is open source — so a reader who wants their own jcifs-ng changes the version there
and rebuilds. Nothing is statically inlined and nothing is patched.

Bouncy Castle is raised to 1.84 by a *constraint* rather than a fork, for the same reason:
a constraint selects a different published artifact and leaves jcifs-ng itself untouched.

`desugar_jdk_libs` is GPL-2.0 and would raise the same question, except that its
Classpath Exception exists for exactly this: linking it produces no obligation on the
app's own code.

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

## marmelroy/Zip, if a scanner reports it

A composition analysis of an iOS release build will flag **CVE-2023-39135** against
`marmelroy/Zip` 2.1.2, a path traversal with **no fixed release in existence**. It is
worth a paragraph here so nobody re-investigates it.

The package holds two modules, and only one of them is the vulnerability. The advisory is
`Zip.unzipFile` — a Swift routine that extracts an archive to disk and joins each entry
name to the destination without checking the result stays inside it. StoryArc does not
declare the package; `readium/swift-toolkit` names it as a dependency of `ReadiumShared`
to reach its other module, the `Minizip` C reader, which `MinizipContainer` uses to read
EPUB entries into memory. Nothing in Readium, and nothing here, calls `Zip.unzipFile` or
anything else in the `Zip` module. Path traversal is a property of writing files; the code
that runs writes none.

That the vulnerable routine has no caller is checked against the binary rather than
assumed: a release build defines its symbols and has **no undefined reference to any of
them**, exposes no Objective-C class, and registers no protocol conformance anything could
dispatch through. The `no_marmelroy_zip` rule in `.swiftlint.yml` fails the build if a
StoryArc source ever reaches for the module.

The full assessment, the evidence, the options and their prices are in
[ADR-0014](docs/decisions/0014-unpatchable-zip-in-the-readium-graph.md).
