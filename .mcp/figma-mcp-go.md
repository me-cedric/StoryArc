# figma-mcp-go Setup

`figma-mcp-go` is a free/local Figma MCP bridge. It uses a Figma plugin instead
of the Figma REST API, so it avoids REST API rate limits and does not require a
Figma API token.

Source: <https://github.com/vkhanhqui/figma-mcp-go>

## Requirements

- Node.js and an MCP-compatible client.
- Figma Desktop.
- Edit role on the target Figma file. Figma plugins run from the editor, so
  view-only access is not enough.
- The `figma-mcp-go` Figma plugin imported and running in the open file.

## Install The Figma Plugin

1. Download `plugin.zip` from the `figma-mcp-go` releases page:
   <https://github.com/vkhanhqui/figma-mcp-go/releases>
2. Unzip it locally.
3. In Figma Desktop, open the target file.
4. Use `Plugins -> Development -> Import plugin from manifest`.
5. Select the unzipped `manifest.json`.
6. Run the plugin inside the target file.

Keep the plugin running while using MCP tools.

## MCP Config

Generic MCP clients:

```json
{
  "mcpServers": {
    "figma-mcp-go": {
      "command": "npx",
      "args": ["-y", "@vkhanhqui/figma-mcp-go@latest"]
    }
  }
}
```

Codex:

```toml
[mcp_servers.figma_go]
enabled = true
required = false
command = "npx"
args = ["-y", "@vkhanhqui/figma-mcp-go@latest"]
enabled_tools = ["get_metadata", "get_selection", "get_design_context", "export_tokens"]
default_tools_approval_mode = "prompt"
```

Projects that require pnpm can replace `npx -y` with:

```bash
pnpm dlx @vkhanhqui/figma-mcp-go@latest
```

## Recommended Allowlist

Start with read/export tools only:

- `get_metadata`
- `get_pages`
- `get_document`
- `get_selection`
- `get_node`
- `get_nodes_info`
- `get_design_context`
- `search_nodes`
- `scan_text_nodes`
- `scan_nodes_by_types`
- `get_viewport`
- `get_styles`
- `get_variable_defs`
- `get_local_components`
- `get_annotations`
- `get_fonts`
- `get_reactions`
- `get_screenshot`
- `export_tokens`

Write tools exist upstream. Do not enable them in shared config unless the team
has accepted the risk and added explicit tool-contract rows.

## Usage Rules

- Prefer `get_selection`, then `get_design_context` on one selected frame or
  component.
- For large files, avoid broad `get_document`, broad `search_nodes`, and full
  page context unless there is no smaller target.
- Ask the designer/user to select the exact frame or component before querying.
- Use exported tokens as supporting evidence, then map them to local tokens and
  existing shared components.
- Do not copy generated CSS blindly. Follow the project's design system.

## Troubleshooting

No tools:

- Restart the MCP client.
- Confirm the client config includes `figma-mcp-go`.

Plugin connection fails:

- Confirm the plugin is running in Figma Desktop.
- Confirm the Figma file is open.
- Confirm you have edit role on the file.

Selection is empty:

- Select one frame, component, or instance in Figma.
- Retry `get_selection`.

Calls time out:

- Restart the Figma plugin.
- Use narrower calls: selection first, then context for one node.
- Avoid broad scans on large pages.
