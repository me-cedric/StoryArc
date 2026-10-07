## MODIFIED Requirements

### Requirement: Credential storage

The app SHALL store every source secret — password, API key, or token — in the
platform secure store, and SHALL NOT write a secret to preferences, logs,
crash reports, backups, or exported diagnostics. The one exception is a library
export for which the reader chose to carry secrets and gave a passphrase: there
each secret is sealed under that passphrase, as `library-portability` states,
and is never written in clear.

#### Scenario: Storing a secret
- **WHEN** a user saves a source that requires authentication
- **THEN** the secret is written to the platform secure store — the iOS Keychain, or a key held in the Android Keystore
- **AND** the registry entry holds only an opaque reference to it

#### Scenario: Secret appears in a diagnostic
- **WHEN** the app writes a log line, an error message, or a diagnostic bundle containing a URL with embedded credentials
- **THEN** the credential portion is redacted before the line leaves memory

#### Scenario: Reading a secret
- **WHEN** the app needs a secret to authenticate a request
- **THEN** it reads it from the secure store at the moment of use and does not retain it beyond the request

#### Scenario: A library export without secrets
- **WHEN** the reader exports the library and does not choose to carry secrets
- **THEN** the document holds no secret, sealed or clear

#### Scenario: A library export that carries secrets
- **WHEN** the reader chooses to carry secrets and gives a passphrase
- **THEN** each secret is in the document only as ciphertext sealed under a key derived from that passphrase
- **AND** an imported secret goes straight to the platform secure store, and nowhere else
