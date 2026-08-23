---
name: spec-to-tickets
description: >
  Write the tracker ticket text for one specification section — summary, short
  why, acceptance criteria taken from the words of the spec, and the link back.
  Use when the user asks to turn a spec or a requirement into a ticket, to draft
  a Jira story from a specification, to write acceptance criteria for a
  requirement, or to review proposed ticket text.
risk_level: low
writes_files: true
requires_tools: []
license: MIT
metadata:
  version: "1"
---

# Spec to tickets

Write the **text** of a ticket from one section of a specification. A separate
tool sends that text to the tracker (Jira Cloud REST v2, or the tracker the
project uses). You never call the tracker API from this skill.

## What the sync tool does, and what you do

The sync tool plans and applies. It writes a plan file —
`docs/delivery/tickets.plan.json` — from the costing sheets and the assignment
document, a human approves the operations, and the tool sends them. Read the plan
file to see the exact summary and description that go out.

You write the words: the summary, the short why, and the acceptance criteria.
Nothing else in this skill asks you to touch the network.

When the project has no sync tool, the same rules apply and a human copies the
text into the tracker. Do not create tickets over an API on your own initiative.

## Read before you write

1. The specification section, under `specs/`. Read the whole section.
2. The costing task and the assignment item that reference it, so the ticket
   matches the work that was estimated.
3. `docs/delivery/tickets.config.json`, for the project and the field names.
4. `docs/delivery/tickets.json`, the registry, to see if a ticket exists.

If the specification section is unclear, ask. Do not fill a gap with a guess.

## The summary

One line, in the vocabulary of the team. Keep it below 255 characters, because
Jira refuses a longer summary.

| Write | Do not write |
| --- | --- |
| the user-visible outcome | the file name or the module |
| the actor, when the spec names one | a phase name such as "Sprint 2" |
| a verb in the active voice | a ticket type such as "Story:" |

Examples. Good: `Import a supplier price list from a CSV file`. Bad:
`CSV importer (backend)`.

## The description

Four blocks, in this order. Keep each block short.

1. **Why** — one or two sentences. The value, not the method.
2. **Acceptance criteria** — a checklist, each line testable.
3. **Steps** — the first steps from the assignment item, if there are any.
4. **Spec** — the link back.

The description is **not** a copy of the specification. Two copies of one
requirement always diverge. Write the criteria and link to the source.

## Acceptance criteria come from the words of the spec

Take each criterion from a sentence that is already in the specification. Keep
the nouns and the verbs of that sentence. Change the grammar only.

Specification: *The system rejects a price list whose currency column is empty.*
Criterion: `A price list with an empty currency column is rejected.`

Rules:

1. One criterion for each requirement or scenario in the section.
2. No criterion without a sentence behind it in the specification.
3. No performance number, no volume, and no deadline that the spec does not give.
4. If a criterion needs a value the spec does not state, write the criterion and
   mark the missing value `[NEEDS CLARIFICATION]`.

**Invent no scope.** An error case, a migration, a permission rule, or a screen
that the specification does not name belongs in a question, not in a ticket. Use
[`harvest-questions`](../harvest-questions/SKILL.md) for those.

## Always link back

Every ticket carries a `specRef`: the repository path of the specification
section, such as `specs/billing/spec.md`. The sync tool turns that path into a
URL with the base in `tickets.config.json`.

The link is never pinned to a commit. A pinned link changes on every commit and
re-fingerprints every ticket.

A ticket with no `specRef` is refused. That guard belongs in the sync tool, not
in this skill.

## What never goes in a ticket

| In the ticket | In the repository |
| --- | --- |
| summary, why, acceptance criteria | the specification itself |
| the spec link | estimates, rates, personas |
| estimate, assignee, labels | gates, seams, scope decisions |

Rates, day counts per profile, and internal disagreements stay in the repository.
A tracker project usually has a wider audience than the repository.

## Do not do these

- Do not create a second ticket for a key the registry already holds.
- Do not propose a status transition. The sync tool never writes one.
- Do not propose a deletion. There is no delete call, by design.
- Do not edit `tickets.json` by hand. The sync tool owns the registry.
