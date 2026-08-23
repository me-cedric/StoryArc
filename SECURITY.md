# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it through GitHub's private vulnerability reporting on this repository —
Security → Report a vulnerability — or contact the maintainer through
[github.com/me-cedric](https://github.com/me-cedric).

Please include what you can: what the issue is, how to reproduce it, which app
and version, and what you think the impact is. You will get an acknowledgement
within a few days, and an assessment with a fix timeline once the report is
confirmed.

## Supported versions

StoryArc is pre-alpha and has no releases. Once releases exist, the latest
release of each app is supported.

## The threat model

StoryArc has **no backend, no account and no telemetry**. It talks only to
servers the user configured. That removes a large class of risk and concentrates
what remains in four places.

| Surface | Risk | Control |
| --- | --- | --- |
| **Stored credentials** | SMB passwords, OPDS credentials and Kavita API keys | iOS Keychain and the Android encrypted store only. Never preferences, logs, backups or diagnostics. Redacted before any string leaves memory. |
| **Network transport** | Credentials or content over a hostile network | TLS enforced; an untrusted certificate is refused by default, with pinning only after showing the fingerprint and an explicit warning. SMB 1 is refused outright. SMB 3 encryption negotiated where the server offers it. |
| **Untrusted file parsing** | A malformed or malicious archive, EPUB or PDF | The largest attack surface in the app. Parsing is bounded, failures are contained, and a corrupt archive yields "opened what I could, skipped N" rather than undefined behaviour. |
| **Reflowable EPUB content** | Publication HTML and JavaScript | EPUB content is HTML by definition and is rendered in a restricted context with no access to app state, credentials or the file system beyond the publication. |

## What is explicitly out of scope

- **Archive passwords.** StoryArc does not prompt for or store them, and states
  plainly that a protected archive cannot be opened.
- **DRM.** No LCP, no Adobe DRM, no circumvention of either. A DRM-protected
  publication is reported as unsupported.
- **The security of a server you configured.** StoryArc is a client. If your
  Kavita instance is exposed to the internet without TLS, that is outside what
  this app can fix — though it will refuse to send your credentials in the clear.

## Dependency risk

Third-party libraries — particularly archive and ebook parsers, which by
definition process untrusted input — are recorded with their licence and
provenance in
[ADR-0005](docs/decisions/0005-format-and-rendering-libraries.md). The RAR
decoder is called out there specifically because its licence is not a standard
OSI licence and needs review before any CBR code ships.
