---
id: compass-evidence-outlives-the-claim
trigger: 'when you are about to report a task complete'
confidence: 0.85
domain: testing
source: adapted from an AI-accelerated frontend POC
---

# A completion claim ships with the artifact that proves it

## Action

Before writing "done", build the bundle:

```bash
agent-compass evidence --run --strict
```

Link `.agent/evidence/index.html` in the handoff. A sentence saying the tests
passed is a claim. A bundle someone else can open is a result.

For a change that has a spec under `specs/changes/<slug>.md`, record the before
side first and the after side last, and link
`.agent/changes/<slug>/index.html` instead. The report shows the file diff, the
tests you touched, and the screenshots side by side.

## Why the terminal output is not enough

The run happened in a session nobody else has. The reviewer reads the summary
days later, on another branch, with the scrollback gone. Evidence that only
existed in your context did not exist.

It also removes the two easiest ways to be accidentally wrong: reporting a green
suite that never ran the changed code, and reporting a change whose after-state
is byte-identical to its before-state. The gate refuses both.

## What the bundle does not prove

It proves the run. It does not prove the result is right. The visual comparison,
the keyboard path and the accessibility review stay human work, and a complete
bundle never substitutes for them.

## When the project cannot produce one

Say so in one line — `no evidence bundle: project declares no test command` —
and name what you verified instead. Silence reads as proof that was never taken.

See [[ui-change-needs-visual-proof]] for the screenshots the bundle collects,
and [[self-review-before-done]] for the pass that comes before this one.
