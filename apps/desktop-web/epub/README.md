# The desktop EPUB bundle

The one JavaScript renderer the three desktop web views load: `WKWebView` on macOS,
WebView2 on Windows, WebKitGTK on Linux ([ADR-0018](../../../docs/decisions/0018-desktop-clients.md)
D6, [design.md](../../../docs/openspec/changes/desktop-clients/design.md) Decision 6). It is
`@readium/navigator` and `@readium/shared` from [readium/ts-toolkit](https://github.com/readium/ts-toolkit),
pinned to exact versions and built with Vite into one file whose digest is recorded, the way
libarchive's sources are.

This directory is **its own pnpm root**. It is not a member of the repository workspace:
the root's `packages/*` glob does not match it, and its own `pnpm-workspace.yaml` stops pnpm
climbing to the root (which it otherwise does, and then installs the root workspace instead
of this one). Nothing at the root depends on it; it depends on nothing at the root.

## Files

| File | What it is |
| --- | --- |
| `package.json` | The two exact pins and `vite`, also exact. `packageManager` matches the root. |
| `pnpm-workspace.yaml` | Marks this directory as a pnpm root and holds the `@readium/shared` override (see below). |
| `pnpm-lock.yaml` | This directory's own lockfile. |
| `vite.config.js` | Library build, one IIFE file, no chunks, no CSS, no source map, the BSD notice as a banner. |
| `src/index.js` | The entry. Wave 1 exposes both packages whole as `StoryArcEpub.navigator` and `StoryArcEpub.shared`; the host glue is tasks 4.1 and 4.2. |
| `dist/storyarc-epub.js` | The built file, **committed**, because the three desktop builds embed it and none of them runs node. |
| `pin.json` | The versions, the licence, and the sha256 of the built file. |
| `check-pin.mjs` | The alarm: `--check`, `--write`, `--self-test`. Task 1.32 wires `--check` into `pnpm lint`. |
| `test/egress.html` | The eight-vector egress page of [ADR-0015](../../../docs/decisions/0015-epub-webview-network-egress.md), ported from the iOS suite. |
| `test/collector.mjs` | The loopback listener the page aims at; serves the page, counts arrivals per vector, `--self-test`. |

## Commands

Run from this directory. `pnpm` self-selects 11.20.0 from `packageManager`.

| Purpose | Command |
| --- | --- |
| Install | `pnpm install --frozen-lockfile` |
| Build the bundle | `pnpm build` |
| Check the pin (offline, no install needed) | `node check-pin.mjs` or `pnpm check` |
| Prove the check can fail | `node check-pin.mjs --self-test` |
| Record a new digest after a bump | `node check-pin.mjs --write` |
| Run the egress collector and open the page | `pnpm egress`, then open the URL it prints |
| Prove the collector counts | `pnpm egress:selftest` |

## The pin

`pin.json` is the record. `check-pin.mjs --check` fails when `package.json` does not pin
exactly what `pin.json` names (a range counts as a failure), when `pnpm-lock.yaml` resolves
anything else or more than one copy of either package, or when `dist/storyarc-epub.js` does
not digest to the recorded sha256. The build is reproducible: two builds from the same
lockfile gave the same digest on 2026-10-16.

To bump: edit the versions in `pin.json` and `package.json` together, then
`pnpm install`, `pnpm build`, `node check-pin.mjs --write`, and commit all five files. Then
run `/opsx:update` on the change, because design.md names the versions too.

**One copy of `@readium/shared`.** `@readium/navigator` 2.11.1 declares `@readium/shared`
2.6.0, one minor behind the 2.7.0 the design pins. Left alone, the bundle would carry both,
and a `Locator` built through the host-facing 2.7.0 would not be the class the navigator
checks. `pnpm-workspace.yaml` overrides `shared` to 2.7.0 for the whole graph; the 2.6.0 to
2.7.0 diff is additive (tokenizers and guided navigation), read with `npm diff`. The check
fails if the lockfile ever resolves a second copy.

## Licence

Both packages are BSD-3-Clause, Copyright (c) 2022, Readium Foundation. The licence requires
the notice to travel with the binary, and the bundle is the binary, so `vite.config.js` reads
the installed `LICENSE` and prepends it as a `/*!` banner that the minifier keeps. The
repository inventory at `packages/licences/notices.json` (which generates
`THIRD_PARTY_NOTICES.md`) needs one entry for this bundle; it is not written from this
directory.

## The egress proof

ADR-0015 denies a publication every way out of the web view, and the proof is the same on
every desktop: a page tries eight ways out at once — a tracking pixel, a scripted image,
`fetch`, `XMLHttpRequest`, `sendBeacon`, a `WebSocket`, an `<iframe>` and a top-level
navigation — each at its own path on a loopback collector, so a run names what escaped. The
page always reports eight attempts. The arrivals are the collector's count, because a page
cannot tell "blocked" from "nobody listening".

In any browser, `pnpm egress` then open `http://127.0.0.1:4815/egress.html`: it reports 8 of
8, which is the control. Inside a web view that denies egress the page cannot reach the
collector either, so it says so and the host reads `GET http://127.0.0.1:4815/count` itself.
Zero is the pass. The page accepts `?collector=<origin>` when it is served from somewhere
other than the collector, such as the app's own scheme.

The navigation vector leaves the page two seconds in; the collector answers it with a
redirect back carrying the run's id, and the page then reports instead of firing again.
