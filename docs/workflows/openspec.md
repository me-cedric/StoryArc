# OpenSpec

Use this when the project keeps its specifications under an
[OpenSpec](https://github.com/Fission-AI/OpenSpec) root — `openspec/`,
`docs/openspec/`, or whatever `agent-compass.commands.json` declares as
`paths.openspec`.

OpenSpec is not a different philosophy from
[spec-driven-development](spec-driven-development.md). It is the same chain with
a different home for the artifacts, and a CLI that can answer *which artifact is
missing* — which is the part a spec-kit layout leaves to a human.

## The vocabulary, mapped

| Spec Kit / compass native | OpenSpec | Lives at |
| ------------------------- | -------- | -------- |
| — | `proposal.md` | `changes/<id>/proposal.md` |
| `spec.md` | delta specs | `changes/<id>/specs/<capability>/spec.md` |
| `plan.md` | `design.md` | `changes/<id>/design.md` |
| `tasks.md` | `tasks.md` | `changes/<id>/tasks.md` |
| `checklist.md` | the `verify` workflow, or a forked schema | see **Adding a checklist gate** |
| the settled spec | main specs | `specs/<capability>/spec.md` |

**The difference that matters:** under OpenSpec the plan, the delta and the tasks
belong to **the change that produced the behaviour**, not to the settled
capability. A main spec is the contract as it stands now; it carries no plan and
no task list, and adding them beside it invents documents nobody updates. Ask
"which change is this work part of", never "where is this capability's plan".

## The lifecycle

Twelve workflows ship with the CLI. `openspec update` installs them for every
agent the project configures — as `/opsx:<name>` slash commands, provider
prompts, and skills.

| Workflow | Does | Writes code |
| -------- | ---- | ----------- |
| `/opsx:explore` | Thinking partner. Maps the problem, may capture artifacts. | never |
| `/opsx:new` | Scaffolds the change directory, one artifact at a time. | never |
| `/opsx:propose` | Scaffolds **and** writes every planning artifact in one pass. | never |
| `/opsx:ff` | Fast-forward: everything needed to start implementing. | never |
| `/opsx:continue` | Writes the **next** artifact the status gate names. | never |
| `/opsx:update` | Revises existing artifacts and keeps them coherent. | never |
| `/opsx:apply` | Implements the tasks, ticking each as it passes. | yes |
| `/opsx:verify` | Completeness / correctness / coherence report. | never |
| `/opsx:sync` | Merges delta specs into the main specs, no archive. | never |
| `/opsx:archive` | Finalises: main specs updated, change moved to `archive/`. | never |
| `/opsx:bulk-archive` | Several completed changes at once. | never |
| `/opsx:onboard` | Guided first cycle, narrated. | yes |

Planning workflows do not edit code even when the request that triggered them
asked to build something. That boundary is in the workflow text, and it is the
reason a proposal never quietly becomes an implementation.

## The status gate

This is the primitive the whole harness rests on:

```bash
openspec status --change "<name>" --json
```

Every artifact comes back with a status, and the schema's `requires` edges decide
it:

| Status | Means |
| ------ | ----- |
| `done` | The artifact exists. |
| `ready` | Its dependencies are met. Write it next. |
| `blocked` | An upstream artifact is missing. `missingDeps` names it. |
| `skipped` | Deliberately declared unnecessary (for example `skip_specs: true`). |

Plus `isPlanningComplete`, `isComplete`, `applyRequires`, and `nextSteps`.

**`openspec validate` and `openspec status` answer different questions.** Validate
asks whether every file present is well-formed. Status asks whether the files that
should be present are. A change holding a proposal and nothing else validates
clean — which is exactly how a half-planned change sits in a repository for weeks
while the gate stays green.

Two more commands complete the picture:

```bash
openspec instructions <artifact|apply|archive> --change "<name>" --json
openspec doctor          # relationship health for the resolved root
openspec templates       # the resolved template path per artifact
openspec schemas         # available workflows, project ones included
```

`instructions` returns `contextFiles` (artifact id → real paths), task progress,
the dynamic instruction, and two project-supplied fields — `context` and
`operationGuidance` — read from the root's `config.yaml`. Neither may override a
CLI-controlled value or unblock a blocked state.

## The one root rule

The CLI resolves the **nearest** `openspec/` from its working directory. A second
root anywhere above or below the real one silently captures resolution: the tool
reports `No changes exist`, and an agent that trusts the answer concludes the
project has no in-flight work.

An empty `openspec/changes/archive/` left behind by a move is enough to do it.
Declare the real root and delete the other:

```json
{ "paths": { "openspec": "docs/openspec" } }
```

See the [`one-artifact-root`](../../knowledge/instincts/one-artifact-root.md)
instinct. `openspec-guard` fails on a second root.

### A root outside `<project>/openspec` breaks the installer

`openspec update` — the command that writes the twelve workflow files — requires the
root at `<project>/openspec` **and** reads the agent directories (`.claude/`,
`.github/`, …) from that same `<project>`. A project that keeps the root at
`docs/openspec` and its agent directories at the repository root satisfies neither
position: from `docs/` the CLI finds the root and no agents, from the root it finds
the agents and no root.

The failure is silent and cumulative. It prints `No configured tools found`, and the
workflows stop being refreshed — one host had six of the twelve missing, `verify` and
`continue` among them, since the day the root moved.

Two ways out, and the guard's `workflows` check tells you it is happening either way:

1. **Keep the root at `<project>/openspec`** so `openspec update` works. Simplest.
2. **Generate the files from the installed package**, and check them in the gate. Each
   `dist/core/templates/workflows/*.js` module exports a skill template and a
   slash-command template; render them to the paths the CLI would use and add a
   `--check` mode. The content stays the vendor's, and a CLI upgrade that changes a
   workflow then fails the build instead of leaving the host a version behind.

## config.yaml is the injection point

Rules written in the root's `config.yaml` reach the agent through
`openspec instructions`, at the moment it writes that artifact — which is far more
effective than the same rule sitting in `AGENTS.md`:

```yaml
schema: spec-driven

context: |
  Hard constraints on every proposal…

rules:
  proposal:
    - State which platforms the change affects. "Both" is an answer; silence is not.
  specs:
    - Requirements describe user-observable behaviour. No framework or library names.
    - Every requirement needs at least one scenario covering the failure path.
  design:
    - Name the concrete library and version per platform. Label anything unverified.
  tasks:
    - A task that changes a screen owes a device screenshot, not a preview.

operations:
  apply:
    guidance:
      - Run the lint, typecheck and test commands from agent-compass.commands.json.
  archive:
    guidance:
      - Run /opsx:verify first. Do not archive on a task list alone.
```

`templates/specs/openspec-config.example.yaml` is a starting point.

**Quote any list item containing `": "`.** An unquoted colon makes YAML read the item
as a nested mapping, the whole document fails to parse, and the CLI's answer is
`No changes exist` — which reads as an empty project rather than as a syntax error.
`- 'Write "[NEEDS CLARIFICATION: question]" for an unknown.'`, with the quotes. A rule
filed under a `rules` group that is not an artifact id is never delivered at all. The
guard's `config` check covers both.

## Enforcement

```bash
agent-compass openspec-guard .            # report
agent-compass openspec-guard . --strict   # warnings fail too
agent-compass openspec-guard . --json
```

| Code | Fails when |
| ---- | ---------- |
| `root` | Two OpenSpec roots exist. |
| `config` | `config.yaml` has a list item with an unquoted `": "`, or a `rules` group that is not an artifact id. |
| `chain` | An active change is missing an artifact its schema requires. |
| `deltas` | A change has no delta spec and no declared `skip_specs`. |
| `stale` | The proposal, specs or design moved in git after `tasks.md` did. |
| `workflows` | The CLI ships a workflow no agent in this project can reach. |
| `ready` | Every task is ticked and the change is still active. |
| `orphans` | A main spec is named by no change, active or archived. |
| `baseline` | A grandfathered change now passes — the entry is stale. |

### Where `chain` gets its list of artifacts

Three sources, in order:

1. **`openspec status --json`**, when the CLI is installed. It is authoritative.
2. **The schema the root declares**, when `<openspec>/schemas/<name>/schema.yaml`
   holds exactly one. Each artifact's `generates` path is resolved against the
   change directory, and a `specs/**/<file>` pattern is satisfied by any
   capability that holds that file. A host on its own schema is therefore judged
   by its own chain: a schema that writes no `design.md` and keeps `tasks.md`
   beside each capability spec used to have both reported missing on a change
   that was in fact complete.
3. **The default spec-driven chain** — proposal, delta specs, design, tasks — when
   the root declares no schema.

Two declared schemas is a `config` warning and falls back to the default. The
guard does not pick one: guessing which chain is in force is the one answer worse
than saying it cannot tell.

Wire it beside `openspec validate --all` in the contract gate, not instead of it:

```json
{ "lint": "pnpm spec:validate && agent-compass openspec-guard . --strict" }
```

`.openspec-guard.json` grandfathers changes that predate a gate:

```json
{ "grandfathered": { "old-change": "predates the verify gate; closed by 2026-09-15" } }
```

It is a **ratchet**. An entry whose change now passes is itself a failure, so the
file drains instead of accumulating. Same discipline as a line-count cap with a
recorded baseline — see
[`cap-as-ratchet-with-baseline`](../../knowledge/instincts/cap-as-ratchet-with-baseline.md).

## Adding a checklist gate

The default `spec-driven` schema has four artifacts and no review gate between
the plan and the code. `/opsx:verify` covers it after implementation. To require a
reviewed checklist *before* implementation, fork the schema into the project:

```bash
cd <the directory holding openspec/>
openspec schema fork spec-driven <project-name>
```

Then edit `<openspec>/schemas/<project-name>/schema.yaml`: add a `checklist`
artifact that `requires: [specs, design]`, make `tasks` require it, and add
`checklist` to `apply.requires`. Set `schema: <project-name>` in `config.yaml`.
Existing changes pin their own schema in `.openspec.yaml`, so they keep the old
chain; grandfather anything that does not.

Keep the OpenSpec delta headings in a forked spec template. A schema that swaps
them for spec-kit headings stops `openspec validate` from understanding the file.

## Rules for agents

1. **Read the spec before the code.** If the behaviour is not in
   `<openspec>/specs/`, propose the change first. Do not implement it and specify
   it afterwards.
2. **Never write an artifact the status gate did not call `ready`.** Run
   `openspec status`, then `/opsx:continue`. Writing `tasks.md` while `design` is
   `blocked` produces a task list for a plan that does not exist.
3. **Print the resolved root** in your handoff. One line, and it makes a wrong
   root visible immediately instead of after the artifacts are lost.
4. **A planning workflow never edits code.** If the work needs both, finish
   planning, stop, and let the user start `/opsx:apply`.
5. **Tick a task only after its validation passes**, in the same pass. A task list
   ticked at the end is a claim, not a record.
6. **Never hand-edit a main spec.** `/opsx:sync` and `/opsx:archive` own that
   file. A hand edit makes the delta unmergeable and loses the history.
7. **`/opsx:verify` before `/opsx:archive`.** A ticked task list says an agent
   believed it was done. Verify checks the code against the requirements.
8. **A change that no longer matches its plan gets `/opsx:update`, not a bigger
   diff.** When implementation contradicts the design, the artifact is what is
   wrong, and it is cheap to fix while you still remember why.
9. **`skip_specs: true` needs the reason written next to it.** The next reader
   cannot tell a deliberate skip from a forgotten delta.

## Related

- [spec-driven-development.md](spec-driven-development.md) — the layout-neutral flow.
- [`openspec-artifact-chain`](../../knowledge/instincts/openspec-artifact-chain.md) — the instinct.
- [`spec-drift-triage`](../../skills/spec-drift-triage/SKILL.md) — when code and spec already disagree.
- [`progress-audit`](../../skills/progress-audit/SKILL.md) — what is built against what is specified.
