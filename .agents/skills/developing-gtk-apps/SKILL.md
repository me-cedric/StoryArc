---
name: developing-gtk-apps
description: Use for any change to a GTK 4/libadwaita app, new or existing, whether or not the request mentions GTK. Trigger on the repo rather than the wording — if Cargo.toml depends on gtk4/libadwaita, or sources import gi/Gtk (Python) or use Gtk (Vala), this applies to every change to that app, including requests phrased purely as symptoms ("reordering doesn't work", "pressing enter should continue the list", "the window opens too small"). Covers app boilerplate and new features; behaviour bugs in drag-and-drop, context menus, keyboard and text editing, focus, selection, and window sizing; threading, signals, and lifecycle; gtk-rs calls that fail to compile; GSettings, resources, packaging, and tests. Delegates widget choice, layout, and HIG to designing-gnome-ui.
---

# Developing GTK Apps

Build robust GTK 4/libadwaita applications with correct architecture, lifecycle, and patterns.

**Core principle:** Get the foundation right before the UI. Application lifecycle, threading model, and resource management are where most GTK apps break.

**Relationship to UI skill:** This skill handles architecture and plumbing. For widget selection, layout, and HIG compliance, use `designing-gnome-ui`.

## Pick the Language Branch First

Every run is a Vala run, a Python run, or a Rust run. Detect the language from the project — `.vala` sources or `'vala'` in `project()` means Vala; `.py` sources with `gi` imports means Python; a `Cargo.toml` with a `gtk4` dependency or `.rs` sources means Rust; for a new project, use the language the user named — then open that branch file before writing any code. Every code-level question (syntax, boilerplate, which function to call) is answered there, not here:

| Language | Open | Covers |
|----------|------|--------|
| Vala | `vala-reference.md` | Boilerplate, ownership (`owned`/`unowned`/`weak`), signals, properties, list models/ListView, async/threads, templates, Meson, VAPI verification |
| Python | `python-reference.md` | Boilerplate, `GLib.idle_add`, actions, GSettings, plus pointers into the deeper Python references |
| Rust | `rust-reference.md` | Boilerplate, subclassing (`mod imp`/wrapper), `clone!`, properties, signals, list models/ListView, async/threads, templates, build, crate-source verification, **compile traps keyed by error text** |

When the project builds widget trees purely in code (no `.ui` files or `.blp` in the repo — a common house rule), stay on that path: skip the template/Blueprint/GResource material and build widgets by hand.

**Subagents:** a subagent does not inherit this skill. When delegating GTK work to a subagent, the prompt must tell it to invoke `developing-gtk-apps` (and `designing-gnome-ui` for UI decisions) before writing code.

The rest of this file is language-neutral: rules that hold in both.

## Decision Flow

| Task | Use |
|------|-----|
| Which widget for settings? | designing-gnome-ui |
| How to structure preferences window? | designing-gnome-ui |
| Feature or behaviour fix in an existing GTK app | THIS SKILL (language branch first) |
| gtk-rs call fails to compile | THIS SKILL (`rust-reference.md` Compile Traps) |
| App crashes on startup | THIS SKILL |
| UI freezes during operation | THIS SKILL |
| How to save user preferences | THIS SKILL (GSettings) |
| Signal not firing/memory leak | THIS SKILL |
| Setting up new app boilerplate | THIS SKILL |
| Packaging for Flatpak | THIS SKILL |
| App can't position/raise its own window | `gnome-shell-companion-reference.md` |
| Need a global shortcut, or to hide from the dock | `gnome-shell-companion-reference.md` |

## What's Current (libadwaita 1.7+, GTK 4.18+)

**Replacements — use the current API:**
- `AdwShortcutsDialog` replaces `GtkShortcutsWindow` (libadwaita 1.8+)
- `.dimmed` CSS class replaces `.dim-label`
- `AdwSpinner` replaces `GtkSpinner` in libadwaita apps
- `Widget::compute_bounds()` replaces `allocation()` (deprecated GTK 4.12; clippy with `-D warnings` rejects it)
- Target Wayland; X11/Broadway backends are deprecated in GTK 4 (removal planned for GTK 5), and GNOME 49+ ships no X11 session to fall back to

**What Wayland forbids outright** — check before designing around it: a client
cannot position its own windows, read back where they are, raise itself above
others, grab a global shortcut, or hide from the dock. Each needs a companion
GNOME Shell extension; see `gnome-shell-companion-reference.md`.

**New widgets (libadwaita 1.6–1.8, all present in the 1.9 API):**
- `AdwToggleGroup` - one widget for a set of exclusive toggles
- `AdwBottomSheet` - persistent bottom sheets
- `AdwWrapBox` - box that wraps children to new lines
- `AdwInlineViewSwitcher` - view switching inside cards, sidebars, boxed lists

## Application ID Rules

| Rule | Example |
|------|---------|
| Reverse domain notation | `com.example.MyApp` |
| Only alphanumeric + dots | `org.gnome.TextEditor` |
| Min 2 segments | `com.myapp` (not `myapp`) |
| Match desktop file | `com.example.MyApp.desktop` |

## Lifecycle

| Signal | When | Use For |
|--------|------|---------|
| `startup` | Once, app launches | Actions, CSS, GSettings |
| `activate` | Each launch/raise | Create/present window |
| `shutdown` | App exits | Save state, cleanup |
| `open` | Files passed to app | Handle file arguments |

When overriding `startup`, chain up to the parent implementation before your own setup — the toolkit initializes itself in the parent's handler, and windows created without it fail. `activate` reuses the existing window when one is open and creates one otherwise, so a second launch raises the running instance.

## Threading

GTK is single-threaded: every widget call belongs to the main loop's thread. Worker threads hand results back by scheduling an idle callback on the main loop (exact call in your branch file). Prefer Gio's async I/O over threads — it runs on the main loop and needs no hand-off; reserve threads for CPU-bound work.

## Actions

Actions connect UI to behavior; menus and keyboard shortcuts invoke them by detailed name. Register app-level actions (`app.name`) in `startup`, window-level actions (`win.name`) during window construction, and bind accelerators to the detailed name (`app.quit` → `<Control>q`). Code in your branch file; stateful/parameterized actions and menu wiring in `gtk-patterns-reference.md`.

## GSettings

User preferences persist through GSettings, backed by a compiled schema. Bind keys directly to object properties so the two sync without handler code; subscribe to `changed::key` only when you need to react beyond the bound property. Code in your branch file; schema XML and installation in `gtk-patterns-reference.md`.

## Debugging (Quick Reference)

```bash
GTK_DEBUG=interactive myapp      # Open GTK Inspector (Ctrl+Shift+D)
G_MESSAGES_DEBUG=all myapp       # Show all debug messages
G_DEBUG=fatal-criticals myapp    # Abort on critical warnings
GSETTINGS_BACKEND=memory myapp   # Test without persisting settings
```

Full debugging patterns, profiling, GDB: `gtk-debugging-reference.md`.

## Definition of Done

The foundation is complete when every line below checks out against the code you wrote:

- Worker threads touch widgets only through idle callbacks on the main loop.
- `startup` overrides chain up to the parent first.
- Every handler connected to a longer-lived object (app, settings, model) is disconnected when the widget closes.
- Signal handlers return promptly; long work runs async or on a worker thread.
- User files live under the XDG directories (GLib's user-data/config/cache helpers).
- The application ID is reverse-domain and matches the desktop file.
- New code uses the current widgets from "What's Current".
- Controls for things Wayland forbids are disabled with an explanation, not left latching while nothing happens.
- (Rust) no `RefCell` borrow is held across a callback that can re-enter the object.
- `journalctl --user _COMM=<app>` shows the app's own warnings — not `-- No entries --`.
- (Vala) every snippet passed the verify-then-compile check in `vala-reference.md`.
- (Rust) every snippet passed the verify-then-`cargo check` in `rust-reference.md`.

## Reference Files

| Need | File |
|------|------|
| **All Vala code**: boilerplate, ownership, signals, list models, async, templates, Meson, VAPI | `vala-reference.md` |
| **All Python code**: boilerplate, threading, actions, GSettings | `python-reference.md` |
| **All Rust code**: boilerplate, subclassing, `clone!`, properties, signals, list models, async, templates, build, **compile-error diagnosis** | `rust-reference.md` |
| Deep GObject, **Python only**: classes, properties, signals, list models, factories | `gtk-gobject-reference.md` |
| Stateful actions, GSettings schemas, GResource, Blueprint, async file ops | `gtk-patterns-reference.md` |
| Desktop file, AppStream metadata, Meson install, Flatpak, icons | `gtk-packaging-reference.md` |
| Companion GNOME Shell extension: window placement, global shortcuts, what Wayland forbids | `gnome-shell-companion-reference.md` |
| Testing — pytest (Python) and GLib.Test/meson test (Vala), headless/CI | `gtk-testing-reference.md` |
| Internationalization: gettext, plurals, .po files, Blueprint i18n, RTL | `gtk-i18n-reference.md` |
| DBus activation, interface export, background services, Flatpak portals | `gtk-dbus-reference.md` |
| GTK Inspector, env vars, profiling, memory debugging, **making logs reachable** | `gtk-debugging-reference.md` |
| UI patterns, widgets, HIG | Use `designing-gnome-ui` skill |

## External References

- [GTK 4 API](https://docs.gtk.org/gtk4/)
- [Libadwaita API](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/)
- [Valadoc](https://valadoc.org/) (Vala bindings for GTK/GLib/Adw)
- [gtk4-rs docs](https://gtk-rs.org/gtk4-rs/stable/latest/docs/) (Rust bindings; pin docs.rs to the crate version in `Cargo.toml`)
- [Blueprint docs](https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/)
