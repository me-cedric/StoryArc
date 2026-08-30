# libarchive, vendored

**Upstream:** <https://github.com/libarchive/libarchive> · **version 3.8.9** ·
[release tarball](https://github.com/libarchive/libarchive/releases/tag/v3.8.9)

The machine-readable copy of that pin — version, tarball URL and digest, the key
the release was signed with, and a digest over every vendored source — is
[`pin.json`](pin.json). `pnpm libarchive:pin` checks it on every `pnpm lint`.

This is the answer to task 0.5 of the `format-scope-and-libraries` change: *how
is libarchive vendored, and can a contributor still build the app?*

## What it is used for

One thing: **decompressing a RAR entry.** Nothing else.

Everything else about a CBR — entry names, page sizes, the cover, whether the
archive is solid or encrypted, and reading stored entries — is done by
`RarReader` on each platform, from headers, with no C at all. TAR needs no
library either (`TarReader`), ZIP is our own reader ([ADR-0008]), and PDF is
PDFKit and `PdfRenderer`. So the seam is a single function, `RarDecoder`, and
nothing above it knows libarchive exists.

That matters because it is what keeps this directory small enough to audit.

## Why sources, not a binary or a submodule

- **Not prebuilt binaries.** Phase 0 found that libarchive's CMake cannot
  configure for iOS at all, so the iOS side has to compile the sources anyway. A
  committed `.xcframework` plus six Android `.a` files would also be opaque
  blobs no reviewer could check against upstream.
- **Not a submodule.** `git clone` without `--recursive` would leave an empty
  directory and a confusing build failure. Task 0.5's own test is whether a
  contributor can build the app, and plain `git clone` has to be enough.
- **Copied sources, pinned by version.** `git clone && build` works. The
  trade-off accepted in exchange is that CVE tracking is manual — see
  *Refreshing* below.

## Why a nested SwiftPM package

SwiftPM will not compile C sources that live outside the package declaring them,
and the sources must be shared with the Android build rather than duplicated. A
local path dependency resolves both: `Package.swift` here declares the
`CLibarchive` target, `apps/ios/Packages/StoryArcKit` depends on it by relative
path, and `apps/android/core/format` compiles the same files with CMake.

One copy, two build systems, no symlinks.

## The file list, and why each file is here

26 of libarchive's 132 sources. The other 106 are parsers and writers for
formats StoryArc does not open — 7-Zip, CAB, ISO, LHA, XAR, and every writer.
Leaving them out is a smaller attack surface, not just a smaller repository:
`SECURITY.md` names archive parsing as the largest one in the app.

| Group | Files |
| --- | --- |
| RAR readers | `archive_read_support_format_rar.c`, `archive_read_support_format_rar5.c` |
| Read framework | `archive_read.c`, `archive_read_open_filename.c`, `archive_read_support_filter_none.c`, `archive_read_add_passphrase.c`, `archive_virtual.c`, `archive_check_magic.c`, `archive_util.c` |
| Entry model | `archive_entry.c`, `archive_entry_copy_stat.c`, `archive_entry_stat.c`, `archive_entry_sparse.c`, `archive_entry_xattr.c`, `archive_entry_link_resolver.c`, `archive_acl.c` |
| Strings, paths, time | `archive_string.c`, `archive_string_sprintf.c`, `archive_pathmatch.c`, `archive_time.c` |
| RAR's own codecs and hashes | `archive_ppmd7.c`, `archive_blake2s_ref.c`, `archive_blake2sp_ref.c` |
| Crypto scaffolding the RAR readers reference | `archive_cryptor.c`, `archive_hmac.c`, `archive_random.c` |

Plus every private header from `libarchive/`, the public `archive.h` and
`archive_entry.h` under `include/`, and `android_lf.h` from upstream's
`contrib/android/include/` — `archive.h` includes it unconditionally on Android.

Only `archive_read_support_format_rar()` and `_rar5()` are ever registered.
`archive_read_support_format_all()` is not vendored, so no other parser is
reachable even by accident.

## config.h

Hand-authored, in `Sources/CLibarchive/config.h`, because there is no configure
step: SwiftPM compiles the sources directly, and libarchive's CMake cannot target
iOS. It covers Apple and Android — both POSIX, both clang — with `__APPLE__` and
`__ANDROID__` guards for the real differences, of which there are three:
`struct stat`'s timestamp fields, `st_flags` and friends, and `major()`/`minor()`
living in `<sys/sysmacros.h>` on bionic.

Every optional dependency is off: no zlib, bzip2, lzma, lz4, zstd, OpenSSL,
nettle, mbedTLS, iconv or libxml2. RAR needs none of them — it carries its own
compression, and libarchive's blake2 and ppmd7 sources are vendored here. Each
one added would mean building it for six Android ABIs and two iOS slices, so each
has to be argued for.

**Verified to compile clean** with this config on macOS (arm64) and on all four
Android ABIs via NDK 29: `aarch64`, `armv7a`, `x86_64`, `i686`.

## Licence

BSD-2-Clause for every file used here, checked per file rather than per project
because libarchive's own `COPYING` warns that "some files have different
licensing terms". The audit is in the repository's
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md). None of the three
readers references the UnRAR licence, which is the whole reason libarchive was
chosen over UnrarKit, Unrar.swift or junrar ([ADR-0005]).

## Refreshing

1. Download the new release tarball and verify its signature against the key
   recorded in `pin.json`.
2. Copy the files in the table above, plus `libarchive/*.h`, plus
   `contrib/android/include/android_lf.h`. A release may add a private header
   the vendored sources now include — 3.8.9 added `archive_integer.h` and
   `archive_platform_stat.h` — so copy until nothing is missing, not just the
   files that were already here.
3. Re-read `config.h` against the new `config.h.in` for macros that appeared or
   changed meaning.
4. Compile for macOS and all four Android ABIs before running any test — a
   missing macro shows up as a compile error, not a test failure.
5. Re-check the per-file licence headers. Upstream has changed them before.
6. Update the version at the top of this file, `ARCHIVE_VERSION_*` in
   `config.h`, `version`/`tag`/`tarball`/`tarballSha256`/`signingKey` in
   `pin.json`, and the libarchive row in `packages/licences/notices.json`.
7. Run `node scripts/libarchive-pin.mjs --write` to re-record the source digest,
   then `pnpm libarchive:pin` to confirm every one of those places agrees.

Because the sources are copied rather than tracked by a package manager,
**vulnerability alerts will not find them automatically.** That is what
`pin.json` and `scripts/libarchive-pin.mjs` exist for: `--check` runs offline in
`pnpm lint` and fails when the five places that state a version disagree or when
a vendored source has been edited in place, and `--upstream` runs weekly in CI
and fails when a newer libarchive release exists. Watch
[libarchive's security advisories](https://github.com/libarchive/libarchive/security/advisories)
too, and treat a RAR-reader CVE as urgent: those two files parse untrusted input
from the internet.

[ADR-0005]: ../../docs/decisions/0005-format-and-rendering-libraries.md
[ADR-0008]: ../../docs/decisions/0008-ranged-reads-and-own-zip-reader.md
