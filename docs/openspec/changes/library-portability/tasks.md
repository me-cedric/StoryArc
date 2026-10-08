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

- [x] 2.1 **Write the document** (both): sources and servers, collections and reading lists,
  pinned shelves, settings, reading themes, per-publication reader settings, reading progress,
  chosen covers.
  **Reopened 2026-10-06 by the wave 11 review:** everything but the chosen covers. design.md
  says a cover the reader chose travels as base64 in the body, and the body has no image
  field and the export does not read `CoverOverrideStore`. See 6.7. **Closed 2026-10-07** by 6.7: both fixtures carry a cover. The export screen of 2.5 must pass the real cover store in.
- [x] 2.2 **No secret is written** (both). A test that exports a source carrying a password, a
  token and an API key, and asserts none of the three appears anywhere in the bytes — not in a
  field, not in a URL, not base64.
- [x] 2.3 **A certificate pin travels** (both), and is flagged on import rather than applied
  silently.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The import preview draws the hosts that gain a pin. Frames: `docs/designs/screenshots/library-portability-android-2026-10-08/` and `docs/designs/screenshots/library-portability-ios-2026-10-08/`.
- [x] 2.4 **The reader is told what it is not** (both): no publication files, no downloads, no
  cover cache. A sentence where the export is offered, in four languages.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The sentence is on the export sheet in four languages on both platforms.
- [x] 2.5 **The export goes somewhere the reader picked** (both), through the system document
  picker.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The export goes through the system save picker. On the emulator and the simulator the picker wrote a JSON file: formatVersion 1, no secrets key, with the sources, progress, pins, themes and covers. **Left (owner step):** export on a phone and import the file on another device. On Android, if the activity is recreated while the picker is open, the picked file stays empty.

## 3. Import

- [x] 3.1 **Read the document and state what will happen first** (both): what will be added,
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
  **Done as built, 2026-10-08 (close-all-yellow, wave 3).** The preview and the result sheet are built and framed on both platforms (`docs/designs/screenshots/library-portability-android-2026-10-08/`, `docs/designs/screenshots/library-portability-ios-2026-10-08/`). What is left is task 3.1b.
- [ ] 3.1b **The import result names each conflict by title, offers the other position, and is framed with a conflict on iOS** (both). Left from 3.1: (1) a list of several conflicts shows one line each, such as 'Kept Page 31 of 40, set aside Page 13 of 40', and none names the title. (2) The result sheet has no 'use the other position' action, which `reading-progress` promises. (3) On iOS the result sheet showed no conflict section for a position on both devices (the preview says '1 title has a position on both devices'), so the section may be unreachable there; find out, and frame it. (4) Owner step: one real export and import between a simulator and an emulator.
- [x] 3.2 **Reading progress merges through `ProgressMerge`** (both), after task 1.4. The
  furthest position wins and finished stays finished, on a device that never synced too.
- [x] 3.3 **A collection that exists on both sides merges its members** (both), and the reader
  is told how many were added.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The preview states how many members each shelf gains, and the result sheet reports it. Frames: see 4.2.
- [x] 3.4 **An imported source asks for its secret once, when it is first reached** (both), and
  stays listed and browsable until then.
  **The import half is built; the asking is not proved (2026-10-06).** An imported source
  arrives with no `credentialReference`, is listed, and is named in
  `LibraryImportPlan.sourcesNeedingSignIn` — asserted on both platforms, including the case
  where this device already holds the secret and is therefore not asked. The asking itself is
  `source-lifecycle`'s existing unauthorised-source flow, which nothing here exercises, so no
  test says an imported source reaches it.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** An imported source is listed and browsable, and its page says it needs a sign-in. Frames: see 4.2. **Left:** no test covers an OPDS catalogue with no credential that answers 401.
- [x] 3.5 **An older document migrates** (both). The transform chain exists with nothing in it;
  a test adds a fake version 0 and proves the chain runs.
- [x] 3.6 **A newer document is refused by name** (both), and the device is unchanged.

## 4. Proof

- [x] 4.1 **Round trip across platforms** (both). Export on Android, import on iOS, and the
  reverse. Assert every record kind survives, including the five from task 1.2.
- [x] 4.2 **Frames**: the export sheet, the import preview stating what will happen, and a
  source marked as needing a sign-in. Both platforms, light and dark, default and largest text.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** Frames, light, dark and largest text where the layout wraps: `docs/designs/screenshots/library-portability-android-2026-10-08/` and `docs/designs/screenshots/library-portability-ios-2026-10-08/`. Not framed on Android: the 'sign-in is no longer stored' screen opened from the Library, because no way into it was found. Not reached on iOS: the result sheet with a conflict.

## 5. The owner's decision

- [x] 5.1 **Decide whether credentials travel** (owner step). **The owner said yes on
  2026-10-07**, knowing it amends two rules. Both are amended: this change now carries a delta
  on `sources` *Credential storage* (`specs/sources/spec.md`), and `AGENTS.md` non-negotiable 4
  names the one exception. The requirement is *Secrets travel only sealed, and only when asked*.
- [x] 5.2 **Seal and open a secret** (both). PBKDF2-HMAC-SHA256 at 600,000 iterations and
  AES-256-GCM with a 12-byte nonce and a 128-bit tag: CommonCrypto `CCKeyDerivationPBKDF` and
  CryptoKit `AES.GCM` on iOS, `SecretKeyFactory("PBKDF2WithHmacSHA256")` and
  `Cipher("AES/GCM/NoPadding")` on Android. No dependency. Every parameter goes in the
  document's `secrets` object. One fixed test vector, sealed once, is opened by both platforms'
  tests, so the two cannot drift. **Built and verified 2026-10-07.** `LibrarySecretSealer` on both platforms; both suites open `packages/test-fixtures/library/sealed-secrets.json` and seal its inputs to its bytes. Android ran on the host JVM only.
- [x] 5.3 **The export asks, and is off by default** (both). A switch "Include passwords" on the
  export sheet; turning it on asks for a passphrase twice. The sheet states that anyone with the
  file and the passphrase can sign in to these servers. Four languages.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The switch is off by default, and the warning and the two-passphrase prompt are framed on both platforms. Not run on iOS: an export with the switch on and a matching pair.
- [x] 5.4 **The import asks for the passphrase** (both), only when the document carries secrets.
  The right one writes each secret to the secure store. A wrong one is stated and may be retried;
  skipping imports the rest and marks those sources as needing a sign-in.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The passphrase prompt, a wrong passphrase (stated, retry allowed) and skipping are framed on both platforms. **Left:** no fixture holds a document sealed by each platform's own exporter.
- [x] 5.5 **Frames**: the export switch with its warning, and the import passphrase prompt. Both
  platforms, light and dark.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** Frames, light and dark: `docs/designs/screenshots/library-portability-android-2026-10-08/` and `docs/designs/screenshots/library-portability-ios-2026-10-08/`.

## 6. From the review of wave 11

A reviewer read sections 1 to 4 against this change's own spec and against `AGENTS.md`. Four
findings were fixed in the same wave: identifiers are compared as parsed values rather than as
text, a setting the writing platform cannot express keeps this device's answer, a secret in a
fragment is stripped like one in a query, and a certificate-pin notice names the host's own
source. These are what the review found and the wave did not close.

- [x] 6.1 **One unreadable record means one thing on both platforms**. iOS refuses the whole
  document when `position.kind` is a word it does not know; Android drops that one record and
  imports the rest. One document, two outcomes. Decide which is right, write it in the spec,
  and make both do it. Android's reading is the better one — `library-portability` /
  *A field this version does not know* already asks for the rest to be imported. **Built and verified 2026-10-07.** iOS reads `position.kind` as text; an unknown kind drops that record alone, as on Android. Spec scenario: *A record this version cannot read*.
- [x] 6.2 **The preview counts records the merge will drop**. `LibraryImportPlan` counts every
  arriving record; the merge silently discards any whose enum this build cannot read. The
  reader is promised more than they get. Count what will land, not what arrived. **Built and verified 2026-10-07.** Plan and merge share one `readableProgress` step. A bad `updatedAt` still differs: iOS refuses the document in the decoder, and Android drops that record.
- [x] 6.3 **An import is all or nothing**. `LibraryArchive.apply` writes seven stores in
  sequence on both platforms. A throw after the third leaves a half-imported library and
  nothing rolls it back. Stage the writes, or record enough to undo them. **Built and verified 2026-10-07.** The apply reads a snapshot, undoes every write on a throw, and throws the first failure again. The test fails the progress write, because the preference stores cannot throw.
- [x] 6.4 **An adopted position keeps this device's watermark**. `ProgressPull` saves the **Verified built on 2026-10-07** against the source: ProgressStore.save keeps the stored syncedPosition when the incoming record has none, on both platforms; SyncedPositionSurvivesTest and LibraryImportTest assert it.
  document's record whole, and that record carries no `syncedPosition`. A device that had
  synchronised with Kavita forgets what it last synchronised after an import — which is the
  state task 1 of `library-sync` exists to stop. Merge the watermark rather than overwrite it.
- [x] 6.5 **A document is bounded before it is parsed**. Neither platform limits the bytes it
  will read, and iOS holds roughly three copies of the document while decoding — serialised,
  re-serialised and decoded. A file a reader was handed can be any size. Refuse one that is
  too large by name, the way a newer version is refused. **Built and verified 2026-10-07.** The limit is 64 MiB, checked before the parse (spec scenario *A document that is too large*). The import screen of 3.1 must check the file size before it reads the file.
- [x] 6.6 **A platform name this build does not know is not fatal**. iOS types `writtenBy` as
  an enum, so a document written by a third platform is refused outright, while Android holds
  it as text. The field names who wrote the document; it decides nothing. **Built and verified 2026-10-07.** `writtenBy` is text on both platforms.
- [x] 6.7 **A chosen cover travels** (both), as base64 in the body, keyed by the override key
  `CoverOverrideStore` files it under. Add one to both fixtures and to the round trip of 4.1.
  It closes task 2.1. **Built and verified 2026-10-07** (spec scenario *A chosen cover travels*). No screen gives `LibraryArchive` the real cover store yet: tasks 2.5 and 3.1 must pass it in. A cover chosen before this change has no key file, and the export finds it only through a progress record or a shelf member.
- [x] 6.8 **The preview draws the pin and the member count** (both). Tasks 2.3 and 3.3 compute
  `certificatePinsToAdd` and `shelvesToMerge` and assert them, and no screen draws either: an
  import changes what the app trusts and says nothing. They close with the preview of 3.1, in
  four languages. Until then both stay partial.
  **Done, 2026-10-08 (close-all-yellow, wave 3).** The preview draws the pin section and the member count on both platforms.

