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
├── manifest.json          every fixture, its properties, and what a correct parse yields
├── comics/                CBZ, CBR, CB7, CBT
├── ebooks/                EPUB 2, EPUB 3, fixed-layout
├── pdf/                   text-layer and scanned
└── malformed/             the ones that matter most
```

## Status

**Empty.** The corpus is created with the format layer, alongside
[ADR-0005](../../docs/decisions/0005-format-and-rendering-libraries.md)'s spike.

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

## Generating, not committing

Where a fixture can be generated deterministically from a script, prefer that to
committing a binary. `scripts/` will hold the generators once the corpus exists.
