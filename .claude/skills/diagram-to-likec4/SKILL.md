---
name: diagram-to-likec4
description: >
  Convert an Excalidraw, draw.io, draw.io SVG, or Mermaid architecture diagram
  into a LikeC4 model. Use when the user wants a structured C4 model from a
  hand-drawn or text architecture diagram.
risk_level: low
writes_files: true
requires_tools: [python3]
license: MIT
metadata:
  version: "2"
---

# Diagram to LikeC4

Turn an architecture diagram into a LikeC4 model.

Its sibling is [`diagram-to-adr`](../diagram-to-adr/SKILL.md), which captures a
decision. Feed this skill's output to
[`likec4-to-openspec`](../likec4-to-openspec/SKILL.md) to derive requirements.

## Inputs

Use a file the user names. Otherwise, look under `docs/drawings/`.

| Extension | Format | Read |
| --- | --- | --- |
| `.excalidraw` | Excalidraw JSON | Shape labels, bindings, and arrow labels |
| `.drawio` | draw.io XML, plain or compressed | Vertex and edge cells on every page |
| `.drawio.svg` | SVG with an embedded draw.io model | The root `content` attribute |
| `.mmd`, `.mermaid` | Mermaid text | Node declarations, links, and subgraph names |

Do not convert BPMN to C4. BPMN describes process flow, not software structure.
Offer `diagram-to-adr` when the user needs to capture a process decision.

## Output

Write one file per diagram to `docs/diagrams/<name>.c4`, unless the host defines
another diagram path. Never modify the source diagram.

## Structured formats

Run the bundled converter for Excalidraw and draw.io inputs:

```bash
python3 skills/diagram-to-likec4/scripts/diagram_to_likec4.py \
  <input> docs/diagrams/<name>.c4
```

The converter maps:

- Excalidraw shapes to `node` elements and bound arrows to relationships.
- draw.io vertex cells to `node` elements and edge cells to relationships.
- Every page in a multi-page draw.io file into one model.
- Embedded draw.io SVG models after unwrapping the picture.

It expands compressed draw.io pages. It rejects a plain SVG that has no embedded
model. A landscape view with `include *` is always present.

## Mermaid

Read Mermaid text directly. Do not send it to the converter.

- Map a flowchart node such as `A[Payment API]` to
  `payment_api = node 'Payment API'`.
- Map a link such as `A -->|charges| B` to
  `payment_api -> b 'charges'`.
- Ignore styling directives. Preserve meaningful subgraph names as boundaries,
  or report that the model does not represent them.
- Do not flatten a sequence or class diagram into a component model. Explain the
  semantic mismatch.

## Refine when supported

The first pass uses one element kind, `node`. If the diagram clearly separates
systems, containers, and components, refine the `specification` block and the
element kinds. Preserve generated identifiers and relationships.

## Validation

Confirm that the output contains `specification`, `model`, and `views` blocks.
Confirm that every relationship endpoint is declared in `model`.
