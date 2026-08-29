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
| `comic-reader` | partial | **Image adjustments are built on both, the whole requirement**: brightness, contrast, inversion and greyscale, live and per series; sharpness is on iOS and on Android from API 33, where a runtime shader exists. Border trimming detects a uniform white or black margin per page and can be turned off for a page it gets wrong; the detection is covered by eight tests a side, and it refuses a gradient, a mid-grey band and a blank page. The sliders and switches were driven end to end on both, on a simulator and on an emulator; trimming itself has only been run against synthetic pages, because the fixture corpus is gradients and has no margins to trim. chapter navigation; orientation lock; slider thumbnails; spread pairing; scroll separator; direction override; memory-pressure prefetch shrink |
| `ebook-reader` | partial | Bookmarks, highlights, notes, in-book search, footnotes; reading aloud (whole requirement); hyphenation; PDF text layer, search and outline are iOS APIs with no UI. **Table of contents built on both; Fast fade over reflowable text built on iOS** |
| `reading-progress` | partial | Synchronisation (whole requirement); conflict-resolution rules are written and unreachable. **The finished lifecycle is built on both**: a completion timestamp that is stamped once and never restamped — reopening a finished publication writes a new position, not a new completion — a finished publication that reopens at the beginning while keeping the record, and "Start from the beginning", confirmed, offered only where there is a position to clear. Four tests a side assert the timestamp table; the restart was driven on an emulator. Room went to version 2 with a written migration, never a destructive fallback. "Manual mark-read" was listed here and is in fact built — `AddToShelfMenu` and `AddToShelfSheet` have carried it for both local publications and Kavita chapters |
| `local-library` | partial | Imported copies (whole requirement); watched changes (whole requirement); resumable scan. **Open-in from another app now works on both platforms**, including a refusal that names the detected format |
| `library-browsing` | partial | Unified library across sources; search grouping by match kind; 8 of 11 filters; per-scope layout. **Date-added and file-size sorting are built on both**: the walk stamps each publication with what the filesystem says, so an unpacked folder is weighed by its pages and a picked Android folder is dated by what the Storage Access Framework will state — the only timestamp it publishes. Both orders were driven on a simulator and on an emulator against the fixture corpus, largest first, identically. **Recent searches are built on both**, offered under the field when nothing is typed and clearable in one action; a term is filed as it is typed and the keystrokes of one word fold back into one entry, which an emulator run caught the first rule getting wrong |
| `settings-and-about` | built | Nothing outstanding. **Search points at a single setting rather than only at its group: ten anchors a side, mirrored case for case, and choosing a match navigates, scrolls the row into view and tints it for two seconds before it fades. Privacy clears downloads beside the cache and the reading history, each row stating its own size — that row used to say nothing downloads yet, which stopped being true when `offline-downloads` landed.** The two search indexes had already drifted, "cache" reaching Downloads on iOS and Privacy on Android; they are realigned term for term and a test a side now asserts that every anchor is reachable. Driven on an emulator in light and dark: searched, navigated, scrolled and watched the tint fade |
| `localization` | built | The reader walk still only covers the library and the seven settings screens: the two readers need a publication on the device, which the emulator has none of. **Both gaps are closed.** `pnpm strings:ios` is the missing-key gate iOS never had — a `LocalizedStringKey` that matches nothing is not an error, not a warning and not a crash, it renders the key, and four shipped strings were doing exactly that: `about.version`, `theme.fontSize.position` and `theme.pageColour.refused` stored their keys positionally (`%1$@`), which SwiftUI never derives, and `catalogue.acquire.other` declared no placeholder for the argument its own translation spends. The About screen had been reading `about.version 0.1.0 1` on a simulator. The gate also fails on any key untranslated in any of the four languages, which is the clause the spec words as a build failure. `pnpm pseudo:android` is the pseudo-locale test: the debug build now sets `isPseudoLocalesEnabled`, without which `en-XA` is not compiled in and the walk would pass because nothing changed. It navigates by position, never by label — under a pseudo-locale there is no label to match — and reports text that leaves its row, controls off the display, and targets under 48dp. Nine routes pass with every string accented and half again as long. **Language override is built on both and switches in place**: Android carries the choice into the composition, iOS into the environment locale and into every `String(localized:)`, so neither recreates anything. Plurals and locale-correct byte formatting are done |
| `native-experience` | partial | Context menus; haptics; quick actions; widgets; handoff; predictive back; tablet sidebar; foldables; cover-derived accent; Increase Contrast; scroll edge effect; launch and memory budgets |
| `sources` | built | Nothing outstanding, with one honest limit: the "cached" notice leaves when a walk completes, even a walk that saw nothing, because the scanner does not report whether it could read a folder — the shelf survives such a walk, but stops saying it is cached. **The metadata cache is built.** The catalogue is written to disk when a walk finishes and restored before the next one starts, so the library is on screen in a file read rather than a folder walk; covers likewise, keyed by publication *and* pixel size. Both live in the caches directory, which is what makes them "evictable independently of downloaded publications" without a line of code for it. A refresh updates incrementally — Android used to empty the shelf and rebuild it — and a publication a walk no longer finds is removed while its progress stays, because progress lives in its own store keyed by identity. Neither the removal nor the write fires on a walk that saw *nothing at all*: that is far more likely to be a folder it could not read than a reader who deleted every book, and emptying the shelf then is the opposite of what the capability promises. Driven on an emulator: with the file moved away, the shelf and its cover are still there. **Connection state is built on both**, with the retry loop on `SourceProbe`'s backoff. **Registry, credential storage, folder-as-source, OPDS-catalogue-as-source, renaming, Settings › Sources, removal and reordering are built.** |
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
4. **Reordering sources is a drag on iOS and two buttons on Android.** `List.onMove`
   gives iOS the drag the spec describes, and gives VoiceOver its own reorder actions with
   it. Compose has no drag-to-reorder; hand-rolling one is a long-press gesture, an
   auto-scroll and a set of semantics actions that a screen reader would still need spelled
   out — so Android mirrors the download queue in the same app, which chose two buttons for
   the same reason. Both persist the same order.
5. **The cleartext exception is wider on Android.** A self-hosted catalogue usually answers
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
| `pnpm strings:ios` | every key a Swift source asks for exists, and is translated in all four languages. Part of `pnpm lint`, so it needs no device |
| `pnpm pseudo:android` | nine routes under `en-XA`: text that leaves its row, controls off the display, targets under 48dp |
| `AccessibilityAuditTests` | Apple's own audit, on the library only |
| `pnpm corpus:check` | The generated test library is well-formed in every format |
| `pnpm opds` | Not a check: a real OPDS server for the walkthrough a unit test cannot do |
| `pnpm kavita` | Not a check either: a mock Kavita, because nobody here has a real one |

CI runs the first four. Nothing checks a screenshot against a reference, which
`native-experience` asks for by name and is now the only one of the three gaps left: a
missing iOS string is gated by `pnpm strings:ios`, and the pseudo-locale is walked by
`pnpm pseudo:android`. Neither of those two covers the readers — the walk needs a
publication on the device, and the emulator has none.
