# The source secret boundary

Companion to [`source-secret-boundary.mmd`](source-secret-boundary.mmd).

The one path a source secret takes in, the one place it rests, and the edges it
is not allowed to cross. Board for the `source-lifecycle` change, requirement 2
(Credential storage).

## Read from

| File |
| --- |
| `apps/android/core/persistence/src/main/kotlin/app/storyarc/core/persistence/CredentialStore.kt` |
| `apps/ios/Packages/StoryArcKit/Sources/Persistence/CredentialStore.swift` |
| `apps/ios/Packages/StoryArcKit/Sources/StoryArcCore/DiagnosticRedaction.swift` |
| `apps/ios/Packages/StoryArcKit/Sources/SettingsFeature/Diagnostic.swift` |

All four paths were re-checked against the tree at the time of writing.

## What makes the promise structural

The registry holds an opaque reference and **nothing else**. That is what turns
"we do not log secrets" from a habit into a property of the shape: there is no
secret in the registry to leak, so the careless code path that would leak one
cannot be written.

## Why the refusal branch has no third option

A device with no usable keystore cannot hold a secret safely. Writing one to an
ordinary preference to keep the feature working is exactly what the requirement
forbids, so `CredentialStore.open` failing means the source is not saved at all.
There is no plaintext fallback, and the diagram has no arrow to one.

## Why one entry per source

Keyed by the source id, rather than one blob holding a map. Removing a source is
then a delete rather than a read-edit-write — which is the difference between a
removal that can half-fail and one that cannot.

On Android the key is AES-256-GCM in the Android Keystore with the ciphertext in
an ordinary preference; the key itself never enters the app's memory. On iOS it
is the Keychain. The diagram draws both as one node because everything upstream
and downstream of it is identical.

## Why the diagnostic bundle carries a count and not a list

The proposal names the diagnostic export as a risk, and sources add the first
values that could carry a hostname or a token. A display name is text the reader
typed, which is exactly where a hostname would appear — so the report does not
carry it at all, rather than carrying it redacted. Redaction is the second line;
not collecting the value is the first.

`DiagnosticRedaction` strips the credential before the line leaves memory, which
is why the arrow into the bundle passes through it and there is no arrow around
it.
