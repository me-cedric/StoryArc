# GObject Reference for GTK 4/Libadwaita (Python)

Python-branch reference: custom GObject classes, properties, signals, and template widgets with PyGObject. Vala runs use `vala-reference.md` and Rust runs use `rust-reference.md` instead of this file — there these live in the language's own idiom.

## Custom GObject Classes

### Basic Subclass

```python
from gi.repository import GObject

class MyModel(GObject.Object):
    """Simple GObject subclass."""

    def __init__(self):
        super().__init__()
        self._name = ""

    @GObject.Property(type=str, default="")
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._name = value
```

### With Type Registration (Required for Templates)

```python
from gi.repository import GObject, Gtk, Adw

@Gtk.Template(resource="/com/example/MyApp/window.ui")
class MyWindow(Adw.ApplicationWindow):
    __gtype_name__ = "MyWindow"  # Must match template name

    # Template children
    header_bar = Gtk.Template.Child()
    content_box = Gtk.Template.Child()

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    @Gtk.Template.Callback()
    def on_button_clicked(self, button):
        print("Button clicked!")
```

## Properties

### Basic Property Types

```python
from gi.repository import GObject

class MyObject(GObject.Object):
    # String property
    @GObject.Property(type=str, default="")
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._name = value

    # Integer property with range
    @GObject.Property(type=int, minimum=0, maximum=100, default=50)
    def progress(self):
        return self._progress

    @progress.setter
    def progress(self, value):
        self._progress = value

    # Boolean property
    @GObject.Property(type=bool, default=False)
    def active(self):
        return self._active

    @active.setter
    def active(self, value):
        self._active = value

    # Float property
    @GObject.Property(type=float, default=1.0)
    def scale(self):
        return self._scale

    @scale.setter
    def scale(self, value):
        self._scale = value
```

### Read-Only Properties

```python
class MyObject(GObject.Object):
    @GObject.Property(type=str, flags=GObject.ParamFlags.READABLE)
    def computed_value(self):
        return f"{self._name}-{self._id}"
```

### Object/Boxed Properties

```python
from gi.repository import GObject, Gio

class MyObject(GObject.Object):
    # Object property (another GObject)
    @GObject.Property(type=Gio.File)
    def file(self):
        return self._file

    @file.setter
    def file(self, value):
        self._file = value

    # GObject.Object for generic objects
    @GObject.Property(type=GObject.Object)
    def model(self):
        return self._model

    @model.setter
    def model(self, value):
        self._model = value
```

### Notify on Change

```python
class MyObject(GObject.Object):
    def __init__(self):
        super().__init__()
        self._items = []

    @GObject.Property(type=int, flags=GObject.ParamFlags.READABLE)
    def count(self):
        return len(self._items)

    def add_item(self, item):
        self._items.append(item)
        self.notify("count")  # Manually notify property changed
```

## Signals

### Defining Custom Signals

```python
from gi.repository import GObject

class MyObject(GObject.Object):
    __gsignals__ = {
        # Signal with no parameters
        "changed": (GObject.SignalFlags.RUN_LAST, None, ()),

        # Signal with parameters
        "item-added": (GObject.SignalFlags.RUN_LAST, None, (str,)),

        # Signal with multiple parameters
        "item-moved": (GObject.SignalFlags.RUN_LAST, None, (int, int)),

        # Signal with return value
        "validate": (GObject.SignalFlags.RUN_LAST, bool, (str,)),
    }

    def add_item(self, name):
        self._items.append(name)
        self.emit("item-added", name)
        self.emit("changed")

    def move_item(self, from_idx, to_idx):
        # Move logic...
        self.emit("item-moved", from_idx, to_idx)

    def set_value(self, value):
        if self.emit("validate", value):
            self._value = value
```

### Connecting to Signals

```python
def on_item_added(obj, name):
    print(f"Added: {name}")

def on_item_moved(obj, from_idx, to_idx):
    print(f"Moved from {from_idx} to {to_idx}")

my_object = MyObject()
my_object.connect("item-added", on_item_added)
my_object.connect("item-moved", on_item_moved)
```

### Signal with Accumulator

```python
class MyObject(GObject.Object):
    __gsignals__ = {
        # Stop emission on first True return
        "should-close": (
            GObject.SignalFlags.RUN_LAST,
            bool,
            (),
            GObject.signal_accumulator_true_handled
        ),
    }
```

## Template Classes

### With Blueprint UI

```blueprint
// window.blp
using Gtk 4.0;
using Adw 1;

template $MyWindow: Adw.ApplicationWindow {
  title: "My App";

  content: Adw.ToolbarView {
    [top]
    Adw.HeaderBar {}

    content: Gtk.Box main_box {
      orientation: vertical;
      spacing: 12;

      Gtk.Button save_button {
        label: "Save";
        clicked => $on_save_clicked();
      }
    };
  };
}
```

```python
# window.py
from gi.repository import Gtk, Adw

@Gtk.Template(resource="/com/example/MyApp/window.ui")
class MyWindow(Adw.ApplicationWindow):
    __gtype_name__ = "MyWindow"

    main_box = Gtk.Template.Child()
    save_button = Gtk.Template.Child()

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    @Gtk.Template.Callback()
    def on_save_clicked(self, button):
        self.save()
```

### With XML UI

```xml
<!-- window.ui -->
<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <template class="MyWindow" parent="AdwApplicationWindow">
    <property name="title">My App</property>
    <child>
      <object class="AdwToolbarView">
        <child type="top">
          <object class="AdwHeaderBar"/>
        </child>
        <property name="content">
          <object class="GtkBox" id="main_box">
            <property name="orientation">vertical</property>
            <property name="spacing">12</property>
            <child>
              <object class="GtkButton" id="save_button">
                <property name="label">Save</property>
                <signal name="clicked" handler="on_save_clicked"/>
              </object>
            </child>
          </object>
        </property>
      </object>
    </child>
  </template>
</interface>
```

## List Models

### Implementing Gio.ListModel

```python
from gi.repository import GObject, Gio

class Item(GObject.Object):
    def __init__(self, title):
        super().__init__()
        self._title = title

    @GObject.Property(type=str)
    def title(self):
        return self._title


class ItemListModel(GObject.Object, Gio.ListModel):
    def __init__(self):
        super().__init__()
        self._items = []

    def do_get_item_type(self):
        return Item

    def do_get_n_items(self):
        return len(self._items)

    def do_get_item(self, position):
        if position < len(self._items):
            return self._items[position]
        return None

    def append(self, item):
        position = len(self._items)
        self._items.append(item)
        self.items_changed(position, 0, 1)

    def remove(self, position):
        if position < len(self._items):
            del self._items[position]
            self.items_changed(position, 1, 0)

    def clear(self):
        n = len(self._items)
        self._items.clear()
        self.items_changed(0, n, 0)
```

### Using with ListView/GridView

```python
# Create model
model = ItemListModel()
model.append(Item("First"))
model.append(Item("Second"))

# Selection model
selection = Gtk.SingleSelection(model=model)

# Factory for items
factory = Gtk.SignalListItemFactory()

def on_setup(factory, list_item):
    label = Gtk.Label()
    list_item.set_child(label)

def on_bind(factory, list_item):
    label = list_item.get_child()
    item = list_item.get_item()
    label.set_label(item.title)

factory.connect("setup", on_setup)
factory.connect("bind", on_bind)

# List view
list_view = Gtk.ListView(model=selection, factory=factory)
```

## Common Patterns

### Weak References for Callbacks

```python
import weakref
from gi.repository import GLib

class MyWindow(Adw.ApplicationWindow):
    def start_timer(self):
        # Use weak reference to avoid preventing garbage collection
        weak_self = weakref.ref(self)

        def on_timeout():
            self = weak_self()
            if self is None:
                return False  # Stop timer, window was destroyed
            self.update()
            return True  # Continue timer

        GLib.timeout_add_seconds(1, on_timeout)
```

### Property Change Batching

```python
class MyModel(GObject.Object):
    def update_all(self, name, value, active):
        # Freeze notifications during batch update
        self.freeze_notify()
        try:
            self.name = name
            self.value = value
            self.active = active
        finally:
            self.thaw_notify()
        # All notifications sent at once after thaw
```

### Dispose Pattern

```python
class MyObject(GObject.Object):
    def __init__(self):
        super().__init__()
        self._connections = []
        self._disposed = False

    def connect_to(self, obj, signal, handler):
        handler_id = obj.connect(signal, handler)
        self._connections.append((obj, handler_id))
        return handler_id

    def do_dispose(self):
        if self._disposed:
            return
        self._disposed = True

        # Disconnect all signal handlers
        for obj, handler_id in self._connections:
            if obj.handler_is_connected(handler_id):
                obj.disconnect(handler_id)
        self._connections.clear()

        # Chain up
        GObject.Object.do_dispose(self)
```

## GTK 4 Widget Subclassing

### Custom Widget with Properties

```python
from gi.repository import Gtk, GObject

class CustomButton(Gtk.Button):
    __gtype_name__ = "CustomButton"

    def __init__(self):
        super().__init__()
        self._count = 0
        self.connect("clicked", self._on_clicked)

    @GObject.Property(type=int, minimum=0, default=0)
    def count(self):
        return self._count

    @count.setter
    def count(self, value):
        self._count = value
        self.set_label(f"Clicked {value} times")

    def _on_clicked(self, button):
        self.count += 1
```

### Composite Widget

```python
@Gtk.Template(string="""
<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <template class="SearchEntry" parent="GtkBox">
    <child>
      <object class="GtkEntry" id="entry">
        <property name="hexpand">true</property>
      </object>
    </child>
    <child>
      <object class="GtkButton" id="clear_btn">
        <property name="icon-name">edit-clear-symbolic</property>
      </object>
    </child>
  </template>
</interface>
""")
class SearchEntry(Gtk.Box):
    __gtype_name__ = "SearchEntry"

    entry = Gtk.Template.Child()
    clear_btn = Gtk.Template.Child()

    __gsignals__ = {
        "search-changed": (GObject.SignalFlags.RUN_LAST, None, (str,)),
    }

    def __init__(self):
        super().__init__()
        self.entry.connect("changed", self._on_entry_changed)
        self.clear_btn.connect("clicked", self._on_clear_clicked)

    def _on_entry_changed(self, entry):
        self.emit("search-changed", entry.get_text())

    def _on_clear_clicked(self, button):
        self.entry.set_text("")
```

## Type Registration Order

**Critical:** Types must be registered before they're used in templates.

```python
# main.py
from gi.repository import Gtk, Adw, Gio

# Register types BEFORE creating application
from .widgets.custom_button import CustomButton
from .widgets.search_entry import SearchEntry
from .window import MyWindow  # Template uses CustomButton

class MyApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.MyApp")

    def do_activate(self):
        win = MyWindow(application=self)
        win.present()
```

## Debugging GObject Issues

```python
# Check if property exists
print(obj.find_property("name"))

# List all properties
for prop in obj.list_properties():
    print(f"{prop.name}: {prop.value_type}")

# Check signal existence
print(GObject.signal_lookup("clicked", Gtk.Button))

# Trace signal emissions
def trace_handler(*args):
    print(f"Signal emitted with args: {args}")

obj.connect("changed", trace_handler)
```
