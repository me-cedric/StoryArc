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
| [SMBClient 0.3.1](https://github.com/kishikawakatsumi/SMBClient) | `MIT` | iOS | Copyright (c) 2024 Kishikawa Katsumi | SMB 2 and SMB 3, which iOS has no API for. Vendored in third_party/SMBClient, with SMB 3 dialects and transport encryption added. ADR-0010, ADR-0019. |
| [Readium Kotlin Toolkit 3.3](https://github.com/readium/kotlin-toolkit) | `BSD-3-Clause` | Android | Copyright (c) 2017, Readium | Reflowable EPUB rendering. ADR-0005. |
| [jsoup 1.22.2](https://jsoup.org) | `MIT` | Android | Copyright (c) 2009-2026 Jonathan Hedley <https://jsoup.org/> | HTML parsing inside the Readium toolkit. ADR-0005. |
| [Timber 5.0.1](https://github.com/JakeWharton/timber) | `Apache-2.0` | Android | Copyright 2013 Jake Wharton | Logging inside the Readium toolkit. ADR-0005. |
| [Koi 0.5.5](https://github.com/mcxiaoke/kotlin-koi) | `Apache-2.0` | Android | Copyright 2015, 2016 Xiaoke Zhang | Utilities inside the Readium streamer. ADR-0005. |
| [Guava 33.3.1-android](https://github.com/google/guava) | `Apache-2.0` | Android | Copyright (C) The Guava Authors | Listenable futures inside media3, the audiobook player. |
| [JSpecify 1.0.0](https://jspecify.dev) | `Apache-2.0` | Android | Copyright 2018-2020 The JSpecify Authors. | The nullness annotations jsoup and Guava carry. |
| [smbj 0.15.0](https://github.com/hierynomus/smbj) | `Apache-2.0` | Android | Copyright (C) 2016 - SMBJ Contributors | SMB 2 and SMB 3 with transport encryption, which Android has no API for. ADR-0010, ADR-0019. |
| [ASN.1 (asn-one) 0.6.0](https://github.com/hierynomus/asn-one) | `Apache-2.0` | Android | Copyright 2016 Jeroen van Erp <jeroen@hierynomus.com> | SPNEGO token parsing inside smbj. ADR-0019. |
| [MBassador 1.3.2](https://github.com/bennidi/mbassador) | `MIT` | Android | Copyright (c) 2012 Benjamin Diedrichsen | The event bus inside smbj. ADR-0019. |
| [SLF4J API 2.0.18](https://www.slf4j.org) | `MIT` | Android | Copyright (c) 2004-2022 QOS.ch Sarl (Switzerland) | The logging facade smbj writes to. ADR-0019. |
| [Bouncy Castle 1.85.2](https://www.bouncycastle.org) | `MIT` | Android | Copyright (c) 2000-2026 The Legion of the Bouncy Castle Inc. (https://www.bouncycastle.org). | The ciphers, MACs and key derivation inside smbj, for SMB signing and SMB 3 encryption. ADR-0019. |
| [desugar_jdk_libs 2.1.5](https://github.com/google/desugar_jdk_libs) | `GPL-2.0-with-classpath-exception` | Android | Copyright (c) Oracle and/or its affiliates. All rights reserved. | Core library desugaring, which the Readium AAR requires. The Classpath Exception is what lets the app link it. |
| [libarchive 3.8.9](https://github.com/libarchive/libarchive) | `BSD-2-Clause` | iOS, Android, Windows, Linux | The libarchive distribution as a whole is Copyright by Tim Kientzle | Decompressing RAR entries. 26 of 132 sources vendored; see third_party/libarchive/VENDORING.md. |
| [AndroidX and Jetpack Compose](https://developer.android.com/jetpack/androidx) | `Apache-2.0` | Android | Copyright (C) The Android Open Source Project | The UI toolkit, lifecycle, Room, media3 and the activity host. |
| [Kotlin and kotlinx](https://github.com/JetBrains/kotlin) | `Apache-2.0` | Android | Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors. | The language, coroutines and serialization. |
| [Literata](https://fonts.google.com/specimen/Literata) | `OFL-1.1` | iOS, Android | Copyright 2017 The Literata Project Authors (https://github.com/googlefonts/literata) | A bundled reading typeface. Designed for screen reading. |
| [Source Serif 4](https://fonts.google.com/specimen/Source+Serif+4) | `OFL-1.1` | iOS, Android | Copyright 2014 The Source Serif 4 Project Authors (https://github.com/adobe-fonts/source-serif) | A bundled reading typeface. |
| [EB Garamond](https://fonts.google.com/specimen/EB+Garamond) | `OFL-1.1` | iOS, Android | Copyright 2017 The EB Garamond Project Authors (https://github.com/octaviopardo/EBGaramond12) | A bundled reading typeface. |
| [Bitter](https://fonts.google.com/specimen/Bitter) | `OFL-1.1` | iOS, Android | Copyright 2011 The Bitter Project Authors (https://github.com/solmatas/BitterPro) | A bundled reading typeface. |
| [Atkinson Hyperlegible](https://fonts.google.com/specimen/Atkinson+Hyperlegible) | `OFL-1.1` | iOS, Android | Copyright 2020 Braille Institute of America, Inc. | A bundled reading typeface, designed for low vision. |
| [Readium TypeScript Toolkit 2.11.1 (navigator), 2.7.0 (shared)](https://github.com/readium/ts-toolkit) | `BSD-3-Clause` | macOS, Windows, Linux | Copyright (c) 2022, Readium Foundation | Reflowable EPUB rendering in the desktop web views, as one pinned bundle. ADR-0018 D6. |
| [PDFium chromium/7881 (pdfium-binaries)](https://github.com/bblanchon/pdfium-binaries) | `BSD-3-Clause` | Windows, Linux | Copyright 2014 The PDFium Authors | The PDF engine behind the Windows and Linux readers, through pdfium-render; macOS keeps PDFKit. ADR-0018. |
<!-- /generated:notices -->

## Desktop dependencies

The Rust crates of `Cargo.lock` and the NuGet packages of `apps/desktop-windows`, read from
those manifests and joined to the licence expression in
[`packages/licences/desktop-deps.json`](packages/licences/desktop-deps.json). PDFium and
libarchive are in the table above. Each crate carries its own licence and copyright files in its
published package; a crate that offers `MIT OR Apache-2.0` is used under either.

<!-- generated:desktop -->
| Component | Licence |
| --- | --- |
| [NuGet Microsoft.WindowsAppSDK 2.5.1](https://www.nuget.org/packages/Microsoft.WindowsAppSDK) | `Microsoft Software License Terms` |
| [NuGet Microsoft.Windows.SDK.BuildTools 10.0.26100.9169](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools) | `Microsoft Software License Terms` |
| [NuGet Microsoft.Windows.SDK.BuildTools.WinApp 0.7.1](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools.WinApp) | `MIT` |
| [NuGet coverlet.collector 6.0.4](https://www.nuget.org/packages/coverlet.collector) | `MIT` |
| [NuGet Microsoft.NET.Test.Sdk 17.14.1](https://www.nuget.org/packages/Microsoft.NET.Test.Sdk) | `MIT` |
| [NuGet xunit 2.9.3](https://www.nuget.org/packages/xunit) | `Apache-2.0` |
| [NuGet xunit.runner.visualstudio 3.1.4](https://www.nuget.org/packages/xunit.runner.visualstudio) | `MIT` |
| [Rust addchain 0.2.1](https://github.com/str4d/addchain) | `MIT OR Apache-2.0` |
| [Rust adler2 2.0.1](https://github.com/oyvindln/adler2) | `0BSD OR MIT OR Apache-2.0` |
| [Rust aead 0.6.1](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust aes-gcm 0.11.1](https://github.com/RustCrypto/AEADs) | `Apache-2.0 OR MIT` |
| [Rust aes 0.8.4](https://github.com/RustCrypto/block-ciphers) | `MIT OR Apache-2.0` |
| [Rust aes 0.9.3](https://github.com/RustCrypto/block-ciphers) | `MIT OR Apache-2.0` |
| [Rust ahash 0.8.12](https://github.com/tkaitchuck/ahash) | `MIT OR Apache-2.0` |
| [Rust aho-corasick 1.1.5](https://github.com/BurntSushi/aho-corasick) | `Unlicense OR MIT` |
| [Rust android_system_properties 0.1.6](https://github.com/nical/android_system_properties) | `MIT OR Apache-2.0` |
| [Rust array-init 2.1.0](https://github.com/Manishearth/array-init/) | `MIT OR Apache-2.0` |
| [Rust ashpd 0.13.13](https://github.com/bilelmoussaoui/ashpd) | `MIT` |
| [Rust asn1-rs-derive 0.6.0](https://github.com/rusticata/asn1-rs.git) | `MIT OR Apache-2.0` |
| [Rust asn1-rs-impl 0.2.0](https://github.com/rusticata/asn1-rs.git) | `MIT/Apache-2.0` |
| [Rust asn1-rs 0.7.2](https://github.com/rusticata/asn1-rs.git) | `MIT OR Apache-2.0` |
| [Rust async-broadcast 0.7.2](https://github.com/smol-rs/async-broadcast) | `MIT OR Apache-2.0` |
| [Rust async-dnssd 0.5.1](https://github.com/stbuehler/rust-async-dnssd) | `MIT` |
| [Rust async-recursion 1.2.0](https://github.com/dcchut/async-recursion) | `MIT OR Apache-2.0` |
| [Rust async-trait 0.1.92](https://github.com/dtolnay/async-trait) | `MIT OR Apache-2.0` |
| [Rust atomic-waker 1.1.2](https://github.com/smol-rs/atomic-waker) | `Apache-2.0 OR MIT` |
| [Rust autocfg 1.5.1](https://github.com/cuviper/autocfg) | `Apache-2.0 OR MIT` |
| [Rust av-data 0.4.4](https://github.com/rust-av/rust-av) | `MIT` |
| [Rust base16ct 1.0.0](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust base64 0.22.1](https://github.com/marshallpierce/rust-base64) | `MIT OR Apache-2.0` |
| [Rust base64 0.23.1](https://github.com/marshallpierce/rust-base64) | `MIT OR Apache-2.0` |
| [Rust base64ct 1.8.3](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust binrw_derive 0.15.2](https://github.com/jam1garner/binrw) | `MIT` |
| [Rust binrw 0.15.2](https://github.com/jam1garner/binrw) | `MIT` |
| [Rust bit-vec 0.9.1](https://github.com/contain-rs/bit-vec) | `Apache-2.0 OR MIT` |
| [Rust bitflags 1.3.2](https://github.com/bitflags/bitflags) | `MIT/Apache-2.0` |
| [Rust bitflags 2.13.2](https://github.com/bitflags/bitflags) | `MIT OR Apache-2.0` |
| [Rust bitreader 0.3.11](https://github.com/irauta/bitreader) | `MIT OR Apache-2.0` |
| [Rust bitvec 1.1.1](https://github.com/bitvecto-rs/bitvec) | `MIT` |
| [Rust block-buffer 0.10.4](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust block-buffer 0.12.1](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust block-padding 0.3.3](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust block-padding 0.4.2](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust bumpalo 3.20.3](https://github.com/fitzgen/bumpalo) | `MIT OR Apache-2.0` |
| [Rust byte-slice-cast 1.2.3](https://github.com/sdroege/bytes-num-slice-cast) | `MIT` |
| [Rust bytemuck 1.25.2](https://github.com/Lokathor/bytemuck) | `Zlib OR Apache-2.0 OR MIT` |
| [Rust byteorder-lite 0.1.0](https://github.com/image-rs/byteorder-lite) | `Unlicense OR MIT` |
| [Rust byteorder 1.5.0](https://github.com/BurntSushi/byteorder) | `Unlicense OR MIT` |
| [Rust bytes 1.12.1](https://github.com/tokio-rs/bytes) | `MIT` |
| [Rust cairo-rs 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust cairo-sys-rs 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust calendrical_calculations 0.2.4](https://github.com/unicode-org/icu4x) | `Apache-2.0` |
| [Rust cbc 0.1.2](https://github.com/RustCrypto/block-modes) | `MIT OR Apache-2.0` |
| [Rust cbc 0.2.1](https://github.com/RustCrypto/block-modes) | `MIT OR Apache-2.0` |
| [Rust cc 1.6.0](https://github.com/rust-lang/cc-rs) | `MIT OR Apache-2.0` |
| [Rust ccm 0.6.1](https://github.com/RustCrypto/AEADs) | `Apache-2.0 OR MIT` |
| [Rust cfg_aliases 0.2.2](https://github.com/katharostech/cfg_aliases) | `MIT` |
| [Rust cfg-expr 0.20.10](https://github.com/EmbarkStudios/cfg-expr) | `MIT OR Apache-2.0` |
| [Rust cfg-if 1.0.5](https://github.com/rust-lang/cfg-if) | `MIT OR Apache-2.0` |
| [Rust chacha20 0.10.2](https://github.com/RustCrypto/stream-ciphers) | `MIT OR Apache-2.0` |
| [Rust chrono 0.4.45](https://github.com/chronotope/chrono) | `MIT OR Apache-2.0` |
| [Rust cipher 0.4.4](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust cipher 0.5.2](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust cmac 0.8.0](https://github.com/RustCrypto/MACs) | `MIT OR Apache-2.0` |
| [Rust cmov 0.5.4](https://github.com/RustCrypto/utils) | `Apache-2.0 OR MIT` |
| [Rust color_quant 1.1.0](https://github.com/image-rs/color_quant.git) | `MIT` |
| [Rust combine 4.6.9](https://github.com/Marwes/combine) | `MIT` |
| [Rust console_error_panic_hook 0.1.7](https://github.com/rustwasm/console_error_panic_hook) | `Apache-2.0/MIT` |
| [Rust console_log 1.1.0](https://github.com/iamcodemaker/console_log) | `MIT/Apache-2.0` |
| [Rust const-oid 0.10.2](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust core_maths 0.1.1](https://github.com/robertbastian/core_maths) | `MIT` |
| [Rust core-foundation-sys 0.8.7](https://github.com/servo/core-foundation-rs) | `MIT OR Apache-2.0` |
| [Rust core-foundation 0.10.1](https://github.com/servo/core-foundation-rs) | `MIT OR Apache-2.0` |
| [Rust cpubits 0.1.1](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust cpufeatures 0.2.17](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust cpufeatures 0.3.1](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust crc32fast 1.5.2](https://github.com/srijs/rust-crc32fast) | `MIT OR Apache-2.0` |
| [Rust crypto-bigint 0.7.5](https://github.com/RustCrypto/crypto-bigint) | `Apache-2.0 OR MIT` |
| [Rust crypto-common 0.1.7](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust crypto-common 0.2.2](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust crypto-mac 0.11.0](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust crypto-primes 0.7.2](https://github.com/entropyxyz/crypto-primes) | `Apache-2.0 OR MIT` |
| [Rust csbindgen 1.9.8](https://github.com/Cysharp/csbindgen/) | `MIT` |
| [Rust ctr 0.10.1](https://github.com/RustCrypto/block-modes) | `MIT OR Apache-2.0` |
| [Rust ctutils 0.4.3](https://github.com/RustCrypto/utils) | `Apache-2.0 OR MIT` |
| [Rust curve25519-dalek-derive 0.1.1](https://github.com/dalek-cryptography/curve25519-dalek) | `MIT/Apache-2.0` |
| [Rust curve25519-dalek 5.0.0-rc.1](https://github.com/dalek-cryptography/curve25519-dalek/tree/main/curve25519-dalek) | `BSD-3-Clause` |
| [Rust data-encoding 2.11.1](https://github.com/ia0/data-encoding) | `MIT` |
| [Rust dav1d-sys 0.8.3](https://github.com/rust-av/dav1d-rs) | `MIT` |
| [Rust dav1d 0.11.1](https://github.com/rust-av/dav1d-rs) | `MIT` |
| [Rust dbl 0.5.0](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust der-parser 10.0.0](https://github.com/rusticata/der-parser.git) | `MIT OR Apache-2.0` |
| [Rust der 0.8.2](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust deranged 0.5.9](https://github.com/jhpratt/deranged) | `MIT OR Apache-2.0` |
| [Rust des 0.9.0](https://github.com/RustCrypto/block-ciphers) | `MIT OR Apache-2.0` |
| [Rust digest 0.10.7](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust digest 0.11.3](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust displaydoc 0.2.7](https://github.com/yaahc/displaydoc) | `MIT OR Apache-2.0` |
| [Rust ecdsa 0.17.0-rc.22](https://github.com/RustCrypto/signatures) | `Apache-2.0 OR MIT` |
| [Rust ed25519-dalek 3.0.0-rc.1](https://github.com/dalek-cryptography/curve25519-dalek/tree/main/ed25519-dalek) | `BSD-3-Clause` |
| [Rust ed25519 3.0.0](https://github.com/RustCrypto/signatures) | `Apache-2.0 OR MIT` |
| [Rust either 1.19.0](https://github.com/rayon-rs/either) | `MIT OR Apache-2.0` |
| [Rust elliptic-curve 0.14.1](https://github.com/RustCrypto/traits) | `Apache-2.0 OR MIT` |
| [Rust endi 1.1.1](https://github.com/zeenix/endi) | `MIT` |
| [Rust enumflags2_derive 0.7.12](https://github.com/meithecatte/enumflags2) | `MIT OR Apache-2.0` |
| [Rust enumflags2 0.7.12](https://github.com/meithecatte/enumflags2) | `MIT OR Apache-2.0` |
| [Rust equivalent 1.0.2](https://github.com/indexmap-rs/equivalent) | `Apache-2.0 OR MIT` |
| [Rust errno 0.3.14](https://github.com/lambda-fairy/rust-errno) | `MIT OR Apache-2.0` |
| [Rust event-listener-strategy 0.5.4](https://github.com/smol-rs/event-listener-strategy) | `Apache-2.0 OR MIT` |
| [Rust event-listener 5.4.2](https://github.com/smol-rs/event-listener) | `Apache-2.0 OR MIT` |
| [Rust fallible_collections 0.4.9](https://github.com/vcombey/fallible_collections.git) | `MIT/Apache-2.0` |
| [Rust fallible-iterator 0.3.0](https://github.com/sfackler/rust-fallible-iterator) | `MIT/Apache-2.0` |
| [Rust fallible-streaming-iterator 0.1.9](https://github.com/sfackler/fallible-streaming-iterator) | `MIT/Apache-2.0` |
| [Rust fastrand 2.5.0](https://github.com/smol-rs/fastrand) | `Apache-2.0 OR MIT` |
| [Rust fdeflate 0.3.7](https://github.com/image-rs/fdeflate) | `MIT OR Apache-2.0` |
| [Rust ff 0.14.0](https://github.com/zkcrypto/ff) | `MIT/Apache-2.0` |
| [Rust fiat-crypto 0.3.0](https://github.com/mit-plv/fiat-crypto) | `MIT OR Apache-2.0 OR BSD-1-Clause` |
| [Rust field-offset 0.3.6](https://github.com/Diggsey/rust-field-offset) | `MIT OR Apache-2.0` |
| [Rust find-msvc-tools 0.1.14](https://github.com/rust-lang/cc-rs) | `MIT OR Apache-2.0` |
| [Rust fixed_decimal 0.7.2](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust flate2 1.1.10](https://github.com/rust-lang/flate2-rs) | `MIT OR Apache-2.0` |
| [Rust foldhash 0.2.0](https://github.com/orlp/foldhash) | `Zlib` |
| [Rust form_urlencoded 1.2.2](https://github.com/servo/rust-url) | `MIT OR Apache-2.0` |
| [Rust fsevent-sys 4.1.0](https://github.com/octplane/fsevent-rust/tree/master/fsevent-sys) | `MIT` |
| [Rust funty 2.0.0](https://github.com/myrrlyn/funty) | `MIT` |
| [Rust futures-channel 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-core 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-executor 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-io 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-lite 2.6.1](https://github.com/smol-rs/futures-lite) | `Apache-2.0 OR MIT` |
| [Rust futures-macro 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-sink 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-task 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures-util 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust futures 0.3.34](https://github.com/rust-lang/futures-rs) | `MIT OR Apache-2.0` |
| [Rust gdk-pixbuf-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust gdk-pixbuf 0.22.0](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust gdk4-sys 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust gdk4 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust generic-array 0.14.7](https://github.com/fizyk20/generic-array.git) | `MIT` |
| [Rust getrandom 0.2.17](https://github.com/rust-random/getrandom) | `MIT OR Apache-2.0` |
| [Rust getrandom 0.3.4](https://github.com/rust-random/getrandom) | `MIT OR Apache-2.0` |
| [Rust getrandom 0.4.3](https://github.com/rust-random/getrandom) | `MIT OR Apache-2.0` |
| [Rust ghash 0.6.0](https://github.com/RustCrypto/universal-hashes) | `Apache-2.0 OR MIT` |
| [Rust gif 0.14.2](https://github.com/image-rs/image-gif) | `MIT OR Apache-2.0` |
| [Rust gio-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust gio 0.22.10](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust glib-macros 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust glib-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust glib 0.22.10](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust gobject-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust graphene-rs 0.22.8](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust graphene-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust group 0.14.0](https://github.com/zkcrypto/group) | `MIT/Apache-2.0` |
| [Rust gsk4-sys 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust gsk4 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust gtk4-macros 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust gtk4-sys 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust gtk4 0.11.5](https://github.com/gtk-rs/gtk4-rs) | `MIT` |
| [Rust hashbrown 0.13.2](https://github.com/rust-lang/hashbrown) | `MIT OR Apache-2.0` |
| [Rust hashbrown 0.16.1](https://github.com/rust-lang/hashbrown) | `MIT OR Apache-2.0` |
| [Rust hashbrown 0.17.1](https://github.com/rust-lang/hashbrown) | `MIT OR Apache-2.0` |
| [Rust hashlink 0.12.2](https://github.com/djc/hashlink) | `MIT OR Apache-2.0` |
| [Rust heck 0.5.0](https://github.com/withoutboats/heck) | `MIT OR Apache-2.0` |
| [Rust hex 0.4.3](https://github.com/KokaKiwi/rust-hex) | `MIT OR Apache-2.0` |
| [Rust hkdf 0.12.4](https://github.com/RustCrypto/KDFs/) | `MIT OR Apache-2.0` |
| [Rust hkdf 0.13.0](https://github.com/RustCrypto/KDFs/) | `MIT OR Apache-2.0` |
| [Rust hmac 0.12.1](https://github.com/RustCrypto/MACs) | `MIT OR Apache-2.0` |
| [Rust hmac 0.13.0](https://github.com/RustCrypto/MACs) | `MIT OR Apache-2.0` |
| [Rust http-body-util 0.1.5](https://github.com/hyperium/http-body) | `MIT` |
| [Rust http-body 1.1.0](https://github.com/hyperium/http-body) | `MIT` |
| [Rust http 1.5.0](https://github.com/hyperium/http) | `MIT OR Apache-2.0` |
| [Rust httparse 1.10.1](https://github.com/seanmonstar/httparse) | `MIT OR Apache-2.0` |
| [Rust hybrid-array 0.4.15](https://github.com/RustCrypto/hybrid-array) | `MIT OR Apache-2.0` |
| [Rust hyper-rustls 0.27.10](https://github.com/rustls/hyper-rustls) | `Apache-2.0 OR ISC OR MIT` |
| [Rust hyper-util 0.1.21](https://github.com/hyperium/hyper-util) | `MIT` |
| [Rust hyper 1.12.0](https://github.com/hyperium/hyper) | `MIT` |
| [Rust iana-time-zone-haiku 0.1.2](https://github.com/strawlab/iana-time-zone) | `MIT OR Apache-2.0` |
| [Rust iana-time-zone 0.1.65](https://github.com/strawlab/iana-time-zone) | `MIT OR Apache-2.0` |
| [Rust icu_calendar_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_calendar 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_casemap_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_casemap 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_collator_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_collator 2.3.1](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_collections 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_datetime_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_datetime 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_decimal_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_decimal 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_experimental_data 0.6.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_experimental 0.6.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_list_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_list 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_locale_core 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_locale_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_locale_fallback_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_locale_fallback 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_locale 2.3.1](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_normalizer_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_normalizer 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_pattern 0.5.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_plurals_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_plurals 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_properties_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_properties 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_provider 2.3.1](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_segmenter_data 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_segmenter 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_time_data 2.3.1](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu_time 2.3.0](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust icu 2.3.1](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust idna_adapter 1.2.2](https://github.com/hsivonen/idna_adapter) | `Apache-2.0 OR MIT` |
| [Rust idna 1.1.0](https://github.com/servo/rust-url/) | `MIT OR Apache-2.0` |
| [Rust image-webp 0.2.4](https://github.com/image-rs/image-webp) | `MIT OR Apache-2.0` |
| [Rust image 0.25.10](https://github.com/image-rs/image) | `MIT OR Apache-2.0` |
| [Rust indexmap 2.14.2](https://github.com/indexmap-rs/indexmap) | `Apache-2.0 OR MIT` |
| [Rust inotify-sys 0.1.8](https://github.com/hannobraun/inotify-sys) | `ISC` |
| [Rust inotify 0.11.5](https://github.com/hannobraun/inotify-rs) | `ISC` |
| [Rust inout 0.1.4](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust inout 0.2.4](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust ipnet 2.12.2](https://github.com/krisprice/ipnet) | `MIT OR Apache-2.0` |
| [Rust itertools 0.15.0](https://github.com/rust-itertools/itertools) | `MIT OR Apache-2.0` |
| [Rust itoa 1.0.18](https://github.com/dtolnay/itoa) | `MIT OR Apache-2.0` |
| [Rust ixdtf 0.6.6](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust jni-macros 0.22.4](https://github.com/jni-rs/jni-rs) | `MIT OR Apache-2.0` |
| [Rust jni-sys-macros 0.4.1](https://github.com/jni-rs/jni-sys) | `MIT OR Apache-2.0` |
| [Rust jni-sys 0.4.1](https://github.com/jni-rs/jni-sys) | `MIT OR Apache-2.0` |
| [Rust jni 0.22.4](https://github.com/jni-rs/jni-rs) | `MIT OR Apache-2.0` |
| [Rust js-sys 0.3.106](https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/js-sys) | `MIT OR Apache-2.0` |
| [Rust kbkdf 0.1.0-rc.1](https://github.com/RustCrypto/KDFs/) | `MIT OR Apache-2.0` |
| [Rust keccak 0.2.2](https://github.com/RustCrypto/sponges) | `Apache-2.0 OR MIT` |
| [Rust keyring-core 1.0.1](https://github.com/open-source-cooperative/keyring-core.git) | `MIT OR Apache-2.0` |
| [Rust kqueue-sys 1.1.2](https://gitlab.com/rust-kqueue/rust-kqueue-sys) | `MIT` |
| [Rust kqueue 1.2.1](https://gitlab.com/rust-kqueue/rust-kqueue) | `MIT` |
| [Rust lazy_static 1.5.1](https://github.com/rust-lang-nursery/lazy-static.rs) | `MIT OR Apache-2.0` |
| [Rust libadwaita-sys 0.9.2](https://gitlab.gnome.org/World/Rust/libadwaita-rs) | `MIT` |
| [Rust libadwaita 0.9.2](https://gitlab.gnome.org/World/Rust/libadwaita-rs) | `MIT` |
| [Rust libc 0.2.190](https://github.com/rust-lang/libc) | `MIT OR Apache-2.0` |
| [Rust libloading 0.9.0](https://github.com/nagisa/rust_libloading/) | `ISC` |
| [Rust libm 0.2.16](https://github.com/rust-lang/compiler-builtins) | `MIT` |
| [Rust libsqlite3-sys 0.38.2](https://github.com/rusqlite/rusqlite) | `MIT` |
| [Rust linux-raw-sys 0.12.1](https://github.com/sunfishcode/linux-raw-sys) | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` |
| [Rust litemap 0.8.3](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust log 0.4.34](https://github.com/rust-lang/log) | `MIT OR Apache-2.0` |
| [Rust lru-slab 0.1.3](https://github.com/Ralith/lru-slab) | `MIT OR Apache-2.0 OR Zlib` |
| [Rust maybe-async 0.2.11](https://github.com/fMeow/maybe-async-rs) | `MIT` |
| [Rust maybe-owned 0.3.4](https://github.com/rustonaut/maybe-owned) | `MIT OR Apache-2.0` |
| [Rust md-5 0.10.6](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust md-5 0.11.0](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust md4 0.10.2](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust memchr 2.8.3](https://github.com/BurntSushi/memchr) | `Unlicense OR MIT` |
| [Rust memoffset 0.9.1](https://github.com/Gilnaa/memoffset) | `MIT` |
| [Rust minimal-lexical 0.2.1](https://github.com/Alexhuszagh/minimal-lexical) | `MIT/Apache-2.0` |
| [Rust miniz_oxide 0.8.9](https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide) | `MIT OR Zlib OR Apache-2.0` |
| [Rust miniz_oxide 0.9.1](https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide) | `MIT OR Zlib OR Apache-2.0` |
| [Rust mio 1.2.4](https://github.com/tokio-rs/mio) | `MIT` |
| [Rust modular-bitfield-impl 0.11.2](https://github.com/robbepop/modular-bitfield) | `MIT/Apache-2.0` |
| [Rust modular-bitfield 0.11.2](https://github.com/robbepop/modular-bitfield) | `MIT/Apache-2.0` |
| [Rust moxcms 0.8.1](https://github.com/awxkee/moxcms.git) | `BSD-3-Clause OR Apache-2.0` |
| [Rust mp4parse 0.17.0](https://github.com/mozilla/mp4parse-rust) | `MPL-2.0` |
| [Rust nom 7.1.3](https://github.com/Geal/nom) | `MIT` |
| [Rust notify-types 2.1.0](https://github.com/notify-rs/notify.git) | `MIT OR Apache-2.0` |
| [Rust notify 8.2.0](https://github.com/notify-rs/notify.git) | `CC0-1.0` |
| [Rust num-bigint-dig 0.9.1](https://github.com/dignifiedquire/num-bigint) | `MIT/Apache-2.0` |
| [Rust num-bigint 0.3.3](https://github.com/rust-num/num-bigint) | `MIT OR Apache-2.0` |
| [Rust num-bigint 0.4.8](https://github.com/rust-num/num-bigint) | `MIT OR Apache-2.0` |
| [Rust num-complex 0.4.6](https://github.com/rust-num/num-complex) | `MIT OR Apache-2.0` |
| [Rust num-conv 0.2.2](https://github.com/jhpratt/num-conv) | `MIT OR Apache-2.0` |
| [Rust num-derive 0.4.2](https://github.com/rust-num/num-derive) | `MIT OR Apache-2.0` |
| [Rust num-integer 0.1.47](https://github.com/rust-num/num-integer) | `MIT OR Apache-2.0` |
| [Rust num-iter 0.1.46](https://github.com/rust-num/num-iter) | `MIT OR Apache-2.0` |
| [Rust num-rational 0.4.2](https://github.com/rust-num/num-rational) | `MIT OR Apache-2.0` |
| [Rust num-traits 0.2.19](https://github.com/rust-num/num-traits) | `MIT OR Apache-2.0` |
| [Rust num 0.4.3](https://github.com/rust-num/num) | `MIT OR Apache-2.0` |
| [Rust oid-registry 0.8.1](https://github.com/rusticata/oid-registry.git) | `MIT OR Apache-2.0` |
| [Rust oid 0.2.1](https://github.com/UnnecessaryEngineering/oid) | `MIT OR Apache-2.0` |
| [Rust once_cell 1.21.4](https://github.com/matklad/once_cell) | `MIT OR Apache-2.0` |
| [Rust oo7 0.6.0](https://github.com/linux-credentials/oo7) | `MIT` |
| [Rust openssl-probe 0.2.1](https://github.com/rustls/openssl-probe) | `MIT OR Apache-2.0` |
| [Rust ordered-stream 0.2.0](https://github.com/danieldg/ordered-stream) | `MIT OR Apache-2.0` |
| [Rust owo-colors 4.4.0](https://github.com/owo-colors/owo-colors) | `MIT` |
| [Rust p256 0.14.0-rc.14](https://github.com/RustCrypto/elliptic-curves) | `Apache-2.0 OR MIT` |
| [Rust p384 0.14.0-rc.14](https://github.com/RustCrypto/elliptic-curves) | `Apache-2.0 OR MIT` |
| [Rust p521 0.14.0-rc.14](https://github.com/RustCrypto/elliptic-curves) | `Apache-2.0 OR MIT` |
| [Rust pango-sys 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust pango 0.22.9](https://github.com/gtk-rs/gtk-rs-core) | `MIT` |
| [Rust parking 2.2.1](https://github.com/smol-rs/parking) | `Apache-2.0 OR MIT` |
| [Rust pastey 0.1.1](https://github.com/as1100k/pastey) | `MIT OR Apache-2.0` |
| [Rust pbkdf2 0.12.2](https://github.com/RustCrypto/password-hashes/tree/master/pbkdf2) | `MIT OR Apache-2.0` |
| [Rust pbkdf2 0.13.0](https://github.com/RustCrypto/password-hashes) | `MIT OR Apache-2.0` |
| [Rust pdfium-render 0.9.4](https://github.com/ajrcarey/pdfium-render) | `MIT OR Apache-2.0` |
| [Rust pem-rfc7468 1.0.0](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust percent-encoding 2.3.2](https://github.com/servo/rust-url/) | `MIT OR Apache-2.0` |
| [Rust picky-asn1-der 0.5.7](https://github.com/Devolutions/picky-rs) | `MIT OR Apache-2.0` |
| [Rust picky-asn1-x509 0.15.5](https://github.com/Devolutions/picky-rs) | `MIT OR Apache-2.0` |
| [Rust picky-asn1 0.10.1](https://github.com/Devolutions/picky-rs) | `MIT OR Apache-2.0` |
| [Rust picky-krb 0.12.4](https://github.com/Devolutions/picky-rs) | `MIT OR Apache-2.0` |
| [Rust picky 7.0.0-rc.25](https://github.com/Devolutions/picky-rs) | `MIT OR Apache-2.0` |
| [Rust pin-project-lite 0.2.17](https://github.com/taiki-e/pin-project-lite) | `Apache-2.0 OR MIT` |
| [Rust pin-utils 0.1.1](https://github.com/rust-lang/pin-utils) | `MIT OR Apache-2.0` |
| [Rust piston-float 1.0.1](https://github.com/pistondevelopers/float.git) | `MIT` |
| [Rust pkcs1 0.8.0-rc.4](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust pkcs8 0.11.0](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust pkg-config 0.3.34](https://github.com/rust-lang/pkg-config-rs) | `MIT OR Apache-2.0` |
| [Rust png 0.18.1](https://github.com/image-rs/image-png) | `MIT OR Apache-2.0` |
| [Rust polyval 0.7.3](https://github.com/RustCrypto/universal-hashes) | `Apache-2.0 OR MIT` |
| [Rust potential_utf 0.1.6](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust powerfmt 0.2.1](https://github.com/jhpratt/powerfmt) | `MIT OR Apache-2.0` |
| [Rust ppv-lite86 0.2.21](https://github.com/cryptocorrosion/cryptocorrosion) | `MIT OR Apache-2.0` |
| [Rust primefield 0.14.0](https://github.com/RustCrypto/elliptic-curves) | `Apache-2.0 OR MIT` |
| [Rust primeorder 0.14.0-rc.14](https://github.com/RustCrypto/elliptic-curves) | `Apache-2.0 OR MIT` |
| [Rust proc-macro-crate 3.5.0](https://github.com/bkchr/proc-macro-crate) | `MIT OR Apache-2.0` |
| [Rust proc-macro2 1.0.107](https://github.com/dtolnay/proc-macro2) | `MIT OR Apache-2.0` |
| [Rust pxfm 0.1.30](https://github.com/awxkee/pxfm) | `BSD-3-Clause OR Apache-2.0` |
| [Rust quick-error 2.0.1](http://github.com/tailhook/quick-error) | `MIT/Apache-2.0` |
| [Rust quick-xml 0.42.0](https://github.com/tafia/quick-xml) | `MIT` |
| [Rust quinn-proto 0.11.19](https://github.com/quinn-rs/quinn) | `MIT OR Apache-2.0` |
| [Rust quinn-udp 0.5.16](https://github.com/quinn-rs/quinn) | `MIT OR Apache-2.0` |
| [Rust quinn 0.11.12](https://github.com/quinn-rs/quinn) | `MIT OR Apache-2.0` |
| [Rust quote 1.0.47](https://github.com/dtolnay/quote) | `MIT OR Apache-2.0` |
| [Rust r-efi 5.3.0](https://github.com/r-efi/r-efi) | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` |
| [Rust r-efi 6.0.0](https://github.com/r-efi/r-efi) | `MIT OR Apache-2.0 OR LGPL-2.1-or-later` |
| [Rust radium 0.7.0](https://github.com/bitvecto-rs/radium) | `MIT` |
| [Rust rand_chacha 0.3.1](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand_chacha 0.9.0](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand_core 0.10.1](https://github.com/rust-random/rand_core) | `MIT OR Apache-2.0` |
| [Rust rand_core 0.6.4](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand_core 0.9.5](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand_pcg 0.10.2](https://github.com/rust-random/rngs) | `MIT OR Apache-2.0` |
| [Rust rand 0.10.3](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand 0.8.8](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rand 0.9.5](https://github.com/rust-random/rand) | `MIT OR Apache-2.0` |
| [Rust rcgen 0.14.10](https://github.com/rustls/rcgen) | `MIT OR Apache-2.0` |
| [Rust regex-automata 0.4.18](https://github.com/rust-lang/regex) | `MIT OR Apache-2.0` |
| [Rust regex-lite 0.1.9](https://github.com/rust-lang/regex) | `MIT OR Apache-2.0` |
| [Rust regex-syntax 0.8.11](https://github.com/rust-lang/regex) | `MIT OR Apache-2.0` |
| [Rust regex 1.13.1](https://github.com/rust-lang/regex) | `MIT OR Apache-2.0` |
| [Rust reqwest 0.12.28](https://github.com/seanmonstar/reqwest) | `MIT OR Apache-2.0` |
| [Rust reqwest 0.13.5](https://github.com/seanmonstar/reqwest) | `MIT OR Apache-2.0` |
| [Rust rfc6979 0.6.0-pre.0](https://github.com/RustCrypto/signatures) | `Apache-2.0 OR MIT` |
| [Rust ring 0.17.14](https://github.com/briansmith/ring) | `Apache-2.0 AND ISC` |
| [Rust rsa 0.10.0-rc.18](https://github.com/RustCrypto/RSA) | `MIT OR Apache-2.0` |
| [Rust rsqlite-vfs 0.1.1](https://crates.io/crates/rsqlite-vfs) | `MIT` |
| [Rust rusqlite 0.40.2](https://github.com/rusqlite/rusqlite) | `MIT` |
| [Rust rustc_version 0.4.1](https://github.com/djc/rustc-version-rs) | `MIT OR Apache-2.0` |
| [Rust rustc-hash 2.1.3](https://github.com/rust-lang/rustc-hash) | `Apache-2.0 OR MIT` |
| [Rust rustcrypto-ff_derive 0.14.0-rc.0](https://github.com/zkcrypto/ff) | `MIT/Apache-2.0` |
| [Rust rustcrypto-ff 0.14.0-rc.1](https://github.com/RustCrypto/ff) | `MIT/Apache-2.0` |
| [Rust rustcrypto-group 0.14.0-rc.1](https://github.com/RustCrypto/group) | `MIT/Apache-2.0` |
| [Rust rusticata-macros 4.1.0](https://github.com/rusticata/rusticata-macros.git) | `MIT/Apache-2.0` |
| [Rust rustix 1.1.5](https://github.com/bytecodealliance/rustix) | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` |
| [Rust rustls-native-certs 0.8.5](https://github.com/rustls/rustls-native-certs) | `Apache-2.0 OR ISC OR MIT` |
| [Rust rustls-pki-types 1.15.1](https://github.com/rustls/pki-types) | `MIT OR Apache-2.0` |
| [Rust rustls-platform-verifier-android 0.2.0](https://github.com/rustls/rustls-platform-verifier) | `MIT OR Apache-2.0` |
| [Rust rustls-platform-verifier 0.7.1](https://github.com/rustls/rustls-platform-verifier) | `MIT OR Apache-2.0` |
| [Rust rustls-webpki 0.103.15](https://github.com/rustls/webpki) | `ISC` |
| [Rust rustls 0.23.46](https://github.com/rustls/rustls) | `Apache-2.0 OR ISC OR MIT` |
| [Rust rustversion 1.0.23](https://github.com/dtolnay/rustversion) | `MIT OR Apache-2.0` |
| [Rust ryu 1.0.23](https://github.com/dtolnay/ryu) | `Apache-2.0 OR BSL-1.0` |
| [Rust same-file 1.0.6](https://github.com/BurntSushi/same-file) | `Unlicense/MIT` |
| [Rust schannel 0.1.30](https://github.com/steffengy/schannel-rs) | `MIT` |
| [Rust sec1 0.8.1](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust security-framework-sys 2.17.0](https://github.com/kornelski/rust-security-framework) | `MIT OR Apache-2.0` |
| [Rust security-framework 3.7.0](https://github.com/kornelski/rust-security-framework) | `MIT OR Apache-2.0` |
| [Rust semver 1.0.28](https://github.com/dtolnay/semver) | `MIT OR Apache-2.0` |
| [Rust serde_bytes 0.11.19](https://github.com/serde-rs/bytes) | `MIT OR Apache-2.0` |
| [Rust serde_core 1.0.229](https://github.com/serde-rs/serde) | `MIT OR Apache-2.0` |
| [Rust serde_derive 1.0.229](https://github.com/serde-rs/serde) | `MIT OR Apache-2.0` |
| [Rust serde_json 1.0.154](https://github.com/serde-rs/json) | `MIT OR Apache-2.0` |
| [Rust serde_repr 0.1.21](https://github.com/dtolnay/serde-repr) | `MIT OR Apache-2.0` |
| [Rust serde_spanned 1.1.1](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust serde_urlencoded 0.7.1](https://github.com/nox/serde_urlencoded) | `MIT/Apache-2.0` |
| [Rust serde 1.0.229](https://github.com/serde-rs/serde) | `MIT OR Apache-2.0` |
| [Rust serdect 0.4.3](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust sha1 0.11.0](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust sha2 0.10.9](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust sha2 0.11.1](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust sha3 0.12.0](https://github.com/RustCrypto/hashes) | `MIT OR Apache-2.0` |
| [Rust shlex 2.0.1](https://github.com/comex/rust-shlex) | `MIT OR Apache-2.0` |
| [Rust signal-hook-registry 1.4.8](https://github.com/vorner/signal-hook) | `MIT OR Apache-2.0` |
| [Rust signature 3.0.0](https://github.com/RustCrypto/traits) | `Apache-2.0 OR MIT` |
| [Rust simd_cesu8 1.2.0](https://github.com/seancroach/simd_cesu8) | `Apache-2.0 OR MIT` |
| [Rust simd-adler32 0.3.10](https://github.com/mcountryman/simd-adler32) | `MIT` |
| [Rust simdutf8 0.1.5](https://github.com/rusticstuff/simdutf8) | `MIT OR Apache-2.0` |
| [Rust slab 0.4.12](https://github.com/tokio-rs/slab) | `MIT` |
| [Rust smallvec 1.16.2](https://github.com/servo/rust-smallvec) | `MIT OR Apache-2.0` |
| [Rust smb-dtyp-derive 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-dtyp 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-fscc 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-msg-derive 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-msg 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-rpc 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb-transport 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust smb 0.12.1](https://github.com/afiffon/smb-rs) | `MIT` |
| [Rust socket2 0.6.5](https://github.com/rust-lang/socket2) | `MIT OR Apache-2.0` |
| [Rust spki 0.8.1](https://github.com/RustCrypto/formats) | `Apache-2.0 OR MIT` |
| [Rust sponge-cursor 0.1.0](https://github.com/RustCrypto/utils) | `MIT OR Apache-2.0` |
| [Rust sqlite-wasm-rs 0.5.5](https://github.com/Spxg/sqlite-wasm-rs) | `MIT` |
| [Rust sspi 0.21.3](https://github.com/devolutions/sspi-rs) | `MIT OR Apache-2.0` |
| [Rust stable_deref_trait 1.2.1](https://github.com/storyyeller/stable_deref_trait) | `MIT OR Apache-2.0` |
| [Rust static_assertions 1.1.0](https://github.com/nvzqz/static-assertions-rs) | `MIT OR Apache-2.0` |
| [Rust subtle 2.6.1](https://github.com/dalek-cryptography/subtle) | `BSD-3-Clause` |
| [Rust syn 1.0.109](https://github.com/dtolnay/syn) | `MIT OR Apache-2.0` |
| [Rust syn 2.0.119](https://github.com/dtolnay/syn) | `MIT OR Apache-2.0` |
| [Rust syn 3.0.6](https://github.com/dtolnay/syn) | `MIT OR Apache-2.0` |
| [Rust sync_wrapper 1.0.2](https://github.com/Actyx/sync_wrapper) | `Apache-2.0` |
| [Rust synstructure 0.13.2](https://github.com/mystor/synstructure) | `MIT` |
| [Rust synstructure 0.14.0](https://github.com/mystor/synstructure) | `MIT` |
| [Rust system-deps 7.0.8](https://github.com/gdesmott/system-deps) | `MIT OR Apache-2.0` |
| [Rust system-deps 9.0.0](https://github.com/gdesmott/system-deps) | `MIT OR Apache-2.0` |
| [Rust tap 1.0.1](https://github.com/myrrlyn/tap) | `MIT` |
| [Rust target-lexicon 0.13.5](https://github.com/bytecodealliance/target-lexicon) | `Apache-2.0 WITH LLVM-exception` |
| [Rust tempfile 3.27.0](https://github.com/Stebalien/tempfile) | `MIT OR Apache-2.0` |
| [Rust thiserror-impl 2.0.21](https://github.com/dtolnay/thiserror) | `MIT OR Apache-2.0` |
| [Rust thiserror 2.0.21](https://github.com/dtolnay/thiserror) | `MIT OR Apache-2.0` |
| [Rust time-core 0.1.9](https://github.com/time-rs/time) | `MIT OR Apache-2.0` |
| [Rust time-macros 0.2.32](https://github.com/time-rs/time) | `MIT OR Apache-2.0` |
| [Rust time 0.3.55](https://github.com/time-rs/time) | `MIT OR Apache-2.0` |
| [Rust tinystr 0.8.4](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust tinyvec 1.13.3](https://github.com/Lokathor/tinyvec) | `Zlib OR Apache-2.0 OR MIT` |
| [Rust tokio-macros 2.7.2](https://github.com/tokio-rs/tokio) | `MIT` |
| [Rust tokio-rustls 0.26.6](https://github.com/rustls/tokio-rustls) | `MIT OR Apache-2.0` |
| [Rust tokio-stream 0.1.19](https://github.com/tokio-rs/tokio) | `MIT` |
| [Rust tokio-util 0.7.20](https://github.com/tokio-rs/tokio) | `MIT` |
| [Rust tokio 1.53.3](https://github.com/tokio-rs/tokio) | `MIT` |
| [Rust toml_datetime 1.1.1+spec-1.1.0](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust toml_edit 0.25.15+spec-1.1.0](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust toml_parser 1.1.3+spec-1.1.0](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust toml_writer 1.1.2+spec-1.1.0](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust toml 1.1.6+spec-1.1.0](https://github.com/toml-rs/toml) | `MIT OR Apache-2.0` |
| [Rust tower-http 0.6.11](https://github.com/tower-rs/tower-http) | `MIT` |
| [Rust tower-layer 0.3.3](https://github.com/tower-rs/tower) | `MIT` |
| [Rust tower-service 0.3.3](https://github.com/tower-rs/tower) | `MIT` |
| [Rust tower 0.5.3](https://github.com/tower-rs/tower) | `MIT` |
| [Rust tracing-attributes 0.1.31](https://github.com/tokio-rs/tracing) | `MIT` |
| [Rust tracing-core 0.1.36](https://github.com/tokio-rs/tracing) | `MIT` |
| [Rust tracing 0.1.44](https://github.com/tokio-rs/tracing) | `MIT` |
| [Rust try-lock 0.2.5](https://github.com/seanmonstar/try-lock) | `MIT` |
| [Rust typenum 1.20.1](https://github.com/paholg/typenum) | `MIT OR Apache-2.0` |
| [Rust uds_windows 1.2.1](https://github.com/haraldh/rust_uds_windows) | `MIT` |
| [Rust unicode-ident 1.0.26](https://github.com/dtolnay/unicode-ident) | `(MIT OR Apache-2.0) AND Unicode-3.0` |
| [Rust universal-hash 0.6.1](https://github.com/RustCrypto/traits) | `MIT OR Apache-2.0` |
| [Rust untrusted 0.9.0](https://github.com/briansmith/untrusted) | `ISC` |
| [Rust url 2.5.8](https://github.com/servo/rust-url) | `MIT OR Apache-2.0` |
| [Rust utf16_iter 1.0.5](https://github.com/hsivonen/utf16_iter) | `Apache-2.0 OR MIT` |
| [Rust utf16string 0.2.0](https://github.com/getsentry/utf16string) | `MIT OR Apache-2.0` |
| [Rust utf8_iter 1.0.4](https://github.com/hsivonen/utf8_iter) | `Apache-2.0 OR MIT` |
| [Rust uuid 1.28.0](https://github.com/uuid-rs/uuid) | `Apache-2.0 OR MIT` |
| [Rust vcpkg 0.2.15](https://github.com/mcgoo/vcpkg-rs) | `MIT/Apache-2.0` |
| [Rust vecmath 1.0.0](https://github.com/pistondevelopers/vecmath.git) | `MIT` |
| [Rust version_check 0.9.5](https://github.com/SergioBenitez/version_check) | `MIT/Apache-2.0` |
| [Rust version-compare 0.2.1](https://gitlab.com/timvisee/version-compare) | `MIT` |
| [Rust walkdir 2.5.0](https://github.com/BurntSushi/walkdir) | `Unlicense/MIT` |
| [Rust want 0.3.2](https://github.com/seanmonstar/want) | `MIT` |
| [Rust wasi 0.11.1+wasi-snapshot-preview1](https://github.com/bytecodealliance/wasi) | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` |
| [Rust wasip2 1.0.4+wasi-0.2.12](https://github.com/bytecodealliance/wasi-rs) | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` |
| [Rust wasm-bindgen-futures 0.4.79](https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/futures) | `MIT OR Apache-2.0` |
| [Rust wasm-bindgen-macro-support 0.2.129](https://github.com/wasm-bindgen/wasm-bindgen/tree/main/crates/macro-support) | `MIT OR Apache-2.0` |
| [Rust wasm-bindgen-macro 0.2.129](https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/macro) | `MIT OR Apache-2.0` |
| [Rust wasm-bindgen-shared 0.2.129](https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/shared) | `MIT OR Apache-2.0` |
| [Rust wasm-bindgen 0.2.129](https://github.com/wasm-bindgen/wasm-bindgen) | `MIT OR Apache-2.0` |
| [Rust web-sys 0.3.106](https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/web-sys) | `MIT OR Apache-2.0` |
| [Rust web-time 1.1.0](https://github.com/daxpedda/web-time) | `MIT OR Apache-2.0` |
| [Rust webpki-root-certs 1.0.9](https://github.com/rustls/webpki-roots) | `CDLA-Permissive-2.0` |
| [Rust weezl 0.1.12](https://github.com/image-rs/weezl) | `MIT OR Apache-2.0` |
| [Rust widestring 1.2.1](https://github.com/VoidStarKat/widestring-rs) | `MIT OR Apache-2.0` |
| [Rust winapi-i686-pc-windows-gnu 0.4.0](https://github.com/retep998/winapi-rs) | `MIT/Apache-2.0` |
| [Rust winapi-util 0.1.11](https://github.com/BurntSushi/winapi-util) | `Unlicense OR MIT` |
| [Rust winapi-x86_64-pc-windows-gnu 0.4.0](https://github.com/retep998/winapi-rs) | `MIT/Apache-2.0` |
| [Rust winapi 0.3.9](https://github.com/retep998/winapi-rs) | `MIT/Apache-2.0` |
| [Rust windows_aarch64_gnullvm 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_aarch64_gnullvm 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_aarch64_msvc 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_aarch64_msvc 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_gnu 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_gnu 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_gnullvm 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_gnullvm 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_msvc 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_i686_msvc 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_gnu 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_gnu 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_gnullvm 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_gnullvm 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_msvc 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows_x86_64_msvc 0.53.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-collections 0.3.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-core 0.62.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-future 0.3.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-implement 0.60.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-interface 0.59.3](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-link 0.2.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-native-keyring-store 1.1.0](https://github.com/open-source-cooperative/windows-native-keyring-store.git) | `MIT OR Apache-2.0` |
| [Rust windows-numerics 0.3.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-registry 0.6.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-result 0.4.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-strings 0.5.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-sys 0.52.0](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-sys 0.60.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-sys 0.61.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-targets 0.52.6](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-targets 0.53.5](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows-threading 0.2.1](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust windows 0.62.2](https://github.com/microsoft/windows-rs) | `MIT OR Apache-2.0` |
| [Rust winnow 1.0.4](https://github.com/winnow-rs/winnow) | `MIT` |
| [Rust wit-bindgen 0.57.1](https://github.com/bytecodealliance/wit-bindgen) | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` |
| [Rust write16 1.0.0](https://github.com/hsivonen/write16) | `Apache-2.0 OR MIT` |
| [Rust writeable 0.6.4](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust wyz 0.5.1](https://github.com/myrrlyn/wyz) | `MIT` |
| [Rust x25519-dalek 3.0.0-rc.1](https://github.com/dalek-cryptography/curve25519-dalek/tree/main/x25519-dalek) | `BSD-3-Clause` |
| [Rust x509-parser 0.18.1](https://github.com/rusticata/x509-parser.git) | `MIT OR Apache-2.0` |
| [Rust yasna 0.6.0](https://github.com/qnighy/yasna.rs) | `MIT OR Apache-2.0` |
| [Rust yoke-derive 0.8.4](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust yoke 0.8.3](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zbus_macros 5.19.0](https://github.com/z-galaxy/zbus/) | `MIT` |
| [Rust zbus_names 4.3.5](https://github.com/z-galaxy/zbus/) | `MIT` |
| [Rust zbus 5.19.0](https://github.com/z-galaxy/zbus/) | `MIT` |
| [Rust zcheapstr 1.1.0](https://github.com/z-galaxy/zcheapstr/) | `MIT` |
| [Rust zerocopy-derive 0.8.63](https://github.com/google/zerocopy) | `BSD-2-Clause OR Apache-2.0 OR MIT` |
| [Rust zerocopy 0.8.63](https://github.com/google/zerocopy) | `BSD-2-Clause OR Apache-2.0 OR MIT` |
| [Rust zerofrom-derive 0.1.8](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zerofrom 0.1.8](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zeroize_derive 1.5.0](https://github.com/RustCrypto/utils) | `Apache-2.0 OR MIT` |
| [Rust zeroize 1.9.1](https://github.com/RustCrypto/utils) | `Apache-2.0 OR MIT` |
| [Rust zerotrie 0.2.5](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zerovec-derive 0.11.6](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zerovec 0.11.8](https://github.com/unicode-org/icu4x) | `Unicode-3.0` |
| [Rust zlib-rs 0.6.8](https://github.com/trifectatechfoundation/zlib-rs) | `Zlib` |
| [Rust zmij 1.0.23](https://github.com/dtolnay/zmij) | `MIT` |
| [Rust zune-core 0.5.3](https://github.com/etemesi254/zune-image) | `MIT OR Apache-2.0 OR Zlib` |
| [Rust zune-heic 0.5.0](https://github.com/etemesi254/zune-image/tree/dev/crates/zune-heic) | `MIT OR Apache-2.0 OR Zlib` |
| [Rust zune-isobmff 0.5.0](https://github.com/etemesi254/zune-image/tree/dev/crates/zune-isobmff) | `MIT OR Apache-2.0 OR Zlib` |
| [Rust zune-jpeg 0.5.15](https://github.com/etemesi254/zune-image/tree/dev/crates/zune-jpeg) | `MIT OR Apache-2.0 OR Zlib` |
| [Rust zvariant_derive 5.15.1](https://github.com/z-galaxy/zbus/) | `MIT` |
| [Rust zvariant_utils 4.2.0](https://github.com/z-galaxy/zbus/) | `MIT` |
| [Rust zvariant 5.15.1](https://github.com/z-galaxy/zbus/) | `MIT` |
<!-- /generated:desktop -->

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

## No copyleft SMB client

Android used `jcifs-ng`, which is LGPL-2.1-or-later. It is replaced by `smbj`, which is
Apache-2.0, so no component in this inventory is LGPL. `smbj` brings Bouncy Castle (MIT),
`asn-one` (Apache-2.0), MBassador (MIT) and the SLF4J API (MIT). See
[ADR-0019](docs/decisions/0019-smb-3-encryption-clients.md).

`desugar_jdk_libs` is GPL-2.0, and its Classpath Exception exists for exactly this case:
linking it produces no obligation on the app's own code.

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
