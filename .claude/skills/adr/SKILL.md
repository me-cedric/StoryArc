---
name: adr
description: Write a MADR 4 decision record from a meeting transcript, call notes or a decision made in chat. Keeps the rejected options and the reasons. Use when the user asks to record or capture a decision.
risk_level: low
writes_files: true
requires_tools: []
disable-model-invocation: true
---

# adr

Record a decision that is structural and costly to undo: architecture, a shared contract, data ownership, build or buy, a cross-cutting convention.
Skip a local choice that the code already shows.
For the architecture of a new project, use `architecture-advisor`.

## Steps

1. Find `docs/decisions`. Create it if it does not exist.
2. Use the template in that directory when one exists. Its name starts with `template` or `adr-template`. Else use the shape below.
3. Take the next number: the highest `NNNN` plus one, in four digits. Name the file `NNNN-kebab-title.md`.
4. Extract from the source. Do not invent. Take the problem, the forces, each option, its pros and cons, the choice, the reasons and the follow-ups.
5. Attribute nothing that the source does not support.
6. Keep every rejected option with the reason that it lost.
7. Set `status: proposed`. Set `accepted` only when the meeting ratified the decision.
8. Set `date` to the meeting date. Fill `decision-makers`, `consulted` and `informed` only from the source.
9. Write each gap as an open question or a follow-up under Consequences.
10. Link both ways. Link the module README or design note to the ADR. Link the ADR to the spec, the issue and the PR.
11. Report the path and a one-line summary.

## Shape (MADR 4)

```markdown
---
status: proposed
date: <YYYY-MM-DD>
decision-makers: []
---
# <short title>
## Context and problem statement
## Decision drivers
## Considered options
## Decision outcome
Chosen option: "<option>", because <reason>.
### Consequences
## Pros and cons of the options
## More information
```

## Rules

- Fill every section, or write `N/A`.
- Supersede, never rewrite. A reversed decision gets a new ADR. Change the status of the old ADR to `superseded by NNNN`.
- Change an `accepted` ADR only in its status.
- Do not commit.
