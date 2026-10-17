#!/usr/bin/env python3
"""Dump the accessibility tree of the running StoryArc windows, as Orca would see it.

Reads AT-SPI through pyatspi (python3-pyatspi). One line per accessible object: depth,
role, name, and the states a screen reader cares about. Objects with no role and no name
are listed too, because each one is a control Orca would announce as nothing (task 4.15).
"""
import sys

try:
    import pyatspi
except ImportError:
    print("pyatspi is not installed", file=sys.stderr)
    sys.exit(2)

WANTED = {
    pyatspi.STATE_FOCUSABLE: "focusable",
    pyatspi.STATE_FOCUSED: "focused",
    pyatspi.STATE_SENSITIVE: "sensitive",
    pyatspi.STATE_SHOWING: "showing",
    pyatspi.STATE_CHECKED: "checked",
    pyatspi.STATE_SELECTED: "selected",
    pyatspi.STATE_PRESSED: "pressed",
}
MAX_DEPTH = 40
nameless = 0


def dump(node, depth):
    global nameless
    if depth > MAX_DEPTH:
        return
    try:
        role = node.getRoleName()
        name = node.name or ""
        states = node.getState()
        words = [word for state, word in WANTED.items() if states.contains(state)]
        description = node.description or ""
    except Exception as error:  # a window that closed under us
        print("  " * depth + f"<unreadable: {error}>")
        return
    if role in ("push button", "toggle button", "check box", "slider", "link", "list item", "image") and not name and not description:
        nameless += 1
        words.append("NO NAME")
    line = "  " * depth + f"{role}: {name!r}"
    if description:
        line += f" [{description}]"
    if words:
        line += " (" + ", ".join(words) + ")"
    print(line)
    try:
        count = node.childCount
    except Exception:
        return
    for i in range(min(count, 200)):
        try:
            child = node.getChildAtIndex(i)
        except Exception:
            continue
        if child is not None:
            dump(child, depth + 1)


def main():
    desktop = pyatspi.Registry.getDesktop(0)
    found = False
    for app in desktop:
        if app is None:
            continue
        if "storyarc" not in (app.name or "").lower():
            continue
        found = True
        print(f"application: {app.name!r}")
        for window in app:
            dump(window, 1)
    if not found:
        print("no StoryArc application on the accessibility bus")
        sys.exit(1)
    print(f"controls with no name: {nameless}")


if __name__ == "__main__":
    main()
