## Why

`ac check` (agent-compass 1.0) runs `openspec validate --all --strict`, and CLI 1.14.3 turns
three warnings into failures: a requirement whose text before its first scenario is longer
than 500 characters, a requirement with no SHALL or MUST, and a task ID declared twice.
Twelve main-spec requirements failed. The project's own lint validates without `--strict`,
so nothing caught them.

## What Changes

- **No behaviour changes.** Every normative clause and every scenario is kept word for word.
- Ten requirements move their examples, tables and edge cases into scenarios, or their
  rationale below the scenarios, so the requirement text states the behaviour in fewer than
  500 characters: comic-reader *Auto-hiding chrome*, kavita-server *Kavita connection*,
  library-browsing *Unified library* and *Presentation*, native-experience *Chrome for a
  mode a reader is in*, publication-formats *Supported formats* and *Streaming capability
  per format*, reading-progress *Resuming*, reading-themes *Theme presets* and *Theme axes*.
- network-share *Discovery* and ebook-reader *Reading aloud* say SHALL instead of SHOULD.
  Both are built on both platforms (`STATUS.md`), so SHOULD understated them.
- The active changes that MODIFY or ADD the same requirements carry the same edit, so their
  archive does not bring the long text back (`pnpm delta:drop` passes).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

comic-reader, ebook-reader, kavita-server, library-browsing, native-experience,
network-share, publication-formats, reading-progress, reading-themes: wording only.

## Impact

`docs/openspec/specs/` only, through this change's archive. No code, no test.
