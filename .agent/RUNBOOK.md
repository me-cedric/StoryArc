# Agent Runbook

## Start Here

1. Read `AGENTS.md`.
2. Read `agent-compass.commands.json` before choosing commands.
3. Read relevant specs under `specs/`.
4. Read project memory summaries and pre-action warnings when configured.
5. Use `docs/architecture/repo-map.md` — match your task type to its Task
   Routing table before broad search, to avoid wrong-layer edits.
6. Use provider-native tools when useful: skills/prompts, MCP, hooks, subagents,
   goals/plans, or review modes. See `docs/tooling/agent-provider-capabilities.md`.
7. Run `node docs/agent-compass/scripts/agent-conformance.mjs --root . --write`
   after changing agent guidance.

## Commands

```json
{
  "schema": 1,
  "packageManager": "<PM>",
  "install": "<PM> install",
  "check": "<PM> check",
  "agentConformance": "node docs/agent-compass/scripts/agent-conformance.mjs --root . --write",
  "agentEvals": "node docs/agent-compass/scripts/agent-evals.mjs --root docs/agent-compass",
  "context": null,
  "doctorReport": null,
  "setupHost": "node docs/agent-compass/scripts/setup-host.mjs . --strict",
  "setupWizard": "node docs/agent-compass/scripts/setup-wizard.mjs .",
  "applyRecommendations": "node docs/agent-compass/scripts/apply-recommendations.mjs .",
  "globalSetupDry": "node docs/agent-compass/scripts/global-setup.mjs $HOME --dry",
  "providerVerify": "node docs/agent-compass/scripts/provider-verify.mjs . --write",
  "specKitBridge": "node docs/agent-compass/scripts/spec-kit-bridge.mjs .",
  "skillsSyncCopy": "node docs/agent-compass/scripts/skills-sync.mjs . --copy",
  "skillsSyncSymlink": "node docs/agent-compass/scripts/skills-sync.mjs . --symlink",
  "skillsListPacks": "node docs/agent-compass/scripts/cli.mjs skills-sync --list-packs",
  "capabilityPackCatalog": "node docs/agent-compass/scripts/cli.mjs catalog --type capability-pack --md",
  "skillsSearch": "node docs/agent-compass/scripts/cli.mjs skills --list",
  "skillQuality": "node docs/agent-compass/scripts/cli.mjs check-skill-quality docs/agent-compass",
  "skillDocsCheck": "node docs/agent-compass/scripts/cli.mjs skill-docs docs/agent-compass --check",
  "upstreamSkillsVerify": "node docs/agent-compass/scripts/cli.mjs upstream-skills docs/agent-compass --verify",
  "upstreamSkillsCheck": "node docs/agent-compass/scripts/cli.mjs upstream-skills docs/agent-compass --check-updates",
  "doctorFix": "node docs/agent-compass/scripts/doctor-fix.mjs .",
  "taskLog": "node docs/agent-compass/scripts/task-log.mjs . --list --markdown",
  "recommend": "node docs/agent-compass/scripts/recommend.mjs . --write",
  "qualityGates": "node docs/agent-compass/scripts/quality-gates.mjs . --write",
  "dashboard": "node docs/agent-compass/scripts/dashboard.mjs . --write",
  "migrationPlan": "node docs/agent-compass/scripts/migration-plan.mjs . --write",
  "policyPackList": "node docs/agent-compass/scripts/policy-pack.mjs . --list",
  "failureMine": "node docs/agent-compass/scripts/failure-mine.mjs . --write",
  "mcpProbe": "node docs/agent-compass/scripts/mcp-probe.mjs . --write",
  "codeIntelStatus": "node docs/agent-compass/scripts/code-intel.mjs status .",
  "codeIntelSetup": "node docs/agent-compass/scripts/code-intel.mjs setup .",
  "codeIntelDoctor": "node docs/agent-compass/scripts/code-intel.mjs doctor .",
  "mcpFigmaGo": "npx -y @vkhanhqui/figma-mcp-go@latest",
  "mcpFigmaGoHelp": "npx -y @vkhanhqui/figma-mcp-go@latest --help",
  "specValidationMap": "node docs/agent-compass/scripts/spec-validation-map.mjs . --write",
  "designImporter": "node docs/agent-compass/scripts/design-importer.mjs . --write",
  "validateChanged": null,
  "lint": null,
  "lintActions": null,
  "typecheck": null,
  "test": null,
  "build": null,
  "projectMemory": {
    "setup": "uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python projectmem && .venv/bin/pjm init",
    "brief": "test -x .venv/bin/pjm && .venv/bin/pjm brief || pjm brief",
    "precheck": "test -x .venv/bin/pjm && .venv/bin/pjm precheck || pjm precheck",
    "show": "test -x .venv/bin/pjm && .venv/bin/pjm show || pjm show",
    "regenerateSummary": "test -x .venv/bin/pjm && .venv/bin/pjm regenerate || pjm regenerate",
    "backfillOptIn": "test -x .venv/bin/pjm && .venv/bin/pjm backfill || pjm backfill"
  },
  "runbook": null,
  "notes": [
    "Replace nulls with real package.json commands.",
    "Agents must use this file before inventing validation commands.",
    "For code changes, fill and run lint + typecheck + relevant tests; add build when config, public exports, routing, or deployment output changed.",
    "After installing projectmem, verify projectMemory commands with pjm --help."
  ]
}
```

## Fit-Based Compass Assets

Detected stacks: Swift iOS.
Skills that fit this project (synced or in the compass checkout):

- `gen-docs`
- `verify-module`
- `verify-quality`
- `verify-change`
- `verify-security`
- `spec-workflow`
- `project-memory`
- `pr-workflow`
- `pr-review-governance`
- `debug-loop`
- `agent-teacher`
- `architecture-advisor`
- `adr-from-meeting`
- `codebase-to-specs`
- `long-running-task`
- `progress-audit`
- `completion-plan`
- `work-splitting`
- `implementation-planning`
- `convert-documents-to-markdown`
- `impact-analysis`
- `delivery-digest`
- `harvest-questions`
- `split-tasks-by-profile`
- `spec-to-tickets`
- `spec-drift-triage`
- `qa-review-pass`
- `diagram-to-adr`
- `diagram-to-likec4`
- `likec4-to-openspec`
- `native-mobile-skills`
- `figma-mcp-frontend`
- `design-taste-skills`
- `ai-native-ui-patterns`
- `high-end-visual-design`
- `minimalist-ui`
- `imagegen-frontend-mobile`

Stack docs worth reading before deep work: `docs/guidelines/coding-style.md`, `docs/guidelines/testing-tdd.md`, `docs/guidelines/documentation.md`, `docs/tooling/native-mobile-skills.md`, `docs/guidelines/accessibility.md`.

## Completion Gate

- changed files
- commands run
- validation result per command
- failures pre-existing or introduced
- remaining risks

## Teaching

Use `docs/workflows/agent-teaching.md` only for explanations, onboarding, or
valuable prompt/tool coaching. Do not coach every turn.

## Provider Smoke Test

Use `.agent/provider-discovery-smoke.md` or generated `.agent/agent-conformance.md`
to ask Claude, Codex, and Copilot which guidance/tools they loaded.
