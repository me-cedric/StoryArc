---
id: spec-kit-workflow
trigger: 'when a project uses GitHub Spec Kit (Specify CLI) for spec-driven work'
confidence: 0.8
domain: workflow
source: host-project-promotion
---

# Follow the Spec Kit Sequence and Stop Before Implement

## Action

In a Spec Kit project, always run the slash-command sequence in order and stop
for explicit approval before implementation:

```
/speckit.specify   → create/update the feature spec from source docs
/speckit.clarify   → targeted questions BEFORE planning
/speckit.plan      → implementation plan (after clarify)
/speckit.checklist → validate spec completeness
/speckit.tasks     → ordered task list (after plan)
/speckit.analyze   → cross-artifact consistency check
[STOP — explicit user approval required]
/speckit.implement → execute tasks
/speckit.converge  → find remaining unbuilt work, append to tasks
```

Before any spec or implementation work, read the project constitution
(`.specify/memory/constitution.md`) and the feature's source docs; work from
generated `specs/`, never directly from raw source documents.

## Why

The constitution encodes hard rules agents otherwise violate: never invent
requirements (ambiguity becomes an open question, not an assumption), preserve
source rule IDs across artifacts, and never skip validation checklists.
Implementing straight from source docs bypasses clarification and produces
untraceable behavior.
