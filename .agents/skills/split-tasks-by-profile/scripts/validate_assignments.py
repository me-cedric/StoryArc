#!/usr/bin/env python3
"""Validate an assignments document (delivery work split by profile).

Usage: validate_assignments.py <assignments.json> [personas.json]

Checks the shape the `split-tasks-by-profile` skill writes: every key present
with the right type, item ids unique across the whole document, gates
referencing real items, seams referencing real profiles, and scope paths that
are repo-relative. When a personas file is given, every non-empty `personaId`
must resolve to a persona.

Prints `OK` on success; exits non-zero listing every problem found (not just the
first, so one run is enough to fix the document).
"""
import json
import os
import sys

ASSIGNMENT_KEYS = ["personaId", "personaName", "scope", "brief", "items", "seams"]
ITEM_KEYS = ["id", "title", "why", "firstSteps", "specRef", "taskRef", "mandays", "gate"]
SEAM_KEYS = ["with", "contract", "rule"]
GATE_KEYS = ["what", "blocks", "unblockedBy", "approver"]

problems: list[str] = []


def bad(msg: str) -> None:
    problems.append(msg)


def load(path: str, what: str):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        print(f"ERROR: {what} not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"ERROR: {what} is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(1)


def check_keys(obj, keys, where: str) -> bool:
    """Exact key set. Returns False when `obj` is not even an object."""
    if not isinstance(obj, dict):
        bad(f"{where} must be an object")
        return False
    for key in keys:
        if key not in obj:
            bad(f"{where} is missing required key '{key}'")
    for key in sorted(set(obj) - set(keys)):
        bad(f"{where} has unexpected key '{key}'")
    return True


def check_str_list(value, where: str) -> None:
    if not isinstance(value, list):
        bad(f"{where} must be an array")
        return
    for i, item in enumerate(value):
        if not isinstance(item, str):
            bad(f"{where}[{i}] must be a string")


def check_scope(value, where: str) -> None:
    check_str_list(value, where)
    if not isinstance(value, list):
        return
    for i, path in enumerate(value):
        if not isinstance(path, str):
            continue
        if path.startswith("/") or ".." in path.replace("\\", "/").split("/"):
            bad(f"{where}[{i}] must be repo-relative without '..': {path!r}")


def main() -> None:
    if len(sys.argv) not in (2, 3):
        print("usage: validate_assignments.py <assignments.json> [personas.json]", file=sys.stderr)
        sys.exit(2)

    doc = load(sys.argv[1], "assignments file")

    persona_ids: set[str] = set()
    if len(sys.argv) == 3 and os.path.exists(sys.argv[2]):
        personas_doc = load(sys.argv[2], "personas file")
        for persona in personas_doc.get("personas", []) or []:
            if isinstance(persona, dict) and isinstance(persona.get("id"), str):
                persona_ids.add(persona["id"])

    if not isinstance(doc, dict):
        print("ERROR: top level must be an object", file=sys.stderr)
        sys.exit(1)
    if not isinstance(doc.get("version"), int):
        bad('"version" must be an integer')
    if not isinstance(doc.get("generatedAt"), str):
        bad('"generatedAt" must be a string (YYYY-MM-DD)')
    check_str_list(doc.get("sources"), '"sources"')
    if not isinstance(doc.get("overlapRisk"), str):
        bad('"overlapRisk" must be a string')

    assignments = doc.get("assignments")
    if not isinstance(assignments, list):
        print('ERROR: "assignments" must be an array', file=sys.stderr)
        sys.exit(1)

    item_ids: set[str] = set()
    profile_names: set[str] = set()

    for a_i, assignment in enumerate(assignments):
        where = f"assignments[{a_i}]"
        if not check_keys(assignment, ASSIGNMENT_KEYS, where):
            continue

        persona_id = assignment.get("personaId")
        if not isinstance(persona_id, str):
            bad(f"{where}.personaId must be a string ('' when no persona fits)")
        elif persona_id and persona_ids and persona_id not in persona_ids:
            bad(f"{where}.personaId '{persona_id}' is not in the personas file")

        name = assignment.get("personaName")
        if not isinstance(name, str) or not name.strip():
            bad(f"{where}.personaName must be a non-empty string")
        else:
            profile_names.add(name)

        if not isinstance(assignment.get("brief"), str):
            bad(f"{where}.brief must be a string")
        check_scope(assignment.get("scope"), f"{where}.scope")

        items = assignment.get("items")
        if not isinstance(items, list):
            bad(f"{where}.items must be an array")
            items = []
        for i_i, item in enumerate(items):
            iwhere = f"{where}.items[{i_i}]"
            if not check_keys(item, ITEM_KEYS, iwhere):
                continue
            item_id = item.get("id")
            if not isinstance(item_id, str) or not item_id.strip():
                bad(f"{iwhere}.id must be a non-empty string")
            elif item_id in item_ids:
                bad(f"{iwhere}.id duplicates an earlier item: {item_id}")
            else:
                item_ids.add(item_id)
            for key in ("title", "why", "specRef", "taskRef", "gate"):
                if not isinstance(item.get(key), str):
                    bad(f"{iwhere}.{key} must be a string")
            if not isinstance(item.get("mandays"), (int, float)) or isinstance(item.get("mandays"), bool):
                bad(f"{iwhere}.mandays must be a number (0 when unknown)")
            check_str_list(item.get("firstSteps"), f"{iwhere}.firstSteps")

        seams = assignment.get("seams")
        if not isinstance(seams, list):
            bad(f"{where}.seams must be an array")
            seams = []
        for s_i, seam in enumerate(seams):
            check_keys(seam, SEAM_KEYS, f"{where}.seams[{s_i}]")

    gates = doc.get("gates")
    if not isinstance(gates, list):
        bad('"gates" must be an array')
        gates = []
    gate_whats: set[str] = set()
    for g_i, gate in enumerate(gates):
        gwhere = f"gates[{g_i}]"
        if not check_keys(gate, GATE_KEYS, gwhere):
            continue
        for key in ("what", "unblockedBy", "approver"):
            if not isinstance(gate.get(key), str):
                bad(f"{gwhere}.{key} must be a string")
        if isinstance(gate.get("what"), str):
            gate_whats.add(gate["what"])
        check_str_list(gate.get("blocks"), f"{gwhere}.blocks")
        for b_i, blocked in enumerate(gate.get("blocks") or []):
            if isinstance(blocked, str) and blocked not in item_ids:
                bad(f"{gwhere}.blocks[{b_i}] references unknown item id '{blocked}'")

    # Cross-references resolved only once every id / name is known.
    for a_i, assignment in enumerate(assignments):
        if not isinstance(assignment, dict):
            continue
        for i_i, item in enumerate(assignment.get("items") or []):
            if isinstance(item, dict):
                gate = item.get("gate")
                if isinstance(gate, str) and gate and gate not in gate_whats:
                    bad(f"assignments[{a_i}].items[{i_i}].gate '{gate}' has no matching entry in gates[]")
        for s_i, seam in enumerate(assignment.get("seams") or []):
            if isinstance(seam, dict):
                other = seam.get("with")
                if isinstance(other, str) and other and other not in profile_names:
                    bad(f"assignments[{a_i}].seams[{s_i}].with '{other}' is not a personaName in this document")

    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        sys.exit(1)

    print(f"OK ({len(assignments)} profiles, {len(item_ids)} items, {len(gates)} gates)")


if __name__ == "__main__":
    main()
