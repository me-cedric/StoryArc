# Tasks

This change amends one specification requirement. It writes no application code,
so no task here owes a screenshot from a simulator or an emulator.

A tick means the file the task names holds what the task describes, and that a
test or a published specification proves it. A tick does not mean the change is
synced: the main spec still holds the old clause until `/opsx:sync` runs.

## 1. Prove the version floor cannot be fed

- [x] 1.1 Read Kavita's published `openapi.json` at v0.8.6, v0.8.8, v0.8.9.1,
  v0.9.0 and v0.9.1.4. `/api/Server/server-info` is absent from all five.
- [x] 1.2 Look for any other route that states a version. `/api/Server/version`,
  `/api/Health/api-version` and `/api/Server/accepting-connections` are absent
  from all five. `/api/Server/server-info-slim` is present and needs an
  administrator. `/api/Health` is present and carries no version.
- [x] 1.3 Confirm the verbs of every route either client calls are the same
  across the five, so a version number would decide nothing.

## 2. Prove the code already stopped asking

- [x] 2.1 Read the assertion before the code. `KavitaClientTests.swift:22` adds a
  server that answers 404 to every route but the token route, and
  `KavitaClientTests.swift:37` asserts the sent paths are
  `["/api/Plugin/authenticate"]` and nothing more.
- [x] 2.2 Read the matching Android assertions. `KavitaTest.kt:220` and
  `KavitaTest.kt:231` make the same two claims against a loopback server.
- [x] 2.3 Read `connect()` on both platforms. `KavitaClient.swift:126` and
  `KavitaClient.kt:83` each authenticate and return.
- [x] 2.4 Confirm no client sends the deleted route. `/usr/bin/grep -rn -F
  "server-info"` over the repository finds it in comments and in the mock's 404
  assertion only.

## 3. Prove the replacement is reachable and translated

- [x] 3.1 Read the 404 rule. `sendVersioned(_:path:)` at
  `KavitaClient.swift:85` maps a 404 to `routeMissing` and remembers the path.
- [x] 3.2 Read where the sentence is drawn. `KavitaConnection.swift:131` on iOS;
  `KavitaMessage.kt:31` and `KavitaConnection.kt:182` on Android.
- [x] 3.3 Confirm the sentence exists in en, fr, de and es on both platforms.
  `Localizable.xcstrings:3357` and `values*/strings.xml` hold all four.

## 4. Write the amendment

- [x] 4.1 Rewrite *Adding a server* so it names the account and nothing else, and
  says the app asks the server nothing more.
- [x] 4.2 State in the requirement prose that the app asks no server for its
  version, and that an unknown route is what raises the "too old" sentence. The
  prose carries it because only `specs/**` reaches the main spec on sync.
- [x] 4.3 Carry *Pasting a full OPDS URL*, *Session token expires* and *API key
  revoked* word for word, so no clause is dropped when the delta merges.
- [x] 4.4 Run `pnpm delta:drop` and read what it says about this delta.

## 5. Keep the status document honest

- [x] 5.1 Name this change in the `kavita-server` row of
  `docs/openspec/STATUS.md`, and say the main spec still holds the old clause
  until this change syncs.
- [x] 5.2 Correct the row's count of the mock's verb table. Measure it with
  `sed -n '/^const ROUTES = \[/,/^\]/p' scripts/kavita-server.mjs |
  /usr/bin/grep -c "at:"`.

## 6. Left open

- [ ] 6.1 **Sync this delta.** Run `/opsx:sync`, then `/opsx:archive`. Until then
  `docs/openspec/specs/kavita-server/spec.md:19-20` still asks for the version
  floor, and a reader of the main spec alone will not know it is amended.
- [ ] 6.2 **Two routes stay wrong, on purpose.** `Reader/mark-chapter-unread` is
  in none of the five specs and `Reader/mark-chapter-read` starts at 0.9.0.
  Measure a replacement against a live server before changing either. Guessing a
  write shape is the mistake this capability already made twice.
