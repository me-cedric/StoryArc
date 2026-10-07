# GTK Testing Reference

Testing GTK 4/libadwaita apps. Three branches: **Vala** (GLib.Test + `meson test`), **Python** (pytest), and **Rust** (`cargo test`). The Headless/CI section at the end applies to all.

## Vala: GLib.Test + meson test

Vala has no pytest. The stack is GLib's Test framework for assertions and the runner, wired into `meson test`:

```vala
// tests/test_main.vala
void drain_events () {
    // Process pending main-loop events so widget state settles
    var ctx = GLib.MainContext.default ();
    while (ctx.pending ()) {
        ctx.iteration (false);
    }
}

void test_label () {
    var label = new Gtk.Label ("Buy groceries");
    drain_events ();
    assert_cmpstr (label.label, GLib.CompareOperator.EQ, "Buy groceries");
}

void test_model () {
    var store = new GLib.ListStore (typeof (Gtk.StringObject));
    store.append (new Gtk.StringObject ("first"));
    assert_cmpuint (store.get_n_items (), GLib.CompareOperator.EQ, 1);
}

int main (string[] args) {
    Gtk.init ();
    Adw.init ();
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/widget/label", test_label);
    GLib.Test.add_func ("/model/append", test_model);
    return GLib.Test.run ();
}
```

```meson
# tests/meson.build
test_exe = executable('myapp-tests',
  'test_main.vala',
  dependencies: dependencies)      # same dependency list as the app

test('unit', test_exe, env: ['GTK_A11Y=none', 'GSETTINGS_BACKEND=memory'])
```

```bash
meson test -C build            # run all tests
meson test -C build --verbose  # show per-assertion output
```

Useful assertions: `assert_cmpstr`, `assert_cmpint`, `assert_cmpuint`, `assert_true`, `assert_false`, `assert_null`, `assert_nonnull`; `Test.expect_message` for asserting warnings.

**Scope honestly:** the Vala UI-testing story is thinner than Python's. GLib.Test gives you assertions and a runner — there is no fixture system, no mocking library, and no widget-interaction simulation comparable to pytest's ecosystem. Put the logic worth testing in plain GObject models and controllers that run headless, keep the widget layer thin, and cover it with the widget-construction smoke tests above plus manual runs.

## Python: pytest

### Setup

```python
# conftest.py
import pytest
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib

@pytest.fixture(scope="session", autouse=True)
def gtk_init():
    Adw.init()   # initializes libadwaita and GTK once for all tests
    yield

def process_pending_events():
    """Process pending main-loop events so widget state settles."""
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)
```

Import `process_pending_events` from `conftest` in test modules.

### Widgets

```python
from myapp.widgets import TodoRow
from conftest import process_pending_events

class TestTodoRow:
    def test_row_displays_title(self):
        row = TodoRow(title="Buy groceries")
        process_pending_events()
        assert row.get_title() == "Buy groceries"

    def test_checkbox_toggles_completed(self):
        row = TodoRow(title="Test task")
        process_pending_events()
        assert not row.completed
        row.check_button.set_active(True)
        process_pending_events()
        assert row.completed

    def test_emits_changed_signal(self):
        row = TodoRow(title="Test task")
        changed = []
        row.connect("changed", lambda w: changed.append(True))
        row.set_title("Updated title")
        process_pending_events()
        assert changed
```

### Windows and Actions

```python
from myapp.window import MainWindow
from myapp.app import MyApp

def test_add_action_creates_item():
    app = MyApp()
    window = MainWindow(application=app)
    initial = window.model.get_n_items()

    window.activate_action("add", None)
    process_pending_events()

    assert window.model.get_n_items() == initial + 1
```

### Async Operations

```python
from gi.repository import GLib

def wait_for_condition(condition_func, timeout_ms=1000):
    """Iterate the main loop until the condition holds or time runs out."""
    context = GLib.MainContext.default()
    start = GLib.get_monotonic_time()
    while not condition_func():
        if GLib.get_monotonic_time() - start > timeout_ms * 1000:
            raise TimeoutError("Condition not met within timeout")
        context.iteration(False)

def test_async_load_completes():
    loader = DataLoader()
    results = []
    loader.load_async(lambda data: results.append(data))
    wait_for_condition(lambda: results, timeout_ms=5000)
    assert results[0] is not None

def test_cancellation():
    loader = DataLoader()
    cancelled = []
    loader.load_async(lambda d: None, on_cancelled=lambda: cancelled.append(True))
    loader.cancel()
    wait_for_condition(lambda: cancelled, timeout_ms=1000)
```

### GSettings

```python
import os
from gi.repository import Gio

@pytest.fixture
def memory_settings():
    """In-memory backend: reads defaults, writes vanish after the test."""
    os.environ["GSETTINGS_BACKEND"] = "memory"
    yield Gio.Settings.new("com.example.MyApp")
    del os.environ["GSETTINGS_BACKEND"]

def test_default_values(memory_settings):
    assert memory_settings.get_int("window-width") == 800
```

### List Models

```python
from myapp.models import TodoListModel

def test_items_changed_signal():
    model = TodoListModel()
    changes = []
    model.connect("items-changed",
        lambda m, pos, removed, added: changes.append((pos, removed, added)))
    model.add("Test item")
    assert changes == [(0, 0, 1)]

def test_filter_model():
    model = TodoListModel()
    model.add("Active task")
    done = model.add("Done task")
    done.completed = True

    filter_model = Gtk.FilterListModel(model=model)
    filter_model.set_filter(Gtk.CustomFilter.new(lambda item: not item.completed))

    assert filter_model.get_n_items() == 1
```

### Mocking Gio

```python
from unittest.mock import patch
from gi.repository import GLib

def test_load_file_error():
    window = MainWindow()
    with patch('gi.repository.Gio.File.new_for_path') as mock_file:
        mock_file.return_value.load_contents_finish.side_effect = GLib.Error(
            "File not found")
        window.load_file("/nonexistent")
        process_pending_events()
        assert window.error_shown
```

### Running

```bash
pytest tests/                 # all tests
pytest tests/test_widgets.py  # one file
pytest --cov=myapp tests/     # with coverage
pytest -m "not slow" tests/   # skip tests marked slow
```

Register markers in `conftest.py` via `pytest_configure` (`config.addinivalue_line("markers", "slow: marks tests as slow")`).

## Rust: cargo test

The standard harness; no GTK-specific runner. The dividing line is the display: glib/gio-only code — models, controllers, everything worth unit-testing — runs with no display and no init, while *any* `gtk::` type (non-widgets like `gtk::StringObject` included) panics without `gtk::init()`, which needs a display.

```rust
// tests/widgets.rs
use gtk::prelude::*;

fn drain_events() {
    // Process pending main-loop events so widget state settles
    let ctx = gtk::glib::MainContext::default();
    while ctx.pending() {
        ctx.iteration(false);
    }
}

#[test]
fn model_append() {
    // glib/gio-only: no display, no init
    let store = gtk::gio::ListStore::new::<gtk::glib::Object>();
    store.append(&gtk::glib::Object::new::<gtk::glib::Object>());
    assert_eq!(store.n_items(), 1);
}

#[test]
fn label_shows_text() {
    gtk::init().expect("GTK could not initialize (no display?)");   // idempotent
    let label = gtk::Label::new(Some("Buy groceries"));
    drain_events();
    assert_eq!(label.label(), "Buy groceries");
}
```

**`--test-threads=1` is not enough.** The harness spawns a *fresh thread per
`#[test]`* regardless of concurrency; serialising them does not make them share
a thread, and GTK may be initialised from exactly one. The second test to run
dies with "Attempted to initialize GTK from two different threads". Put every
widget case in **one** `#[test]` as plain functions, with a runner that reports
each by name and keeps going after a failure:

```rust
fn builds_a_row() { /* ... plain fn, not #[test] ... */ }
fn binding_replaces_content() { /* ... */ }

#[test]
fn widget_suite() {
    let mut failures = Vec::new();
    macro_rules! case {
        ($case:ident) => {
            // Collected, not propagated: each case builds its own widgets, so
            // an unwind part-way through one does not leak into the next.
            if std::panic::catch_unwind(std::panic::AssertUnwindSafe($case)).is_err() {
                failures.push(stringify!($case));
            }
        };
    }
    case!(builds_a_row);
    case!(binding_replaces_content);
    assert!(failures.is_empty(), "failed: {failures:#?}");
}
```

```bash
GSETTINGS_BACKEND=memory GTK_A11Y=none cargo test
```

Keep the logic in plain `glib::Object` subclasses that pass the display-free path, and the widget layer thin — the same scoping advice as Vala above.

### Rules that turn a green suite red for the wrong reason

| Rule | Why |
|------|-----|
| **Build test windows with no application attached** — `adw::init()` (idempotent, subsumes `gtk::init()`), then `adw::Window::new()` / `gtk::Window::new()`. | A window given an application that has not started up triggers `Gtk-CRITICAL: New application windows must be added after the GApplication::startup signal has been emitted`. Widget behaviour needs no application; only tests *of* the application lifecycle construct one (below). |
| **Read a widget's own visibility with `get_visible()`.** | `is_visible()` is ancestor-aware — false for every widget in a window that was never presented, so it fails headless even when your code set visibility correctly. gtk4-rs keeps the `get_` prefix here precisely to distinguish the two. |
| **Never assert inside a signal handler.** Record into a `Cell`/`RefCell` and assert after the loop returns. | Handlers are called across `extern "C"`, where a Rust panic cannot unwind — it aborts the whole process ("thread caused non-unwinding panic"), so you get SIGABRT instead of a named failure. |
| **Give the application under test its own ID.** | A `GApplication` sharing an ID with a *running* instance becomes a remote for it: `run()` forwards the command line and returns immediately, never emitting `startup` or `activate`. The test then silently drives the user's live app and asserts on nothing. |
| **`register()` before expecting window IDs.** | `gtk_application_window_get_id()` is 0 until the app has started up, so anything derived from it (notably the D-Bus object path) is unavailable. Needs a session bus: `dbus-run-session`. |
| **Defer work that needs `activate`'s result.** | A handler connected with `connect_activate` runs *before* the class closure (`ApplicationImpl::activate`), so it sees the state from before windows were created. Schedule with `glib::idle_add_local_once`, which runs after the emission finishes. |

**Bound every `run()`.** "The app never quits" is a real failure mode; without a
timeout guard it hangs CI instead of failing:

```rust
fn run_bounded(app: &MyApp, timeout: Duration) -> bool {
    let timed_out = Rc::new(Cell::new(false));
    let guard = glib::timeout_add_local_once(timeout, glib::clone!(
        #[weak] app, #[strong] timed_out,
        move || { timed_out.set(true); app.quit(); }));
    app.run_with_args::<&str>(&[]);
    if !timed_out.get() { guard.remove(); }
    timed_out.get()
}
```

Redirect `XDG_DATA_HOME` to a `tempfile::tempdir()` **before** the app registers
— `startup` is where most apps resolve their data paths.

## Offscreen Previews — WidgetPaintable (all languages)

Capturing a widget tree without presenting a window:

- **Pump the main loop until layout settles before capturing.** `GtkTextView` measures 0-height on the first layout pass (688×0 on pass one, 688×272 a pass later); a single iteration is not enough. Drain until `pending()` clears, then confirm the measured size is nonzero before snapshotting.
- **`WidgetPaintable` draws nothing for a scroller whose content overflows it.** Size the widget so the content fits, or capture the scroller's child directly.
- **An `AdwDialog` presents into an overlay layer the parent's `WidgetPaintable` does not capture.** Capture the dialog's own child instead.

## Headless / CI (all languages)

```bash
xvfb-run meson test -C build     # virtual framebuffer (Vala)
xvfb-run pytest tests/           # same for Python
xvfb-run cargo test -- --test-threads=1   # same for Rust (needs the xvfb package)

GDK_BACKEND=broadway pytest tests/   # alternative: web backend, no X server
```

Set in the test environment:
- `GTK_A11Y=none` — skips the accessibility bus, removing a common source of CI hangs and D-Bus warnings.
- `GSETTINGS_BACKEND=memory` — tests read schema defaults and leave no state behind.
