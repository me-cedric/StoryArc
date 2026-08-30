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
| **Network transport** | Credentials or content over a hostile network | TLS enforced; an untrusted certificate is refused by default, with pinning only after showing the fingerprint and an explicit warning. SMB 1 is refused outright. SMB 3 encryption negotiated where the server offers it. **SMB message integrity is not equal on the two platforms:** Android asks for signing on every session and verifies what it receives; iOS signs only when the server insists and never verifies a response, so a share read on iOS is not tamper-evident. See [ADR-0016](docs/decisions/0016-ios-smb-response-signing.md) — decided, risk accepted. |
| **Untrusted file parsing** | A malformed or malicious archive, EPUB or PDF | The largest attack surface in the app. Parsing is bounded, failures are contained, and a corrupt archive yields "opened what I could, skipped N" rather than undefined behaviour. |
| **ZIP container parsing** | StoryArc's own reader, per [ADR-0008](docs/decisions/0008-ranged-reads-and-own-zip-reader.md) | Every read is bounds-checked against the source length, and **no length field taken from a file is used to allocate** — an inflate size from the central directory is capped before a buffer is reserved. The central directory is the only authority; local headers are never trusted for sizes. |
| **TAR container parsing** | StoryArc's own reader | 512-byte headers with no compression, so no library is involved. Every header's checksum is verified — TAR's only integrity check, and what stops 512 arbitrary bytes being read as an entry. A header claiming more bytes than the file holds yields no entry rather than a wild offset. |
| **RAR header parsing** | StoryArc's own reader | RAR headers carry no compression, so names, sizes and flags are parsed here rather than in C. Entry counts are capped at 50 000, header sizes at 1 MB, the walk never moves backwards, and RAR5's variable-length integers are capped at ten groups so a run of continuation bytes cannot spin the reader. |
| **RAR entry decompression** | `libarchive`, a C library, on untrusted bytes | The only C on the path, and the only thing it does. Chosen partly *because* it is the most audited RAR implementation in open source. **26 of its 132 sources are vendored**, so the parsers for 7-Zip, CAB, ISO, LHA and XAR are not merely unreachable — they are not in the build. Only `format_rar` and `format_rar5` are ever registered. One entry is capped at 512 MB, and a short read is a failure rather than a truncated page. Because the sources are vendored rather than fetched, **no scanner will ever raise an advisory against them** — so the version is pinned in [`pin.json`](third_party/libarchive/pin.json), `pnpm libarchive:pin` fails when the tree, `config.h`, `VENDORING.md` and the notices inventory stop agreeing or when a source is edited in place, and a weekly job fails when upstream publishes a newer release. Advisories still have to be watched by a person — see [VENDORING.md](third_party/libarchive/VENDORING.md). |
| **A folder of images** | Filesystem traversal | Symbolic links are not followed, and a resolved path is re-checked against the publication root at read time. A folder is chosen by the user but is still untrusted input: a link is how a crafted folder would read a file outside itself. |
| **Reflowable EPUB content** | Publication HTML and JavaScript | EPUB content is HTML by definition and is rendered in a restricted context with no access to app state, credentials or the file system beyond the publication. **Network egress is denied by default on both platforms**, so a publication cannot reach a host the reader never configured: iOS compiles a `WKContentRuleList` allowing only the publication's own scheme, and Android combines `WebSettings.blockNetworkLoads` with a `connect-src 'none'` policy — neither alone is sufficient, because `blockNetworkLoads` does not stop a WebSocket and CSP has no directive for a top-level navigation. Measured against an eight-vector page: all eight escape unblocked on Android and six of eight on iOS; none escapes with the block in place. Scripting stays on, because turning it off would change what publications render. The consequence is that a publication's genuine remote font, image or stylesheet no longer loads, without notice. [ADR-0015](docs/decisions/0015-epub-webview-network-egress.md) — decided. |

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
