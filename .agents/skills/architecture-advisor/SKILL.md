---
name: architecture-advisor
description: >
  Help decide and justify the architecture for a NEW project from client needs —
  technology-neutral, research-first, no unlabeled guesses. Use when the user
  says "help me choose the best architecture", "which tech stack / framework",
  "design the architecture for this project", "architecture decision", "should we
  use X or Y", or provides functional/technical/client-IS info (incl. images)
  and wants a recommendation, mermaid diagrams, ADR, caveats, open questions, a
  technical backlog, or a list of technical meetings to request.
risk_level: medium
writes_files: false
requires_tools: []
---

# Architecture Advisor

Turn a client's needs into a justified architecture recommendation. Requirements
drive technology — **never** the reverse, and never the house stacks by default.

## Operating principles

1. **Requirements first, technology second.** Derive what the system must do and
   its quality attributes, then pick technology to fit. The repo's `stacks/` and
   `skills/` are *one input*, not the answer. If Flutter, Go, serverless, a
   modular monolith, an event-driven design, or anything else fits the needs
   better, propose it and say why.
2. **No unlabeled guesses.** Tag every material statement:
   - **Known** — stated by the user or found in a cited source.
   - **Assumed** — an *educated* guess; label it, give the basis, and confirm if
     it changes the decision.
   - **Unknown** — an open question.
   Never present an Assumed/Unknown as Known. Educated guesses are allowed; blind
   guesses are not.
3. **Ask before guessing on anything decision-changing.** One focused question at
   a time; don't ask what a sensible default or the provided material answers.
4. **Cite and date.** Tech facts move fast and your training has a cutoff —
   research current sources before asserting versions, limits, pricing, or
   "best practice", and note the source + recency.
5. **Two-way-door bias.** Prefer reversible choices; flag one-way doors
   (data model, core language/runtime, primary datastore, vendor lock-in).

## Pipeline

Follow in order; loop back when new facts land.

1. **Intake.** Fill `architecture-intake.md`: functional scope, NFRs (scale,
   latency, availability, security, compliance, data residency), constraints
   (budget, team skills, timeline, deadlines), the **client's current IS &
   tools** (existing systems, IdP/SSO, data stores, hosting, integrations,
   vendor commitments), and data shape/volume. Read any **images/diagrams** the
   user provides and extract the current state into the intake. Mark each entry
   Known / Assumed / Unknown.
2. **Clarify.** Ask focused questions for *blocking* unknowns only. Proceed on
   non-blocking ones with a labeled educated guess recorded in the assumptions
   register.
3. **Research (ladder, use what's available, degrade gracefully).**
   - Web search for current best practice, benchmarks, limits, pricing.
   - context7 MCP for live library/framework/SDK docs.
   - `gh search repos` / `gh search code` for reference implementations.
   - The host project's own MCP servers / docs for client-system facts.
   - The repo's `stacks/`, `skills/`, `knowledge/` as candidate inputs.
   Enable these via [`docs/tooling/mcp-servers.md`](../../docs/tooling/mcp-servers.md)
   (context7 for docs, exa for web research, fetch for pages, playwright for live
   apps). Cite sources and dates. Do not assert a current-tech fact you did not
   verify.
4. **Architecturally-significant requirements (ASRs).** Distill the quality
   attributes that actually shape the design and weight them (e.g. scalability,
   security/compliance, time-to-market, cost, team fit, operability).
5. **Candidate architectures.** Produce **2–3 distinct options**, each with a
   concrete stack. At least one must come from *outside* the repo's house
   stacks unless requirements rule it out (say why). Avoid a single pre-baked
   answer.
6. **Score.** Use `decision-matrix.md`: rate each option against the weighted
   ASRs and constraints. Show the matrix.
7. **Recommend.** Pick the best fit. Give rationale traceable to requirements,
   the key trade-offs, the runner-up and when it would win, and the risks.
8. **Diagrams.** Produce mermaid from `diagrams.md`: C4 context + container, a
   key sequence, a deployment view, and a data model (ERD) when data matters.
   Include an as-is diagram when the client has an existing IS.
9. **Deliverables.** Write the decision into `architecture-decision.md` (ADR +
   options + matrix + diagrams + risks + **assumptions register** + **open
   questions**). On request, also produce:
   - **Technical backlog** (`tech-backlog.md`): epics → stories → spikes, with
     the riskiest unknowns as time-boxed spikes first.
   - **Technical meetings** (`technical-meetings.md`): which workshops to request,
     each with objective, attendees/roles, inputs, questions, expected outputs.
10. **Validate.** Before delivering, check: every recommendation traces to a
    requirement; every assumption is labeled with a confirmation path; current-
    tech claims are cited; ≥1 non-house option was genuinely considered; open
    questions are listed, not silently resolved.

## Quick start

```text
agent-compass new arch <name>     # scaffold docs/architecture/decisions/<name>.md
```

Or just ask: "help me choose the best architecture for …" and paste the brief
(and any diagrams). The advisor runs the pipeline, asking questions where the
material is genuinely unclear.

## Output contract

Lead with the recommendation and its one-line justification, then: options +
matrix, diagrams, risks/caveats, assumptions register, open questions. Keep
prose tight. Mark everything Known / Assumed / Unknown. End with the single most
useful next action (often: the meetings to request or the first spike to run).

## Anti-patterns

- Recommending the stack you know best instead of the stack the client needs.
- Stating versions/limits/pricing from memory without a current source.
- Burying assumptions in prose instead of a register with confirmation paths.
- One option presented as inevitable; no trade-off analysis.
- Resolving a blocking unknown with a silent guess instead of a question.

## Templates

In `templates/architecture/` (host: `docs/agent-compass/templates/architecture/`):
`architecture-intake.md`, `architecture-decision.md`, `decision-matrix.md`,
`diagrams.md`, `tech-backlog.md`, `technical-meetings.md`. Process:
[`docs/workflows/architecture-decision.md`](../../docs/workflows/architecture-decision.md).
