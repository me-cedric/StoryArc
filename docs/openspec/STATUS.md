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
| `comic-reader` | partial | Image adjustments (whole requirement); border crop; chapter navigation; orientation lock; slider thumbnails; spread pairing; scroll separator; direction override; memory-pressure prefetch shrink |
| `ebook-reader` | partial | Bookmarks, highlights, notes, in-book search, footnotes; reading aloud (whole requirement); hyphenation; PDF text layer, search and outline are iOS APIs with no UI. **Table of contents built on both; Fast fade over reflowable text built on iOS** |
| `reading-progress` | partial | Synchronisation (whole requirement); "start from the beginning"; completion timestamp; manual mark-read; conflict-resolution rules are written and unreachable |
| `local-library` | partial | Imported copies (whole requirement); watched changes (whole requirement); resumable scan. **Open-in from another app now works on both platforms**, including a refusal that names the detected format |
| `library-browsing` | partial | Unified library across sources; search grouping by match kind; recent searches; 8 of 11 filters; date-added and file-size sorting; per-scope layout |
| `settings-and-about` | partial | Language group; Downloads group; search does not highlight the matched setting. **Sources group is built** |
| `localization` | partial | Language override; no pseudo-locale test; no CI gate on a missing key for iOS. Plurals and locale-correct byte formatting are done |
| `native-experience` | partial | Context menus; haptics; quick actions; widgets; handoff; predictive back; tablet sidebar; foldables; cover-derived accent; Increase Contrast; scroll edge effect; launch and memory budgets |
| `sources` | partial | Reordering has no UI; metadata cache; connection state is never probed for a remote source. **Registry, credential storage, folder-as-source, OPDS-catalogue-as-source, renaming, Settings › Sources and removal are built** |
| `offline-downloads` | absent | Everything |
| `opds-catalog` | partial | OPDS 2.0 groups are flattened rather than shown as groups; no publication detail screen, so choosing another format is a menu; Android has no facet menu; a fetched file is a cache entry, not a managed download. **All three requirements are built on both platforms: adding a catalogue with sign-in and certificate pinning, browsing sections and paginated grids with search, and fetching a publication and opening it** |
| `kavita-server` | absent | Everything |
| `network-share` | absent | Everything |
| `collections-and-reading-lists` | absent | Everything |

## What blocks what

`sources` is the keystone. Five capabilities wait on it, and so do the three open tasks
in `format-scope-and-libraries`:

```
sources (registry, credentials, cache, health)
  ├── opds-catalog          built on both
  ├── kavita-server ──── reading-progress: synchronisation
  ├── network-share
  └── offline-downloads ─ comic-reader: "offer to delete the download"
                        └ settings-and-about: clearable downloads
                        └ format-scope-and-libraries 5.2, 5.3, 6.5
```

`collections-and-reading-lists` depends on `sources` only for its server-backed half. Its
local half — a collection a reader makes themselves — needs nothing that does not exist.

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

CI runs the first three. Nothing checks a screenshot against a reference, nothing tests
a pseudo-locale, and nothing gates a missing iOS string. `native-experience` asks for the
first of those by name.
