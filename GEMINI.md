# StoryArc — Agent Guide

Read [`AGENTS.md`](AGENTS.md) first. It carries the project-specific contract and
takes precedence over the agent-compass baseline vendored at
[`docs/agent-compass/`](docs/agent-compass/AGENTS.md).

Every behaviour is specified in `docs/openspec/specs/` before it is built. Use the
OpenSpec workflow to propose a change rather than implementing an unspecified one.

The OpenSpec root is `docs/openspec`. The CLI resolves it from `docs/`, so run
`cd docs` before any `openspec` command, or use the `pnpm spec:*` scripts.
