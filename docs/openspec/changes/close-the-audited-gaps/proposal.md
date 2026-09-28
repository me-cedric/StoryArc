## Why

The 2026-09-28 audit (`docs/delivery/remaining-work-2026-09-28.md`) read all
seventeen capability specs and four open changes against the source on both
platforms, then had eight reviewers try to refute every claim. The result
stands: **225 items where the code does not do what the spec says** — 115
defects, 71 unbuilt clauses, 16 one-platform gaps, 5 missing, 8 dead code, and
10 open-change tasks left unticked. 35 of the 225 could not start because they
waited on an owner decision. The owner has now made all 35 decisions (recorded
in this change's `design.md`, D1–D35 and LL), so the work can start. This
change carries the audited list and the decisions into one task chain so the
gates track it instead of a delivery memo.

Both platforms are affected. 153 items touch both, 35 are iOS-only, 37 are
Android-only.

## What Changes

- Land the six worktrees from `2026-09-12` that already hold finished or
  near-finished tests for `collections-and-reading-lists`, `native-experience`,
  `comic-reader`, `settings-and-about`, `ebook-reader` and `library-browsing`.
- Fix the 115 defects and build the 71 unbuilt clauses, 16 one-platform gaps, 5
  missing scenarios and 8 dead-code call sites the audit found, applying the 35
  owner decisions (D1–D35) and the local-library "unreachable" wording
  decision (LL) where a decision was the blocker.
- Tick the 10 open-change tasks the audit found still unbuilt in
  `audiobooks-and-playback`, `collections-and-reading-lists`, `opds-catalog`,
  `one-library-three-destinations` and `one-vocabulary-in-four-languages`, by
  building the code those changes already specify.
- Update eight main specs where an owner decision changes what the spec
  requires, not merely what the code does (see Modified Capabilities below).
- **Capabilities the 225 items touch** (build items only; a capability listed
  here does not necessarily get a spec delta — see Modified Capabilities):
  `sources`, `publication-formats`, `comic-reader`, `page-transitions`,
  `ebook-reader`, `reading-themes`, `read-aloud-and-reader-theming` (the open
  changes `read-aloud-beyond-the-reader` and `reader-theming-and-page-transitions`),
  `audiobooks-and-playback` (the open change of that name),
  `reading-progress`, `kavita-server`, `collections-and-reading-lists`,
  `local-library`, `network-share`, `opds-catalog`, `offline-downloads`,
  `library-browsing`, `publication-detail` (open change),
  `one-library-three-destinations` (open change),
  `one-vocabulary-in-four-languages` (open change), `localization`,
  `native-experience`, `settings-and-about`.
- No new capability. No capability is removed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `comic-reader`: **Navigation within a publication** — the *Reaching the end*
  scenario states how the end screen's download offer meets
  `offline-downloads`' automatic-cleanup sweep (decision D7).
- `offline-downloads`: **Storage management** — the *Automatic cleanup*
  scenario states the end screen's "Keep" exemption when automatic cleanup is
  on (decision D7).
- `page-transitions`: **The curl** — states what a forward curl on the last
  page reveals, so "nothing lifts" gains the end-screen case instead of
  lifting into an empty sheet (decision D10).
- `reading-themes`: **Theme presets** — states where the light/dark pair a
  linked appearance switches between is chosen (decision D15), and what
  Original keeps live versus moves into the publisher-styles notice (decision
  D16).
- `settings-and-about`: **Appearance** — states the two preset pickers under
  the "Follow appearance" link that choose the light/dark pair (decision D15).
- `ebook-reader`: **Reflowable rendering** — the *Publisher styles* and *An
  axis is inert while publisher styles are on* scenarios state which axes
  apply under Original and which move into the unavailable notice (decision
  D16).
- `local-library`: **Folder libraries** — the *Access is revoked* scenario's
  state name moves from `unauthorized` to `unreachable`, matching the code on
  both platforms, and keeps naming the lost access and offering re-pick
  (decision LL). **Opening a single file** — the *Remembering an opened file
  on Android* scenario states that a persistable hand-over grant is now kept
  and listed, matching the iOS half (decision D24).
- `network-share`: a new requirement, **Local network permission**, states
  when Android requests `ACCESS_LOCAL_NETWORK`, and what happens on denial
  across discovery and the first connection to a share, a catalogue or a
  Kavita server (decision D25).

## Non-goals

- The fifteen **possible additions** the audit lists (word lookup and
  translate, download-ahead, KOReader sync, a Komga source, app lock, spread
  split/rotate, audio bookmarks, smart shelves, reading statistics, WebDAV, an
  Audiobookshelf source, panel-by-panel view, new-issue notifications, Siri
  and Shortcuts actions, importing a reader's own font) and the six **ADR and
  security-review deferrals** it lists (CB7 support, a Minizip security
  assessment) are out of scope. None is in a spec; each needs its own
  `/opsx:propose`.
- The desktop apps (`apps/desktop-macos`, `apps/desktop-windows`,
  `apps/desktop-linux`) stay planning-only per
  [ADR-0004](../../decisions/0004-desktop-strategy.md). This change adds no
  desktop code and no desktop spec reinterpretation.
- No new capability. An item that would need one — a Komga source, an
  Audiobookshelf source, reading statistics as a new surface — is a possible
  addition above, not a task here.
- Home-screen widgets and CarPlay build everything code can reach; the
  App Group / signing-team provisioning and the CarPlay audio entitlement
  stay an owner step, not a task this change ticks (see `design.md`).
- Live verification against the owner's Kavita server for the write routes
  (D2, D32) stays an owner step; this change builds against Kavita's
  documented API and the mock only.
- SMB 3 encryption on iOS is a client decision recorded in a new ADR (decision
  D26); this change does not reopen ADR-0010 or ADR-0016 beyond that record.

## Impact

- **Code**: `apps/ios/Packages/StoryArcKit`, `apps/ios/Packages/StoryArcEpub`,
  every Android module under `apps/android`, and their test suites. No
  `packages/design-tokens` change is expected; `packages/test-fixtures` gains
  fixtures only if a task needs one the corpus lacks.
- **Specs**: eight delta files under eight capabilities (above).
- **ADRs**: one new ADR recording the SMB 3 client decision (D26), updating
  ADR-0010 and ADR-0016.
- **Dependencies**: Android replaces `jcifs-ng` with `smbj` (Apache-2.0,
  decision D26); the acknowledgements inventory gains the iOS `SMBClient`
  package, the eight Readium transitive packages, `bcprov`, `jsoup` and
  `desugar_jdk_libs` (decision D20).
