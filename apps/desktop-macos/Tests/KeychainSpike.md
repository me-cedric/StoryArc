# Keychain spike, task 1.13 — 2026-10-16

**Question.** Can an ad-hoc signed build of the Mac app (`CODE_SIGN_IDENTITY=-`, no team,
App Sandbox on) add an item to the data-protection keychain with
`kSecUseDataProtectionKeychain`?

**Measurement.** `MacCredentialStore.probeDataProtectionKeychain(service:)` runs one
`SecItemAdd` of a generic password with `kSecUseDataProtectionKeychain: true` and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, inside the sandboxed `StoryArc.app` that
hosts `StoryArcMacTests`. Run on 2026-10-16 with Xcode 27.1 (27A9275) on macOS 26.

**Result.** `SecItemAdd` returned **`errSecMissingEntitlement` (-34018)**. The inference in
`design.md` Decision 2 holds: the data-protection keychain needs an application identifier
or a keychain access group in the signature, and an ad-hoc build has neither.

**Decision.** Ad-hoc builds use the login keychain. `MacCredentialStore.path` is `.login`
and the wrapper delegates to `CredentialStore`, whose queries carry no
`kSecUseDataProtectionKeychain`. The data-protection path waits for the team-signed build
of task 6.8, which adds the keychain access group entitlement at the same time. No
keychain group is declared now, so `EntitlementsTests` asserts exactly four keys.

**Pinned.** `MacCredentialStoreTests.dataProtectionKeychainRefusesAnAdHocBuild` asserts the
-34018 status. When a signed build changes the answer, that test fails by name, and the
path is flipped on that evidence.

**Verified on the chosen path.** A secret saved through the wrapper reads back and leaves
with its source, and a scan of every regular file under the app container
(`APP_SANDBOX_CONTAINER_ID` is required, so an unsandboxed run fails rather than passes)
finds the secret in no file, as UTF-8, UTF-16 in either byte order, or base64. Planting
the secret in `tmp/` of the container made that scan fail by name before this note was
written.

**Known wart, not a defect.** The login keychain ACLs an item to the app's designated
requirement, and an ad-hoc signature's requirement is its code hash, so a rebuilt binary is
a different app to the keychain: the first read after a rebuild prompts, or fails, for an
item the previous build wrote. The test suite never sees this because each test saves and
reads in one process. Task 6.8's signed build has a stable requirement and does not.
