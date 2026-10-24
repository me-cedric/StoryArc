---
name: spec-flow
description: Write, validate and archive OpenSpec specs (konvoy-delivery schema); map screens, convert docs, draft specs from code, triage drift. Use before code for a feature or unclear task.
risk_level: medium
writes_files: true
requires_tools: [openspec, git]
---

# spec-flow

Use the smallest spec that prevents a misunderstanding.
A tiny edit needs only an inline brief: goal, non-goal, acceptance, validation.

## Layout

OpenSpec lives in `docs/openspec`. The schema is `konvoy-delivery`.

```text
docs/openspec/constitution.md
docs/openspec/changes/<id>/proposal.md
docs/openspec/changes/<id>/specs/<cap>/{spec,plan,checklist,tasks}.md
docs/openspec/changes/archive/
```

## Flow

1. Proposal: write what and why. Do not name a stack. Start with `openspec new change <id>`.
2. Clarify: ask until no high-impact `[NEEDS CLARIFICATION]` remains. Use `grill` for a long interview.
3. Specs: fill the headings of the schema template. Then append the delta section. See `references/delta-section.md`.
4. Plan and tasks: write ordered tasks, tests first. Mark parallel-safe tasks with `[P]`.
5. Apply: implement only after the spec, plan and tasks are stable.
6. Validate, then archive.

```bash
openspec status --change <id> --json
openspec instructions apply --change <id> --json
openspec validate --all --strict --json
openspec archive <id>
```

Read `status` before each step. Do not guess which artifact is ready.
Run `validate` before you report done. Run `archive` only when the user asks.

Run `ac check --docs` before you report done. It checks the RAID files, the ADRs and the screen tags.
It also runs `openspec validate` when the CLI is installed.

## Init from specs

Use this to start a project from input documents: a brief, a tender, meeting notes.

1. Run `ac init --from-specs <dir>`. It creates the layout and copies the documents into `docs/openspec/inbox/<dir name>/`.
2. Convert each document that is not Markdown. See `references/convert-documents.md`.
3. Run `grill` on the inbox. It writes one RAID file for each open question.
4. Write `docs/openspec/constitution.md` if it does not exist. Ask for the governing rules. Do not invent them.
5. Write one change for each feature: the proposal first, then the quartet for each capability.
6. Keep the inbox files. They are the source of each requirement.

## Migrate specs

Use this for a project with spec-kit (`.specify/`, `specs/<feature>/`), a root `specs/` folder or a single-file question list.

1. Run `ac migrate --docs --dry`. Show the plan to the user.
2. Run `ac migrate --docs` only when the user says yes. Each source moves under `migrated/`. Nothing is deleted.
3. Do each `manual` item with the user.
4. Append the delta section to each migrated `spec.md`. See `references/delta-section.md`.
5. Run `ac check --docs`. Report each `openspec validate` failure. Do not hide it.

## Delta section

Read `references/delta-section.md` when you append the delta section to a spec.

## Screens

The registry is `docs/designs/screens.json`. It has one entry per screen:

```json
{ "version": 1, "screens": [
  { "id": "SCR-014", "aliases": ["login"], "route": "/login",
    "figma": { "fileKey": "<key>", "nodeId": "12:345" },
    "stories": ["Auth/LoginForm"], "specRefs": ["auth/spec.md#REQ-003"] } ] }
```

- Tag each requirement of a screen with the line `Screen: SCR-014`. An alias is also correct: `Screen: login`.
- Match a name from the user against `aliases` first.
- An alias belongs to one screen only.
- Take the next free number for a new screen. Never reuse an id.
- `ac check` fails on a tag that is not an id or an alias in the registry.
- `ui-conformance` reads this registry.

## Specs from code

Use this for a codebase that has no specs.

1. Group the code into capabilities. Draft the eight largest first. List the others under "Not covered".
2. Read the entry points, routes, jobs, migrations, schemas and tests. Use the code graph first when the project has one.
3. Put this line under the title of each draft: `> Inferred from code, not reviewed. Drafted from <commit sha>.`
4. Add the sections "Open questions" and "Not covered" to each draft.
5. Never invent a requirement. Never present a likely defect as intended behavior.
6. Never overwrite a spec. Write the draft beside it and name the conflict.
7. Hand the open questions to `grill`.

## OpenSpec CLI

Read `references/openspec.md` for the root rule, the `config.yaml` rules and a checklist gate.

## Drift triage

Read `references/drift-triage.md` when a spec changes after tickets exist.

## Convert documents

Read `references/convert-documents.md` when a task needs the content of a .docx, .pptx, .xlsx, .odt, .rtf, .epub or .pdf file.
