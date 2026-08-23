---
name: figma-mcp-frontend
description: Use Figma MCP design context to implement frontend screens, design systems, components, and styles.
risk_level: medium
writes_files: false
requires_tools: []
---

# Figma MCP Frontend

Use when work references a Figma file/frame, design system, component library,
tokens, or visual implementation from design.

## Before Code

1. Read repo UI rules, existing components, tokens, and route/page patterns.
2. Verify Figma MCP tools are available.
3. Pull design context for the selected frame or file.
4. Extract:
   - design tokens: color, type, spacing, radius, shadows
   - components and variants
   - molecular component composition
   - layout constraints and responsive rules
   - states: hover, focus, disabled, loading, empty, error
5. Map Figma components to existing code components before creating new ones.

If Figma MCP is unavailable or rate-limited, use project-local design exports
and screenshots before guessing. Common fallback locations: checked-in design
docs, `docs/design/`, `templates/design-system/`, and user-provided PNG exports.
Report the gap clearly.

## Implement

- Reuse existing design system first.
- Create new components only when no matching local component exists.
- Do not invent visual rules that conflict with Figma, local tokens, or shared
  components.
- Preserve accessibility basics: labels, focus, contrast, keyboard flow.
- Validate visually with screenshot or browser check when UI changed.

## Report

List Figma source, mapped components, changed files, validation, and visual risks.
