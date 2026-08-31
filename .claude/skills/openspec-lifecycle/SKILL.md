---
name: openspec-lifecycle
description: >
  Drive and enforce the OpenSpec change lifecycle: resolve the one root, ask the
  status gate which artifact is next, keep proposal, delta specs, design and
  tasks coherent, verify before archiving, and fail the gate when a change is
  half-planned. Use when the project keeps specs under an openspec/ or
  docs/openspec/ root, when a change is missing an artifact, when `openspec
  validate` passes but the work is not planned, or when the user asks to
  propose, apply, verify, sync or archive a change.
risk_level: medium
writes_files: true
requires_tools: [git]
license: MIT
metadata:
  version: "1"
---

# OpenSpec lifecycle

The reference is [`docs/workflows/openspec.md`](../../docs/workflows/openspec.md).
This skill is the procedure.

Two facts decide everything below:

- **The artifacts belong to a change, not to a capability.** A main spec under
  `<openspec>/specs/` is the contract as it stands. The plan (`design.md`), the
  delta and the task list live in `changes/<id>/`.
- **`openspec validate` and `openspec status` answer different questions.**
  Validate checks the files that are there. Status checks the files that should
  be. A change with a proposal and nothing else validates clean.

## 0. Resolve the root, once, out loud

```bash
node -e "const r=require('./agent-compass.commands.json').paths?.openspec; console.log(r||'(not declared)')"
```

Then confirm what the CLI itself resolves, and **run every `openspec` command
from the directory that holds the root** — it resolves the *nearest* one:

```bash
cd <dir holding openspec/> && openspec context
```

If two roots exist, stop and say so. An empty `openspec/changes/archive/` left by
a move captures resolution, and the CLI then answers `No changes exist` — which
reads as "this project has no in-flight work". Print the resolved root in your
handoff.

## 1. Ask the gate before you write

```bash
openspec list --json
openspec status --change "<name>" --json
```

Read `artifacts[]` (`done` / `ready` / `blocked` / `skipped`),
`isPlanningComplete`, `applyRequires`, `nextSteps`. Write **only** what is
`ready`. Then, per artifact:

```bash
openspec instructions <artifact-id> --change "<name>" --json
```

`context` and `operationGuidance` in that output come from the root's
`config.yaml`. Read both and apply them. Neither may unblock a blocked state or
override a CLI-controlled value; report a conflict rather than resolving it.

## 2. Match the workflow to the request

| The user wants | Run |
| -------------- | --- |
| To think, not build | `/opsx:explore` |
| A whole plan from a description | `/opsx:propose` |
| Only enough to start coding | `/opsx:ff` |
| The next artifact | `/opsx:continue` |
| An existing plan revised and made coherent | `/opsx:update` |
| The code | `/opsx:apply` |
| To know whether the code matches the plan | `/opsx:verify` |
| Main specs updated, change kept open | `/opsx:sync` |
| Done | `/opsx:verify`, then `/opsx:archive` |

If a workflow is missing, the project never ran `openspec update` after a CLI
upgrade. Say so and run it — `verify` and `continue` are the two whose absence
breaks the harness, and they are commonly the ones missing.

**A planning workflow never edits code**, even when the request that triggered it
asked for a feature. Finish the artifacts, stop, and let the user start apply.

## 3. Writing each artifact

| Artifact | Holds | Never holds |
| -------- | ----- | ----------- |
| `proposal.md` | Why, what changes, which capabilities, non-goals | A technical decision |
| `specs/<capability>/spec.md` | Requirements as user-observable behaviour, with scenarios | A class, framework or library name |
| `design.md` | The concrete approach, per platform, with versions | A requirement the spec does not state |
| `tasks.md` | Ordered, test-first tasks naming the file or command each touches | An estimate |

- Every requirement needs at least one scenario on the failure or offline path.
- Write `[NEEDS CLARIFICATION: question]` for an unknown. Never guess one.
- A change that adds and modifies no requirement declares `skip_specs: true` in
  `.openspec.yaml` **with the reason written beside it** — otherwise the next
  reader cannot tell a deliberate skip from a forgotten delta.

## 4. Applying

1. `openspec instructions apply --change "<name>" --json`, then read every path in
   `contextFiles`.
2. One task at a time. Run its validation. **Tick it in the same pass** —
   `- [ ]` → `- [x]`. A list ticked at the end is a claim, not a record.
3. When the implementation contradicts the design, the artifact is what is wrong.
   Stop and run `/opsx:update`. Do not absorb the delta into a bigger diff.
4. When a task needs work the spec does not describe, surface the added scope and
   ask. Never narrow, defer or except specified behaviour to make a task fit.

## 5. Before archiving

```bash
/opsx:verify <name>
```

Three dimensions, reported separately: completeness (tasks and requirement
coverage), correctness (requirement → code, scenario → test), coherence (the
design decisions the code actually follows). Fix or record every CRITICAL. Then
`/opsx:archive`, which is what updates the main specs — **never hand-edit a main
spec yourself**; the delta becomes unmergeable and the history is lost.

## 6. Enforce it

```bash
agent-compass openspec-guard . --strict
```

`root`, `chain`, `deltas`, `stale`, `workflows`, `ready`, `orphans`, `baseline`.
Put it beside `openspec validate --all` in the contract gate — not instead of it.
Grandfather anything that predates a new gate in `.openspec-guard.json`, with a
reason and a closing date; an entry that now passes fails the guard, so the file
drains.

## Report

Name the resolved root, the change, the artifacts you wrote, the status the gate
reported after, whether verify ran, and what the guard said. Follow the
Completion Gate in `AGENTS.md`.
