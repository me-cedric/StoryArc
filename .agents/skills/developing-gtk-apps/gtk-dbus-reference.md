# GTK DBus Reference

DBus activation and background services for GTK 4/libadwaita apps. Service files, portals, and type signatures are language-neutral; interface export differs sharply — Vala generates the interface from an annotated class, Python registers XML introspection by hand, and Rust typically reaches for the `zbus` crate (interface generated from a trait via `#[interface]`); with gio alone, Rust follows the Python shape below (`DBusNodeInfo` from XML + `register_object`).

## When to Use DBus Activation

- App needs to run tasks when not visible (sync, downloads)
- Other apps need to communicate with your app
- System services need to trigger your app (notifications, files)
- Startup performance optimization (delay full UI until needed)

## DBus Service File

```ini
# data/com.example.MyApp.service
[D-BUS Service]
Name=com.example.MyApp
Exec=/usr/bin/myapp --gapplication-service
```

**Install with meson:**
```meson
# data/meson.build
install_data(
    'com.example.MyApp.service',
    install_dir: get_option('datadir') / 'dbus-1' / 'services'
)
```

## Exporting and Consuming an Interface (Vala)

Annotate a class with `[DBus]`; valac generates the introspection, method dispatch, property access, and signal emission:

```vala
[DBus (name = "com.example.MyApp")]
public class Service : GLib.Object {
    public signal void item_added (string item_id);

    // public methods become D-Bus methods (CamelCased: AddItem)
    public string add_item (string title) throws GLib.Error {
        var id = GLib.Uuid.string_random ();
        item_added (id);        // emitting the signal emits it on the bus
        return id;
    }

    public uint item_count { get; private set; default = 0; }
}

// Export — e.g. in Application.dbus_register override or after Bus.own_name:
void export (GLib.DBusConnection conn) throws GLib.IOError {
    conn.register_object ("/com/example/MyApp", new Service ());
}
```

The client side mirrors the interface as an `abstract` declaration and gets a live proxy:

```vala
[DBus (name = "com.example.MyApp")]
public interface ServiceProxy : GLib.Object {
    public signal void item_added (string item_id);
    public abstract string add_item (string title) throws GLib.Error;
    public abstract uint item_count { get; }
}

async void client () throws GLib.Error {
    ServiceProxy proxy = yield GLib.Bus.get_proxy (
        GLib.BusType.SESSION,
        "com.example.MyApp",
        "/com/example/MyApp");
    var id = proxy.add_item ("milk");           // synchronous call
    proxy.item_added.connect ((item_id) => {    // bus signal as Vala signal
        print ("added: %s\n", item_id);
    });
}
```

The Python sections below hand-roll what these attributes generate.

## Application with DBus Activation (Python)

```python
from gi.repository import Gio, GLib, Adw

class MyApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.example.MyApp",
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE
        )
        self.add_main_option(
            "gapplication-service",
            0,
            GLib.OptionFlags.NONE,
            GLib.OptionArg.NONE,
            "Run as background service",
            None
        )

    def do_command_line(self, command_line):
        options = command_line.get_options_dict()

        if options.contains("gapplication-service"):
            # Running as service - don't show UI
            self.hold()  # Keep alive until explicitly released
            return 0

        # Normal launch - show window
        self.activate()
        return 0

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = MainWindow(application=self)
        win.present()
```

## Exporting DBus Interface (Python)

```python
# Define interface in XML
DBUS_INTERFACE = """
<node>
  <interface name="com.example.MyApp">
    <method name="Sync">
      <arg type="b" name="result" direction="out"/>
    </method>
    <method name="AddItem">
      <arg type="s" name="title" direction="in"/>
      <arg type="s" name="item_id" direction="out"/>
    </method>
    <property name="ItemCount" type="u" access="read"/>
    <signal name="ItemAdded">
      <arg type="s" name="item_id"/>
    </signal>
  </interface>
</node>
"""

class MyApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.MyApp")
        self._dbus_id = 0

    def do_dbus_register(self, connection, object_path):
        # Called when app registers on session bus
        introspection = Gio.DBusNodeInfo.new_for_xml(DBUS_INTERFACE)

        self._dbus_id = connection.register_object(
            object_path,
            introspection.interfaces[0],
            self._handle_method_call,
            self._handle_get_property,
            None  # set_property handler
        )
        return Adw.Application.do_dbus_register(self, connection, object_path)

    def do_dbus_unregister(self, connection, object_path):
        if self._dbus_id:
            connection.unregister_object(self._dbus_id)
        Adw.Application.do_dbus_unregister(self, connection, object_path)

    def _handle_method_call(self, connection, sender, path, interface,
                            method, params, invocation):
        if method == "Sync":
            result = self.perform_sync()
            invocation.return_value(GLib.Variant("(b)", (result,)))
        elif method == "AddItem":
            title = params.unpack()[0]
            item_id = self.add_item(title)
            invocation.return_value(GLib.Variant("(s)", (item_id,)))
            # Emit signal
            connection.emit_signal(
                None, path, interface, "ItemAdded",
                GLib.Variant("(s)", (item_id,))
            )
        else:
            invocation.return_error_literal(
                Gio.dbus_error_quark(),
                Gio.DBusError.UNKNOWN_METHOD,
                f"Unknown method: {method}"
            )

    def _handle_get_property(self, connection, sender, path, interface, prop):
        if prop == "ItemCount":
            return GLib.Variant("u", self.get_item_count())
        return None
```

## Calling DBus Methods from Other Apps (Python; Vala uses the proxy above)

```python
from gi.repository import Gio, GLib

def call_myapp_sync():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    result = bus.call_sync(
        "com.example.MyApp",           # Bus name
        "/com/example/MyApp",          # Object path
        "com.example.MyApp",           # Interface
        "Sync",                        # Method
        None,                          # Parameters
        GLib.VariantType("(b)"),       # Return type
        Gio.DBusCallFlags.NONE,
        -1,                            # Timeout (-1 = default)
        None                           # Cancellable
    )
    return result.unpack()[0]

# Async version
def call_myapp_sync_async(callback):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    bus.call(
        "com.example.MyApp",
        "/com/example/MyApp",
        "com.example.MyApp",
        "Sync",
        None,
        GLib.VariantType("(b)"),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
        callback
    )
```

## Background Portal (Flatpak) (Python shown; same portal call from Vala)

For Flatpak apps, use the Background portal to request background permission:

```python
from gi.repository import Gio, GLib

def request_background_permission(window):
    """Request permission to run in background."""
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    # Get window handle for portal
    handle = ""  # Empty for non-portal-aware windows

    options = GLib.Variant("a{sv}", {
        "reason": GLib.Variant("s", "Sync data in background"),
        "autostart": GLib.Variant("b", False),
        "commandline": GLib.Variant("as", ["myapp", "--gapplication-service"]),
    })

    try:
        result = bus.call_sync(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Background",
            "RequestBackground",
            GLib.Variant("(sa{sv})", (handle, options)),
            GLib.VariantType("(o)"),
            Gio.DBusCallFlags.NONE,
            -1,
            None
        )
        # Result is a request object path for async response
        return True
    except GLib.Error as e:
        print(f"Background permission denied: {e.message}")
        return False
```

**Flatpak manifest permission:**
```json
{
    "finish-args": [
        "--talk-name=org.freedesktop.portal.Background"
    ]
}
```

## Service Lifecycle (Python shown; `hold()`/`release()` identical in Vala)

```python
class MyApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.MyApp")
        self._hold_count = 0

    def start_background_task(self):
        """Keep app alive during background work."""
        self.hold()
        self._hold_count += 1
        # Start async work...

    def finish_background_task(self):
        """Release hold when work completes."""
        self._hold_count -= 1
        self.release()
        # If no windows and no holds, app will exit

    def do_shutdown(self):
        # Cleanup background tasks
        self.cancel_pending_operations()
        Adw.Application.do_shutdown(self)
```

## Autostart (Non-Flatpak)

```ini
# ~/.config/autostart/com.example.MyApp.desktop
[Desktop Entry]
Type=Application
Name=My App Background Service
Exec=myapp --gapplication-service
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
```

## Listening for Signals (Python; Vala proxies surface bus signals as Vala signals)

```python
def listen_for_item_added():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def on_signal(connection, sender, path, interface, signal, params):
        item_id = params.unpack()[0]
        print(f"Item added: {item_id}")

    bus.signal_subscribe(
        "com.example.MyApp",          # Sender
        "com.example.MyApp",          # Interface
        "ItemAdded",                  # Signal
        "/com/example/MyApp",         # Path
        None,                         # arg0
        Gio.DBusSignalFlags.NONE,
        on_signal
    )
```

## DBus Type Signatures

| Type | Signature | Python | Vala | Rust |
|------|-----------|--------|------|------|
| Boolean | `b` | `bool` | `bool` | `bool` |
| Int32 | `i` | `int` | `int` | `i32` |
| UInt32 | `u` | `int` | `uint` | `u32` |
| Int64 | `x` | `int` | `int64` | `i64` |
| UInt64 | `t` | `int` | `uint64` | `u64` |
| Double | `d` | `float` | `double` | `f64` |
| String | `s` | `str` | `string` | `String` / `&str` |
| Object Path | `o` | `str` | `GLib.ObjectPath` | `glib::variant::ObjectPath` |
| Array | `a` | `list` | array (`string[]` etc.) | `Vec<T>` |
| Dict | `a{sv}` | `dict` | `HashTable<string, Variant>` | `HashMap<K, V>` |
| Tuple | `(...)` | `tuple` | struct or out params | tuple |

```python
# Examples
GLib.Variant("s", "hello")                    # String
GLib.Variant("i", 42)                         # Int32
GLib.Variant("as", ["a", "b", "c"])          # Array of strings
GLib.Variant("(si)", ("hello", 42))          # Tuple
GLib.Variant("a{sv}", {"key": GLib.Variant("s", "value")})  # Dict
```
