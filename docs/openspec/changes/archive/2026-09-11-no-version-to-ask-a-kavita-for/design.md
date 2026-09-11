# Design

This change amends a requirement to match code that already shipped. The
decisions below were taken in the code first; each names the file that proves it.

## What was measured, and against what

Kavita publishes `openapi.json` at its repository root. Five releases were read,
which is every release in real use between April 2025 and September 2026:
**v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4**. v0.9.1 is the current `latest`
on Docker Hub. A live 0.9.1.4 server answered the requests below.

| Route | In the five specs | Live 0.9.1.4 |
| --- | --- | --- |
| `GET /api/Server/server-info` | absent from all five | 404 |
| `GET /api/Server/version` | absent from all five | 404 |
| `GET /api/Health/api-version` | absent from all five | 404 |
| `GET /api/Server/accepting-connections` | absent from all five | 404 |
| `GET /api/Server/server-info-slim` | present | 403, administrators only |
| `GET /api/Health` | present | 200 `"Ok"`, no version in it |
| `POST /api/Plugin/authenticate` | present in all five | 200, `username` and `token` |

`/swagger/v1/swagger.json` is off in a production Kavita, so a client cannot read
the spec from the server either.

**Conclusion:** a reader's API key cannot learn the version of the server it
authenticates against. This is a fact about Kavita, not about StoryArc.

## Why no floor is worth keeping

The verbs of every route either client calls are identical across those five
releases. A version number would therefore decide nothing that a request does not
already decide by answering or by returning 404.

## What each platform does instead

Feature detection, at the request rather than at the handshake.

- **iOS.** `URLSession` from Foundation, iOS 26.0.
  `Sources/Kavita/KavitaClient.swift:126` — `connect()` calls `authenticate()`
  and returns. `sendVersioned(_:path:)` in the same file maps a 404 to
  `KavitaError.routeMissing` and remembers the path for the session.
- **Android.** `OkHttp` through the module's own client, minSdk 31.
  `core/kavita/src/main/kotlin/app/storyarc/core/kavita/KavitaClient.kt:83` —
  `connect()` calls `authenticate()` and returns. The same 404 rule holds there.

`KavitaIdentity` now carries `username` alone, on both platforms, because
`Plugin/authenticate` answers with `username` and `token` and nothing else. A
type that carried a version would state something the server did not say.

## Accessibility consequence

The reader now learns of an old server at the screen that failed, in a sentence
that names what went wrong, rather than at the add-server sheet in a sentence
naming a version number they cannot act on.

- `kavita.error.tooOldForRequest` (iOS) and `kavita_error_too_old_for_request`
  (Android): "That server is too old for StoryArc. It does not know the request
  StoryArc sends." Translated in en, fr, de and es on both platforms.
- The sentence is text drawn in the failure position, so VoiceOver and TalkBack
  read it with the surface that failed. Nothing is conveyed by colour alone.
- The old floor's sentence, `kavita.error.tooOld`, was deleted with the gate. It
  named a version the reader had no way to change and no way to check.

## Open Questions

- **`Reader/mark-chapter-unread` has no replacement.** It is absent from all five
  specs, so unmarking a chapter is dead against every Kavita. The nearest route
  is `Reader/mark-multiple-unread`, whose body is `seriesId`, `volumeIds`,
  `chapterIds` and `generateReadingSession` — a different shape from the
  `{seriesId, chapterId}` both clients send. No shape has been measured against a
  live server, so nothing is changed here. Callers: `KavitaMetadata.swift:196`
  and `KavitaClient.kt:163`.
- **`Reader/mark-chapter-read` starts at 0.9.0.** It is absent from v0.8.6,
  v0.8.8 and v0.8.9.1, so it answers 404 on those three. Its `MarkChapterReadDto`
  matches what both clients send. The 404 already raises the "too old" sentence,
  which is the correct answer for those releases, so nothing is changed here
  either.
