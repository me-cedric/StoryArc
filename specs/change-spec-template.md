# StoryArc does not use this template

**Propose a change with `/opsx:propose "<idea>"` instead.** The command scaffolds every
artifact that StoryArc's OpenSpec lifecycle requires, in the layout the guard checks.

`agent-compass` created this file on 2026-09-07. Its template describes a spec-kit change,
saved as `specs/changes/<id-slug>.md`. StoryArc keeps changes at
`docs/openspec/changes/<name>/` and each one carries five artifacts, not one file. The
template is kept as this pointer because `agent-compass` recreates a missing seed on every
sync, and an edited seed survives.

## The artifacts a StoryArc change carries

| Artifact | Holds |
| --- | --- |
| `proposal.md` | What changes and why |
| `design.md` | How, and which options were refused |
| `specs/<capability>/spec.md` | The delta: the requirement text this change adds or replaces |
| `tasks.md` | The work, one tickable line each |
| `.openspec.yaml` | Configuration, including `skip_specs` when a change specifies nothing |

## The commands

| Command | Use |
| --- | --- |
| `/opsx:propose "<idea>"` | Scaffold the change and write every artifact |
| `/opsx:ff "<idea>"` | Write only what is needed to start implementing |
| `/opsx:continue` | Write the next artifact the status gate calls ready |
| `/opsx:apply` | Implement the change and tick each task as it passes |
| `/opsx:archive` | Retire the change and rewrite the main spec |

Read [`AGENTS.md`](../AGENTS.md) section 3b for the rules that bind these commands. Run
`cd docs` before any bare `openspec` command, or use the `pnpm spec:*` scripts. The CLI
resolves the nearest root, and the root is `docs/openspec`.

A change with no delta spec must declare `skip_specs: true` in `.openspec.yaml` and give the
reason in a comment. `pnpm spec:guard` fails on a change that specifies nothing and does not
say so.
