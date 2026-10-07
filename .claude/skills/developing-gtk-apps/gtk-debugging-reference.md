# GTK Debugging Reference

Environment variables, GTK Inspector, and debugging tools for GTK 4/libadwaita apps. Env vars and the Inspector are language-neutral; code snippets are marked per language.

## Environment Variables

```bash
# Debug GTK warnings
GTK_DEBUG=interactive myapp  # Opens inspector

# Debug GLib
G_MESSAGES_DEBUG=all myapp  # All debug messages
G_MESSAGES_DEBUG=Gtk myapp  # Only GTK messages

# Debug GSettings
GSETTINGS_BACKEND=memory myapp  # Don't persist settings

# Debug threading issues
G_DEBUG=fatal-criticals myapp  # Abort on critical warnings

# Force specific display backend
GDK_BACKEND=wayland myapp
GDK_BACKEND=x11 myapp
```

## GTK Inspector

```python
# Enable inspector in code
Gtk.Window.set_interactive_debugging(True)

# Or press Ctrl+Shift+D in app (if enabled)
```

### Inspector Features

- **Objects:** Browse widget tree, inspect properties
- **CSS:** Live CSS editing, see applied styles
- **Recorder:** Record and replay rendering
- **Statistics:** Frame timing, memory usage
- **Actions:** View and trigger actions
- **Logs:** GLib log messages

## Adaptive Preview (libadwaita 1.7+)

```bash
# Preview app on different device sizes
# Press Ctrl+Shift+M in inspector to open adaptive preview
# Features: device bezels, scaling, screenshots
```

## Debugging Common Issues

### UI Not Updating (Python)

```python
# Check if on main thread
import threading
print(f"Current thread: {threading.current_thread().name}")

# Force UI update
from gi.repository import GLib
while GLib.MainContext.default().pending():
    GLib.MainContext.default().iteration(False)
```

### Signal Not Firing (Python)

```python
# Check signal exists
from gi.repository import GObject
signal_id = GObject.signal_lookup("clicked", Gtk.Button)
print(f"Signal exists: {signal_id != 0}")

# Trace all signals
def trace_handler(*args):
    print(f"Signal received: {args}")
widget.connect("notify", trace_handler)
```

### Memory Leaks

**Vala** — add a destructor with a debug print; if it never fires when the widget should die, a strong reference (usually a connected closure or a missing `unowned`) is holding it — see Ownership in `vala-reference.md`:

```vala
~MyWindow () {
    GLib.debug ("MyWindow finalized");
}
```

**Rust** — same probe, as `Drop` on the imp struct; if it never fires, a strong reference (usually a plain `move` closure that should have been `clone!` with `#[weak]`) is holding the object — see Closures in `rust-reference.md`:

```rust
impl Drop for MyWindow {                 // on imp::MyWindow, inside mod imp
    fn drop(&mut self) {
        glib::g_debug!("myapp", "MyWindow finalized");
    }
}
```

**Python:**

```python
import gc
import weakref

# Track object destruction
def check_cleanup():
    weak_ref = weakref.ref(widget)
    widget.destroy()
    gc.collect()
    print(f"Widget destroyed: {weak_ref() is None}")
```

### CSS Not Applying (Python)

```python
# Check CSS load errors
css_provider = Gtk.CssProvider()
try:
    css_provider.load_from_string("invalid {")
except GLib.Error as e:
    print(f"CSS error: {e.message}")

# Debug CSS classes
for css_class in widget.get_css_classes():
    print(f"CSS class: {css_class}")
```

## Logging

**Vala** — GLib logging is built in; messages appear under `G_MESSAGES_DEBUG`:

```vala
GLib.debug ("loaded %d items", n);
GLib.message ("sync started");
GLib.warning ("could not open %s", path);
GLib.critical ("invariant violated");   // aborts under G_DEBUG=fatal-criticals
```

**Rust** — the same GLib log levels as macros (first argument is the log domain):

```rust
glib::g_debug!("myapp", "loaded {} items", n);
glib::g_message!("myapp", "sync started");
glib::g_warning!("myapp", "could not open {}", path);
glib::g_critical!("myapp", "invariant violated");   // aborts under G_DEBUG=fatal-criticals
```

**Python:**

```python
from gi.repository import GLib

# Set log handler
def log_handler(domain, level, message, user_data):
    print(f"[{domain}] {level}: {message}")

GLib.log_set_handler(None, GLib.LogLevelFlags.LEVEL_WARNING, log_handler, None)

# Log from your code
GLib.log("myapp", GLib.LogLevelFlags.LEVEL_DEBUG, "Debug message")
GLib.log("myapp", GLib.LogLevelFlags.LEVEL_WARNING, "Warning message")
```

## Profiling

```bash
# GTK frame timing
GTK_DEBUG=snapshot myapp

# Sysprof integration
sysprof-cli -c myapp

# Python profiling
python -m cProfile -o profile.out myapp
```

## Inspecting at Runtime (Python)

```python
# In a running app, access inspector:
Gtk.Window.set_interactive_debugging(True)

# Inspect widget hierarchy
def print_tree(widget, indent=0):
    print("  " * indent + type(widget).__name__)
    if hasattr(widget, 'get_first_child'):
        child = widget.get_first_child()
        while child:
            print_tree(child, indent + 1)
            child = child.get_next_sibling()

print_tree(window)
```

## GDB Integration

```bash
# Python apps
gdb --args python myapp.py

# Rust apps: native binary, full debug info in the dev profile
gdb ./target/debug/myapp

# Vala apps: debug the native binary (meson's default buildtype includes -g);
# gdb shows the generated C — map names back via the Vala->C convention
# (MyApp.do_work -> my_app_do_work)
gdb ./build/src/myapp

# Useful GDB commands for GTK
# (gdb) break g_log
# (gdb) break gtk_widget_realize
# (gdb) call gtk_window_set_interactive_debugging(1)
```

## Running Without a Display

Headless test setup (xvfb, `GTK_A11Y=none`): `gtk-testing-reference.md`. To eyeball the app itself without a session, Broadway serves it to a browser:

```bash
broadwayd :5 &
GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 myapp
# Access at http://localhost:8080
```

## Your Logs Probably Go Nowhere

Verify this before trusting any log line you have written:

```bash
journalctl --user -b _COMM=myapp
```

`-- No entries --` is the common answer, and it is a trap. Launched from the
dock, an app is started by **D-Bus activation** and inherits stdout/stderr from
the bus daemon — sockets that produce no journal records. Everything works when
you run it from a terminal, so the gap is invisible during development and total
in real use.

Route records to the journal explicitly rather than relying on where stderr
happens to point:

```rust
// Before anything else can log. g_log_writer_journald writes to the journal
// socket directly; the fallback keeps `cargo run` readable in a terminal.
glib::log_set_writer_func(|level, fields| {
    match glib::log_writer_journald(level, fields) {
        glib::LogWriterOutput::Handled => glib::LogWriterOutput::Handled,
        _ => glib::log_writer_standard_streams(level, fields),
    }
});
```

**Install a panic hook.** A Rust panic inside a GTK signal handler or a D-Bus
callback crosses `extern "C"` and **aborts** — it cannot unwind, so there is no
chance to report it afterwards, and the only symptom the user sees is the window
vanishing:

```rust
let previous = std::panic::take_hook();
std::panic::set_hook(Box::new(move |info| {
    glib::g_critical!("myapp", "PANIC at {}: {}", location(info), message(info));
    previous(info);
}));
```

**Get the severity right.** `g_debug!` is invisible unless `G_MESSAGES_DEBUG`
is set, so a failure logged at debug level is a failure nobody will ever see.
Reserve it for *expected* states (an optional component that is not installed)
and warn for everything else — but make that distinction on the error, not the
call site:

```rust
if err.matches(gio::DBusError::ServiceUnknown) {
    glib::g_debug!("myapp", "{method}: helper not running");   // expected
} else {
    glib::g_warning!("myapp", "{method} failed: {err}");        // a real fault
}
```

**Deduplicate.** Anything on a timer will log the same line forever. Remember
the last message per source and log only the first occurrence and any change;
otherwise the one interesting record is buried under thousands of copies.

**Make unrecoverable states visible in the UI.** A save that keeps failing is
data loss in progress: log it once, and show an `AdwBanner` (persistent —
the condition is ongoing, and a toast is too easy to miss while typing).

**Ship a `--diagnose` flag.** One command that prints versions, whether optional
components are reachable, resolved paths and store health turns "it doesn't
work" into a diagnosis, and costs a couple of hours once. Build the report as a
struct with a `render()` method so its conclusions can be unit-tested.
