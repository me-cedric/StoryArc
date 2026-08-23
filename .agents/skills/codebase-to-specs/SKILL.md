---
name: codebase-to-specs
description: >
  Reverse-engineer an existing codebase into draft specifications, decision
  records, and an architecture sketch. Use when a legacy or third-party project
  has code but missing or incomplete product and architecture documentation.
risk_level: medium
writes_files: true
requires_tools: [git]
license: MIT
metadata:
  version: "1"
---

# Codebase to specifications

Create the first documentation draft from code that already exists. Describe
observed behavior. Do not present observed behavior as agreed intent.

## Required warning

Put this warning directly below the title of every generated document:

```markdown
> **Inferred from code, not reviewed.** Drafted from `<commit sha>`. Review this
> document before you use it as a source of truth.
```

Only a human reviewer can remove the warning.

## Read the evidence

1. Read the host `AGENTS.md` and its configured document paths.
2. Use the configured code graph before a broad repository search. Check index
   coverage for every path that supports a material or exhaustive claim.
3. Read `README.md`, `CONTRIBUTING.md`, and relevant files under `docs/`.
4. Read the package or build manifests and the command registry.
5. Read the observable surfaces: entry points, routes, handlers, jobs,
   migrations, schemas, and tests.
6. Read recent commit subjects with `git log --oneline -50`. Reuse the team's
   established terms.

Source code is authoritative for current behavior. Existing reviewed documents
remain authoritative for intent. Report conflicts between them.

## Bound the work

Group the code into capabilities: the small set of things the system does for a
user or another system. Do not create one specification per file.

List all discovered capabilities. Draft the largest eight first. If more remain,
list them under **Not covered** so the scope is visible.

## Outputs

Use the host's configured paths. Use these defaults only when the host has no
local convention.

| Document | Default path | Content |
| --- | --- | --- |
| Capability specification | `specs/<capability>/spec.md` | Inputs, outputs, rules, scenarios, questions, and gaps |
| Decision record | `docs/decisions/NNN-<title>.md` | A consequential choice visible in the implementation |
| Architecture sketch | `docs/diagrams/<system>.c4` | Observed systems, containers, and relationships |

Every specification must include these sections:

### Open questions

List facts the code cannot establish: unexplained constants, conflicting paths,
unreachable branches, unclear ownership, and behavior that can be a defect or a
requirement. Write each item as a question for a reviewer.

### Not covered

List every scope you did not inspect and the reason: time limit, generated code,
vendored code, missing access, excluded files, or incomplete graph coverage.

## Rules

- Never invent a requirement to make a draft look complete.
- Never describe a likely defect as intended behavior. State the observed
  behavior and the concern separately.
- Never overwrite an existing specification or decision record. Write a draft
  beside it and name the conflict.
- Never infer intent from graph silence or missing tests.
- Never remove the inference warning.
- Never commit or push. Leave the drafts for review.

## Report

Report:

1. Capabilities found and drafted.
2. Files written.
3. Open questions, most consequential first.
4. Evidence and scopes not read.
5. Conflicts with existing documents.

The next action is human review of the open questions. That review turns an
observed draft into an agreed specification.
