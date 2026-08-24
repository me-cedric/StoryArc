#!/usr/bin/env python3
"""Map a Figma design-token JSON export to a design.md (google-labs-code) file.

Usage: figma_to_designmd.py <tokens.json> <output-design.md> [--name NAME]

Handles the two common token shapes:
  - W3C DTCG:        { group: { token: { "$type": "color", "$value": "#..." } } }
  - Tokens Studio:   { group: { token: { "type": "color", "value": "#..." } } }

Flattens the token tree (dot-joined names), buckets tokens by type into
colors / typography / rounded / spacing, and writes a design.md with YAML front
matter + the canonical section headings. This is a best-effort starting point;
verify the nested schema against the design.md spec and refine by hand.
"""
import json
import sys

TYPE_BUCKET = {
    "color": "colors",
    "dimension": "spacing",
    "spacing": "spacing",
    "space": "spacing",
    "borderradius": "rounded",
    "radius": "rounded",
    "fontfamily": "typography",
    "fontfamilies": "typography",
    "fontsize": "typography",
    "fontsizes": "typography",
    "typography": "typography",
    "fontweight": "typography",
    "lineheight": "typography",
}

SECTIONS = [
    "Overview", "Colors", "Typography", "Layout",
    "Elevation & Depth", "Shapes", "Components", "Do's and Don'ts",
]


def walk(node, path, out):
    """Collect (dotted-name, type, value) leaves from a nested token tree."""
    if not isinstance(node, dict):
        return
    value = node.get("$value", node.get("value"))
    typ = node.get("$type", node.get("type"))
    if value is not None and not isinstance(value, dict):
        out.append((".".join(path), (typ or "").lower(), value))
        return
    for key, child in node.items():
        if key in ("$value", "value", "$type", "type", "$description", "description"):
            continue
        walk(child, path + [key], out)


def yaml_scalar(value) -> str:
    s = str(value)
    if s == "" or any(c in s for c in ":#{}[],&*?|<>=!%@`\"'") or s.strip() != s:
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return s


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--name"]
    name = "Design System"
    if "--name" in sys.argv:
        i = sys.argv.index("--name")
        if i + 1 < len(sys.argv):
            name = sys.argv[i + 1]
            args = [a for a in args if a != name]
    if len(args) != 2:
        print("usage: figma_to_designmd.py <tokens.json> <output-design.md> [--name NAME]", file=sys.stderr)
        sys.exit(2)
    src, dst = args[0], args[1]

    with open(src, encoding="utf-8") as fh:
        data = json.load(fh)

    leaves = []
    walk(data, [], leaves)

    buckets = {"colors": {}, "typography": {}, "rounded": {}, "spacing": {}}
    for dotted, typ, value in leaves:
        bucket = TYPE_BUCKET.get(typ)
        if bucket is None:
            # fall back to name hints when the token has no usable $type
            low = dotted.lower()
            if "color" in low:
                bucket = "colors"
            elif "radius" in low or "round" in low:
                bucket = "rounded"
            elif "font" in low or "text" in low or "type" in low:
                bucket = "typography"
            elif "space" in low or "spacing" in low or "gap" in low:
                bucket = "spacing"
            else:
                continue
        buckets[bucket][dotted] = value

    lines = ["---", f"name: {yaml_scalar(name)}"]
    for bucket in ("colors", "typography", "rounded", "spacing"):
        entries = buckets[bucket]
        if not entries:
            continue
        lines.append(f"{bucket}:")
        for k, v in entries.items():
            lines.append(f"  {yaml_scalar(k)}: {yaml_scalar(v)}")
    lines.append("---")
    lines.append("")

    for section in SECTIONS:
        lines.append(f"## {section}")
        lines.append("")
        if section == "Overview":
            lines.append(f"Design tokens for **{name}**, imported from Figma.")
        else:
            lines.append("<!-- TODO: describe -->")
        lines.append("")

    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")

    total = sum(len(b) for b in buckets.values())
    print(f"wrote {dst}: {total} tokens "
          f"(colors={len(buckets['colors'])}, typography={len(buckets['typography'])}, "
          f"rounded={len(buckets['rounded'])}, spacing={len(buckets['spacing'])})")


if __name__ == "__main__":
    main()
