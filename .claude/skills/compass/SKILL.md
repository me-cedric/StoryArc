---
name: compass
description: Set up, update, migrate, extend and promote agent-compass in a project with the ac CLI. Use when the user asks to install, sync, upgrade or extend compass, or to move a project skill into compass.
risk_level: medium
writes_files: true
requires_tools: [node, git]
disable-model-invocation: true
---

# compass

Run `ac` from the project root. It never prompts.
Exit 0 is success. Exit 1 is an error or drift. Exit 2 is a usage error.
Every command takes `--dry` (show the changes, write nothing) and `--json`.

Commands that exist: `ac init`, `ac sync`, `ac sync --to <tag>`, `ac check --frozen`, `ac doctor --tokens`.
Dev-loop commands: `ac env`, `ac dev` and `ac run`. The skills `env`, `local-run` and `e2e` tell how to use them.
`ac ui` opens the local web UI: assets on and off, the recommended set for the stack, env, run, tests, usage, delivery, promote.
`ac usage` shows tokens and cost by day, project and model. `ac promote <skill>` copies a project skill into compass.
Compass owns the text between its markers and the files that `ac sync` lists. Put project rules outside the markers.

## init

1. Confirm that the project is a git repository.
2. Run `ac init --dry --json`. Read the plan.
3. Run `ac init`. It creates `.agents/compass.json` and then syncs.
4. Run `ac doctor`. Fix each `fail` line. Report each `warn` line.
5. Run `ac check --frozen`. It must pass.
6. Report the changed files and the command results.

A project that has specs starts with `spec-flow`, section "Init from specs".

## update

1. Run `ac sync --dry --json`. Read each change.
2. Run `ac sync`. To move to another compass version, run `ac sync --to <tag>`.
3. An item with the action `kept` is a file that the project edited. Compass keeps the edit.
4. To take the update for a kept item, revert the file. To stop updates for it, add its path to `exclude` in `.agents/compass.json`.
5. Run `ac check --frozen`. Then run `ac doctor --tokens`.
6. Do not edit a managed file to change compass behavior. Change compass, or add the path to `exclude`.

## migrate

Use this for an old install: a submodule, a vendored copy, `.agent/agent-compass.lock`, or double skill copies.

1. Run `ac migrate --dry`.
2. If `ac` prints "migrate needs --docs", stop. Tell the user that this compass version migrates only the docs layout. For the docs, use `spec-flow`.
3. Show the plan to the user. Run `ac migrate` only after a yes.
4. Run `ac check --frozen`. Report each file that the command kept because the project edited it.

## extend

Add a skill, rule or pack to compass itself.

1. Pick the place: a skill in `skills/<name>/SKILL.md`, a rule in `rules/`, a pack in `packs/<name>/`.
2. Use a generic name. Never use a client, project or person name. `node scripts/check-naming.mjs` fails on them.
3. Write the skill frontmatter keys in this order: `name`, `description`, `risk_level`, `writes_files`, `requires_tools`.
4. Add `disable-model-invocation: true` for a skill that only the user starts.
5. Add `metadata.stacks` for a skill that fits some stacks only.
6. Keep the description of a model-invoked skill to 220 characters or fewer. Keep the SKILL.md body to 120 lines or fewer.
7. Write each repository path as a path placeholder: the key of `PATH_DEFAULTS` in `engine/config.mjs` in capitals, with `_DIR` or `_FILE`, in double braces. Any other double-brace token with capital letters is an install error.
8. Add or change a test in `test/` for each changed script.
9. Run `npm run check`. Fix each finding.
10. Do not commit unless the user asks.

## promote

Move a project skill, named `<project>-<name>`, into compass.

1. Run `ac promote`.
2. If `ac` prints "Unknown command", stop. Tell the user that this compass version has no promote command.
3. Check the result before you accept it:
   - The name is generic.
   - The text has no secret, client name, project name or hard-coded path.
   - The frontmatter follows section "extend".
4. Report the promoted skill and the project copy that the user can now remove.
