---
name: project-memory
description: >
  Use when a project has projectmem or durable agent memory. Reads memory before
  work, checks pre-action warnings, and records durable findings, failed
  attempts, decisions, fixes, validation, and risks.
license: MIT
compatibility: projectmem
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: "[before|during|after]"
risk_level: medium
writes_files: false
requires_tools: []
---

# Project Memory

Use projectmem for durable project memory when available.

## Before Starting

Run or request the projectmem equivalent:

```bash
pjm regenerate   # after a pull/merge: fold teammates' shared events into the log
pjm brief
pjm precheck
```

Also search memory for relevant files, modules, libraries, and errors when the
task is non-trivial.

## Shared Vs Local (collaborative repos)

`events.jsonl` is the committed, union-merged source of truth. The projections
(`summary.md`, `PROJECT_MAP.md`, `AI_INSTRUCTIONS.md`, `issues/`) are gitignored
and rebuilt by `pjm regenerate`. Never commit a projection — committing a
regenerated summary silently overwrites teammates.

## During Work

Log:

- failed attempts immediately
- important findings when discovered
- fragile files or risky areas
- reusable library or tooling gotchas

## After Work

Log:

- decisions
- fixes
- files changed
- validation commands and results
- remaining risks

For durable architecture/design decisions, also write a committed ADR under
`docs/decisions/NNN-*.md` (one file per decision merges cleanly) — don't leave
them only in the regenerated summary.

## Never Log

Do not log secrets, tokens, credentials, personal data, raw customer data, or
temporary brainstorming.

If projectmem is unavailable, continue the task and report memory logging as
`not run` with the reason.
