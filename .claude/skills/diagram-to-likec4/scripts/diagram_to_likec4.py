#!/usr/bin/env python3
"""Convert Excalidraw or draw.io structured diagrams into LikeC4.

Usage: diagram_to_likec4.py <input> <output.c4>

Supported inputs:
- .excalidraw JSON
- .drawio XML, including compressed pages
- .drawio.svg with an embedded draw.io model

Mermaid is readable text and is handled by the skill instructions. BPMN is a
process model, not an architecture model, and is intentionally unsupported.
"""

import base64
import html
import json
import re
import sys
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path
from urllib.parse import unquote

SHAPE_TYPES = {"rectangle", "ellipse", "diamond"}
EDGE_TYPES = {"arrow", "line"}
MAX_INPUT_BYTES = 20 * 1024 * 1024
MAX_MODEL_BYTES = 20 * 1024 * 1024


def read_text(path: str) -> str:
    source = Path(path)
    if source.stat().st_size > MAX_INPUT_BYTES:
        raise ValueError(f"input exceeds {MAX_INPUT_BYTES} bytes")
    return source.read_text(encoding="utf-8")


def slugify(text: str, used: set[str]) -> str:
    base = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip()).strip("_").lower() or "node"
    if base[0].isdigit():
        base = "n_" + base
    name, index = base, 2
    while name in used:
        name, index = f"{base}_{index}", index + 1
    used.add(name)
    return name


def quote(text: str) -> str:
    """Return a one-line LikeC4 string literal."""
    clean = re.sub(r"\s+", " ", text).strip()
    if "'" not in clean:
        return "'" + clean + "'"
    if '"' not in clean:
        return '"' + clean + '"'
    return "'" + clean.replace("'", "") + "'"


def read_excalidraw(path: str):
    data = json.loads(read_text(path))
    elements = [item for item in data.get("elements", []) if not item.get("isDeleted")]

    text_for = {}
    for element in elements:
        if element.get("type") == "text" and element.get("containerId"):
            text_for[element["containerId"]] = (element.get("text") or "").strip()

    used: set[str] = set()
    nodes = {}
    for element in elements:
        if element.get("type") in SHAPE_TYPES:
            title = (
                element.get("text")
                or text_for.get(element.get("id"), "")
                or "Node"
            ).strip() or "Node"
            nodes[element["id"]] = (slugify(title, used), title)

    relationships = []
    for element in elements:
        if element.get("type") not in EDGE_TYPES:
            continue
        source = (element.get("startBinding") or {}).get("elementId")
        target = (element.get("endBinding") or {}).get("elementId")
        if source in nodes and target in nodes:
            label = (
                element.get("text")
                or text_for.get(element.get("id"), "")
                or ""
            ).strip()
            relationships.append((nodes[source][0], nodes[target][0], label))
    return nodes, relationships


def inflate_drawio(text: str) -> str:
    """Expand a bounded raw-deflate draw.io page body."""
    try:
        compressed = base64.b64decode(text, validate=True)
        decompressor = zlib.decompressobj(-zlib.MAX_WBITS)
        raw = decompressor.decompress(compressed, MAX_MODEL_BYTES + 1)
        if len(raw) > MAX_MODEL_BYTES or decompressor.unconsumed_tail:
            return ""
        remaining = MAX_MODEL_BYTES + 1 - len(raw)
        raw += decompressor.flush(remaining)
        if len(raw) > MAX_MODEL_BYTES or not decompressor.eof:
            return ""
        return unquote(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, zlib.error):
        return ""


def strip_markup(value: str) -> str:
    text = re.sub(r"<br\s*/?>", " ", value, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def unwrap_drawio_svg(source: str) -> str:
    try:
        root = ET.fromstring(source)
    except ET.ParseError:
        return ""
    content = (root.get("content") or "").strip()
    if content.startswith("<"):
        return content
    decoded = unquote(content)
    return decoded if decoded.startswith("<") else ""


def read_drawio(path: str):
    source = read_text(path)
    if path.lower().endswith(".drawio.svg"):
        source = unwrap_drawio_svg(source)
        if not source:
            raise ValueError("SVG has no embedded draw.io model")

    root = ET.fromstring(source)
    cells = []
    for diagram in root.iter("diagram"):
        model = diagram.find("mxGraphModel")
        if model is None:
            expanded = inflate_drawio((diagram.text or "").strip())
            if not expanded:
                continue
            model = ET.fromstring(expanded)
        cells.extend(model.iter("mxCell"))
    if root.tag == "mxGraphModel":
        cells.extend(root.iter("mxCell"))

    used: set[str] = set()
    nodes = {}
    for cell in cells:
        if cell.get("vertex") != "1":
            continue
        title = strip_markup(cell.get("value") or "") or "Node"
        nodes[cell.get("id")] = (slugify(title, used), title)

    relationships = []
    for cell in cells:
        if cell.get("edge") != "1":
            continue
        source, target = cell.get("source"), cell.get("target")
        if source in nodes and target in nodes:
            relationships.append(
                (nodes[source][0], nodes[target][0], strip_markup(cell.get("value") or ""))
            )
    return nodes, relationships


READERS = {
    ".excalidraw": read_excalidraw,
    ".drawio.svg": read_drawio,
    ".drawio": read_drawio,
}


def render(nodes, relationships) -> str:
    output = ["specification {", "  element node", "}", "", "model {"]
    for _, (variable, title) in nodes.items():
        output.append(f"  {variable} = node {quote(title)}")
    if nodes and relationships:
        output.append("")
    for source, target, label in relationships:
        relation = f"  {source} -> {target}"
        output.append(f"{relation} {quote(label)}" if label else relation)
    output += [
        "}",
        "",
        "views {",
        "  view index {",
        "    title 'Landscape'",
        "    include *",
        "  }",
        "}",
    ]
    return "\n".join(output) + "\n"


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: diagram_to_likec4.py <input> <output.c4>", file=sys.stderr)
        raise SystemExit(2)

    source, destination = sys.argv[1], sys.argv[2]
    reader = next(
        (handler for extension, handler in READERS.items() if source.lower().endswith(extension)),
        None,
    )
    if reader is None:
        print(
            "unsupported input; use .excalidraw, .drawio, or .drawio.svg",
            file=sys.stderr,
        )
        raise SystemExit(2)

    try:
        nodes, relationships = reader(source)
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(nodes, relationships), encoding="utf-8")
    except (ET.ParseError, json.JSONDecodeError, OSError, ValueError) as error:
        print(f"conversion failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error

    print(f"wrote {destination}: {len(nodes)} elements, {len(relationships)} relationships")


if __name__ == "__main__":
    main()
