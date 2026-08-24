#!/usr/bin/env python3
"""Validate (and lightly normalize) a Konvoy network-flows document.

Usage: validate_flows.py <flows.json>

Checks the top-level shape { "version": int, "flows": [ ... ] } and every flow
object against the app schema. Fills a missing/empty `id` with a fresh UUID v4
and writes the file back only if it changed. Prints `OK` on success; exits
non-zero with a precise message on the first error.
"""
import json
import sys
import uuid

REQUIRED_KEYS = [
    "id", "name", "description", "source", "destination",
    "cidr", "vlan", "subnet", "protocol", "ports", "direction", "action",
]
DIRECTIONS = {"Ingress", "Egress", "Both"}
ACTIONS = {"Allow", "Deny"}


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: validate_flows.py <flows.json>", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        fail(f"file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if not isinstance(doc, dict):
        fail("top level must be an object { \"version\": 1, \"flows\": [...] }")
    if not isinstance(doc.get("version"), int):
        fail('"version" must be an integer')
    flows = doc.get("flows")
    if not isinstance(flows, list):
        fail('"flows" must be an array')

    changed = False
    seen_ids = set()
    for i, flow in enumerate(flows):
        where = f"flows[{i}]"
        if not isinstance(flow, dict):
            fail(f"{where} must be an object")
        # exact key set
        extra = set(flow) - set(REQUIRED_KEYS)
        if extra:
            fail(f"{where} has unexpected keys: {sorted(extra)}")
        for key in REQUIRED_KEYS:
            if key not in flow:
                fail(f"{where} is missing required key '{key}'")
            if not isinstance(flow[key], str):
                fail(f"{where}.{key} must be a string (got {type(flow[key]).__name__})")
        # id: fill if empty
        if not flow["id"].strip():
            flow["id"] = str(uuid.uuid4())
            changed = True
        if flow["id"] in seen_ids:
            fail(f"{where}.id duplicates an earlier flow: {flow['id']}")
        seen_ids.add(flow["id"])
        # enums
        if flow["direction"] not in DIRECTIONS:
            fail(f"{where}.direction must be one of {sorted(DIRECTIONS)} (got '{flow['direction']}')")
        if flow["action"] not in ACTIONS:
            fail(f"{where}.action must be one of {sorted(ACTIONS)} (got '{flow['action']}')")

    if changed:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        print(f"OK (filled {len([1 for f in flows])} flows; wrote generated UUIDs)")
    else:
        print(f"OK ({len(flows)} flows valid)")


if __name__ == "__main__":
    main()
