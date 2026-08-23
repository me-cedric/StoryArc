---
name: diagram-to-adr
description: >
  Draft a MADR Architecture Decision Record from an Excalidraw, draw.io,
  Mermaid, or BPMN diagram. Use when the user wants to capture the decision,
  options, and drivers shown by an architecture or process diagram.
risk_level: low
writes_files: true
requires_tools: []
license: MIT
metadata:
  version: "2"
---

# Diagram to ADR

Read a diagram, infer the decision it shows, and draft a Markdown Architecture
Decision Record in [MADR 4.0](https://adr.github.io/madr/) format.

Its siblings are [`adr-from-meeting`](../adr-from-meeting/SKILL.md), which starts
from a transcript, and [`diagram-to-likec4`](../diagram-to-likec4/SKILL.md),
which turns an architecture diagram into a model.

## Inputs

Use a file the user names. Otherwise, look under `docs/drawings/`.

| Extension | Format | Read |
| --- | --- | --- |
| `.excalidraw` | Excalidraw JSON | Shape labels, arrow labels, and free text in `elements` |
| `.drawio` | draw.io XML | Cell labels and all pages |
| `.drawio.svg` | SVG with an embedded draw.io model | The root `content` attribute |
| `.mmd`, `.mermaid` | Mermaid text | Node text, link labels, and subgraph names |
| `.bpmn` | BPMN 2.0 XML | Task, event, gateway, and lane names |

Ignore HTML markup inside draw.io labels. When a draw.io page is compressed,
use `diagram-to-likec4` to decode it before you interpret its content.

A BPMN diagram describes a process. Focus its ADR on sequence, ownership,
exceptions, or the choice represented by a gateway.

## Output

Write `docs/decisions/NNN-<kebab-title>.md`, unless the host defines another ADR
path or numbering convention. Match the width and format of existing ADR names.
If none exist, start at `001`. Do not renumber or edit existing ADRs.

## MADR template

```markdown
---
status: "proposed"
date: <YYYY-MM-DD>
decision-makers: []
consulted: []
informed: []
---

# <short title>

## Context and Problem Statement

<Problem or decision question. Reference the source diagram.>

## Decision Drivers

- <driver>

## Considered Options

- <option>

## Decision Outcome

Chosen option: "<option>", because <reason>.

### Consequences

- Good, because <positive consequence>.
- Bad, because <negative consequence>.

## Pros and Cons of the Options

### <option>

- Good, because <argument>.
- Neutral, because <argument>.
- Bad, because <argument>.

## More Information

<Source diagram path and follow-up links.>
```

## Procedure

1. Identify the decision, options, and drivers shown by the diagram.
2. Determine the next ADR number from the host convention.
3. Write the complete MADR. Keep `status: "proposed"` and set the current date.
4. Use `TODO:` for every field the diagram does not establish.
5. Reference the source diagram under **More Information**.

Never fabricate decision-makers, options, or an outcome. A diagram is evidence,
not proof that the team agreed to a decision.
