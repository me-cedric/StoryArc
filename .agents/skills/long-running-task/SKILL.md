---
name: long-running-task
description: >
  Run broad, multi-phase, autonomous coding work safely: intake, plan,
  checkpoint, optional one-at-a-time subagents, implementation loops, validation,
  and final sweep. Use when the user asks to keep going until a large goal is
  finished or gives many phases.
risk_level: medium
writes_files: true
requires_tools: []
---

# Long Running Task

Use this when work spans many files, phases, or validation loops.

## Intake Gate

Confirm or infer:

- Goal
- Context
- Constraints
- Done when
- Validation
- Stop condition
- Checkpoint cadence
- Out of scope

If a missing field blocks safe work, ask one focused question. Otherwise infer
from repo files and continue.

## Loop

1. Read host rules, command registry, project memory, specs, and active files.
2. Write a short plan: phases, files likely touched, validation commands.
3. Work one phase at a time.
4. Use at most one subagent at a time when it saves context or provides review.
5. Review subagent output before trusting it.
6. After each phase, self-review diff and run the smallest relevant check.
7. If validation fails, fix introduced failures before moving on.
8. Stop only at the stop condition, a true blocker, or explicit user redirect.

## Safety Defaults

- No commit, push, PR, deploy, publish, production write, migration against
  production, or secret output unless explicitly approved.
- No invented commands. Use `agent-compass.commands.json`, `package.json`, or
  documented equivalents.
- No broad rewrite when a narrow fix satisfies the goal.

## Handoff

Use the Completion Gate:

- Goal
- Mode
- Files changed
- Commands run
- Validation result per command
- Risks
- Next step
