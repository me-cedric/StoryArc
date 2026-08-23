---
name: debug-loop
description: >
  Build a tight failing feedback loop before diagnosing hard bugs, flaky tests,
  regressions, or performance issues.
risk_level: medium
writes_files: false
requires_tools: []
---

# Debug Loop

Use when bug is unclear, flaky, slow, or reported only as "broken".

## Rule

No theory before loop. First create one command that can catch the exact symptom.

## Loop Ladder

Stop at first rung that catches the bug:

1. Existing focused test.
2. New smallest regression test.
3. CLI or script with fixture input.
4. HTTP request against running service.
5. Playwright/browser script for UI.
6. Captured trace replay.
7. Tiny harness around one function/module.
8. Stress loop for flaky bugs.

## Tighten

Loop must be:

- **Specific**: asserts user's symptom, not "does not crash".
- **Fast**: seconds if possible.
- **Deterministic**: same verdict, or high reproduction rate for flakes.
- **Agent-runnable**: no manual clicks unless wrapped in a written HITL script.

## Work

1. Name loop command and run it once.
2. Minimize inputs until every remaining part is load-bearing.
3. Change one thing at a time.
4. Keep the loop as the regression check.
5. Report command, red/green evidence, and remaining uncertainty.

If no loop can be built, stop and ask for the missing artifact: logs, HAR,
fixture, environment access, or permission for temporary instrumentation.
