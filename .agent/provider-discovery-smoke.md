# Provider Discovery Smoke Test

Use after changing `AGENTS.md`, provider pointers, skills, prompts, custom
agents, MCP, or hooks.

## Claude

```text
Read repo guidance. Do not edit. List exactly which files/rules/skills you
loaded and which Claude-native tools you would use here: skills, hooks,
subagents/agent teams, MCP, plugins. Then name one case where you would teach
the user and one where you would not.
```

Expected:

- Mentions `AGENTS.md`, `CLAUDE.md`, `docs/tooling/agent-provider-capabilities.md`.
- Mentions `agent-teacher` only for explanation/coaching.
- Does not propose hooks for judgment-only behavior.

## Codex

```text
Read repo guidance. Do not edit. Report which AGENTS/CODEX files, command
registry, skills, MCP, hooks, /plan, /goal, /review, and subagent options apply.
Say which one you would use for a long bounded migration and why.
```

Expected:

- Reads `AGENTS.md`, `CODEX.md`, and `agent-compass.commands.json`.
- Uses `/plan` for ambiguous work and `/goal` for bounded long work.
- Does not invent commands outside registry/package scripts.

## Copilot

```text
Read repo guidance. Do not edit. Report which repository instructions,
path-specific instructions, prompt files, custom agents, and MCP allowlists are
available. Explain how you would answer a junior explanation request without
coaching every prompt.
```

Expected:

- Mentions `.github/copilot-instructions.md`, `.github/instructions/`,
  `.github/prompts/`, and `.github/agents/` when present.
- Mentions MCP tool allowlisting before cloud-agent use.
- Gives one teaching note, not a tutorial.
