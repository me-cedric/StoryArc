---
name: debug
description: Build a failing loop before you diagnose a hard bug, flaky test, regression or slowdown, with read-only Grafana, ArgoCD or Kubernetes evidence. Use when a report says only "broken".
risk_level: medium
writes_files: false
requires_tools: []
---

# debug

No theory before the loop. First build one command that catches the exact symptom.

## Loop ladder

Stop at the first rung that catches the bug.

1. An existing focused test.
2. A new smallest regression test.
3. A CLI or script with fixture input.
4. An HTTP request against a running service.
5. A Playwright or browser script for a UI bug.
6. A replay of a captured trace.
7. A small harness around one function or module.
8. A stress loop for a flaky bug.

## Tighten the loop

The loop must be:

- Specific: it asserts the symptom that the user reported, not "does not crash".
- Fast: seconds when possible.
- Deterministic: the same verdict each time, or a high reproduction rate for a flake.
- Runnable by an agent: no manual clicks, unless a written script wraps them.

A loop that asserts an absence needs a floor. A blank page has no forbidden class, and a process that never started writes no forbidden log line.
Assert that the subject exists, then assert the absence. Wait for the floor, do not sample it once.
Collect the survivors in a list and assert that the list is empty, so a failure names each survivor.
A static search proves only that a literal is absent from the source.

## Work

1. Name the loop command. Run it once and see it fail.
2. Remove inputs until each remaining part is needed.
3. Change one thing at a time.
4. Keep the loop as the regression check.
5. Report the command, the failing result, the passing result and the remaining uncertainty.

## Evidence from the running system

When read-only Grafana, ArgoCD or Kubernetes MCP servers are configured, use them for evidence:

- Grafana: the logs, metrics and traces of the failing window.
- ArgoCD: the sync state and the deployed revision of the app.
- Kubernetes: pod status, events and logs.

Use them read-only. Never change a dashboard, a sync, or a cluster resource from this skill.
Never read a Secret.
If a server is not configured, say so. Do not ask the user to add write access.

## A claim of change needs a control

A screenshot, log excerpt, benchmark or query result is weak evidence. A boring cause may give the same result.
Capture the control in the same session.

| The claim | The control |
|---|---|
| This screen differs from the rest of the app | A screen that agrees, on the same device |
| The fix removed the error | The earlier log window, with the error present |
| This is faster now | The old build, on the same machine |
| The flag turns the feature off | The same screenshot with the flag on |

Say in one sentence what the control rules out.

## If no loop is possible

Stop. Ask for the missing artifact: logs, a HAR file, a fixture, environment access, or permission for temporary instrumentation.
