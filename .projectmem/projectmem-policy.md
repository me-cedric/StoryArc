# Project Memory Policy

Use `projectmem` for durable project memory when available.

## Shared Vs Local

projectmem is event-sourced: `events.jsonl` is an append-only log (the source of
truth) and every other file is a projection rebuilt from it by `pjm regenerate`.
Share the log, not the projections — a regenerated file cannot be git-merged and
the last writer silently overwrites the others.

- **Shared (committed):** `.projectmem/events.jsonl`. Appends from different people
  merge cleanly; `.gitattributes` gives it `merge=union` so concurrent appends
  auto-combine instead of conflicting. Because the log now crosses into git, the
  secrets/PII/local-path review applies to it.
- **Local (gitignored, rebuilt on demand):** `.projectmem/summary.md`,
  `PROJECT_MAP.md`, `AI_INSTRUCTIONS.md`, `issues/`, plus watch files, data
  directories, and DB files. Never commit these — run `pjm regenerate` to rebuild
  them from the merged log.
- **After every `git pull`/merge:** run `pjm regenerate` to fold teammates' events
  into your local summary. (The vendored `post-merge` hook does this automatically.)
- **Known limit:** projectmem mints sequential issue ids (`0042`). Two people
  working offline can mint the same id; the union merge keeps both lines, but a
  later `pjm fix --issue`/`--supersedes` referring to that id may be ambiguous.
  Rare for small teams.
- Backfill is opt-in. It can create many legacy issue files.

## Durable Decisions Go In Notes, Not The Log

The event log is a high-churn running record. For knowledge that must survive and
stay readable — architecture and design decisions — write a committed, one-file
note instead of relying on the regenerated summary: an ADR under
`docs/decisions/NNN-*.md` (one decision per file merges without conflict).

## Before Starting

- Read relevant projectmem summaries.
- Check pre-action warnings before editing fragile areas.
- Search memory for related files, modules, libraries, and previous errors.

## During Work

- Log failed attempts immediately.
- Log important findings when discovered.
- Log fragile files or risky areas when discovered.

## After Work

- Log decisions.
- Log fixes.
- Log files changed.
- Log validation commands and results.
- Log remaining risks.

## Never Log

- secrets
- tokens
- credentials
- private keys
- personal data
- temporary brainstorming
- stale todo noise

Keep entries concise, factual, and useful for future agents.
