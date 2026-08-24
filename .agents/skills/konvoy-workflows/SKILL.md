---
name: konvoy-workflows
description: How to produce work in a Konvoy project — where every artefact lives, what format each one takes, and the multi-step workflows (realign the code to changed specs, plan a delivery from specs and team, split work across teams). Use whenever asked to write a specification, a decision record, personas, a costing sheet, a plan, tickets, diagrams or documentation in this repository.
---

# Working in a Konvoy project

This repository is driven by **Konvoy**, a delivery cockpit. Every screen in it
is a view over files here, so anything you produce has to land in the right
place, in the right format, or nobody will see it.

An agent that writes a perfectly good specification into `specs/` instead of the
configured OpenSpec root has produced nothing. Read the layout before you write.

## 0. Ask the Konvoy MCP server first

Konvoy runs a local MCP server, and this project is already configured to use
it. If your tools include `konvoy_project_context`, call it before anything
else. It answers with the active project, every artefact path, the pages that
are enabled and the delivery profile — that is section 1 and section 2 of this
document, resolved and current.

| Tool | What it answers |
| --- | --- |
| `konvoy_project_context` | The active project, its paths, its surfaces, its profile |
| `konvoy_list_projects` | Every project Konvoy knows |
| `konvoy_list_artifacts` | One artefact kind, and the directory it lives in |
| `konvoy_read_file`, `konvoy_list_files` | Files, restricted to this repository |
| `konvoy_list_tools` | The bundled tools, and which can run here |
| `konvoy_search` | A literal string, with path and line number |
| `konvoy_git_status`, `konvoy_git_log` | The working tree and the recent commits |
| `konvoy_delivery_diff` | What changed since a base reference |

The server also offers **prompts**. Each one is a Konvoy workflow, with this
project's paths already filled in. Ask for the prompt list before you invent a
procedure for a delivery task — `spec-to-tickets`, `impact-analysis`,
`delivery-digest` and `harvest-questions` are among them.

Three groups of tools appear only when the user allowed them on the MCP Servers
page. When you do not see a group, do that work with your own tools, or ask the
user to turn the switch on.

| Group | Tools |
| --- | --- |
| Write | `konvoy_write_file`, `konvoy_decide_adr`, `konvoy_git_commit`, `konvoy_tickets_plan`, `konvoy_tickets_set_state`, `konvoy_tickets_sync` |
| Forge | `konvoy_pull_request_create`, `_comment`, `_review`, `_merge`, `konvoy_tickets_apply` |
| Scripts | `konvoy_qa_run`, `konvoy_run_tool` |

`konvoy_git_commit` commits and never pushes. The forge tools change what your
whole team sees, and `konvoy_pull_request_merge` cannot be undone.

If the server does not answer, Konvoy is closed or the user stopped it. Read the
files directly and continue. The rest of this document tells you how.

## 1. Read the layout first

`.agents/konvoy.json` carries a `paths` object with this project's real
locations. **Read it before writing anything.**

```bash
cat .agents/konvoy.json | grep -A 20 '"paths"'
```

If the file has no `paths` block, the project has not been saved from Konvoy
since that was added. Fall back to the defaults below, and say which you used.

### What this project is called

The same file carries `project_name` and `project_logo`. When `project_name` is
set, use that name in any document, slide, heading or README you write for this
project. Do not invent a name from the folder. When `project_logo` is set, it is
a repository-relative path to an image you can reference where a document wants
a mark.

```bash
cat .agents/konvoy.json | grep -E '"project_name"|"project_logo"'
```

### Who you are working for, and what they may change

The same file carries a `profiles` object. When `profiles.enabled` is `true`,
this team has agreed who changes which parts of the project.

```bash
cat .agents/konvoy.json | grep -A 20 '"profiles"'
git config user.email
```

Read `profiles.members` for the lower-cased email of the person you are working
for. When their email is absent, `profiles.fallback` names their profile. An
empty `fallback` and no entry means they have not been given one.

`profiles.presets` lists the surfaces a profile may change, but only for the
profiles this project changed; a profile that is absent from it uses the set
Konvoy ships. The `full` profile changes everything.

Two rules follow:

1. **Read anything.** A profile restricts writing, never reading. Most work here
   crosses pages, and an agent that refused to read the costing sheet could not
   check an estimate against a specification.
2. **Stop and ask before you write outside their profile.** Say which surface you
   want to change and which profile it belongs to, and wait for an explicit
   answer. Do not work around it by writing the same content somewhere else.

When `profiles.enabled` is `false` or the object is absent, this project has not
asked for any of it. Do not ask for approval you were not told to ask for.

### If `specs_from` is set, the specifications are not here

Read `specs_from` in the same file. When it names a repository, this repository is
a **linked child**: it holds application code, and the repository named there
holds the specifications for it.

```bash
cat .agents/konvoy.json | grep '"specs_from"'
```

Three rules follow, and they matter more than convenience:

1. **Never create a specification here.** Not under `openspec`, not under
   `specs/`. A specification written in a child is a second source of truth, and
   the team reads the parent.
2. **Read the specification from the parent repository.** Ask for its path, or for
   the text itself. Say plainly that you need it — guessing the content of a
   specification you cannot read produces code nobody asked for.
3. **Write code, tests and code-level documentation here.** That is what a child
   is for.

When `specs_from` is absent or empty, this repository owns its own
specifications — the single-repository layout — and the rest of this skill
applies unchanged.

| key | default | holds |
| --- | --- | --- |
| `openspec` | `docs/openspec` | the specifications |
| `adr` | `docs/decisions` | the decision records |
| `personas` | `docs/personas/personas.json` | the personas, on the Team tab |
| `costing` | `docs/costing` | the costing sheets |
| `planning` | `docs/planning` | the members and their availability, on the Team tab; the schedule the Planning tab draws |
| `delivery` | `docs/delivery` | delivery notes, impacts, tickets, questions |
| `drawings` | `docs/drawings` | boards: Excalidraw, draw.io, Mermaid, BPMN |
| `diagrams` | `docs/diagrams` | LikeC4 models |
| `designs` | `docs/designs` | prototypes and mockups |
| `slides` | `docs/slides` | markdown decks |
| `openapi` | `docs/api` | OpenAPI contracts |
| `data_models` | `docs/data-models` | DBML schemas |
| `flows` | `docs/network/flows.json` | network flows |

## 2. Rules

These are enforced by the application. Working around them produces a repository
Konvoy can no longer read.

- **Never commit and never push.** The user commits from Konvoy, which marks the
  message and keeps the working tree reviewable. Leave your work uncommitted.
- **Never write a secret** into the repository. Credentials live in the system
  keychain; Konvoy puts them there.
- **Never edit `.agents/konvoy.json` by hand.** It is the provisioning ledger,
  and the application is its only writer.
- **Never edit `.agents/skills/` or `.claude/skills/` by hand.** Those are
  vendored; they are adopted and removed from the Agent Compass tab.
- **Never write to a repository-root `specs/`.** This project's specification
  root is the `openspec` path above. Two roots means half the specs stop being
  read.
- `AGENTS.md` and the provider files at the repository root are this project's
  contract. They win over anything here.

## 3. Formats

- **Specifications** — OpenSpec. `specs/<capability>/spec.md` is what exists;
  `changes/<id>/{proposal,tasks,design}.md` is work in flight;
  `changes/archive/` is what shipped. Requirements sit under one
  `## Requirements` heading, one `### Requirement:` each, with `#### Scenario:`
  below and GIVEN/WHEN/THEN bullets.
- **Decision records** — MADR 4.0, one file per decision, named `NNNN-slug.md`.
  YAML frontmatter carries `status` and `date`. Keep the options that lost: that
  is the part a reader cannot reconstruct.
- **Personas** — one JSON document with a `personas` array, written on the
  **Team** tab beside the members and their availability. The costing and the
  schedule join on the persona id, so an id that changes breaks both. A persona
  is a role: `username` names who fills it, and `active` says the project still
  uses it. Each persona carries two daily rates: `tjm` is the sale rate and
  `cjm` is the internal cost. The difference between them is the margin.
- **Costing** — one JSON sheet per wave of work. Write MVP 1, MVP 2 and the
  evolutions as separate files; do not put a scope column inside one sheet.
  A sheet holds `meta`, `groups`, `features` and `plan`:
  - `meta` — `name`, `status` (`draft`, `review`, `frozen`, `archived`),
    `currency`, `marginRate` as a fraction, `startDate` as `YYYY-MM-DD`, `notes`.
    Never edit a sheet whose status is `frozen` or `archived`.
  - `groups` — the product, lot or module above the features. Optional. A
    feature names its group with `groupId`, or `""` to stay ungrouped.
  - `features` — each holds `tasks`. Complexity from 1,2,3,5,8,13,21; priority
    P0–P4; MoSCoW; basis. A task points at a persona by id and at its
    predecessor by task id.
  - `plan` — man-days per persona per month, keyed by persona id, index `0`
    being the month `meta.startDate` names.

  A task states its size in one of two ways, and `chargeType` says which:
  `"days"` means `mandays` is man-days, and `"ratio"` means `mandays` is a
  **percentage of the build total**. Use `ratio` for work that scales with
  everything else — management, quality assurance, a warranty period — and set
  `"kind": "other"` on it, so it does not feed the total it takes its own
  percentage of. Everything else is `"kind": "build"`.

  Use `"basis": "assistant-suggested"`, never `"human"` — a human decides that.
  Write `"reviewed": false` on every task you add, for the same reason: only a
  reviewed estimate can be pinned.
- **Boards** — one file per board, in whichever of four formats the extension
  names. The Schemas tab picks its editor from that extension, so the extension is
  the decision. Prefer the text format (`.mmd`) when a reviewer should be able to
  read the board in a `git diff`; prefer a canvas format (`.excalidraw`,
  `.drawio`, `.bpmn`) when position and grouping carry meaning.
  - `.excalidraw` — Excalidraw JSON:
    `{"type":"excalidraw","version":2,"source":"konvoy","elements":[],"appState":{},"files":{}}`.
    Every element needs id, type, x, y, width, height, angle, strokeColor,
    backgroundColor, fillStyle, strokeWidth, strokeStyle, roughness, opacity,
    groupIds, seed and version.
  - `.drawio` — draw.io mxGraph XML. Write it **uncompressed**, so the board
    survives a `git diff` and a merge: `<mxfile><diagram><mxGraphModel><root>`
    with the two mandatory cells `<mxCell id="0"/>` and
    `<mxCell id="1" parent="0"/>`, then one `mxCell` per shape with `vertex="1"`
    and one per connector with `edge="1"`, `source` and `target`. The label goes in
    the `value` attribute.
  - `.drawio.svg` — the same model inside a picture: draw.io writes the XML into the
    root `<svg>` element's `content` attribute, so the file renders in GitLab and
    GitHub and stays editable. Only draw.io writes this form; never hand-write it.
  - `.mmd` or `.mermaid` — Mermaid text, for example `flowchart TD` followed by
    `A[Payment API] --> B[(Ledger)]`.
  - `.bpmn` — BPMN 2.0 XML. A `<bpmn:definitions>` needs a `<bpmn:process>` **and**
    a `<bpmndi:BPMNDiagram>` placing every element; a model with no diagram
    interchange is valid XML that the editor refuses to open.
- **Questions** — one file per item under `<delivery>/questions`: a question,
  risk, assumption, issue or dependency, moving open → assigned → answered →
  folded. `folded` means the answer went back into the spec.

## 4. Workflows

### The specs changed — realign the implementation

Asked as "the specs/mockups/design changed, what does the code have to change?".
Do it in this order and report each step:

1. Read the current `<openspec>`, `docs/design.md` and `<designs>`.
2. Use **git** to find what changed there and when. The real diff, not your
   recollection of the files.
3. Read the implementation. Per requirement, say: satisfied, drifted, or never
   built.
4. Write the plan into `<delivery>` as a delivery note — one entry per gap, each
   with the requirement it comes from, the files it touches, the acceptance test
   that proves it, and a size.
5. List what you could not decide, and why.

Produce the plan. Do not change the implementation in the same pass: a plan the
user has not read is not a plan they agreed to.

### The specs and the team are in place — plan the delivery

Read `<openspec>`, `<personas>`, `<planning>` and any existing `<costing>`, then
produce in this order, stopping for review between each:

1. A costing sheet in `<costing>`.
2. A split of the work across the teams, into `<delivery>`, chosen so two teams
   touch as few of the same files as possible. Name every seam where they still
   have to agree, and the contract at that seam.
3. A schedule in `<planning>` respecting presence windows, absences and the
   predecessor links, with the critical path named.
4. The three assumptions the whole plan rests on, and what breaks if each is
   wrong.

### Derive rather than invent

The chain runs one way, and each step reads the one before it:

```
specs → personas → costing → members and availability → planning
specs → delivery notes → tickets
specs → questions (what the specs do not answer)
```

Never invent a persona the specs do not imply, or a task no requirement asks
for. When something is missing, say so and ask — a plausible invention costs
more to find than a gap.

## 5. Before you finish

- Say which files you wrote, and which path key each came from.
- Say what you assumed.
- Leave the work uncommitted. The user reviews a diff before it becomes history.
