# @storyarc/test-fixtures

The shared publication corpus. Both test suites read the same files and assert
the same expected parse.

This is the mechanism that keeps two independent implementations
([ADR-0001](../../docs/decisions/0001-independent-native-cores.md)) honest. Two
codebases can drift; two codebases asserting the same fixture against the same
expectation drift loudly.

## Layout

```
packages/test-fixtures/
├── scripts/generate.py    the generator — fixtures are generated, not hand-authored
├── manifest.json          every fixture and what a correct parse yields
└── comics/                8 archives, 6.5 kB total
```

## Status

**8 comic archives, covering the ZIP path.** EPUB, PDF, RAR, 7-Zip and TAR
fixtures land with their format work.

| Fixture | Pins |
| --- | --- |
| `natural-sort.cbz` | page10 sorts after page9, not after page1 |
| `nested-chapters.cbz` | pages order by full path, so ch10 follows ch2 |
| `non-image-entries.cbz` | `ComicInfo.xml`, `Thumbs.db`, `.DS_Store` and `__MACOSX/` resource forks are never pages |
| `mislabelled-zip.cbr` | a ZIP named `.cbr` opens — format comes from content |
| `single-page.cbz` | a one-page publication does not divide by zero |
| `double-page-spread.cbz` | a wide image is one spread, not two pages |
| `truncated.cbz` | a damaged archive fails cleanly rather than crashing |
| `no-pages.cbz` | an archive with no images reports zero pages, not an error |

## Generated, then committed

```bash
python3 scripts/generate.py           # rewrite comics/ and manifest.json
python3 scripts/generate.py --check   # fail if the committed output is stale
```

Fixtures are **generated** so they are reproducible from a readable script,
legally clean, and tiny — every page is a 2×3 procedurally-coloured PNG, so there
is no real artwork anywhere in the repository. The output is then **committed**,
so neither test suite needs Python to run. Same generate-then-commit pattern as
the design tokens.

**They are not byte-identical across machines.** DEFLATE output differs between
zlib builds, so regenerating on another machine produces different bytes for the
same logical fixture. That is why `manifest.json` records **no hashes and no file
sizes** — either would make the staleness check machine-specific and therefore
useless. Git pins the archives' bytes; the manifest pins their *meaning*, and
`--check` compares only that. `--check` never writes, so it cannot itself cause
the drift it is looking for.

Colours are distinct per page index, so a wrong page order is visible rather
than merely failing an assertion.

## Rules for a fixture

1. **Small.** Single-digit kilobytes where possible; a 200-page comic is not
   needed to prove page ordering. The repository must not become a comic
   library.
2. **Legally clean.** Public-domain or self-generated artwork only. Never a real
   commercial publication, not even for a private test.
3. **Deliberate.** Every fixture exists to pin one behaviour. Name it after that
   behaviour — `natural-sort-page10-after-page9.cbz`, not `test3.cbz`.
4. **Documented.** `manifest.json` records the expected page count, page order,
   metadata, reading direction and cover for each one. Both suites read it, so
   neither can quietly disagree about what correct means.
5. **The malformed ones are the point.** A truncated archive, a broken central
   directory, a `ComicInfo.xml` with a bad encoding declaration, an EPUB with a
   spine referencing a missing item. `publication-formats` requires the app to
   open what it can and say what it skipped — that requirement is only real if a
   fixture proves it.

## How the two suites consume it

Both read `manifest.json` and assert against the **same** recorded expectations,
which is the mechanism that makes divergence loud:

| Platform | Locates the corpus by | Test |
| --- | --- | --- |
| iOS | walking up from `#filePath` — SPM cannot declare a resource outside its package root | `Tests/FormatsTests/ComicArchiveTests.swift` |
| Android | a `storyarc.fixtures` system property set by `core/format/build.gradle.kts`, with a walk-up fallback for IDE runs | `core/format/src/test/.../ComicArchiveTest.kt` |

Neither copies the files. One corpus, two readers.
