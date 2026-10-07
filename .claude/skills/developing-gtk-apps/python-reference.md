# Python Reference for GTK 4/Libadwaita

The Python (PyGObject) branch of `developing-gtk-apps`: every concept in SKILL.md rendered in Python. Deep GObject subclassing lives in `gtk-gobject-reference.md`; this file is the working set every Python run needs.

## Application Boilerplate

```python
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, Gio, GLib

class MyApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.example.MyApp",
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS
        )

    def do_startup(self):
        Adw.Application.do_startup(self)   # chain up FIRST — toolkit init happens here
        self.setup_actions()

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = MyWindow(application=self)
        win.present()

    def setup_actions(self):
        quit_action = Gio.SimpleAction.new("quit", None)
        quit_action.connect("activate", lambda a, p: self.quit())
        self.add_action(quit_action)
        self.set_accels_for_action("app.quit", ["<Control>q"])

class MyWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_default_size(800, 600)

def main():
    app = MyApp()
    return app.run(None)
```

Lifecycle overrides use the `do_` prefix (`do_startup`, `do_activate`, `do_shutdown`, `do_open`) and chain up with the explicit class name: `Adw.Application.do_startup(self)`.

## Threading: Back to the Main Loop

Worker threads hand results to the main loop with `GLib.idle_add`; the callback runs on the main thread where widget calls are safe:

```python
import threading

def start_work(self):
    threading.Thread(target=self._worker, daemon=True).start()

def _worker(self):
    result = slow_computation()               # worker thread
    GLib.idle_add(self.label.set_text, result)  # main loop: widget call safe
```

For I/O, prefer Gio's async calls (`load_contents_async` etc.) — they run on the main loop with no thread at all; patterns with `Gio.Task` and cancellation in `gtk-patterns-reference.md`.

## Actions

```python
# In do_startup — app-level action (invoked as "app.quit")
quit_action = Gio.SimpleAction.new("quit", None)
quit_action.connect("activate", lambda a, p: self.quit())
self.add_action(quit_action)
self.set_accels_for_action("app.quit", ["<Control>q"])

# In window __init__ — window-level action ("win.save")
save_action = Gio.SimpleAction.new("save", None)
save_action.connect("activate", self.on_save)
self.add_action(save_action)
self.get_application().set_accels_for_action("win.save", ["<Control>s"])
```

Stateful (toggle/radio) and parameterized actions: `gtk-patterns-reference.md`.

## GSettings

```python
self.settings = Gio.Settings.new("com.example.MyApp")

# Bind key <-> property (syncs and persists automatically)
self.settings.bind("window-width", window, "default-width",
    Gio.SettingsBindFlags.DEFAULT)

# Manual read/write
dark = self.settings.get_boolean("dark-mode")
self.settings.set_boolean("dark-mode", True)

# React beyond the binding
self.settings.connect("changed::dark-mode", self.on_dark_changed)
```

Schema XML and installation: `gtk-patterns-reference.md`.

## Handler Cleanup

A handler connected to a longer-lived object (app, settings, shared model) keeps the window alive until disconnected:

```python
def __init__(self, **kwargs):
    super().__init__(**kwargs)
    self._handler = self.app.settings.connect("changed", self.on_changed)

def do_close_request(self):
    self.app.settings.disconnect(self._handler)
    return False   # allow close
```

Handlers on objects the window itself owns die with the window and need no cleanup.

## XDG Directories

```python
import os
from gi.repository import GLib

data_dir = os.path.join(GLib.get_user_data_dir(), "myapp")     # ~/.local/share/myapp
config_dir = os.path.join(GLib.get_user_config_dir(), "myapp") # ~/.config/myapp
cache_dir = os.path.join(GLib.get_user_cache_dir(), "myapp")   # ~/.cache/myapp
os.makedirs(data_dir, exist_ok=True)
```

## Going Deeper

| Need | File |
|------|------|
| Custom GObject classes, properties, signals, list models, templates | `gtk-gobject-reference.md` |
| Property bindings, GResource loading, Blueprint templates, async file ops | `gtk-patterns-reference.md` |
| pytest setup, widget/async/GSettings tests | `gtk-testing-reference.md` |
