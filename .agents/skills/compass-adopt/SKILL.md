---
name: compass-adopt
description: >
  Wire agent-compass into an existing project end-to-end with minimal user
  input: detect the stack, run non-interactive setup, install only what fits,
  verify, and report. Use when the user asks to "set up", "adopt", "install
  agent-compass into", or "make agentic" an existing repository.
risk_level: medium
writes_files: true
requires_tools: []
---

# Compass Adopt — set up an existing project

Mission: an existing repository leaves this playbook with the agent contract,
command registry, specs/memory starters, provider pointers, MCP examples, and
only the skills/templates that fit its stack — verified, with a readiness
report.

Paths below assume you run from the agent-compass checkout; from a host that
vendors it, prefix with the submodule path (usually `docs/agent-compass/`).

## Inputs (ask only for what detection cannot answer)

1. **Host path** — required. Everything else has a detectable default.
2. **Vendoring mode** — submodule (tracked updates; default when the user wants
   to keep receiving improvements) vs standalone copy (no submodule). Ask once
   if the user gave no signal.
3. **Team shape** — maps to a policy pack: `solo-dev` (default), `startup-fast`,
   `strict-enterprise`, `regulated-api`. Infer from context before asking.

## Fast path

When the defaults fit (detected stacks, fit-based skill subset, `solo-dev`-ish
setup), one command does steps 3–7:

```bash
node scripts/adopt.mjs /path/to/host
```

Then jump to step 6 (fill the command registry with real commands) and step 8
(report). Use the granular steps when the user stated preferences or something
fails.

## Steps

1. **Inspect the host.** Read its `package.json`, lockfiles, and top-level
   directories. Confirm it is a git repo. Then let detection do the work:

   ```bash
   node scripts/recommend.mjs /path/to/host --json
   ```

   This reports detected stacks and setup gaps. Do not re-derive by hand.

2. **Vendor (submodule mode only).** From the host root:

   ```bash
   git submodule add <agent-compass-url> docs/agent-compass
   ```

   Skip for standalone mode — the scripts work from any checkout.

3. **Run non-interactive setup.** Detection fills the answers; `--yes` skips
   prompts:

   ```bash
   node scripts/setup-wizard.mjs /path/to/host --yes
   ```

   If the user stated preferences (scope, providers, skill sync mode), write
   `agent-compass.answers.json` in the host first, run the wizard with
   `--no-run`, review the plan, then run
   `node scripts/setup-host.mjs /path/to/host --strict`.

4. **Apply the policy pack** matching the team shape:

   ```bash
   node scripts/apply-recommendations.mjs /path/to/host --policy solo-dev
   ```

5. **Select what fits — do not install everything.** Fit-based selection is
   data-driven (`scripts/lib/profiles.mjs`): detection maps the host to stack
   ids, profiles map stack ids to assets. Get the selection and sync exactly it:

   ```bash
   node scripts/recommend.mjs /path/to/host --json   # → assets.skills/templates/docs
   node scripts/skills-sync.mjs /path/to/host --only <assets.skills, comma-joined>
   ```

   Working-style skills (`caveman`, `ponytail`, …) are user preference — add
   them only if the user wants them. Point the host's docs/instructions at the
   `assets.docs` list rather than copying those files. Browse everything else
   with `node scripts/catalog.mjs --md`.

6. **Fill the command registry with real commands.** Open the host's
   `agent-compass.commands.json` and replace placeholders with the actual
   install/lint/typecheck/test/build commands from the host's `package.json`.
   This is the step agents depend on most; never leave placeholders.

7. **Verify.**

   ```bash
   node scripts/agent-onboard.mjs /path/to/host
   node scripts/install.mjs --doctor --deep /path/to/host
   ```

   Read `.agent/doctor-report.md` and `.agent/recommendations.md` in the host;
   fix criticals (missing pointers, empty registry, broken MCP placeholders).

8. **Recover missing project knowledge.** If the host has code but no reviewed
   specifications or architecture documents, offer `codebase-to-specs`. Keep
   every generated document marked as inferred until a human reviews it. Do not
   run this step when reviewed specifications already exist.

9. **Report** against the Completion Gate: files created, commands run,
   verification results, skipped recommendations with reasons, and the top
   remaining follow-ups from `.agent/recommendations.md`.

## Failure handling

- A script exits non-zero → read its output, fix the cause (usually a missing
  file or non-git host), re-run. Scripts are idempotent and never overwrite.
- Host already has `AGENTS.md` or other agent config → keep it; the installer
  skips existing files. Offer a diff-style summary of what compass would add.
- No `package.json` (non-Node host) → core assets still apply; skip stack
  skills and note that the command registry needs the host's real build/test
  commands regardless of language.
