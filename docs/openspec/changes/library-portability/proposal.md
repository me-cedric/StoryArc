## Why

StoryArc writes 34 durable stores on iOS and 28 on Android, and not one of them is versioned.
A reader who changes phone, or changes platform, rebuilds their sources, their collections,
their reading lists, their settings and their reading position by hand — or loses them.

There is no format to take the data out in, so there is nothing to take it out to. This change
writes one.

## What Changes

- **One versioned document** carries the reader's library: sources and servers, collections and
  reading lists, pinned shelves, settings, reading themes, per-publication reader settings,
  reading progress, and the covers the reader chose.
- **It is JSON, and it is readable.** A reader can open it, a future version can diff it, and a
  partial recovery is possible when something goes wrong. That is the point of exporting at all.
- **Secrets do not travel by default.** A server's address and username do; its password, token
  or API key does not. The reader signs in again once per server on import.
- **BREAKING for the `sources` capability if secrets ever do travel.** Including them, even
  encrypted, contradicts a standing requirement and a stated non-negotiable. See Impact.
- **Import merges, it does not replace.** Reading progress goes through the conflict machinery
  this repo already has, so the furthest position wins and finished stays finished.
- **An older document is migrated forward. A newer one is refused**, with its version named,
  rather than partly read.

## Capabilities

### New Capabilities

- `library-portability`: what an export carries, what it must never carry, how a document
  declares its version, and what an import does when both sides have moved.

### Modified Capabilities

None in this change. See Impact: the secrets question is deliberately left to a separate,
explicit decision rather than quietly amended here.

## Impact

**The owner asked for credentials to be encrypted into the export with a passphrase. This
proposal does not do that, and the reason is not a technical one.**

- `docs/openspec/specs/sources/spec.md`, *Credential storage*: the app "SHALL NOT write a
  secret to preferences, logs, crash reports, **backups**, or exported diagnostics."
- `AGENTS.md` non-negotiable 4: "Secrets go to the platform secure store. Never preferences,
  logs, **backups**, or diagnostics."

An encrypted secret in a file is still a secret written to a backup. Doing it needs both of
those amended, and `AGENTS.md` calls its list non-negotiable. That is the owner's call to make
knowingly, not a thing to slip into an export format — so the document format reserves an
optional `secrets` object, the writer never fills it, and a separate change can turn it on if
the owner decides to amend the contract. The crypto is specified here so that decision is a
yes or a no rather than a design exercise: PBKDF2-HMAC-SHA256 at the current OWASP iteration
count, AES-256-GCM, every parameter stored in the document.

- 34 iOS stores and 28 Android stores, nearly all JSON under matching `app.storyarc.*` keys,
  plus one SwiftData store and one Room database for reading progress.
- **Five pairs disagree on the wire today** and the export has to reconcile them: the source
  timestamp (`Date` versus epoch millis), the `SourceKind` raw value (`localFolder` versus
  `LOCAL_FOLDER`), the shelf cover key (`coverMemberID` versus `coverMemberId`), the reading
  position (one JSON blob versus nine flat columns), and the pinned-shelf container.
- `ProgressMerge`, `ProgressPull.merging` and `SyncConflictNotice` are reused rather than
  rewritten — and `ProgressMerge` has a bug an import would hit every time. See design.md.
- The export's plain body carries server hostnames and publication titles.
  `settings-and-about` redacts a hostname from a diagnostic, so an export is a different kind
  of artefact from a diagnostic and the spec says so in as many words.
