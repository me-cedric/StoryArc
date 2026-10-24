---
name: remaining-work
description: Audit what the code delivers against the specs, then write the remaining-work backlog and the completion plan (CP view). Use when asked how far along the project is, what is left, or for a roadmap.
risk_level: low
writes_files: true
requires_tools: [git]
disable-model-invocation: true
---

# remaining-work

Measure what the code delivers, not what a status document reports.
The order is audit, plan, split, detail.

## Files

| File | Content |
|---|---|
| `docs/planning/audit/rows.jsonl` | One JSON row for each requirement |
| `docs/planning/audit/state.json` | The commit and the date of the last run |
| `docs/planning/completion-plan.md` | The CP view |

Row keys: `id`, `status`, `percent`, `evidence` (a `file:line`), `missing`, `date`.
`status` is `done`, `partial`, `skeleton`, `gap`, `gated` or `not_audited`.
The rows are the deliverable. Every percentage and every item comes from them. The report is a view of the rows.

## 1. Audit

1. Extract the requirements from `docs/openspec` with a script. Compare the total with the last count. A different total means that the extractor broke.
2. Map the code: modules, routes, jobs, tables and screens. Keep backend and frontend apart.
3. Rate each requirement. It is `done` only when the code is wired and tested.
4. A status document, a task checkbox, a type or a schema-only table is not proof. An API with no screen is not delivered.
5. `gap` means unbuilt. `gated` means blocked on a decision or a credential.
6. Run a second pass that tries to refute each `done`. It may lower a status. It may not raise one.
7. A claim with no `file:line` becomes `gap`. Open each cited `file:line` after the run.
8. An agent that returns no row leaves `not_audited`. Never average over missing rows.

Extraction traps:

- A duplicate id in one file is a redefinition. Keep the first position. The later text wins.
- Match every id prefix family. Match lower-case suffixes such as `-004b`.
- Take every table row whose first cell is a valid id. This includes appendices.
- Exclude a requirement only on a structured marker, never on prose.

## 2. Refresh

Audit again only what moved. Carry every other row forward with its original date.

1. These changes put a requirement back in scope: its text changed, it is new, or a file that its evidence cites changed.
2. New code that no row cites needs a discovery pass. Group it by directory. Ask whether it implements a `gap` requirement.
3. Name the pivot files, such as a root module or a shared schema. They inflate the scope.
4. Before a fan-out, state the scope and the cost in one line. Wait for a yes.
5. If nothing moved, say so and stop.
6. Report the movement: rows audited again, advances, regressions, the old and new percent. Separate fresh rows from carried rows.
7. Say that this is static analysis. Neither the app nor the tests ran.

## 3. Completion plan

Write `docs/planning/completion-plan.md` from the `gap` and `partial` rows.

1. Read the repository rules first. Each item cites the real rules that apply.
2. Write one item for each coherent unit of work. Use the id `CP-NNN`.
3. Each item has these fields: title, requirement ids, tier, what and why, plan, rules, ticket or `NO TICKET`, dependencies and gate. The plan names real files, endpoints, tables and jobs.
4. Order the items by dependency. Put foundations first, then the tiers.
5. End with two lists: the tracker delta (items with no ticket) and the gate register (item, what unblocks it, who approves).
6. Use `task-flow` to create tickets after the user says yes.
7. For a large scope, run one sub-agent for each domain. Merge the shared items into one foundation section.

## 4. Split

1. Give each owner a self-contained set of directories. One writer for each file.
2. Name each seam. The owner exposes a service and a contract. The consumer wires on top.
3. Put the shared foundations first.
4. Flag the largest overlap risk and say how to contain it.
5. Use `task-flow`, section "Assign by profile", to write the assignments.

## 5. Detail

Do this for one item, when the user asks for a build-ready plan.

1. Read the current code first. Every path and signature must be real.
2. Write these parts: objective, files, schema or migration, contracts, ordered logic and edge cases. Then add resilience and security, jobs, env vars, tests, ticket and dependencies.
3. For a missing credential or decision, build it now. Use these four parts:
   - A mock provider that is on by default.
   - Env vars on every surface.
   - A typed error when the secret is absent.
   - One switch from mock to live.

Do not commit.
