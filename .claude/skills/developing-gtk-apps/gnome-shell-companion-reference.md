# Companion GNOME Shell Extensions

When a GTK app needs something Wayland does not let a client do, the operation
usually exists *inside the compositor*. A small GNOME Shell extension exposing a
narrow D-Bus interface is the supported way to reach it.

Read this before promising a feature in the table below — several are impossible
from the app alone, and finding that out after building the UI is expensive.

## What a Wayland client genuinely cannot do

| Want | Reality |
|------|---------|
| Position its own window | No `xdg-shell` request. GTK 4 removed `gtk_window_move`. Mutter does not implement `wlr-layer-shell`. |
| Read back where its window is | No protocol for it. `GdkSurface` has no screen position. |
| Keep a window above others | No client-side always-on-top. |
| Grab a global shortcut | Compositor-owned. Portal (`org.freedesktop.portal.GlobalShortcuts`) or an extension. |
| Hide from the dock / Alt-Tab | GTK 4 dropped `set_skip_taskbar_hint` (X11-only in GTK 3). From an extension: `Meta.Window.hide_from_window_list()`. |
| Fall back to X11 | GNOME 49+ ships no X11 session. |

**Design consequence:** the feature is unavailable, not broken, when the
extension is missing. Make every call degrade to a no-op, and make the *UI* say
so — a pin button that latches while nothing happens reads as a bug in your app,
whereas one that is insensitive with an explanatory tooltip reads as the truth.

## Matching app windows to `Meta.Window`

GTK exports every `GtkApplicationWindow` on the session bus at
`<app-object-path>/window/<id>`, and passes that path to Mutter over the
`gtk_shell1` protocol. The extension reads it back:

```js
window.get_gtk_window_object_path()   // "/com/example/MyApp/window/1"
```

This is both the reliable identifier *and* the security boundary. GTK derives
the prefix from the application ID, so no other application can produce a
matching path:

```js
const WINDOW_PATH_PREFIX = '/com/example/MyApp/window/';

_findWindow(objectPath) {
    if (typeof objectPath !== 'string' || !objectPath.startsWith(WINDOW_PATH_PREFIX))
        return null;                                  // every method goes through this
    for (const actor of global.get_window_actors()) {
        const window = actor.meta_window;
        if (window?.get_gtk_window_object_path?.() === objectPath)
            return window;
    }
    return null;
}
```

Say this explicitly in the extensions.gnome.org submission notes; reviewers read
every line and an extension that moves windows will be looked at closely.

Rust side: `gtk::prelude::GtkApplicationWindowExt::id()` returns 0 until the app
is registered, so build the path only after `startup`.

## Coordinates: store monitor-relative, not absolute

Absolute compositor coordinates rot the moment a display is unplugged, resized
or rearranged. Store a **connector name** (`"DP-1"`) plus coordinates relative to
that monitor's **work area** — panels and docks already subtracted, so restored
windows never land under the top bar.

```js
const area = Main.layoutManager.getWorkAreaForMonitor(index);  // not monitor geometry
const manager = global.backend.get_monitor_manager();
for (const monitor of manager.get_monitors()) {
    if (!monitor.is_active()) continue;
    const connector = monitor.get_connector();               // "DP-1"
    const index = manager.get_monitor_for_connector(connector);  // -1 if gone
}
```

Clamp on **both** sides. The app resolves against a monitor list that may be
seconds old; the extension re-clamps against the compositor's live view before
moving anything. Neither trusts the other's arithmetic.

`window.move_resize_frame(false, x, y, w, h)` — `user_op = false` marks this as
state restoration rather than a drag. Call `unmaximize(Meta.MaximizeFlags.BOTH)`
first; a maximised or tiled window ignores the geometry otherwise.

## Mutter APIs that are not what you would guess

Verify against the installed typelib before writing the call — these cost a
logout each to get wrong, because there is no way to reload an extension:

```bash
strings /usr/lib/*/mutter-*/Meta-*.typelib | grep -xE 'hide_from_window_list|move_resize_frame'
```

| Want | Call | Trap |
|------|------|------|
| Hide from dock / Alt-Tab / overview | `window.hide_from_window_list()` / `show_in_window_list()` | **`Meta.Window:skip-taskbar` is a read-only property.** Assigning to it fails *silently* in GJS, which is indistinguishable from "this Mutter is too old". Only `is_skip_taskbar()` reads it. |
| Move/resize | `window.move_resize_frame(user_op, x, y, w, h)` | Pass `user_op = false` for state restoration. A maximised or tiled window ignores it — `unmaximize(Meta.MaximizeFlags.BOTH)` first. |
| Above other windows | `window.make_above()` / `unmake_above()` | No client-side equivalent exists at all. |
| Monitor for a connector | `manager.get_monitor_for_connector(name)` | Returns `-1` when the monitor is gone. |
| Work area | `Main.layoutManager.getWorkAreaForMonitor(index)` | Not `get_monitor_geometry` — that includes the panel and dock. |
| Monitor manager | `global.backend.get_monitor_manager()` | |

## The reply-shape trap

**This is the single most expensive mistake in a companion extension**, because
the error names neither the method nor the field:

```
GDBus.Error:org.gnome.gjs.JSError.ValueError:
    Service implementation returned an incorrect value type
```

GJS packs a reply by walking the declared out-signature, and the wrapping rule
is asymmetric (`Gio.js`, `_handleDBusReply`):

```js
} else if (outArgs.length === 1) {
    // if one arg, we don't require the handler wrapping it into an Array
    ret = [ret];
}
```

So a method with **one** out argument must return the bare value — returning
`[monitors]` becomes `[[monitors]]` — while a method with **several** must
return an array. Getting it backwards is silent until called.

**Return an explicit `GLib.Variant` and the rule stops mattering**, because
`_handleDBusReply` passes a Variant straight through. It is also the only form
that can be unit-tested outside a compositor:

```js
// interface.js — no shell imports, so `gjs -m test.js` can exercise it
export function listMonitorsReply(monitors) {
    return new GLib.Variant('(a(ssbiiii))', [monitors]);
}
```

```js
// test.js — compare against the signature parsed from the interface XML,
// so the implementation and the contract cannot drift apart silently.
const iface = Gio.DBusNodeInfo.new_for_xml(INTERFACE_XML).interfaces[0];
const declared = m => `(${iface.lookup_method(m).out_args.map(a => a.signature).join('')})`;
assertEqual(listMonitorsReply([]).get_type_string(), declared('ListMonitors'));
```

**Coerce at the boundary too.** A null connector, a missing work area or a
float where `i` is declared fails the same opaque way, so convert explicitly
(`String(...)`, `Boolean(...)`, `Math.round(...)`) and drop entries you cannot
represent rather than failing the whole call.

## Making it testable

Nothing that imports `gi://Meta` or `resource:///org/gnome/shell/…` runs outside
a live session, and every mistake there costs a **logout** to discover. Split
accordingly:

```
extension.js    shell glue — Meta/Main calls, kept as thin as possible
geometry.js     pure arithmetic, no imports          } testable with
interface.js    D-Bus XML + shared constants         } `gjs -m test.js`
test.js         the runner
```

The highest-value check is that the interface matches the client:

```js
const iface = Gio.DBusNodeInfo.new_for_xml(INTERFACE_XML).interfaces[0];
const info = iface.lookup_method('Place');
const sig = info.in_args.map(a => a.signature).join('') + '->' +
            info.out_args.map(a => a.signature).join('');
// Must match the VariantTy strings on the client. A mismatch is otherwise
// silent: the call just fails at runtime and the feature quietly does nothing.
```

Also worth static-checking, because each only fails at `enable()` time:

- every `gi://` namespace used is imported
- `metadata.json` has `settings-schema` if `getSettings()` is called
- `disable()` releases everything `enable()` created

## Gotchas that cost a logout each

**`metadata.json` needs `settings-schema`.** `this.getSettings()` with no
argument reads it; omit it and `enable()` throws `Expected type string for
argument 'schema_id' but got type undefined` — which names neither your file nor
the real cause.

**Newly installed extensions need a logout on Wayland.** The shell scans for
extensions at session start, and there is no way to restart the compositor in
place. `org.gnome.Shell.Extensions.ReloadExtension` still appears in
introspection but is **deprecated and now a no-op** ("ReloadExtension is
deprecated and does not work"). `disable` + `enable` does *not* re-import the
ES module or re-read `metadata.json` either.

**Budget your logouts.** Every JS or metadata change costs a full session, so
the loop is: make *all* the changes, run every static check, then log out once.
A `log()` line at the end of `enable()` is worth its weight — it is how you tell
"my new code is running and misbehaving" from "the shell is still running the
old code", and those two look identical from the outside.

**`disable()` must be unconditional and total.** Bus names, `Main.wm`
keybindings and signal handlers all survive a lock screen or shell restart
otherwise, and leaking any of them is the most common review rejection:

```js
disable() {
    this._hider?.destroy();   this._hider = null;
    this._shortcut?.destroy(); this._shortcut = null;   // removeKeybinding()
    this._service?.destroy();  this._service = null;    // unexport + bus_unown_name
}
```

## Global shortcuts

The compositor owns accelerators, so register in the extension and poke the app
through its exported action group — this reuses a running instance, and D-Bus
activation starts a stopped one:

```js
Main.wm.addKeybinding('new-note', settings, Meta.KeyBindingFlags.NONE,
    Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this._activate());

Gio.DBus.session.call(APP_ID, APP_OBJECT_PATH, 'org.gtk.Actions', 'Activate',
    new GLib.Variant('(sava{sv})', ['new-note', [], {}]),   // exact signature
    null, Gio.DBusCallFlags.NONE, -1, null, null);
```

The settings key must be `type="as"`; anything else throws at `enable()`. Check
the accelerator is free first — sweep `gsettings list-recursively` over the
`*.keybindings`, `media-keys` and `mutter` schemas.

## Packaging: the constraint that shapes everything

**No sandboxed format can install a GNOME Shell extension.** The shell loads
extension JavaScript into the compositor process from two fixed, unsandboxed
directories (`/usr/share/gnome-shell/extensions`, `~/.local/share/gnome-shell/extensions`).

| Format | App | Extension |
|--------|-----|-----------|
| `.deb` / distro package | ✅ | ✅ `/usr/share/gnome-shell/extensions` — the only single artifact covering both |
| plain `install.sh` into `~/.local` | ✅ | ✅ no root needed |
| Flatpak | ✅ | ❌ ship separately; app needs `--talk-name=<your.iface>` |
| Snap | ✅ | ❌ plus strict confinement cannot write `~/.local` at all (the `home` interface excludes dot-directories), so it needs `personal-files` or classic — both gated on store manual review |

The conventional split is **extension → extensions.gnome.org** (one-click
install, per-shell-version compatibility handled for you) and **app → distro
package or Flatpak**.

Bundle for EGO with `gnome-extensions pack`, naming every extra module and the
schema explicitly — files must sit at the archive **root**, never in a
subdirectory, or the shell silently ignores the bundle:

```sh
gnome-extensions pack extension \
  --extra-source=geometry.js --extra-source=interface.js \
  --schema=schemas/org.gnome.shell.extensions.myapp.gschema.xml
```
