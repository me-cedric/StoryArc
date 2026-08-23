# MCP Tool Contract

One row per **tool** (not just per server). This is what turns "connected
everything" into bounded, auditable autonomy. Keep it next to `.mcp/README.md`
and update it whenever a server's allowlist changes.

## Columns

- **Access** — `read` (cannot change state) or `write` (mutates files, systems,
  or external data). Default new tools to `write` until proven read-only.
- **Sensitivity** — `none` / `local` / `secret` / `personal`. What the tool can
  see or emit.
- **Approval** — `auto` (allowed without prompt), `prompt` (per-call approval),
  or `never` (do not enable).
- **Failure** — the expected failure and what the agent should do.
- **Validation** — how to confirm the tool works before relying on it.

## Contract

| Server | Tool | Access | Sensitivity | Approval | Failure | Validation |
| ------ | ---- | ------ | ----------- | -------- | ------- | ---------- |
| projectmem | get_instructions | read | local | auto | empty on fresh repo | returns guidance text |
| projectmem | get_summary | read | local | auto | empty on fresh repo | returns summary text |
| projectmem | get_project_map | read | local | auto | project map missing | returns project map |
| projectmem | precheck_file | read | local | auto | no warnings found | returns warnings list |
| projectmem | get_issue | read | local | auto | id not found | returns record |
| projectmem | log_issue | write | local | prompt | write denied if read-only mount | new issue appears |
| projectmem | record_attempt | write | local | prompt | write denied if read-only mount | attempt appears in memory |
| projectmem | record_fix | write | local | prompt | write denied if read-only mount | fix appears in memory |
| projectmem | add_decision | write | local | prompt | write denied if read-only mount | decision appears in memory |
| projectmem | add_note | write | local | prompt | write denied if read-only mount | note appears in memory |
| figma | get_file | read | local | prompt | file not open / no auth | returns frames |
| figma | get_selection | read | local | prompt | nothing selected | returns nodes |
| figma-mcp-go | get_metadata | read | local | prompt | plugin not running / no file open | returns file metadata |
| figma-mcp-go | get_pages | read | local | prompt | plugin not running / no file open | returns page list |
| figma-mcp-go | get_document | read | local | prompt | plugin not running / no file open | returns current page tree |
| figma-mcp-go | get_selection | read | local | prompt | nothing selected | returns selected nodes |
| figma-mcp-go | get_node | read | local | prompt | node id not found | returns node data |
| figma-mcp-go | get_nodes_info | read | local | prompt | node ids not found | returns node info |
| figma-mcp-go | get_design_context | read | local | prompt | node unavailable | returns depth-limited design context |
| figma-mcp-go | search_nodes | read | local | prompt | no matches | returns matching nodes |
| figma-mcp-go | scan_text_nodes | read | local | prompt | no text nodes | returns text nodes |
| figma-mcp-go | scan_nodes_by_types | read | local | prompt | no matching types | returns matching nodes |
| figma-mcp-go | get_viewport | read | local | prompt | plugin not running / no file open | returns viewport data |
| figma-mcp-go | get_styles | read | local | prompt | no local styles | returns local styles |
| figma-mcp-go | get_variable_defs | read | local | prompt | no local variables | returns variable collections |
| figma-mcp-go | get_local_components | read | local | prompt | no components | returns local components |
| figma-mcp-go | get_annotations | read | local | prompt | no annotations | returns annotations |
| figma-mcp-go | get_fonts | read | local | prompt | no fonts found | returns fonts used |
| figma-mcp-go | get_reactions | read | local | prompt | no reactions | returns prototype reactions |
| figma-mcp-go | get_screenshot | read | local | prompt | export failed | returns base64 screenshot |
| figma-mcp-go | export_tokens | read | local | prompt | export failed | returns design tokens |
| headroom | headroom_compress | read | local | auto | input too small to compress | returns compressed payload |
| headroom | headroom_retrieve | read | local | auto | id not cached | returns original chunk |
| headroom | headroom_stats | read | none | auto | no session yet | returns token savings |
| angular-cli | get_best_practices | read | none | auto | — | returns best-practices guide |
| angular-cli | search_documentation | read | none | auto | no results | returns doc excerpts |
| angular-cli | list_projects | read | local | auto | no angular.json found | returns workspace projects |
| angular-cli | onpush_zoneless_migration | read | local | auto | not applicable to code | returns migration analysis |
| angular-cli | devserver.wait_for_build | read | local | auto | no dev server running | returns latest build logs |
| angular-cli | ai_tutor | read | none | prompt | interactive; rarely useful in agent runs | returns tutor session |
| angular-cli | devserver.start | write | local | prompt | port in use / build fails | dev server reachable |
| angular-cli | devserver.stop | write | local | prompt | no dev server running | server stops |
| angular-cli | run_target | write | local | prompt | target missing / task fails | target output returned |
| context7 | resolve-library-id | read | none | auto | library not found | returns library id |
| context7 | query-docs | read | none | auto | id not found | returns version-correct docs |
| sequential-thinking | sequentialthinking | read | none | auto | — | returns a reasoning step |
| fetch | fetch | read | none | auto | url unreachable/blocked | returns page markdown |
| playwright | browser_* | write | local | prompt | no browser / no page | drives a real browser |

## Rules

- Allowlist tools explicitly. Never enable a whole server when only a few tools
  are needed.
- Mark every `write` tool `prompt` unless the team has accepted standing
  auto-approval for a specific safe tool.
- `secret`/`personal` tools default to `never` in shared config; enable locally
  only with an explicit, reviewed reason.
- A tool not listed here is **not approved**. Add the row first.

## Provider notes

- **Codex** enforces the allowlist with `enabled_tools` and approval with
  `default_tools_approval_mode` in `config.toml`. See `codex.example.toml`.
- **Copilot cloud / code review** allowlists tools in repo MCP settings; prefer
  read-only tools because configured tools may run autonomously. See
  `copilot-cloud.example.json`.
- **Gemini** config (`.gemini/settings.json`) does **not** express a per-tool
  allowlist. Its contract is enforced by this document plus the client's
  approval prompts — keep `write`/`secret` servers disabled there unless
  approval is on.
