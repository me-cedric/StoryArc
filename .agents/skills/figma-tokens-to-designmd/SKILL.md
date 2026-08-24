---
name: figma-tokens-to-designmd
description: >
  Convert a Figma design-token JSON export into a design.md design-system file
  (google-labs-code/design.md format). Use when the user has Figma
  tokens/variables JSON and wants a machine-readable design.md with colors,
  typography, spacing and rounding tokens.
risk_level: low
writes_files: true
requires_tools: [python3]
license: MIT
metadata:
  version: "1"
---

# Figma tokens → design.md

Map a Figma **design-token** JSON export to a `design.md` file in the
[google-labs-code/design.md](https://github.com/google-labs-code/design.md)
format (YAML token front matter + Markdown sections).

> This is the design-**system** `design.md` (colors/typography tokens) — a
> different artifact from a Google *design-doc*. Do not overwrite any existing
> design-doc.

Use [`figma-mcp-frontend`](../figma-mcp-frontend/SKILL.md) instead when the goal
is to implement screens from live Figma design context rather than to persist the
token set.

## Inputs

A Figma token JSON file provided by the user (W3C DTCG `{"$type","$value"}` or
Tokens-Studio `{"type","value"}` shape).

## Output

`design.md` at the repository root, or the path the project already uses, with:

1. **YAML front matter** (delimited by `---`): `name` (required), plus token maps
   `colors`, `typography`, `rounded`, `spacing` (and `components` when present).
2. **Markdown body** — `##` sections, present ones in this **exact order**:
   `Overview`, `Colors`, `Typography`, `Layout`, `Elevation & Depth`, `Shapes`,
   `Components`, `Do's and Don'ts`.

## Procedure

1. Run the mapper to produce a first draft:

   ```bash
   python3 skills/figma-tokens-to-designmd/scripts/figma_to_designmd.py \
     <tokens.json> design.md --name "<Design system name>"
   ```

   It flattens the token tree and buckets tokens by type (color → `colors`,
   dimension/spacing → `spacing`, radius → `rounded`, font/typography →
   `typography`).

2. Review the generated front matter. **Verify the nested token schema against
   the design.md spec** and adjust key names/shape if the spec differs — the
   script's mapping is a starting point, not the authority.

3. Fill in the `##` body sections with human-readable rationale (keep them in the
   canonical order; omit a section rather than reordering).

## Validation

- The file must start with a `---` YAML front-matter block containing a non-empty
  `name`.
- Any `##` sections present must appear in the canonical order above.
