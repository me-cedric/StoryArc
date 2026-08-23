---
name: implementation-planning
description: >
  Produce a detailed, production-ready, plug-and-play implementation spec for a
  scope of work-items that a developer or agent can start or one-shot: exact
  files, schema, contracts, logic, resilience/security, jobs, env scaffolding,
  and tests — including mock/fail-closed paths for anything missing credentials.
  Use when you need a build-ready plan, not just a backlog.
risk_level: low
writes_files: false
requires_tools: []
---

# Implementation Planning

Take scoped work-items down to a build-ready spec — concrete enough to hand a
single item to an agent and get correct code, and safe to build now even when
credentials or decisions are missing.

## When to use

- You have a backlog (from `completion-plan`) and need per-item build detail.
- "Make a detailed plan I can refer to / one-shot the implementation."
- Preparing work that depends on credentials/decisions you don't have yet.

## Per-item template

For every work-item, produce: **Objective · Files** (create/modify, real paths) ·
**Schema/migration · Contracts** (shared types → DTO → endpoints `METHOD /path` →
API doc → acceptance tests) · **Logic** (ordered steps, edge cases, transaction
boundaries) · **Resilience & security** (which apply) · **Jobs** · **Plug-and-play**
· **Tests** · **Ticket/Specs · Dependencies**.

## Plug-and-play (missing credentials/decisions)

Build it fully now; make going live a config change, not a rewrite:

1. Ship a **mock/stub provider** wired by default so it runs offline.
2. Declare the **env vars on every required surface** (validation + examples +
   local dev defaults).
3. **Fail closed with a typed error** mapped to a clean response when the secret
   is absent — never crash or leak.
4. Leave **one flip** (key present / env flag) that swaps mock→live with zero
   code change. State it explicitly per item.

## Discipline

- **Read the current code first** so every path/signature is real, and **follow
  the repo's own conventions** (module layout, logging, DB, contract-sync,
  tests) — cite the specific rule per item, don't restate generic advice.
- Prefer extending existing files over new ones.
- **Run at scale** by fanning out one sub-agent per area over the current code;
  keep every item's output on the same template.

## Output

A build-ready plan document (per-area sections, per-item detail, a suggested
build order) plus a consolidated env/gate view for the plug-and-play items.
