# No version to ask a Kavita for

**Platforms: both.** This change writes no application code. It amends one
requirement so that the specification stops asking for a check that no Kavita
server can answer, and that both apps stopped performing on 2026-09-07.

## Why

`kavita-server` → *Kavita connection* → *Adding a server* still says this:

> - **THEN** the app authenticates, confirms the server version and the account name, and saves the source
> - **AND** rejects a server whose version is older than the minimum StoryArc supports, naming the required version

Both clauses are now implemented by nothing, and neither can be implemented.

### The route that fed the floor never existed

The version came from `GET /api/Server/server-info`. That route is absent from
Kavita's published `openapi.json` at v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and
v0.9.1.4 — every release in real use between April 2025 and September 2026 — and
a live 0.9.1.4 answers 404 to it. `connect()` sent it after authenticating, and
any non-2xx throws, so **adding a Kavita source failed for every reader on every
version, on both platforms**. The floor it fed could never fire, because the
request that fed it always failed first.

### No other route states the version either

`/api/Server/version`, `/api/Health/api-version` and
`/api/Server/accepting-connections` all answer 404.
`/api/Server/server-info-slim` is refused with 403 unless the account is an
administrator. Swagger is off in a production Kavita. `/api/Health` answers `Ok`
and carries no version in it. A reader's API key therefore cannot learn the
version of the server it authenticates against.

### A version number would decide nothing

The verbs of every route either client calls are identical across those five
releases. There is no version boundary for a floor to sit on.

### The code already stopped, and something else took over

`connect()` now authenticates and stops, on both platforms:
`apps/ios/Packages/StoryArcKit/Sources/Kavita/KavitaClient.swift:126` and
`apps/android/core/kavita/src/main/kotlin/app/storyarc/core/kavita/KavitaClient.kt:83`.
Two tests a side assert that one request is sent and that a server answering 404
to every other route is still added — `KavitaClientTests.swift:22,37` and
`KavitaTest.kt:220,231`.

What replaced the floor is feature detection, which was already there. A 404 on a
route the app asks for is read as that route missing, the answer is remembered
for the session, and the reader is told in a sentence that is already translated
into en, fr, de and es: `kavita.error.tooOldForRequest` on iOS, drawn from
`KavitaConnection.swift:131`, and `kavita_error_too_old_for_request` on Android,
drawn from `KavitaMessage.kt:31` and `KavitaConnection.kt:182`. Nothing
else — not a 401, a 403, a 500 or a timeout — is read as an old server.

## What changes

- `kavita-server` → *Kavita connection*: *Adding a server* stops naming a version
  and names the account only. One paragraph of requirement prose states that the
  app asks no server for its version, and that an unknown route is what raises
  the "too old" sentence.
- The three other scenarios of that requirement are carried word for word.
- No application code changes. No screenshot is owed.

## Non-goals

- **Adding a Kavita version source.** None exists for a reader's key. Building
  one would need an administrator account, which StoryArc does not ask for.
- **Widening what counts as an old server.** Only a 404 on a route the app asks
  for means the route is missing. Every other failure keeps its own sentence.
- **Fixing the two `Reader/mark-chapter-*` routes.** `mark-chapter-unread` is in
  none of the five published specs and `mark-chapter-read` starts at 0.9.0. No
  replacement has been measured against a live server, so both are left alone and
  written down instead.
- **Touching any other `kavita-server` requirement.** Library structure,
  metadata, progress and search are unchanged.
