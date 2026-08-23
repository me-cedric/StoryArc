---
name: likec4-to-openspec
description: >
  Turn a LikeC4 model into an OpenSpec change proposal (proposal + spec deltas +
  tasks). Use when the user wants to derive specs or requirements from a C4
  model, or mentions likec4/c4 plus openspec.
risk_level: low
writes_files: true
requires_tools: []
license: MIT
metadata:
  version: "1"
---

# LikeC4 → OpenSpec

Read a LikeC4 model and scaffold an
[OpenSpec](https://github.com/Fission-AI/OpenSpec) change proposal: a
human-readable proposal plus spec deltas whose requirements trace to the model's
elements and relationships.

## Inputs

LikeC4 files (`.c4`) under `docs/diagrams/`, or one the user names. Parse the
`model { }` block for elements (systems/containers/components) and their
relationships. [`diagram-to-likec4`](../diagram-to-likec4/SKILL.md)
produces such a file from a sketch.

## Output — an OpenSpec change

Create a change folder under `specs/changes/<change-id>/` where `<change-id>` is a
short kebab-case slug (e.g. `derive-specs-from-c4`). When the project keeps its
OpenSpec root somewhere else, use that root.

```
specs/changes/<change-id>/
  proposal.md
  tasks.md
  specs/<capability>/spec.md      # one capability per major element/system
```

### proposal.md

```markdown
## Why

{Why this change — the problem the C4 model implies. 1-3 sentences.}

## What Changes

- {bullet per capability/behavior derived from the model}

## Impact

- Affected specs: {list the <capability> folders below}
- Affected code: {containers/components from the model, if known}
```

### specs/<capability>/spec.md — spec deltas

Each capability maps to one significant element in the model. Requirements MUST
use OpenSpec's operative headings and **every requirement needs at least one
scenario**:

```markdown
## ADDED Requirements

### Requirement: {capability} SHALL {behavior derived from the element/relationship}

{One sentence of clarifying detail.}

#### Scenario: {a concrete situation}

- **WHEN** {trigger}
- **THEN** {expected outcome}
```

Use `## MODIFIED Requirements` / `## REMOVED Requirements` instead of
`## ADDED Requirements` only when changing existing specs under the spec root.

### tasks.md

```markdown
## 1. Implementation

- [ ] 1.1 {task}
- [ ] 1.2 {task}
```

## Procedure

1. Parse the `.c4` model: list elements and `a -> b` relationships.
2. Group into **capabilities** (one per system/major container).
3. Write `proposal.md`, then one `specs/<capability>/spec.md` per capability with
   `### Requirement:` + `#### Scenario:` entries derived from the element's
   relationships (each `a -> b 'verb'` suggests a behavior).
4. Write `tasks.md`.
5. Keep requirement text testable (use SHALL/WHEN/THEN). Do not invent behaviors
   the model does not imply — mark gaps with `TODO:`.

## Validation

- Every `### Requirement:` has at least one `#### Scenario:` with a `**WHEN**`
  and a `**THEN**`.
- If the OpenSpec CLI is available, run `openspec validate <change-id> --strict`
  and fix reported issues.
