---
name: progress-audit
description: >
  Audit how much of a project is actually built by diffing its specs, functional
  docs, and requirement registers against the real code into an honest, verified
  progress matrix (per feature/subfeature and global). Use when asked how far
  along a project is, what's left, percent complete, a progress or
  status/completion report, or to "compare the specs to the code".
risk_level: low
writes_files: false
requires_tools: []
---

# Progress Audit

Measure what is *delivered*, not what is *reported*. The output is a per-feature
progress matrix plus a global verdict, honest enough to plan against.

## When to use

- "How far along are we / what's left / are we on track?"
- A progress, status, or completion report across a whole project or domain.
- Comparing specs / functional docs / requirements to the code actually on a branch.
- Before scoping remaining work (feeds `completion-plan`).

## Method

1. **Map the requirement sources.** Enumerate the specs, functional docs,
   requirement registers, and any priority/sequencing tiers. This is the
   denominator — what *should* exist.
2. **Map the code.** Enumerate the real modules, routes/endpoints, jobs, tables,
   and UI screens on the target branch. Split backend vs frontend explicitly.
3. **Diff per feature/subfeature.** For each capability the spec requires, find
   and read the actual code. Rate done / partial / skeleton / gap / gated, with
   an honest percent, concrete file-path evidence, and what's missing.
4. **Roll up** to per-domain and global figures, and to a layered verdict (e.g.
   backend vs frontend vs governance) — a single average hides imbalance.

## Verify, don't trust

- A capability is **done** only when it is wired and tested — not because a
  status doc, a task checkbox, a type, or a schema-only table exists. See the
  `verified-progress-signal` instinct.
- Distinguish **gap** (simply unbuilt) from **gated** (blocked on a
  decision/credential) — they need different follow-up.
- Separate **backend** from **frontend**: an API with no screen is not a
  delivered feature.

## Run at scale

For anything beyond a few features, fan out **one sub-agent per feature/domain**
returning a **structured schema** (id, status, percent, evidence, gaps), then run
an **adversarial verification pass** that tries to *refute* every "done"/high
claim by opening the cited files. Reconcile assessor vs verifier before rolling
up. Deterministic orchestration (a workflow) keeps it repeatable.

## Output

- A per-feature/subfeature matrix: status, percent, evidence, gaps, gated items.
- Per-domain rollup + global figure + a layered honest verdict.
- Optionally reconcile against any existing status doc and explain divergences.
- Feed the result into `completion-plan` to scope the remaining work.
