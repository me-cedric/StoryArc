# OpenSpec: the root, config.yaml and a checklist gate

Read this when the project uses the OpenSpec CLI.

## The one root

- The CLI resolves one root. An empty `changes/archive/` left by a move makes `openspec status` report `No changes exist`, which reads as an empty project. Remove the stray folder.
- `openspec update` writes the twelve workflow files. It needs the root at `<project>/openspec` and reads the agent folders (`.claude/`, `.github/`) from the same `<project>`.
  Compass keeps the root at `docs/openspec`, so run `openspec update` only when the project also keeps that root, or generate the workflow files from the installed package.
- `openspec validate` checks that each present file is well formed. `openspec status --change <name> --json` checks that each required file is present. Use `status` as the gate.

## config.yaml is the injection point

A rule in the root `config.yaml` reaches the agent through `openspec instructions` at the moment it writes that artifact. It works better than the same rule in `AGENTS.md`.

- Put each rule under the id of the artifact that it governs (`proposal`, `specs`, `design`, `tasks`). A `rules` group that is not an artifact id is never delivered.
- Quote a list item that holds `": "`. An unquoted one is a YAML syntax error, and the CLI reports `No changes exist` instead of the error.
  Write `- 'Write "[NEEDS CLARIFICATION: question]" for an unknown.'` with the quotes.
- A rule cannot override a value that the CLI controls, and it cannot unblock a blocked artifact.

## A checklist gate

```bash
openspec schema fork spec-driven <project-name>
```

Then edit `<openspec>/schemas/<project-name>/schema.yaml`: add a `checklist` artifact and put `checklist` in `apply.requires`. Set `schema: <project-name>` in `config.yaml`.
An existing change pins its own schema in `.openspec.yaml` and keeps the old chain.

## Rules for the agent

1. Read the spec before the code. When the behavior is not in `<openspec>/specs/`, propose the change first.
2. A planning workflow writes no code, even when the request asked to build something.
3. The plan, the delta and the tasks belong to the change that produces the behavior, never to the settled capability. Ask "which change is this work part of".
4. Run `openspec status` before each artifact. Write the artifact that it names `ready`. Never write around a `blocked` one.
