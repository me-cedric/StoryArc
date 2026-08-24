---
id: verified-progress-signal
trigger: 'when reporting how complete a project/feature is, or auditing progress'
confidence: 0.9
domain: delivery
source: hand-authored
---

# Measure completion against wired, tested code — never reported status

## Action

When judging whether a feature is done, open and read the code that implements
it. Count it **done** only if the endpoint/job/screen is wired and tested. Do
**not** infer completion from:

- status docs, roadmaps, or "implemented" labels,
- task-checkbox counts in a tracker,
- a type, a DTO, or a schema-only table with no consumer,
- a service that exists but is registered/routed nowhere.

Separate **backend** from **frontend** (an API with no screen is not a delivered
feature). Distinguish **gap** (unbuilt) from **gated** (blocked on a
credential/decision). For scale, fan out per-feature assessors and add an
**adversarial pass that tries to refute every "done"** before reporting a number.

## Why

Reported status drifts from reality — trackers lag the code (both over- and
under-reporting), and schema/type scaffolding reads as "started" when nothing is
wired. Averaging unverified per-feature guesses produces a confident wrong
number. Verifying against wired code, and refuting "done" claims, is what makes a
progress report trustworthy enough to plan against.
