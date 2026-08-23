---
name: spec-workflow
description: >
  Use for project ideas, feature specs, requirements, unclear tasks, technical
  plans, task breakdowns, or requests that need spec-driven clarification before
  implementation.
license: MIT
compatibility: markdown
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[project|feature|bugfix|task]"
risk_level: medium
writes_files: false
requires_tools: []
---

# Spec Workflow

Use the smallest spec artifact that prevents misunderstanding.

## When To Use

- New project or product idea.
- New feature or behavior change.
- Ambiguous bugfix.
- High-risk change touching auth, money, data, security, migrations, or shared
  contracts.
- User asks for specs, requirements, planning, task breakdown, or clearer agent
  guidance.

Tiny mechanical edits may use an inline spec brief instead of `specs/<id-slug>/`.

## Flow

1. **Spec**: what and why only. No stack choices or implementation details.
2. **Clarify**: ask until no high-impact `[NEEDS CLARIFICATION]` remains.
3. **Plan**: translate approved spec into technical approach and validation.
4. **Tasks**: write ordered, test-first tasks with parallel-safe `[P]` markers.
5. **Implement**: only after spec, plan, and tasks are stable.
6. **Converge**: compare code, tests, docs, and specs; update stale artifacts.

## Artifact Layout

```text
specs/<id-slug>/
  spec.md
  plan.md
  tasks.md
  checklist.md
```

Use `specs/000-project/` for new project creation.

## Inline Brief For Small Tasks

```markdown
Spec brief:
- Goal:
- Non-goal:
- Acceptance:
- Validation:
```

If the brief exposes ambiguity, promote it to a full spec folder.
