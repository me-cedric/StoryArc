---
id: plan-before-operational-change
trigger: 'before changing infrastructure, CI/CD, containers, cloud, Kubernetes, security controls, incident state, or compliance evidence'
confidence: 0.9
domain: operations
source: adapted from BagelHole/DevOps-Security-Agent-Skills@0365f57a079b1332f95cf26e31dd2d5332a8399f
---

# Observe, plan, bound, then mutate

## Action

Before an operational write:

1. Resolve exact target and authorization.
2. Capture current state.
3. Produce plan/diff/dry-run output.
4. State blast radius, health gate, rollback, and stop condition.
5. Require explicit approval for production or destructive action.
6. Apply smallest scope, verify it, then expand.

During an incident, preserve evidence before remediation when safe. For
compliance, distinguish documented/configured controls from observed and tested
effectiveness.

## Why

Most infrastructure failures are target, scope, or rollback failures—not syntax
failures. A green command exit proves execution, not safety, effective control,
or correct environment.
