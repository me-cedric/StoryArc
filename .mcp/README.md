# MCP Setup

This project may use MCP servers for agent tools and context.

## Servers

| Name | Purpose | Setup | Secret Location |
| ---- | ------- | ----- | --------------- |
| projectmem | Durable project memory (decisions, failures, fixes) | See `.mcp/projectmem.example.json` | none or local only |
| codebase-memory-mcp | Structural code graph: symbols, callers, dependencies, change impact | See `.mcp/codebase-memory.example.json` | none; fully local |
| figma | Design context | See `.mcp/figma.example.json` | client secret store |
| figma-mcp-go | Figma plugin bridge for free/local design reads | See `.mcp/figma-mcp-go.md` and `.mcp/figma-mcp-go.example.json` | none; requires Figma Desktop plugin running and edit role on the Figma file |
| headroom | Context compression (compress/retrieve/stats) | See `.mcp/headroom.example.json` | none or local only |
| angular-cli | Angular CLI tools + live best practices/doc search | See `.mcp/angular-cli.example.json` (ships `--read-only`) | none |
| research (context7, sequential-thinking, fetch, playwright) | Live docs, reasoning, web pages, browser | See `.mcp/recommended.example.json` + `docs/tooling/mcp-servers.md` | none |

Gemini CLI reads MCP servers from `.gemini/settings.json` instead of `.mcp/`
examples — start from the host's `.gemini/settings.example.json` (template:
`templates/gemini/` in agent-compass).

## Rules

- Do not commit tokens.
- Prefer official servers/plugins.
- Prefer portable stdio commands (`uvx`, `npx`) plus `cwd: "."` for shared
  examples.
- Copy `*.example.json` into your local MCP client config and keep local MCP
  config out of git.
- Verify tool availability before using a server.
- Log only durable facts, never secrets or personal data.
- `codebase-memory-mcp` answers *where the code is*; `projectmem` answers *what
  happened and why*. Do not write structural facts into project memory, and do
  not open a second ADR store through a code-graph tool — `docs/decisions/` is
  canonical.
- Record every enabled tool in [`tool-contract.md`](tool-contract.md) with its
  access (read/write), sensitivity, and approval mode. A tool absent from the
  contract is not approved.

## Figma Free Bridge

`figma-mcp-go` is a local plugin bridge for teams that hit official Figma MCP
or REST API limits. It does not require a Figma API token, but the Figma plugin
must be imported and running in Figma Desktop. Users need edit role on the target
Figma file because plugins run from the editor; view-only access is not enough.

Default shared examples should enable read/export tools first. Upstream write
tools exist, but do not allowlist them until the team has accepted the risk and
updated `tool-contract.md`.

Full setup guide: [`figma-mcp-go.md`](figma-mcp-go.md).
