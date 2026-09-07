# This folder is not the specs root

**StoryArc keeps its specifications under [`docs/openspec/`](../docs/openspec).** The
capability specs are at `docs/openspec/specs/`, and the changes that amend them are at
`docs/openspec/changes/`. That path is declared in
[`agent-compass.commands.json`](../agent-compass.commands.json) under `paths.openspec`, and a
declaration wins over any convention.

`agent-compass` created this folder on 2026-09-07 when it synced its managed files. Its
templates describe spec-kit, which lays specs out as `specs/000-project/spec.md`. StoryArc
uses OpenSpec instead. The original template said the specs live here. That sentence was
wrong for this repository and is the reason this page replaced it.

Nothing reads a spec from this folder. Two files remain, and each says why:

| File | Why it is here |
| --- | --- |
| `constitution.md` | `agent-compass doctor` checks that the file exists. It now holds StoryArc's real principles instead of the template placeholders. |
| `change-spec-template.md` | The template for a workflow StoryArc does not use. It now points at the OpenSpec change flow. |

Do not add a spec to this folder. Do not create `specs/changes/`. A second changes
directory would give the OpenSpec CLI a second root to resolve, and the CLI resolves the
nearest one.

## Where to go instead

| You want to | Do this |
| --- | --- |
| Read what a capability must do | Open `docs/openspec/specs/<capability>/spec.md` |
| See how much of it exists | Read [`docs/openspec/STATUS.md`](../docs/openspec/STATUS.md) |
| Change a specified behaviour | Run `/opsx:propose "<idea>"`, which scaffolds a change |
| Check a change is complete | Run `pnpm spec:guard` |

Never hand-edit a spec under `docs/openspec/specs/`. Propose a change, then archive it. The
archive step rewrites the main spec, and a hand edit is lost without a record.
