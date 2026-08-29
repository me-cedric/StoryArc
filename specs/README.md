# Specs

This folder stores specification-driven development artifacts for the project.

## Layout

```text
specs/
  constitution.md
  000-project/
    spec.md
    plan.md
    tasks.md
    checklist.md
  001-feature-name/
    spec.md
    plan.md
    tasks.md
    checklist.md
```

## Rules

- Write or update the spec before implementation when intent is unclear, broad,
  user-facing, high-risk, or architectural.
- Keep specs focused on what and why. Put how in `plan.md`.
- Resolve `[NEEDS CLARIFICATION]` markers before planning.
- Keep implementation, tests, docs, and specs aligned before closing work.
