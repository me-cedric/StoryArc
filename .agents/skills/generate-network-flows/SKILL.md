---
name: generate-network-flows
description: Generate or extend the project's network-flow (IPAM) list as validated JSON. Use when the user asks to add network flows, firewall rules, ingress/egress rules, or to build the IPAM flows document. Emits objects in the exact app schema and validates every field.
license: MIT
allowed-tools: Read Write Edit Bash(python3:*)
metadata:
  version: "1"
---

# Generate network flows

Produce network-flow objects that the Konvoy **Network flows** tab renders, written to the app's flows document.

## Output

File: `docs/network/flows.json` — a single JSON object:

```json
{ "version": 1, "flows": [ /* flow objects */ ] }
```

If the file already exists, **read it first and append** to `flows`; never drop existing entries. Preserve their `id`s.

## Flow object — exact shape

Every flow object MUST have exactly these keys, all strings unless noted:

```json
{
  "id": "<uuid v4>",
  "name": "",
  "description": "",
  "source": "",
  "destination": "",
  "cidr": "",
  "vlan": "",
  "subnet": "",
  "protocol": "TCP",
  "ports": "",
  "direction": "Ingress",
  "action": "Allow"
}
```

Rules:
- `id` — a fresh UUID v4 per new flow. Do not reuse.
- `protocol` — one of `TCP`, `UDP`, `ICMP`, `Any` (free string, but prefer these).
- `direction` — exactly one of `Ingress`, `Egress`, `Both`.
- `action` — exactly one of `Allow`, `Deny`.
- `ports` — a string, e.g. `"443"` or `"8000-8100"` or `""`.
- All keys are always present; use `""` for unknown values (never omit a key, never use `null`).

## Procedure

1. Gather the flows to add from the user's request (source, destination, ports, direction, action, etc.).
2. Read `docs/network/flows.json` if it exists; otherwise start from `{ "version": 1, "flows": [] }`.
3. Append the new flow objects (generate a UUID v4 for each `id`).
4. Write the merged document to `docs/network/flows.json`.
5. **Validate** by running the bundled validator, which checks every field/type/enum and fills any missing UUIDs in place:

   ```bash
   python3 scripts/validate_flows.py docs/network/flows.json
   ```

   Fix any error it reports and re-run until it prints `OK`.

Do not reformat unrelated parts of the file or reorder existing flows.
