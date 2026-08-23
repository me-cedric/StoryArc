---
name: design-taste-skills
description: "Use when a frontend surface needs a visual direction rather than a bug fix — a landing page, a marketing site, a portfolio, a redesign, a brand system, a dense product UI, or turning a mockup or screenshot into code. Picks the one tracked design skill that fits the surface and installs it, then holds the visual-proof gate in force. Triggers: landing page, marketing site, redesign, make it look good, design direction, visual identity, brand kit, logo system, minimal UI, brutalist, editorial layout, screenshot to code, mockup to code, image to code, it looks like a template, AI slop."
risk_level: low
writes_files: false
requires_tools: []
version: 1.0.0
---

# Design Taste Skills

Ten design skills are tracked at
[`Leonxlnx/taste-skill`](https://github.com/Leonxlnx/taste-skill) (MIT).
Agent Compass keeps no copy of them and installs the one that fits the surface.

They are not interchangeable. **A dense product UI and a landing page want
opposite advice** — one wants information density, restraint, and predictable
affordances; the other wants scale contrast, atmosphere, and a point of view.
Loading both produces a landing page that reads like a dashboard, or a dashboard
that fights its own users. Pick one group and stay in it.

## Procedure

### 1. Name the surface, then pick the group

| Surface | Install | Why |
| ------- | ------- | --- |
| Landing page, marketing site, portfolio, campaign | `design-taste-frontend` + at most one of `industrial-brutalist-ui` / `stitch-design-taste` | Anti-template direction with room for a strong opinion |
| Dense product UI, admin, dashboard, back-office | `high-end-visual-design` + `minimalist-ui` | Restraint and hierarchy; nothing that competes with the data |
| An existing surface being reworked | `redesign-existing-projects` | Audit-first: it reads what is there before proposing change |
| Brand system, logo, identity deck | `brandkit` | Identity work, not page layout |
| A mockup, screenshot, or Figma frame to convert | `image-to-code` | Reads a reference and produces markup |
| Generated imagery for a web or mobile surface | `imagegen-frontend-web` / `imagegen-frontend-mobile` | Art direction for generated assets |

Do not install a landing-page skill and a product-UI skill into the same project
unless the project genuinely has both surfaces — and then say which surface you
are working on before you start.

### 2. Install it

```bash
# A project, for Claude Code + Codex + Copilot
agent-compass external-skills . --source taste-skill --skill minimalist-ui,high-end-visual-design

# The full curated set, when a project spans several surfaces
agent-compass external-skills . --source taste-skill --recommended

# User-wide
agent-compass external-skills --source taste-skill --recommended --global
```

The upstream folder names differ from the skill names (`skills/soft-skill/`
declares `high-end-visual-design`). Install by skill name; the mapping table is in
[style-and-design-skills.md](../../docs/tooling/style-and-design-skills.md#upstream-folder-names-differ-from-skill-names).

### 3. Give it a direction, not a vacuum

These skills produce their worst output when asked to "make it look good" with no
constraint. Before generating anything, fix:

- the **surface** and its primary job;
- a **style direction** with a name (editorial, Swiss, brutalist, luxury, bento,
  scrollytelling) — never "clean and modern";
- the **palette and type** source: an existing design system, a Figma token
  export, or a deliberate choice you can defend;
- what must **not** change: existing tokens, component API, brand constraints.

If the project already has a design system, the system wins and the skill's job
is to use it well. Read
[`figma-tokens-to-designmd`](../figma-tokens-to-designmd/SKILL.md) or
[`figma-mcp-frontend`](../figma-mcp-frontend/SKILL.md) first when Figma is the
source of truth.

### 4. Ship the screenshot

`AGENTS.md` §6 applies to every surface these skills touch. A design change is a
change the user can see, so it owes visual proof at the project's viewport
matrix — see
[`visual-regression-playwright`](../visual-regression-playwright/SKILL.md) and the
[`ui-change-needs-visual-proof`](../../knowledge/instincts/ui-change-needs-visual-proof.md)
instinct.

A design skill's own claim that the result "looks expensive" is not proof.

### 5. Agent surfaces are a separate concern

If the surface shows model output — streaming answers, tool calls, approval
gates, agent task rows — [`ai-native-ui-patterns`](../ai-native-ui-patterns/SKILL.md)
governs its behaviour, and it composes with either design group. Taste does not
decide whether a citation is visible or an approval gate blocks.

## Freshness

```bash
agent-compass upstream-skills --check-updates
agent-compass upstream-skills --update taste-skill --dry
```

The source publishes 13 skills; Agent Compass curates 10. The other three are
tracked and installable by name, but uncurated — read one before you use it.

## Related

- [style-and-design-skills.md](../../docs/tooling/style-and-design-skills.md) —
  install routes, the folder-name mapping, and the tracked inventories.
- [accessibility](../../docs/guidelines/accessibility.md) — a direction that
  fails contrast or keyboard navigation is not finished.
