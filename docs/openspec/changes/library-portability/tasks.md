A ticked box here means: the code exists on both platforms, a test that fails without it
landed, and a document written on one platform was read on the other. A tick does **not** mean
a person moved a real library between two real devices.

## 1. The document

- [x] 1.1 **The format, as a type on both platforms** (both). A version, the app version, the
  writing platform, a moment, a body, and an optional `secrets` object the writer never fills.
- [x] 1.2 **The five disagreements reconcile at the boundary** (both). The source timestamp as
  ISO 8601, `SourceKind` in lower camel, `coverMemberId`, the reading position as named fields,
  the pinned shelves as a list. design.md holds the table. A test writes on one platform's
  encoder and reads on the other's decoder, for each of the five.
- [x] 1.3 **An unknown field survives a decode** (both), and a decode of a newer version
  refuses by name without changing anything.
- [x] 1.4 **Fix `ProgressMerge` on a device with no watermark** (both). It reads
  `local.syncedPosition` to decide whether the local side moved, and a never-synchronised
  device has none, which it reads as "moved". Every import onto a new phone takes that branch.
  **This is a prerequisite, not a nice-to-have**: do it before task 3.2.

## 2. Export

- [~] 2.1 **Write the document** (both): sources and servers, collections and reading lists,
  pinned shelves, settings, reading themes, per-publication reader settings, reading progress,
  chosen covers.
  **Reopened 2026-10-06 by the wave 11 review:** everything but the chosen covers. design.md
  says a cover the reader chose travels as base64 in the body, and the body has no image
  field and the export does not read `CoverOverrideStore`. See 6.7.
- [x] 2.2 **No secret is written** (both). A test that exports a source carrying a password, a
  token and an API key, and asserts none of the three appears anywhere in the bytes — not in a
  field, not in a URL, not base64.
- [~] 2.3 **A certificate pin travels** (both), and is flagged on import rather than applied
  silently.
- [ ] 2.4 **The reader is told what it is not** (both): no publication files, no downloads, no
  cover cache. A sentence where the export is offered, in four languages.
- [ ] 2.5 **The export goes somewhere the reader picked** (both), through the system document
  picker.

## 3. Import

- [~] 3.1 **Read the document and state what will happen first** (both): what will be added,
  what merged, what will need a sign-in. Nothing changes until the reader agrees.
  **The answer is built and the screen is not (2026-10-06).** `LibraryImportPlan` carries
  every line the screen has to show — sources to add, sources needing a sign-in, shelves to
  add, shelves to merge with how many members each gains, positions to add and to merge,
  hosts gaining a pin and the source each arrived with, whether the settings change, and how
  many themes arrive. `LibraryImport.plan` computes it and changes nothing, which
  `planningChangesNothing` asserts on both platforms. What is missing is the screen that
  draws it, and the four languages it draws it in. That one screen is also where task 2.3's
  pin flag, task 3.3's member count and task 3.6's refusal reach the reader: each of the
  three is computed and asserted, and none of them is drawn. See task 2.5.
- [x] 3.2 **Reading progress merges through `ProgressMerge`** (both), after task 1.4. The
  furthest position wins and finished stays finished, on a device that never synced too.
- [~] 3.3 **A collection that exists on both sides merges its members** (both), and the reader
  is told how many were added.
- [~] 3.4 **An imported source asks for its secret once, when it is first reached** (both), and
  stays listed and browsable until then.
  **The import half is built; the asking is not proved (2026-10-06).** An imported source
  arrives with no `credentialReference`, is listed, and is named in
  `LibraryImportPlan.sourcesNeedingSignIn` — asserted on both platforms, including the case
  where this device already holds the secret and is therefore not asked. The asking itself is
  `source-lifecycle`'s existing unauthorised-source flow, which nothing here exercises, so no
  test says an imported source reaches it.
- [x] 3.5 **An older document migrates** (both). The transform chain exists with nothing in it;
  a test adds a fake version 0 and proves the chain runs.
- [x] 3.6 **A newer document is refused by name** (both), and the device is unchanged.

## 4. Proof

- [x] 4.1 **Round trip across platforms** (both). Export on Android, import on iOS, and the
  reverse. Assert every record kind survives, including the five from task 1.2.
- [ ] 4.2 **Frames**: the export sheet, the import preview stating what will happen, and a
  source marked as needing a sign-in. Both platforms, light and dark, default and largest text.

## 5. The owner's decision

- [x] 5.1 **Decide whether credentials travel** (owner step). **The owner said yes on
  2026-10-07**, knowing it amends two rules. Both are amended: this change now carries a delta
  on `sources` *Credential storage* (`specs/sources/spec.md`), and `AGENTS.md` non-negotiable 4
  names the one exception. The requirement is *Secrets travel only sealed, and only when asked*.
- [ ] 5.2 **Seal and open a secret** (both). PBKDF2-HMAC-SHA256 at 600,000 iterations and
  AES-256-GCM with a 12-byte nonce and a 128-bit tag: CommonCrypto `CCKeyDerivationPBKDF` and
  CryptoKit `AES.GCM` on iOS, `SecretKeyFactory("PBKDF2WithHmacSHA256")` and
  `Cipher("AES/GCM/NoPadding")` on Android. No dependency. Every parameter goes in the
  document's `secrets` object. One fixed test vector, sealed once, is opened by both platforms'
  tests, so the two cannot drift.
- [ ] 5.3 **The export asks, and is off by default** (both). A switch "Include passwords" on the
  export sheet; turning it on asks for a passphrase twice. The sheet states that anyone with the
  file and the passphrase can sign in to these servers. Four languages.
- [ ] 5.4 **The import asks for the passphrase** (both), only when the document carries secrets.
  The right one writes each secret to the secure store. A wrong one is stated and may be retried;
  skipping imports the rest and marks those sources as needing a sign-in.
- [ ] 5.5 **Frames**: the export switch with its warning, and the import passphrase prompt. Both
  platforms, light and dark.

## 6. From the review of wave 11

A reviewer read sections 1 to 4 against this change's own spec and against `AGENTS.md`. Four
findings were fixed in the same wave: identifiers are compared as parsed values rather than as
text, a setting the writing platform cannot express keeps this device's answer, a secret in a
fragment is stripped like one in a query, and a certificate-pin notice names the host's own
source. These are what the review found and the wave did not close.

- [ ] 6.1 **One unreadable record means one thing on both platforms**. iOS refuses the whole
  document when `position.kind` is a word it does not know; Android drops that one record and
  imports the rest. One document, two outcomes. Decide which is right, write it in the spec,
  and make both do it. Android's reading is the better one — `library-portability` /
  *A field this version does not know* already asks for the rest to be imported.
- [ ] 6.2 **The preview counts records the merge will drop**. `LibraryImportPlan` counts every
  arriving record; the merge silently discards any whose enum this build cannot read. The
  reader is promised more than they get. Count what will land, not what arrived.
- [ ] 6.3 **An import is all or nothing**. `LibraryArchive.apply` writes seven stores in
  sequence on both platforms. A throw after the third leaves a half-imported library and
  nothing rolls it back. Stage the writes, or record enough to undo them.
- [ ] 6.4 **An adopted position keeps this device's watermark**. `ProgressPull` saves the
  document's record whole, and that record carries no `syncedPosition`. A device that had
  synchronised with Kavita forgets what it last synchronised after an import — which is the
  state task 1 of `library-sync` exists to stop. Merge the watermark rather than overwrite it.
- [ ] 6.5 **A document is bounded before it is parsed**. Neither platform limits the bytes it
  will read, and iOS holds roughly three copies of the document while decoding — serialised,
  re-serialised and decoded. A file a reader was handed can be any size. Refuse one that is
  too large by name, the way a newer version is refused.
- [ ] 6.6 **A platform name this build does not know is not fatal**. iOS types `writtenBy` as
  an enum, so a document written by a third platform is refused outright, while Android holds
  it as text. The field names who wrote the document; it decides nothing.
- [ ] 6.7 **A chosen cover travels** (both), as base64 in the body, keyed by the override key
  `CoverOverrideStore` files it under. Add one to both fixtures and to the round trip of 4.1.
  It closes task 2.1.
- [ ] 6.8 **The preview draws the pin and the member count** (both). Tasks 2.3 and 3.3 compute
  `certificatePinsToAdd` and `shelvesToMerge` and assert them, and no screen draws either: an
  import changes what the app trusts and says nothing. They close with the preview of 3.1, in
  four languages. Until then both stay partial.

