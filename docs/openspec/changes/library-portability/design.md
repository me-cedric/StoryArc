## Context

62 durable stores across the two platforms, almost all JSON blobs under matching
`app.storyarc.*` keys, plus one SwiftData store and one Room database for reading progress.
The two platforms already share a vocabulary and agree on most key names. They disagree on five
pairs, and those five are the whole of the cross-platform work.

## Goals / Non-Goals

**Goals.** A reader moves phone or platform and keeps their library. The file outlives the app
version that wrote it. A human can read it.

**Non-Goals.** Backing up publication files. Continuous sync — that is `library-sync`, which
builds on this document rather than inventing a second one.

## Decisions

### JSON, not a zip and not protobuf

A zip was considered for carrying cover images. It buys nothing: a shelf's chosen cover is a
member identifier, not an image; a publication cover is extracted from the publication; and the
cover cache is a cache. Only the covers a reader *chose* are images with no other source, and
those are few and base64 in the body is enough.

Protobuf was considered because Mihon uses it and because it keeps unknown fields across a
round trip, which JSON does not. It was rejected: it needs a toolchain and a schema on both
platforms, neither of which exists here, and it produces a binary file. The owner asked for a
format that survives a change to the app, and a file nobody can open does not survive — it
depends on an app that can open it, which is the thing being insured against.

### The five disagreements are reconciled in the document, not in the stores

The document defines one shape. Each platform converts at its own boundary.

| Record | iOS | Android | The document |
| --- | --- | --- | --- |
| Source timestamp | `Date` | epoch millis | ISO 8601 string |
| `SourceKind` | `localFolder` | `LOCAL_FOLDER` | lower camel |
| Shelf cover key | `coverMemberID` | `coverMemberId` | `coverMemberId` |
| Reading position | one JSON blob | nine flat columns | the named fields |
| Pinned shelves | container A | container B | a list of pins |

Changing the stores themselves to agree was the alternative. It is a migration on both
platforms for every existing install, to fix a divergence nothing but the export can see.

### Reading progress merges through the machinery that exists

`ProgressMerge`, `ProgressPull.merging` and `SyncConflictNotice` are on both platforms, tested,
and implement ADR-0006: the furthest position wins and finished is sticky. An import is the
same problem as a server disagreement.

**`ProgressMerge` has a bug an import hits every time, and it has to be fixed first.** It reads
`local.syncedPosition` to decide whether the local side moved. A device that has never
synchronised with a server has no watermark, and the code reads that absence as "the local side
moved". Every import onto a never-synced device — which is the common case, a new phone — would
take that branch. Task 1.4 fixes it, and it is a prerequisite rather than a nice-to-have.

### Secrets stay out, and the hole is shaped for a later yes

The owner chose to encrypt credentials into the export. Two standing rules forbid it: the
`sources` capability's *Credential storage* requirement, and `AGENTS.md` non-negotiable 4,
which both name backups explicitly. An encrypted secret in a file is a secret in a file.

Rather than amend a non-negotiable inside an unrelated change, the document reserves an optional
`secrets` object that the writer never fills. Turning it on is one change: fill it, flip a
setting, and amend the two rules. The crypto is decided here so that change is a decision and
not a design:

- **PBKDF2-HMAC-SHA256**, because both platforms ship it with no dependency. Argon2id and
  scrypt reach neither without one — Apple CryptoKit offers neither, and Android's
  `SecretKeyFactory` offers neither. Two platforms implementing different KDFs, or iOS gaining
  a crypto dependency this project has avoided, are both worse than a weaker-but-shared KDF.
- **AES-256-GCM**, which Android already uses with a 12-byte nonce and a 128-bit tag, and which
  iOS has in CryptoKit.
- **Every parameter in the document**: salt, nonce, iteration count, KDF name, cipher name. A
  hard-coded parameter cannot be raised later without breaking every file already written.
- OWASP's current iteration count at the time of writing, not a number baked into a comment.

### A newer document is refused, not partly read

An older app meeting a newer export can only guess at what it does not understand. Guessing
changes data silently. Refusing names the problem and leaves the device as it was. The cost is
that an older app cannot read a newer export at all, and the reader has to update — which is a
thing they can do, unlike recovering silently merged data.

## Risks / Trade-offs

**The plain body carries hostnames and publication titles.** `settings-and-about` redacts a
hostname from a diagnostic, so an export is a more sensitive artefact than a diagnostic and the
spec says so. A reader who shares an export shares their server addresses and what they read.
The app says this where the export is offered.

**Merging is harder to reason about than replacing.** It is also the only honest option: a
reader importing onto a device they have been using would lose that device's reading with a
replace, and would not be told which.

## Migration Plan

Format version 1 is the first. The transform chain exists from the start, with no transforms
in it, so the second version has somewhere to go.

## Open Questions

**One, and it is the owner's.** Should credentials travel, encrypted under a passphrase? The
owner has already said yes once. This change records that saying yes means amending the
`sources` capability and an `AGENTS.md` non-negotiable, which was not known when they said it.
The format is built so the answer can be yes later with no rework.
