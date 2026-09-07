# StoryArc Constitution

Version: 1.0.0
Last amended: 2026-09-07

## Purpose

This file records the principles that a change must not break. A change that breaks one is
wrong even when it compiles and every test passes.

**[`AGENTS.md`](../AGENTS.md) is the authority.** This page states the same rules in the
shape `agent-compass doctor` looks for. Where the two disagree, `AGENTS.md` wins, and the
disagreement is a defect in this page. The template that `agent-compass` seeded here held
placeholder principles and the date `YYYY-MM-DD`. A constitution that states nothing true is
worse than none, because it is quoted.

## Principles

### 1. No cross-platform user interface

Every pixel is SwiftUI or Compose. StoryArc adds no web view, no shared interface
abstraction, and no cross-platform toolkit. Reflowable EPUB content is the single exception,
because that content is HTML by definition. See
[ADR-0001](../docs/decisions/0001-independent-native-cores.md).

### 2. No backend, no account, no analytics, no crash reporting

Data leaves the device only to a source that the reader configured. StoryArc runs no server
of its own.

### 3. Offline is a normal state

An unreachable source is grey, never red. The library stays browsable. A downloaded
publication stays readable.

### 4. Secrets go to the platform secure store

A secret never reaches preferences, logs, backups, or diagnostics. Redact a secret before any
string leaves memory.

### 5. The artwork is the interface

Chrome recedes, hides itself, and never tints the artwork.

### 6. Every behaviour is specified before it is built

The specs are at `docs/openspec/specs/`. Propose a change when the behaviour you are about to
build is absent from them. Never hand-edit a main spec: the archive step rewrites it, and a
hand edit is lost without a record.

### 7. A test that cannot fail is not a test

Revert the production line, run the test, and confirm it fails by name. Section 5 of
`AGENTS.md` names three guards that shipped and could never have failed.

### 8. No AI attribution

No commit, pull request, review, or issue carries an AI signature or a co-authorship line.

## Governance

- Amend this file by raising the version and adding a row to the history below.
- `AGENTS.md` outranks this page. A stricter rule there is the rule.
- Review this page when the product direction, the platform floor, or the validation gate
  changes.

## Amendment History

| Version | Date | Change |
| ------- | ---- | ------ |
| 1.0.0 | 2026-09-07 | Replaced the `agent-compass` placeholder with StoryArc's own principles, taken from `AGENTS.md` section 2. |
| 0.1.0 | 2026-09-07 | Seeded by `agent-compass` sync, with placeholder principles and no date. |
