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
| `ebook-reader` | partial | Bookmarks, highlights, notes, in-book search, footnotes; reading aloud (whole requirement); hyphenation; PDF text layer, search and outline are iOS APIs with no UI. **The table of contents is built on both platforms** |
| `reading-progress` | partial | Synchronisation (whole requirement); "start from the beginning"; completion timestamp; manual mark-read; conflict-resolution rules are written and unreachable |
| `local-library` | partial | Imported copies (whole requirement); watched changes (whole requirement); resumable scan. **Open-in from another app now works on both platforms**, including a refusal that names the detected format |
| `library-browsing` | partial | Unified library across sources; search grouping by match kind; recent searches; 8 of 11 filters; date-added and file-size sorting; per-scope layout |
| `settings-and-about` | partial | Language group; search does not highlight the matched setting; clearable downloads |
| `localization` | partial | Language override; no pseudo-locale test; no CI gate on a missing key for iOS. Plurals and locale-correct byte formatting are done |
| `native-experience` | partial | Context menus; haptics; quick actions; widgets; handoff; predictive back; tablet sidebar; foldables; cover-derived accent; Increase Contrast; scroll edge effect; launch and memory budgets |
| `sources` | partial | Registry lifecycle; credential storage; metadata cache; source health screen. Models and pure helpers exist and nothing constructs them |
| `offline-downloads` | absent | Everything |
| `opds-catalog` | absent | Everything |
| `kavita-server` | absent | Everything |
| `network-share` | absent | Everything |
| `collections-and-reading-lists` | absent | Everything |

## What blocks what

`sources` is the keystone. Five capabilities wait on it, and so do the three open tasks
in `format-scope-and-libraries`:

```
sources (registry, credentials, cache, health)
  ├── opds-catalog
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

## What the checks cover

| Check | Covers |
| --- | --- |
| `pnpm check` | specs *and changes*, tokens, generated notices, fixtures, both apps' lint and unit tests |
| `pnpm smoke:android` | thirteen routes still open without crashing |
| `pnpm a11y:android` | unnamed controls, raw values as names, targets under 48dp |
| `AccessibilityAuditTests` | Apple's own audit, on the library only |

CI runs the first three. Nothing checks a screenshot against a reference, nothing tests
a pseudo-locale, and nothing gates a missing iOS string. `native-experience` asks for the
first of those by name.
