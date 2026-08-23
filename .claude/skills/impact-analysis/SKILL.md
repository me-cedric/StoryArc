---
name: impact-analysis
description: >
  Analyse what changed since a base git reference and produce the developer
  action plan — technical impacts, blast radius, and the exact project documents
  that are now stale. Use when the user asks for the impact of a change, what a
  branch breaks, what a diff affects, which docs to update after a change, or a
  technical action plan before merging.
risk_level: low
writes_files: true
requires_tools: [git]
license: MIT
metadata:
  version: "1"
---

# Impact analysis

Answer one question for the team: **given what changed, what else has to change?**

The output is the developer-facing half of the delivery flow. Its twin is
[`delivery-digest`](../delivery-digest/SKILL.md), which says the same thing to a
Product Owner. Never mix the two audiences in one file.

## Paths

This skill uses the default compass layout below. When the host project puts an
artifact somewhere else, use the host path and say so in the report.

| Artifact | Default path |
| --- | --- |
| Specs | `specs/` |
| Decisions | `docs/decisions/` |
| Delivery outputs | `docs/delivery/` |

## Read the change first

```bash
git diff --stat <base>...HEAD    # committed work
git status --short               # work in progress
git diff <base>                  # the actual patch
```

`<base>` is whatever the user names (a branch, a tag, `HEAD~5`). If they do not
name one, ask — guessing the base makes every number in the report wrong.

**Never claim an impact you have not opened the file to confirm.** A grep hit is
a lead, not a finding.

## The seven impact axes

Walk all seven. Report `none` explicitly for the ones that came back empty —
a silent axis reads as "not checked".

1. **Behaviour** — what a user or a caller can now do, or can no longer do.
   Breaking changes get their own line.
2. **Contracts** — API routes, methods, status codes, payloads, DTOs, shared
   types, events, queue message shapes. Any consumer of a changed contract is an
   impact even if its own files are untouched. See
   [`api-contract-sync`](../api-contract-sync/SKILL.md).
3. **Data** — schema changes, migrations, backfills, indexes, retention. Say
   whether the migration is reversible.
4. **Configuration** — env vars, feature flags, secrets, infrastructure values.
   An added variable must land on every surface: validation schema, `.env`
   example, deployment config. See
   [`env-var-sync`](../../knowledge/instincts/env-var-sync.md).
5. **Security & privacy** — authn/authz, ownership checks on by-id paths, input
   validation, injection surface, logging of sensitive values, new dependencies.
6. **Operations** — build, CI, deployment order, rollback path, observability
   (does a new failure mode have a signal?).
7. **Delivery artifacts** — the documents listed below.

## Documents to check for staleness

For each, state `up to date`, `stale — <what to change>`, or `not affected`.

| Artifact | Default path | Goes stale when |
| --- | --- | --- |
| Specs | `specs/` | behaviour changed, or a requirement is now implemented |
| Decisions | `docs/decisions/` | a choice was made or reversed that no ADR records |
| API contracts | the OpenAPI source and request collection | any route, payload, status code or auth rule moved |
| Data models | `docs/data-models/` | a table, column, relation or enum changed |
| Diagrams | `docs/diagrams/` | a component, container or dependency appeared or vanished |
| Network flows | `docs/infra/network-flows.json` | a new port, protocol, source or destination is required |
| Design system | `design.md` | tokens, components or UI rules changed |
| Assignments | `docs/delivery/assignments.json` | scope moved between profiles, or a gate cleared |
| Module docs | `**/README.md`, `**/DESIGN.md` | a module's public API, files or configuration changed |

## Output

File: `docs/delivery/impacts/<YYYY-MM-DD>-<kebab-slug>.md`

```markdown
---
title: <one line, what this change is>
date: <YYYY-MM-DD>
base: <the base reference>
audience: dev
---

# <title>

## Change set

<n> files, +<insertions> / −<deletions>. Commits: <n>.
One line per meaningful group of files — not a file listing.

## Impacts

### Behaviour
### Contracts
### Data
### Configuration
### Security & privacy
### Operations

Each axis: findings, or `None.`

## Documents to update

| Document | State | Action |
| --- | --- | --- |

## Action plan

Ordered checklist. Each item names a file or a command, and an owner profile
when `docs/delivery/assignments.json` says who owns that scope.

- [ ] …

## Risks

What could still break, and how you would notice.

## Validation

The commands that prove this change works, and their result:
`passed` | `failed` | `partial` | `not run` + reason.
```

## Rules

- Order the action plan by dependency, not by severity. A blocked item first is
  a stalled plan.
- An item nobody can act on is a **risk**, not a task.
- If the diff is truncated, say so and name what you did not read.
- Do not fix anything from this skill. It produces the plan; a separate task
  executes it.
- Do not commit or push. The user commits.
