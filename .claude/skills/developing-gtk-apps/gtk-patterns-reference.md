# GTK Patterns Reference

Deeper patterns for bindings, actions, GSettings schemas, resources, Blueprint, and file operations. Reached by task, not by language: schema/resource/Blueprint formats are language-neutral; where code differs, snippets are marked **Python** / **Vala** / **Rust**. Basics (connecting signals, simple actions, settings bind) live in the branch files `python-reference.md` / `vala-reference.md` / `rust-reference.md`.

## Property Bindings

**Python:**

```python
# One-way binding
source.bind_property(
    "active",              # source property
    target, "sensitive",   # target object, property
    GObject.BindingFlags.SYNC_CREATE
)

# Two-way binding
entry.bind_property(
    "text",
    model, "name",
    GObject.BindingFlags.BIDIRECTIONAL | GObject.BindingFlags.SYNC_CREATE
)

# With transform
def transform_to(binding, value):
    return value.upper()

source.bind_property_full(
    "text", target, "label",
    GObject.BindingFlags.SYNC_CREATE,
    transform_to, None
)
```

**Vala** (plain bindings in `vala-reference.md`; transform):

```vala
model.bind_property ("count", button, "sensitive",
    GLib.BindingFlags.SYNC_CREATE,
    (binding, from_value, ref to_value) => {
        to_value.set_boolean (from_value.get_int () > 0);
        return true;    // transform succeeded
    });
```

**Rust** (plain bindings in `rust-reference.md`; transform):

```rust
model
    .bind_property("count", &button, "sensitive")
    .sync_create()
    .transform_to(|_binding, count: i32| Some(count > 0))
    .build();
```

## Stateful and Parameterized Actions

**Python:**

```python
# Toggle action
dark_action = Gio.SimpleAction.new_stateful(
    "dark-mode",
    None,
    GLib.Variant.new_boolean(False)
)
dark_action.connect("change-state", self.on_dark_mode_changed)
self.add_action(dark_action)

def on_dark_mode_changed(self, action, value):
    action.set_state(value)
    is_dark = value.get_boolean()

# Radio action (string state)
view_action = Gio.SimpleAction.new_stateful(
    "view",
    GLib.VariantType.new("s"),
    GLib.Variant.new_string("grid")
)
view_action.connect("change-state", self.on_view_changed)

# Action with parameter
open_action = Gio.SimpleAction.new("open-item", GLib.VariantType.new("s"))
open_action.connect("activate", self.on_open_item)
self.add_action(open_action)

def on_open_item(self, action, parameter):
    self.open_item(parameter.get_string())

# Trigger from code
self.activate_action("open-item", GLib.Variant.new_string("item-123"))
```

**Vala:**

```vala
// Toggle action
var dark = new GLib.SimpleAction.stateful (
    "dark-mode", null, new GLib.Variant.boolean (false));
dark.change_state.connect ((action, value) => {
    action.set_state (value);
    apply_dark_mode (value.get_boolean ());
});
this.add_action (dark);

// Parameterized (note: constructor syntax, not VariantType.new)
var open_item = new GLib.SimpleAction ("open-item", new GLib.VariantType ("s"));
open_item.activate.connect ((action, parameter) => {
    open (parameter.get_string ());
});
this.add_action (open_item);
```

**Rust** (the `ActionEntry` builder forms of both are in `rust-reference.md`; bare `SimpleAction`):

```rust
// Toggle action
let dark = gio::SimpleAction::new_stateful("dark-mode", None, &false.to_variant());
dark.connect_change_state(|action, value| {
    let value = value.expect("no state");
    action.set_state(value);
    let is_dark = value.get::<bool>().expect("bool state");
    apply_dark_mode(is_dark);
});
app.add_action(&dark);

// Parameterized
let open_item = gio::SimpleAction::new("open-item", Some(glib::VariantTy::STRING));
open_item.connect_activate(|_action, parameter| {
    let id = parameter.and_then(|p| p.get::<String>()).expect("string parameter");
    open(&id);
});
app.add_action(&open_item);

// Trigger from code
app.activate_action("open-item", Some(&"item-123".to_variant()));
```

## GSettings Schemas

Reading and binding settings: branch files. The schema itself is language-neutral:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <schema id="com.example.MyApp" path="/com/example/MyApp/">
    <key name="window-width" type="i">
      <default>800</default>
      <summary>Window width</summary>
    </key>
    <key name="window-height" type="i">
      <default>600</default>
    </key>
    <key name="dark-mode" type="b">
      <default>false</default>
    </key>
    <key name="recent-files" type="as">
      <default>[]</default>
    </key>
  </schema>
</schemalist>
```

```bash
# Compile for local testing
glib-compile-schemas /path/to/schemas/

# Or point GSettings at an uninstalled schema dir
export GSETTINGS_SCHEMA_DIR=/path/to/schemas/
```

Install location and Meson wiring: `gtk-packaging-reference.md`.

## Resources (GResource)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gresources>
  <gresource prefix="/com/example/MyApp">
    <file preprocess="xml-stripblanks">window.ui</file>
    <file>style.css</file>
    <file>icons/symbolic/my-icon-symbolic.svg</file>
  </gresource>
</gresources>
```

**Vala:** `gnome.compile_resources` output listed as a build source links resources into the binary — they register automatically, no loading code (Meson wiring in `vala-reference.md`).

**Rust:** `build.rs` compiles the same XML and `gio::resources_register_include!` embeds it — wiring in `rust-reference.md` (Composite Templates).

**Python:** compile and load at startup:

```bash
glib-compile-resources --target=resources.gresource resources.xml
```

```python
resource = Gio.Resource.load(
    os.path.join(os.path.dirname(__file__), "resources.gresource"))
Gio.resources_register(resource)
```

Using registered resources (either language, Python shown):

```python
builder = Gtk.Builder.new_from_resource("/com/example/MyApp/window.ui")

css_provider = Gtk.CssProvider()
css_provider.load_from_resource("/com/example/MyApp/style.css")
Gtk.StyleContext.add_provider_for_display(
    Gdk.Display.get_default(),
    css_provider,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
)
```

## Blueprint (UI Definition)

Blueprint is a declarative markup language for GTK 4 UIs that compiles to Builder XML. Cleaner than XML, with IDE support. Which widgets to put in the template: `designing-gnome-ui` skill.

```
<!-- XML (verbose) -->
<object class="AdwHeaderBar">
  <child type="end">
    <object class="GtkMenuButton">
      <property name="icon-name">open-menu-symbolic</property>
    </object>
  </child>
</object>
```

```blueprint
// Blueprint (concise)
Adw.HeaderBar {
  [end]
  MenuButton {
    icon-name: "open-menu-symbolic";
  }
}
```

Meson integration (`blueprint-compiler batch-compile` into `gnome.compile_resources`): `vala-reference.md` shows the wiring; it is identical for Python projects. Port existing XML with `blueprint-compiler port window.ui`.

### Complete Window Template

```blueprint
// window.blp
using Gtk 4.0;
using Adw 1;

template $MyAppWindow: Adw.ApplicationWindow {
  default-width: 800;
  default-height: 600;
  title: "My App";

  content: Adw.ToastOverlay toast_overlay {
    child: Adw.ToolbarView {
      [top]
      Adw.HeaderBar {
        [start]
        Gtk.Button {
          icon-name: "list-add-symbolic";
          tooltip-text: "Add Item";
          action-name: "win.add";
        }

        [end]
        Gtk.MenuButton {
          icon-name: "open-menu-symbolic";
          tooltip-text: "Main Menu";
          menu-model: primary_menu;
        }
      }

      content: Adw.Clamp {
        maximum-size: 600;
        child: Gtk.Box {
          orientation: vertical;
          margin-top: 24;
          margin-bottom: 24;
          margin-start: 12;
          margin-end: 12;
          spacing: 24;

          Adw.PreferencesGroup {
            title: "Items";

            Adw.ActionRow {
              title: "Example Item";
              subtitle: "Click to view";
              activatable: true;

              [suffix]
              Gtk.Image {
                icon-name: "go-next-symbolic";
              }
            }
          }
        };
      };
    };
  };
}

menu primary_menu {
  section {
    item {
      label: "_Preferences";
      action: "app.preferences";
    }
    item {
      label: "_Keyboard Shortcuts";
      action: "win.show-help-overlay";
    }
    item {
      label: "_About";
      action: "app.about";
    }
  }
}
```

**Property bindings in Blueprint:**

```blueprint
Gtk.Label {
  label: bind model.name;  // One-way binding
}

Gtk.Entry {
  text: bind model.value bidirectional;  // Two-way
}
```

**Loading the template** — Vala: `[GtkTemplate]` in `vala-reference.md`; Rust: `#[derive(CompositeTemplate)]` in `rust-reference.md`. Python:

```python
@Gtk.Template(resource="/com/example/MyApp/window.ui")
class MyAppWindow(Adw.ApplicationWindow):
    __gtype_name__ = "MyAppWindow"

    toast_overlay = Gtk.Template.Child()

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        add_action = Gio.SimpleAction.new("add", None)
        add_action.connect("activate", self._on_add)
        self.add_action(add_action)

    def _on_add(self, action, param):
        self.toast_overlay.add_toast(Adw.Toast(title="Item added"))
```

## Async File Operations with Gio

**Python:**

```python
def load_file_async(self, path, callback):
    file = Gio.File.new_for_path(path)
    file.load_contents_async(None, callback)

def on_file_loaded(self, file, result):
    try:
        success, contents, etag = file.load_contents_finish(result)
        self.process_content(contents.decode('utf-8'))
    except GLib.Error as e:
        self.show_error(f"Could not load file: {e.message}")

def save_file_async(self, path, content, callback):
    file = Gio.File.new_for_path(path)
    file.replace_contents_async(
        content.encode('utf-8'),
        None,   # etag
        False,  # make_backup
        Gio.FileCreateFlags.REPLACE_DESTINATION,
        None,   # cancellable
        callback
    )

def on_file_saved(self, file, result):
    try:
        file.replace_contents_finish(result)
        self.show_toast("File saved")
    except GLib.Error as e:
        self.show_error(f"Could not save: {e.message}")
```

**Vala** (read + cancellation in `vala-reference.md`; write):

```vala
async void save (string path, string content) throws GLib.Error {
    var file = GLib.File.new_for_path (path);
    yield file.replace_contents_async (
        content.data,
        null,       // etag
        false,      // make_backup
        GLib.FileCreateFlags.REPLACE_DESTINATION,
        null,       // cancellable
        null);      // out new_etag (ignored)
}
```

**Rust** (read + cancellation in `rust-reference.md`; write):

```rust
async fn save(path: &str, content: String) -> Result<(), glib::Error> {
    let file = gio::File::for_path(path);
    file.replace_contents_future(
        content.into_bytes(),
        None,  // etag
        false, // make_backup
        gio::FileCreateFlags::REPLACE_DESTINATION,
    )
    .await
    .map_err(|(_bytes, err)| err)?;   // error side carries the bytes back too
    Ok(())
}
```

## File Monitors: Ignore Your Own Writes

`GFileMonitor` reports the app's own saves exactly like external edits: an editor that autosaves while watching its file sees every save come back as a change event and prompts the user about their own typing. Set a flag before each save and swallow events until the monitor reports the write has settled (Rust shown; same shape in every language):

```rust
let saving = Rc::new(Cell::new(false));
let monitor = file.monitor_file(gio::FileMonitorFlags::NONE, gio::Cancellable::NONE)?;
monitor.connect_changed(glib::clone!(
    #[strong]
    saving,
    move |_monitor, _file, _other, event| {
        if saving.get() {
            if event == gio::FileMonitorEvent::ChangesDoneHint {
                saving.set(false);   // our save has settled; resume watching
            }
            return;
        }
        // genuinely external change: prompt / reload
    }
));
// before every save the app initiates: saving.set(true);
```

## Settings Bind Flags

Bind read-only or system-provided keys with `GET` so the widget cannot write back:

```python
settings.bind("system-setting", widget, "prop", Gio.SettingsBindFlags.GET)
```

(Vala: `GLib.SettingsBindFlags.GET`, same shape. Rust: `settings.bind("system-setting", &widget, "prop").get_only().build()`.)
