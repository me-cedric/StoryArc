# Implementation status

What is built against what is specified, capability by capability. Written because the
change task lists track three changes and the specs describe fifteen capabilities, so
"how much of StoryArc exists" had no answer anywhere.

Audited 2026-08-27 by reading every `specs/*/spec.md` against the app source on both
platforms, and kept current as things land. A capability is **built** when every requirement has code on both platforms,
**partial** when some do, **absent** when none do.

Keep this current. A status document that lags is worse than none, because it is believed.

| Capability | State | What is missing |
| --- | --- | --- |
| `publication-formats` | partial | CB7 decoder (declared open question); EPUB publisher, description, series, series index; EPUB spine-render cover fallback; re-decode on zoom; codec name in the placeholder; spread pairing; skipped-page count in the UI |
| `comic-reader` | partial | Border crop, which is the one part of image adjustments still missing -- **brightness, contrast, inversion and greyscale are built on both**, live and per series; sharpness is on iOS and on Android from API 33, where a runtime shader exists. The iOS controls were driven end to end on a simulator. The Android ones render in the chrome with the right label, and were not driven: no button in the Android reader chrome responds to a synthetic tap, the shipped fit and transition buttons included, so whether that is an emulator artefact or a hit-testing defect is still open. chapter navigation; orientation lock; slider thumbnails; spread pairing; scroll separator; direction override; memory-pressure prefetch shrink |
| `ebook-reader` | partial | Bookmarks, highlights, notes, in-book search, footnotes; reading aloud (whole requirement); hyphenation; PDF text layer, search and outline are iOS APIs with no UI. **Table of contents built on both; Fast fade over reflowable text built on iOS** |
| `reading-progress` | partial | Synchronisation (whole requirement); "start from the beginning"; completion timestamp; manual mark-read; conflict-resolution rules are written and unreachable |
| `local-library` | partial | Imported copies (whole requirement); watched changes (whole requirement); resumable scan. **Open-in from another app now works on both platforms**, including a refusal that names the detected format |
| `library-browsing` | partial | Unified library across sources; search grouping by match kind; recent searches; 8 of 11 filters; date-added and file-size sorting; per-scope layout |
| `settings-and-about` | partial | Search does not highlight the matched setting. **Sources, Downloads and Language groups are built, and every summary row states a real value** |
| `localization` | partial | No pseudo-locale test; no CI gate on a missing key for iOS. **Language override is built on both and switches in place**: Android carries the choice into the composition, iOS into the environment locale and into every `String(localized:)`, so neither recreates anything. Plurals and locale-correct byte formatting are done |
| `native-experience` | partial | Context menus; haptics; quick actions; widgets; handoff; predictive back; tablet sidebar; foldables; cover-derived accent; Increase Contrast; scroll edge effect; launch and memory budgets |
| `sources` | partial | Reordering has no UI; metadata cache; connection state is never probed for a remote source. **Registry, credential storage, folder-as-source, OPDS-catalogue-as-source, renaming, Settings › Sources and removal are built** |
| `offline-downloads` | partial | Background transfer is built on both. **Android is verified end to end**: a foreground service holds the process, a download started on the screen finishes with the app off it, and the service stops itself when the queue empties. **iOS is verified only in the foreground**: the transfer goes through a background `URLSession`, which is what lets the system carry it, and a download completes and lands through that path -- but the Simulator's transfer daemon never delivers a completion that lands while the app is suspended, and keeps reporting the task as live, so the suspended case needs a real device to confirm. A completion that arrives with nobody waiting is adopted, and a download nothing is carrying goes back in the queue. Automatic cleanup is built, unit-tested and wired on both platforms, but has not been seen working on a device. **Everything else is built on both: the queue holds for Wi-Fi and for a disk limit and resumes by itself, queued downloads reorder from the downloads view, a download resumes after the app is killed because the record carries everything the transfer needs, and finishing a publication removes its download reversibly -- the bytes are moved aside, not deleted, so the ten-second undo is a real undo** |
| `opds-catalog` | partial | OPDS 2.0 groups are flattened rather than shown as groups; no publication detail screen, so choosing another format is a menu. **All three requirements are built on both platforms: adding a catalogue with sign-in and certificate pinning, browsing sections and paginated grids with search, and fetching a publication and opening it** |
| `kavita-server` | built | Nothing outstanding. **Built on both platforms: authentication with token renewal, version check, extracting a base and key from a pasted OPDS URL, and reading libraries, series, volumes, chapters and server search. A reader pastes a server's OPDS URL, browses a library as a grid of covers with progress, reads the server's own summary and people rather than the file's, resumes at the chapter Kavita reports as next, and reads it. Reading position travels both ways: it is sent when the reader closes the chapter or leaves the app, held on disk when the server is unreachable, and flushed on the next connection; what other devices have read shows on the series grid. A chapter can be marked read or unread by hand, and the mark reaches the server. A server's own collections and reading lists appear beside the local ones, each labelled with the source it came from, and open to a grid of covers or a numbered run of chapters. A chapter can be added to one of the server's lists, and a publication from anywhere else is told why it cannot go in one.** Built against Kavita's documented API and the mock in `scripts/kavita-server.mjs`, never against a live server |
| `network-share` | partial | SMB 3 transport encryption is unmet, and now measured rather than assumed: jcifs-ng carries the negotiate context and no cipher, SMBClient offers SMB 2 only. A server that *requires* encryption is refused with a sentence naming the setting to change, which `scripts/smb-server.sh --encrypted` tests. **Everything else is built on both platforms: add a share and be told which failure happened, pick one discovered on the network or type it by hand, browse its tree to pick a root, read a comic streamed from it with nothing written to the device and the next pages prefetched, confirm first on a metered connection, and keep reading across a dropped connection.** Driven against a real Samba server with `server signing = mandatory`, authenticated. Discovery is verified on iOS only -- the Android emulator's NAT does not carry the host network's multicast. [ADR-0010](../decisions/0010-smb-clients.md) records the two clients |
| `collections-and-reading-lists` | partial | Converting a local list to a server one. No composite cover, no bulk selection from the library, no bulk download or mark-read. No composite cover, no bulk selection from the library, no bulk download or mark-read. **A reader can create, rename by re-creating, delete and populate local collections and ordered reading lists on both platforms, reorder a list, see their position in it, add any publication to any number of them, and be offered the next entry in list order rather than the next in series when they finish one** |

## What blocks what

`sources` is the keystone. Five capabilities wait on it, and so do the three open tasks
in `format-scope-and-libraries`:

```
sources (registry, credentials, cache, health)
  ├── opds-catalog          built on both
  ├── kavita-server ──── reading-progress: synchronisation
  ├── network-share
  └── offline-downloads ─ comic-reader: "offer to delete the download"   partial on both
                        └ settings-and-about: clearable downloads
                        └ format-scope-and-libraries 5.2, 5.3, 6.5
```

`collections-and-reading-lists` depends on `sources` only for its server-backed half. Its
local half — a collection a reader makes themselves — is built on both platforms.

## Where the two platforms differ

They are near line-for-line equal wherever code exists. The real divergences:

1. **Volume-button page turns are Android-only.** Deliberate: iOS cannot capture the
   volume buttons within App Store rules, and the app says so rather than shipping a dead
   switch.
2. **PDF text layer, search and outline are iOS-only.** `PDFKit` provides them and
   `PdfRenderer` does not. `format-scope-and-libraries` makes that an iOS-only feature for
   1.0. No UI calls them on either platform yet.
3. **Android has a manual library refresh; iOS has none.** Neither watches the filesystem.
4. **The cleartext exception is wider on Android.** A self-hosted catalogue usually answers
   over plain HTTP on a `.local` name or a private address. iOS says exactly that with
   `NSAllowsLocalNetworking`; Android's network security config can name a host or an IP
   literal but not a range, so the exception there covers every host. Both platforms
   complete a typed address with no scheme to `https`, so reaching a server over cleartext
   takes a reader typing `http://`.

## What the checks cover

| Check | Covers |
| --- | --- |
| `pnpm check` | specs *and changes*, tokens, generated notices, fixtures, both apps' lint and unit tests |
| `pnpm smoke:android` | thirteen routes still open without crashing |
| `pnpm a11y:android` | unnamed controls, raw values as names, targets under 48dp |
| `AccessibilityAuditTests` | Apple's own audit, on the library only |
| `pnpm corpus:check` | The generated test library is well-formed in every format |
| `pnpm opds` | Not a check: a real OPDS server for the walkthrough a unit test cannot do |
| `pnpm kavita` | Not a check either: a mock Kavita, because nobody here has a real one |

CI runs the first three. Nothing checks a screenshot against a reference, nothing tests
a pseudo-locale, and nothing gates a missing iOS string. `native-experience` asks for the
first of those by name.
