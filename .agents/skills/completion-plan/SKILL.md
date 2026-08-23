---
name: completion-plan
description: >
  Turn specs and a progress audit into an exhaustive, structured backlog of the
  remaining work — each item with a short rationale, a concrete plan, the
  engineering rules that apply, a matched tracker ticket (or "create one"),
  dependencies, and any approval gate. Use when scoping what's left, building a
  completion/roadmap plan, or checking which work is missing from the tracker.
risk_level: low
writes_files: false
requires_tools: []
---

# Completion Plan

Convert "what's missing" into an ordered, actionable backlog a team or agent can
execute — grounded in the repo's real conventions.

## When to use

- Scoping the remaining work to finish a project, domain, or milestone.
- Building a completion plan / roadmap / technical vision of what's left.
- Reconciling a backlog/tracker against the specs — finding untracked work.
- After `progress-audit`; before `work-splitting` or `implementation-planning`.

## Method

1. **Start from the gaps.** Use the audit's per-subfeature "missing" findings (or
   the specs directly) as the raw backlog.
2. **Read the repo's conventions first** — its module patterns, resilience,
   security, contract-sync, testing, and env rules — so every item's plan and
   "rules" reference the *actual* standards, not generic advice.
3. **Write work-items.** One coherent unit of work each (not per line, not per
   whole feature). For each: id, title, feature(s), priority/tier, *what it is
   and why*, a concrete plan (real files/endpoints/tables/jobs), the specific
   engineering rules that apply, the matched tracker ticket (or `NO TICKET —
   create`), dependencies, and any gate.
4. **Order by dependency and priority tier** (foundation → then tiers). Surface
   the critical-path foundations everything else consumes.
5. **Report the tracker delta** — list real deliverables with no ticket so they
   can be created.

## Run at scale

Fan out **one sub-agent per domain**, each reading its gap slice + the tracker +
the repo conventions + current code, returning **structured work-items**. Then
reconcile cross-cutting items into a single "foundation" section and dedupe.

## Output

- An ordered backlog document, grouped by tier/domain, each item build-ready.
- A "missing from the tracker" list (tickets to create).
- A gate register: each blocked item, what unblocks it, who approves.
- Hand items to `work-splitting` (to assign) or `implementation-planning` (to detail).
