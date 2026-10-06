A ticked box here means: the code exists on both platforms, a test that fails without it
landed, and a document written on one platform was read on the other. A tick does **not** mean
a person moved a real library between two real devices.

## 1. The document

- [ ] 1.1 **The format, as a type on both platforms** (both). A version, the app version, the
  writing platform, a moment, a body, and an optional `secrets` object the writer never fills.
- [ ] 1.2 **The five disagreements reconcile at the boundary** (both). The source timestamp as
  ISO 8601, `SourceKind` in lower camel, `coverMemberId`, the reading position as named fields,
  the pinned shelves as a list. design.md holds the table. A test writes on one platform's
  encoder and reads on the other's decoder, for each of the five.
- [ ] 1.3 **An unknown field survives a decode** (both), and a decode of a newer version
  refuses by name without changing anything.
- [x] 1.4 **Fix `ProgressMerge` on a device with no watermark** (both). It reads
  `local.syncedPosition` to decide whether the local side moved, and a never-synchronised
  device has none, which it reads as "moved". Every import onto a new phone takes that branch.
  **This is a prerequisite, not a nice-to-have**: do it before task 3.2.

## 2. Export

- [ ] 2.1 **Write the document** (both): sources and servers, collections and reading lists,
  pinned shelves, settings, reading themes, per-publication reader settings, reading progress,
  chosen covers.
- [ ] 2.2 **No secret is written** (both). A test that exports a source carrying a password, a
  token and an API key, and asserts none of the three appears anywhere in the bytes — not in a
  field, not in a URL, not base64.
- [ ] 2.3 **A certificate pin travels** (both), and is flagged on import rather than applied
  silently.
- [ ] 2.4 **The reader is told what it is not** (both): no publication files, no downloads, no
  cover cache. A sentence where the export is offered, in four languages.
- [ ] 2.5 **The export goes somewhere the reader picked** (both), through the system document
  picker.

## 3. Import

- [ ] 3.1 **Read the document and state what will happen first** (both): what will be added,
  what merged, what will need a sign-in. Nothing changes until the reader agrees.
- [ ] 3.2 **Reading progress merges through `ProgressMerge`** (both), after task 1.4. The
  furthest position wins and finished stays finished, on a device that never synced too.
- [ ] 3.3 **A collection that exists on both sides merges its members** (both), and the reader
  is told how many were added.
- [ ] 3.4 **An imported source asks for its secret once, when it is first reached** (both), and
  stays listed and browsable until then.
- [ ] 3.5 **An older document migrates** (both). The transform chain exists with nothing in it;
  a test adds a fake version 0 and proves the chain runs.
- [ ] 3.6 **A newer document is refused by name** (both), and the device is unchanged.

## 4. Proof

- [ ] 4.1 **Round trip across platforms** (both). Export on Android, import on iOS, and the
  reverse. Assert every record kind survives, including the five from task 1.2.
- [ ] 4.2 **Frames**: the export sheet, the import preview stating what will happen, and a
  source marked as needing a sign-in. Both platforms, light and dark, default and largest text.

## 5. The owner's decision

- [ ] 5.1 **Decide whether credentials travel** (owner step). Saying yes means amending
  `docs/openspec/specs/sources/spec.md` *Credential storage* and `AGENTS.md` non-negotiable 4,
  both of which name backups. The format already reserves the `secrets` object and design.md
  fixes the crypto — PBKDF2-HMAC-SHA256, AES-256-GCM, parameters in the document — so a yes is
  one change and no rework. **Do not implement this without that amendment.**
