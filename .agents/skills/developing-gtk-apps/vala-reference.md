# Vala Reference for GTK 4/Libadwaita

The Vala branch of `developing-gtk-apps`: every concept in SKILL.md rendered in idiomatic Vala. Every snippet here compiles against GTK 4.22 / libadwaita 1.9 / Vala 0.56.

## Verify Signatures Before Asserting Them

Vala/GTK signatures are easy to misremember. Before writing any call you are not certain of:

1. **Locate the declaration in the installed VAPI.** Bindings live in two places: `/usr/share/vala-*/vapi/` (ships with Vala: `gtk4.vapi`, `glib-2.0.vapi`, `gio-2.0.vapi`) and `/usr/share/vala/vapi/` (ships with each library's dev package: `libadwaita-1.vapi`). Search both, and match all class forms — most libadwaita classes are `sealed`:

   ```bash
   grep -rn -E 'public (sealed |abstract )?class ToolbarView' /usr/share/vala*/vapi/
   grep -rn 'bind_property' /usr/share/vala-*/vapi/gobject-2.0.vapi
   ```

2. **Compile to confirm.** A grep locates a symbol; only a compile confirms the signature. Typecheck a snippet without linking:

   ```bash
   valac --pkg gtk4 --pkg libadwaita-1 -C snippet.vala      # emit C only
   valac --pkg gtk4 --gresources app.gresource.xml -C win.vala  # templates need the gresource XML
   ```

Because the libadwaita VAPI ships with libadwaita itself, an older Vala compiler still sees the current Adwaita API.

## Application Boilerplate

```vala
public class MyApp : Adw.Application {
    public MyApp () {
        Object (
            application_id: "com.example.MyApp",
            flags: GLib.ApplicationFlags.DEFAULT_FLAGS
        );
    }

    public override void startup () {
        base.startup ();          // chain up FIRST — toolkit init happens here
        setup_actions ();
    }

    public override void activate () {
        var win = this.active_window ?? new MyWindow (this);
        win.present ();
    }

    private void setup_actions () {
        var quit_action = new GLib.SimpleAction ("quit", null);
        quit_action.activate.connect (() => this.quit ());
        this.add_action (quit_action);
        this.set_accels_for_action ("app.quit", { "<Control>q" });
    }
}

public class MyWindow : Adw.ApplicationWindow {
    public MyWindow (Gtk.Application app) {
        Object (application: app, default_width: 800, default_height: 600);
    }
}

int main (string[] args) {
    return new MyApp ().run (args);
}
```

**GObject-style construction:** `Object (application_id: "...", flags: ...)` sets *construct properties* by name. Use it for any GObject-derived class whose parent expects properties at construction (`Gtk.Application`, windows, widgets). Plain field assignment in the constructor body runs too late for `construct`-only properties.

**`construct` blocks vs constructors:** a `construct { }` block runs on *every* construction path (any named constructor, `Object.new`, template instantiation) after properties are set. Put initialization that must always happen there; put per-constructor argument handling in the constructor itself.

```vala
public class Widget : GLib.Object {
    public string id { get; construct; }        // settable only at construction

    public Widget (string id) {
        Object (id: id);
    }

    construct {
        // runs for every constructor, after Object(...) set the properties
    }
}
```

**Lifecycle overrides:** `public override void activate ()`, `public override void startup ()`, `public override void shutdown ()`. In `startup`, call `base.startup ()` before anything else — GTK/Adwaita initialize in the parent handler, and skipping the chain-up leaves the toolkit uninitialized so window creation fails.

## Ownership and Memory — the Vala Footgun

Vala uses automatic reference counting, not a GC. Three reference kinds:

| Keyword | Meaning | Reach for it when |
|---------|---------|-------------------|
| (default) | Strong: holds a reference, keeps the object alive | Normal ownership |
| `unowned` | Borrowed: no refcount change, no lifetime guarantee | Template children, getters returning internals, hot paths |
| `weak` | Like `unowned`, but becomes `null` when the object dies (GObject fields only) | Back-references that would form a cycle |

**Template children must be `unowned`.** The template (the widget tree) owns them; an owned field would create a widget↔field cycle and the window never finalizes:

```vala
[GtkChild]
private unowned Gtk.Label status_label;   // unowned is required, not optional
```

**Closures capture `this` strongly.** Connecting a lambda that mentions `this` (even implicitly, via a field or method) to a signal on a *longer-lived* object (the app, a `GLib.Settings`, a shared model) makes that object keep your window alive. Disconnect when the window closes:

```vala
public class MyWindow : Adw.ApplicationWindow {
    private ulong settings_handler;
    private GLib.Settings settings = new GLib.Settings ("com.example.MyApp");

    construct {
        settings_handler = settings.changed["dark-mode"].connect (() => {
            // captures `this` strongly via implicit field access
        });
        this.close_request.connect (() => {
            settings.disconnect (settings_handler);
            return false;    // false = allow the close to proceed
        });
    }
}
```

Handlers connected to objects *this widget owns* (its own buttons, its own model) need no disconnect — they die together.

**Break back-reference cycles with `weak`:**

```vala
public class Controller : GLib.Object {
    private weak Gtk.Window? window;    // window owns controller; observe, don't own

    public Controller (Gtk.Window window) {
        this.window = window;
    }
}
```

**Other ownership rules that bite:**
- Property getters return unowned values — you cannot `return new Object ()` from a getter. Store the object, or expose a method returning `owned`.
- `(owned)` transfers ownership: `var mine = (owned) other;` leaves `other` null.
- Receiving an `unowned` return into an owned variable takes a new reference (fine); keeping an `unowned` variable past the owner's lifetime is a use-after-free.

## Signals

```vala
public class TodoItem : GLib.Object {
    public signal void changed ();
    public signal void renamed (string old_title, string new_title);

    public void rename (string title) {
        renamed (this.title, title);   // emit = call it like a method
        this.title = title;
        changed ();
    }

    public string title { get; set; default = ""; }
}

void wire_up (TodoItem item) {
    // Lambda handler
    item.renamed.connect ((old_title, new_title) => {
        print ("%s -> %s\n", old_title, new_title);
    });

    // Keep the id to disconnect later
    ulong id = item.changed.connect (() => print ("changed\n"));
    item.disconnect (id);

    // Property-change notification: detail uses dashes, not underscores
    item.notify["title"].connect (() => {
        print ("title is now %s\n", item.title);
    });
}
```

In templates, `[GtkCallback]` connects a method to a handler named in the UI file (see Composite Templates below).

## Properties and Bindings

```vala
public class Person : GLib.Object {
    public string name { get; set; default = ""; }          // auto-property
    public int age { get; private set; default = 0; }        // read-only outside
    public string id { get; construct; }                     // construction-only
}
```

**Bind properties so state syncs without handler code** — same shape for object↔object and settings↔object:

```vala
// One-way, applied immediately:
item.bind_property ("title", label, "label", GLib.BindingFlags.SYNC_CREATE);

// Two-way:
item.bind_property ("title", entry.buffer, "text",
    GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE);

// GSettings key ↔ property (persists automatically):
var settings = new GLib.Settings ("com.example.MyApp");
settings.bind ("window-width", win, "default-width", GLib.SettingsBindFlags.DEFAULT);

// React beyond the binding:
settings.changed["dark-mode"].connect (() => {
    var dark = settings.get_boolean ("dark-mode");
});
```

## Composite Templates

```vala
[GtkTemplate (ui = "/com/example/MyApp/window.ui")]
public class DemoWindow : Adw.ApplicationWindow {
    [GtkChild]
    private unowned Gtk.Label status_label;      // unowned — template owns it
    [GtkChild]
    private unowned Gtk.Button save_button;

    public DemoWindow (Gtk.Application app) {
        Object (application: app);
    }

    [GtkCallback]     // matches handler="on_save_clicked" in the .ui file
    private void on_save_clicked (Gtk.Button button) {
        status_label.label = "saved";
    }
}
```

Requirements that fail at build time if missed:
- The `.ui` file must be in a GResource; `valac` needs `--gresources app.gresource.xml` to validate the template (Meson's `gnome.compile_resources` + listing `resources` as a source handles this).
- The template `class` attribute in the `.ui` file must equal the Vala type's C name (`DemoWindow` → `class="DemoWindow"`).
- Each `[GtkChild]` field name must match an `id` in the UI file.

Blueprint (`.blp`) compiles to these `.ui` files; syntax in `gtk-patterns-reference.md`.

## List Models and ListView

Modern GTK 4 lists: a `GLib.ListStore` of GObject-derived items, a factory that builds and recycles row widgets, a selection model wrapping the store, and a `Gtk.ListView` on top. Reuse `ListStore` rather than implementing `GLib.ListModel` yourself.

```vala
public class TodoItem : GLib.Object {
    public string title { get; set; default = ""; }
    public bool completed { get; set; default = false; }

    public TodoItem (string title) {
        Object (title: title);
    }
}

var store = new GLib.ListStore (typeof (TodoItem));
store.append (new TodoItem ("Buy groceries"));

var factory = new Gtk.SignalListItemFactory ();

// setup: build the row widget once per recycled row — no item data here
factory.setup.connect ((obj) => {
    var list_item = (Gtk.ListItem) obj;      // signal passes GLib.Object; cast first
    list_item.child = new Gtk.Label ("") { xalign = 0 };
});

// bind: fill the row for the item it currently shows
factory.bind.connect ((obj) => {
    var list_item = (Gtk.ListItem) obj;
    var label = (Gtk.Label) list_item.child;
    var item = (TodoItem) list_item.item;    // item is GLib.Object? — cast to your type

    var binding = item.bind_property ("title", label, "label",
        GLib.BindingFlags.SYNC_CREATE);
    list_item.set_data ("title-binding", binding);   // stash for unbind
});

// unbind: release what bind created — rows are recycled, not destroyed
factory.unbind.connect ((obj) => {
    var list_item = (Gtk.ListItem) obj;
    GLib.Binding binding = list_item.steal_data ("title-binding");
    binding.unbind ();
});

var selection = new Gtk.SingleSelection (store);   // or Gtk.MultiSelection / NoSelection
var list_view = new Gtk.ListView (selection, factory);

selection.notify["selected-item"].connect (() => {
    var item = selection.selected_item as TodoItem;
    if (item != null) { open (item); }
});
```

**Which work goes where:** `setup` builds widgets, `bind` fills them, `unbind` reverses `bind`, `teardown` reverses `setup` (rarely needed). Rows are recycled: without the `unbind` release, a recycled row keeps its binding to the *old* item — the old item stays alive (a binding holds both ends) and its property changes keep writing into a row now showing a different item. Setting the label directly in `bind` with no binding needs no `unbind`; that suffices for items that never change while displayed.

**Filtering and sorting** wrap the store; the view sees one combined model:

```vala
var filter = new Gtk.CustomFilter ((obj) => !((TodoItem) obj).completed);
var filtered = new Gtk.FilterListModel (store, filter);

var sorter = new Gtk.CustomSorter ((a, b) => {
    return GLib.strcmp (((TodoItem) a).title, ((TodoItem) b).title);
});
var sorted = new Gtk.SortListModel (filtered, sorter);
var selection = new Gtk.SingleSelection (sorted);
```

`Gtk.GridView` takes the same selection model and factory; only the layout differs.

## Async and Threads

**Gio async + `yield` for I/O** — stays on the main loop, no thread hand-off:

```vala
public async string load (string path, GLib.Cancellable? cancellable = null) throws GLib.Error {
    var file = GLib.File.new_for_path (path);
    uint8[] contents;
    yield file.load_contents_async (cancellable, out contents, null);
    return (string) contents;
}

// Calling from sync code (e.g. a signal handler): begin/end pattern
private GLib.Cancellable? cancellable;

public void on_open () {
    cancellable = new GLib.Cancellable ();
    load.begin ("/path", cancellable, (obj, res) => {
        try {
            label.label = load.end (res);        // errors surface at .end()
        } catch (GLib.IOError.CANCELLED e) {
            // user cancelled; nothing to show
        } catch (GLib.Error e) {
            warning ("load failed: %s", e.message);
        }
    });
}

// Cancel from anywhere (e.g. close_request):
cancellable?.cancel ();
```

Inside another `async` method, call directly with `yield load (path)` instead of begin/end.

**Threads for CPU-bound work** — hop back to the main loop with `Idle.add` before touching widgets:

```vala
new GLib.Thread<void> ("crunch", () => {
    var result = heavy_computation ();      // worker thread
    GLib.Idle.add (() => {
        label.label = result;               // main loop: widget calls safe here
        return GLib.Source.REMOVE;
    });
});
```

**Many similar jobs** — a pool with bounded threads:

```vala
var pool = new GLib.ThreadPool<string>.with_owned_data ((job) => {
    process (job);                          // worker thread
}, 4, false);
pool.add ("job-1");
```

`GLib.MainContext.default ().invoke (...)` is the equivalent hop when you already hold a `MainContext` reference.

## Error Handling

```vala
public errordomain SyncError {
    NETWORK,
    CONFLICT
}

public void refresh () throws SyncError {
    throw new SyncError.NETWORK ("offline");
}

try {
    refresh ();
} catch (SyncError.CONFLICT e) {       // catch one code
    resolve (e);
} catch (SyncError e) {                // catch the rest of the domain
    warning ("sync failed: %s", e.message);
}
```

- Catching is by domain (or `GLib.Error` for anything); test a specific code with `e is SyncError.CONFLICT`.
- Uncaught errors are compile *warnings*, not errors — treat those warnings as bugs.
- Async errors surface at `.end()`; wrap that call in try/catch (see Async above).

## Actions

App/window basics are in the boilerplate above. Stateful and parameterized:

```vala
// Toggle with state
var dark = new GLib.SimpleAction.stateful (
    "dark-mode", null, new GLib.Variant.boolean (false));
dark.change_state.connect ((action, value) => {
    action.set_state (value);
    apply_dark_mode (value.get_boolean ());
});
this.add_action (dark);

// Parameterized
var open_item = new GLib.SimpleAction ("open-item", new GLib.VariantType ("s"));
open_item.activate.connect ((action, parameter) => {
    open (parameter.get_string ());
});
this.add_action (open_item);
```

Note `new GLib.VariantType ("s")` — a constructor, not a `.new()` static.

## XDG Directories

```vala
string data_dir = GLib.Path.build_filename (
    GLib.Environment.get_user_data_dir (), "myapp");     // ~/.local/share/myapp
string config_dir = GLib.Path.build_filename (
    GLib.Environment.get_user_config_dir (), "myapp");   // ~/.config/myapp
string cache_dir = GLib.Path.build_filename (
    GLib.Environment.get_user_cache_dir (), "myapp");    // ~/.cache/myapp
GLib.DirUtils.create_with_parents (data_dir, 0755);
```

## Meson Build

Layout: root `meson.build` declares the project and subdirs; `data/` compiles resources and installs schemas; `src/` builds the executable.

```meson
# meson.build (root)
project('myapp', ['c', 'vala'],
  version: '1.0.0',
  meson_version: '>= 1.0.0')

gnome = import('gnome')
i18n = import('i18n')

dependencies = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1'),
]

subdir('data')
subdir('src')
```

```meson
# data/meson.build — Blueprint -> .ui -> GResource, plus schema install
blueprints = custom_target('blueprints',
  input: files('window.blp'),
  output: '.',
  command: [find_program('blueprint-compiler'), 'batch-compile',
            '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@'])

resources = gnome.compile_resources('myapp-resources',
  'myapp.gresource.xml',
  dependencies: blueprints,
  c_name: 'myapp')

install_data('com.example.MyApp.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas')
gnome.post_install(glib_compile_schemas: true)
```

```meson
# src/meson.build — resources listed as a source links them into the binary
sources = files('main.vala', 'window.vala')

executable('myapp', sources, resources,
  dependencies: dependencies,
  install: true)
```

```bash
meson setup build && meson compile -C build && ./build/src/myapp
```

Dependencies are found by pkg-config name (`gtk4`, `libadwaita-1`); install the distro's dev packages for gtk4, libadwaita, and `blueprint-compiler` (package names vary by distro).

## Testing

GLib's Test framework plus `meson test`; details, harness code, and headless setup in `gtk-testing-reference.md`. Summary: `GLib.Test.init (ref args)`, `Test.add_func ("/path", fn)`, `Test.run ()`; call `Gtk.init ()`/`Adw.init ()` first for widget tests; run under `xvfb-run` in CI.

## VAPI: Binding and Reading

- A `.vapi` maps a C library's symbols to Vala. `valac --pkg foo` finds `foo.vapi` in the standard dirs (see "Verify Signatures" above) or in `--vapidir` paths.
- To confirm a signature, read the declaration in the VAPI directly — it is ordinary Vala syntax (`public async bool load_contents_async (...)` tells you the exact parameters, `out` params, and `throws`).
- Binding a C library that has GObject Introspection data: `vapigen --library foo-1.0 --pkg glib-2.0 Foo-1.0.gir`, with a `.metadata` file for fixes (nullable returns, out params). A plain C library with no GIR needs a hand-written VAPI (`[CCode (cname = ...)]` attributes mapping each symbol).
