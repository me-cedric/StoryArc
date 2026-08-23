# Agent-Ready Work Intake

Fill this before handing work to an agent. An agent should refuse to start broad
or irreversible work until the five required fields are answered (a sensible
default counts as answered). Small mechanical edits may inline a one-line brief
instead.

## Required

**Goal** — the outcome in one sentence. Not the method.

**Context** — where it lives: paths, modules, related specs/PRs, prior attempts.

**Constraints** — what must stay true: APIs to preserve, files not to touch,
performance/security limits, libraries to use or avoid, no new dependencies.

**Done when** — the observable acceptance check. "All X pass", "endpoint returns
Y", "screen matches Z". Avoid "looks good".

**Validation** — exact commands the agent must run and report (prefer
`agent-compass.commands.json` entries): lint, typecheck, the relevant tests.

## For long-running work (goal/background/cloud agents)

**Stopping condition** — the single state that ends the loop.

**Checkpoint cadence** — when to report progress (every N steps / per file /
per failing test fixed).

**Out of scope** — what NOT to expand into. Protects against scope creep in
autonomous loops.

## Definition of agent-ready

- [ ] Goal is an outcome, not a vague verb ("improve", "clean up").
- [ ] At least one concrete file/path or entrypoint in Context.
- [ ] Constraints name what must not change.
- [ ] Done-when is checkable by a command or an observation.
- [ ] Validation commands exist in the project (or are marked `not run` with a
      reason).

## Why this exists

The highest-leverage automation is preventing a vague start. A precise intake
removes clarification loops and makes `/goal`, subagents, and cloud agents safe.
To turn a rough request into this shape, use the `prompt-upgrade` prompt file or
the `agent-teacher` skill. See
[`../../docs/workflows/agent-improvement-loop.md`](../../docs/workflows/agent-improvement-loop.md).
