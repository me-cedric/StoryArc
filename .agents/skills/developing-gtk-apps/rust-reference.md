# Rust Reference for GTK 4/Libadwaita (gtk4-rs)

The Rust branch of `developing-gtk-apps`: every concept in SKILL.md rendered in idiomatic gtk4-rs. Every snippet here passes `cargo check` against the `gtk4` 0.11 / `libadwaita` 0.9 crates (glib 0.22) on GTK 4.22 / libadwaita 1.9.

## Crates and Feature Levels

```toml
[dependencies]
gtk = { package = "gtk4", version = "0.11", features = ["v4_22"] }
adw = { package = "libadwaita", version = "0.9", features = ["v1_7"] }
```

The `package =` renames give the `gtk::` and `adw::` paths used throughout this file.

**Crate version and library version are separate axes.** `gtk4` 0.11 is the *binding* release; which *GTK* API it exposes is opted into per crate feature: `v4_10`, `v4_12`, … `v4_22` (`gtk4` 0.11.4 goes up to `v4_24`). Pick the feature matching the oldest GTK you ship on — `v4_22` for GTK 4.22. The `gnome_50` meta-feature bundles `v4_22` with matching gio/pango levels for the GNOME 50 runtime. Same scheme for libadwaita: `v1_7` unlocks the 1.7 API. Enabling a feature above the installed library compiles fine and fails at link/run time with missing symbols.

## Verify Signatures Before Asserting Them

gtk-rs churns hard between 0.x releases (`clone!` syntax, channels, builders have all changed); trust the installed crate source over memory or older examples. Before writing any call you are not certain of:

1. **Grep the crate source in the cargo registry** — the same role the `.vapi` files play for Vala. Generated API lives under `src/auto/`:

   ```bash
   grep -rn "pub fn bind_property" ~/.cargo/registry/src/*/glib-0.22.*/src/object.rs
   grep -rn "fn connect_selected_item_notify" ~/.cargo/registry/src/*/gtk4-0.11.*/src/
   ```

   Proc-macro syntax (`clone!`, `Properties`, `CompositeTemplate`) is documented in `glib-macros-*/src/lib.rs` and `gtk4-macros-*/src/lib.rs` doc comments. docs.rs pinned to the exact crate version is the same content rendered.

2. **`cargo check` to confirm.** A grep locates a symbol; only a typecheck confirms the call. Keep one scratch project with a warm `target/` and check snippets there — warm checks finish in well under a second.

## Compile Traps — Keyed by Error Text

When a gtk-rs call fails to compile, grep this section for the error text before rewriting the call. Each entry gives the failure and the form that compiles.

**The diagnostic rule behind half of these:** an E0599/E0277/E0034 naming a trait unrelated to your widget (`IsA<TypeModule>`, `IsA<gtk4::Dialog>`) means method resolution picked a wrong `*Ext` trait because the method you meant does not exist on the type. The real cause is one of: the property is construct-only (set it at construction), the method lives behind a prelude you have not imported, or the name is a signal, not a method.

### `E0433: failed to resolve ... 'glib'` inside `clone!` / `closure_local!`

The macros expand to `glib::`-prefixed paths, so the `glib` *module* must be in scope in the invoking file — importing only the macro (`use gtk::glib::clone;`) leaves the expansion dangling in any crate without a direct `glib` dependency. Import the module and call through it:

```rust
use gtk::glib;
// ...
button.connect_clicked(glib::clone!(
    #[weak]
    label,
    move |_| label.set_label("clicked")
));
```

### `E0034: multiple applicable items in scope` (`activate_action`, `unrealize`)

Windows implement `Widget`, `ActionGroup`, and `Window`, and their `*Ext` traits overlap once both preludes are in scope. Fully-qualify the trait:

```rust
// Detailed "win."-name, resolved up the widget tree:
let _ = gtk::prelude::WidgetExt::activate_action(&window, "win.save", None);
// Unprefixed name, directly on the action group:
gio::prelude::ActionGroupExt::activate_action(&window, "save", None);
gtk::prelude::WidgetExt::unrealize(&window);
```

### `E0599: no associated function or constant named 'builder'`

gtk-rs generates a `Builder` only for types with writable construct properties. `AdwToastOverlay`, `AdwShortcutsSection`, and `AdwShortcutsItem` have none — use their constructors:

```rust
let overlay = adw::ToastOverlay::new();
let section = adw::ShortcutsSection::new(Some("General"));
section.add(adw::ShortcutsItem::new("Quit", "<Control>q"));   // add() takes the item by value
```

`adw::ShortcutsDialog` itself does have a builder. The `Shortcuts*` types need libadwaita crate feature `v1_8`.

### `E0599: no method named ...` on a type from another gtk-rs-family crate

Every crate in the family (soup3, gdk4, gsk4, …) puts instance methods on `*Ext` traits behind its own prelude. `soup::Session::send_and_read_async` lives on `SessionExt`:

```rust
use soup::prelude::*;   // the soup3 package's lib name is "soup"

session.send_and_read_async(&msg, glib::Priority::DEFAULT, gio::Cancellable::NONE, |res| { /* ... */ });
let bytes = session.send_and_read_future(&msg, glib::Priority::DEFAULT).await?;
let code: u32 = msg.status_code();   // not msg.status().into_glib()
```

### `IsA<gtk4::Dialog> is not implemented for AlertDialog` — `response` is a signal

`adw::AlertDialog` is not a `gtk::Dialog` and has no `response()` method (`adw::prelude::AlertDialogExt::response(...)` is E0782 — that path is a trait). Emit or connect the signal:

```rust
dialog.emit_by_name::<()>("response", &[&"confirm"]);      // e.g. driving a dialog in a test
dialog.connect_response(None, |_dialog, response| { /* ... */ });
```

### `IsA<TypeModule> is not implemented for TextTag` — construct-only property

`tag.set_name(...)` resolved to `TypeModuleExt::set_name` because `TextTag` has no name setter: `name` is construct-only. Set it at construction:

```rust
let tag = gtk::TextTag::new(Some("bold"));
```

### `E0308: mismatched types` — signature shapes to check first

- `adw::ToggleGroup::add` and `adw::ShortcutsSection::add` take the child **by value**, not by reference.
- Nullable-string setters take `Option<&str>`: `label.set_tooltip_text(Some("hint"))`.
- `glib::compute_checksum_for_bytes(glib::ChecksumType::Sha256, &bytes)` takes `&glib::Bytes` — wrap a slice with `glib::Bytes::from`.
- Handlers that conceptually return bool return `glib::Propagation`: `window.connect_close_request(|_| glib::Propagation::Proceed);`.

### One-liners

- `gdk::ContentFormats::contain_mime_type` — singular `contain`.
- Unix signal sources left `glib` in the 0.22 series: add the `glib-unix` crate and call `glib_unix::unix_signal_add_local(signum, || glib::ControlFlow::Continue)` (`_once` and non-local variants exist there too).
- `cairo::PdfSurface::set_metadata` needs cairo-rs feature `v1_16`.
- `WidgetExt::allocation()` is deprecated since GTK 4.12; use `widget.compute_bounds(&parent)`.

## Application Boilerplate

```rust
use adw::prelude::*;
use gtk::{gio, glib};

const APP_ID: &str = "com.example.MyApp";

fn main() -> glib::ExitCode {
    let app = adw::Application::builder().application_id(APP_ID).build();

    app.connect_startup(|app| {
        // Runs after GTK/Adwaita init — register actions, load CSS, settings
        setup_actions(app);
    });

    app.connect_activate(|app| {
        let win = app
            .active_window()
            .unwrap_or_else(|| build_window(app).upcast());
        win.present();
    });

    app.run()
}

fn build_window(app: &adw::Application) -> adw::ApplicationWindow {
    adw::ApplicationWindow::builder()
        .application(app)
        .default_width(800)
        .default_height(600)
        .build()
}

fn setup_actions(app: &adw::Application) {
    let quit = gio::ActionEntry::builder("quit")
        .activate(|app: &adw::Application, _action, _param| app.quit())
        .build();
    app.add_action_entries([quit]);
    app.set_accels_for_action("app.quit", &["<Control>q"]);
}
```

**Chain-up:** `connect_startup` handlers run after GTK's own startup handler, so the toolkit is already initialized. The chain-up rule bites only when *subclassing* the application — override `ApplicationImpl::startup` and call `self.parent_startup()` first:

```rust
impl ApplicationImpl for MyApp {
    fn startup(&self) {
        self.parent_startup();   // chain up FIRST — toolkit init happens here
        // register actions, load CSS, read settings
    }
}
```

## Subclassing — the Two Halves of Every GObject

This is where gtk-rs differs most from every other binding, and the part people cargo-cult. Every GObject subclass is *two* types:

- **The `imp` struct** (private, in `mod imp`): holds all state and implements the vfunc traits. There is exactly one per object instance, owned by the GObject system.
- **The wrapper** (public, from `glib::wrapper!`): a refcounted *handle* to the GObject — `Clone` on it copies a reference, not the object. This is what the rest of the app passes around.

The split exists because a GObject is shared and refcounted C data: no `&mut self` is ever available, so the imp struct's fields must use interior mutability, and the public type must be a handle rather than the data itself. Navigation: `wrapper.imp()` reaches the state; `imp.obj()` reaches the wrapper (for calling inherited methods).

```rust
use adw::prelude::*;
use adw::subclass::prelude::*;
use gtk::{gio, glib};
use std::cell::{Cell, RefCell};

mod imp {
    use super::*;

    #[derive(Default)]                               // instantiated via Default
    pub struct MyWindow {
        pub dirty: Cell<bool>,
        pub draft: RefCell<String>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for MyWindow {
        const NAME: &'static str = "MyWindow";       // GType name — must be unique
        type Type = super::MyWindow;                 // the public wrapper below
        type ParentType = adw::ApplicationWindow;
    }

    impl ObjectImpl for MyWindow {
        fn constructed(&self) {
            self.parent_constructed();
            self.obj().set_default_size(800, 600);   // wrapper methods via obj()
        }
    }
    // One empty impl per ancestor class — this is how the hierarchy is declared
    impl WidgetImpl for MyWindow {}
    impl WindowImpl for MyWindow {}
    impl ApplicationWindowImpl for MyWindow {}
    impl AdwApplicationWindowImpl for MyWindow {}
}

glib::wrapper! {
    pub struct MyWindow(ObjectSubclass<imp::MyWindow>)
        @extends adw::ApplicationWindow, gtk::ApplicationWindow, gtk::Window, gtk::Widget,
        @implements gio::ActionGroup, gio::ActionMap, gtk::Accessible, gtk::Buildable,
                    gtk::ConstraintTarget, gtk::Native, gtk::Root, gtk::ShortcutManager;
}

impl MyWindow {
    pub fn new(app: &adw::Application) -> Self {
        glib::Object::builder().property("application", app).build()
    }

    pub fn mark_dirty(&self) {
        let imp = self.imp();
        imp.dirty.set(true);
        imp.draft.borrow_mut().push_str("edit\n");
    }
}
```

- `@extends` lists every ancestor class, `@implements` every interface — the compiler enforces the full list (a window subclass needs all eight interfaces above; error messages name any you miss).
- Construction goes through `glib::Object::builder()` with construct properties by name — the GObject system calls `Default` on the imp struct, sets properties, then runs `constructed`.
- `dispose` is where handlers connected to longer-lived objects get disconnected (see Closures below); `constructed` is the post-construction hook.
- Non-widget models subclass plain `glib::Object`: omit `ParentType` (it defaults to `glib::Object`), implement only `ObjectImpl`, and the wrapper takes no `@extends`.

### Interior Mutability in the imp Struct

Fields can never be `mut` — mutation always goes through a cell type:

| Type | For | Access |
|------|-----|--------|
| `Cell<T>` | `Copy` values (flags, counters) | `get()` / `set()` — no borrow, no panic risk |
| `RefCell<T>` | Everything else mutable | `borrow()` / `borrow_mut()` — panics on conflict |
| `OnceCell<T>` (`std::cell`) | Set once after construction (settings, child objects) | `set()` / `get()` |

**`RefCell` panics are the Rust-side runtime crash.** `borrow_mut()` while any borrow is live panics at runtime — and GTK re-enters your code: a `borrow_mut()` held across a signal emission or widget call panics when the handler borrows again. Keep borrows short and drop them before calling anything that can emit:

```rust
let title = self.imp().draft.borrow().clone();   // copy out, borrow ends
self.set_title(Some(&title));                    // now safe to re-enter
```

**The same trap, one level out: never hold a borrow across a callback you
invoke.** Anything you call may re-enter the object — a "new item" handler
typically ends up refreshing the very collection you are iterating:

```rust
// WRONG: on_action re-enters and calls set_entries() -> borrow_mut() -> abort
let entries = self.entries.borrow();
if let Some(entry) = entries.get(index) { on_action(&entry.action); }

// RIGHT: copy what you need, drop the borrow, then dispatch
let action = {
    let entries = self.entries.borrow();
    entries.get(index).map(|e| e.action.clone())
};
if let Some(action) = action { on_action(&action); }
```

In a D-Bus or signal callback this is not a recoverable panic: the unwind
crosses `extern "C"` and **aborts the process**. Extract the dispatch into a free
function taking `&RefCell<T>` so a test can pass a callback that re-enters and
prove it does not abort.

## Closures and Reference Cycles — `glib::clone!`

Signal-handler closures are `move` closures, and cloning a wrapper into one stores a *strong* reference. A widget whose own handler captures it strongly can never finalize (widget → closure → widget), and a handler on a longer-lived object (app, settings, shared model) keeps your window alive until disconnected. `glib::clone!` captures weakly instead — attribute syntax (glib 0.20 replaced the old `@weak x =>` form with these attributes):

```rust
let id = settings.connect_changed(
    Some("dark-mode"),
    glib::clone!(
        #[weak(rename_to = win)]
        self,
        move |settings, _key| {
            let dark = settings.boolean("dark-mode");
            win.imp().status_label.set_label(if dark { "dark" } else { "light" });
        }
    ),
);
// dispose: settings.disconnect(id) — store the SignalHandlerId in the imp struct
```

| Attribute | Effect |
|-----------|--------|
| `#[weak] obj` | Weak capture; closure body silently returns if upgrade fails |
| `#[weak_allow_none] obj` | Weak capture surfaced as `Option` — body runs either way |
| `#[strong] obj` | Explicit strong capture (for the object that owns the handler's target) |
| `#[to_owned] v` | Capture a `ToOwned` value by owned copy |
| `#[weak(rename_to = x)]` | Rename in the body — required for `self` |
| `#[upgrade_or] expr` / `#[upgrade_or_else]` / `#[upgrade_or_default]` / `#[upgrade_or_panic]` | Return value when a `#[weak]` upgrade fails (default is `()`) |

**Which capture for which edge:** handlers a widget connects on *itself or its own children* take `#[weak] self` — the widget outlives neither end, and weak breaks the cycle. Handlers on *longer-lived* objects take `#[weak]` *and* a stored `SignalHandlerId` disconnected in `dispose` — weak alone stops the leak, but the dead handler keeps firing into an upgrade failure until disconnected.

## Properties

`#[derive(glib::Properties)]` generates the ParamSpecs, getters/setters, and notify plumbing hand-written `properties()`/`set_property()` used to require:

```rust
use gtk::glib;
use gtk::prelude::*;
use gtk::subclass::prelude::*;

mod imp {
    use super::*;
    use std::cell::{Cell, OnceCell, RefCell};

    #[derive(Default, glib::Properties)]
    #[properties(wrapper_type = super::TodoItem)]
    pub struct TodoItem {
        #[property(get, set)]
        pub title: RefCell<String>,
        #[property(get, set)]
        pub completed: Cell<bool>,
        #[property(get, construct_only)]
        pub id: OnceCell<String>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for TodoItem {
        const NAME: &'static str = "TodoItem";
        type Type = super::TodoItem;
    }

    #[glib::derived_properties]      // supplies ObjectImpl's property vfuncs
    impl ObjectImpl for TodoItem {}
}

glib::wrapper! {
    pub struct TodoItem(ObjectSubclass<imp::TodoItem>);
}

impl TodoItem {
    pub fn new(title: &str) -> Self {
        glib::Object::builder().property("title", title).build()
    }
}
```

The wrapper gains typed methods per property: `title()`, `set_title()`, `notify_title()`, `connect_title_notify()`. Setting through `set_title` notifies automatically; writing the `RefCell` directly bypasses notify (do that only inside the imp, followed by `self.obj().notify_title()` if anyone binds to it).

**Bind properties so state syncs without handler code** — builder style:

```rust
// One-way, applied immediately
item.bind_property("title", &label, "label").sync_create().build();

// Two-way
item.bind_property("title", &entry.buffer(), "text")
    .bidirectional()
    .sync_create()
    .build();

// With transform
item.bind_property("completed", &button, "sensitive")
    .sync_create()
    .transform_to(|_binding, completed: bool| Some(!completed))
    .build();

// GSettings key <-> property (persists automatically)
let settings = gio::Settings::new("com.example.MyApp");
settings.bind("window-width", &win, "default-width").build();

// React beyond the binding
settings.connect_changed(Some("dark-mode"), |settings, _key| {
    let _dark = settings.boolean("dark-mode");
});
```

## Signals

Custom signals are declared in `ObjectImpl::signals()`; emitted by name; connected either typed (`connect_closure`) or untyped (`connect_local`):

```rust
// In the imp module:
use glib::subclass::Signal;
use std::sync::OnceLock;

impl ObjectImpl for TodoItem {
    fn signals() -> &'static [Signal] {
        static SIGNALS: OnceLock<Vec<Signal>> = OnceLock::new();
        SIGNALS.get_or_init(|| {
            vec![Signal::builder("renamed")
                .param_types([str::static_type(), str::static_type()])
                .build()]
        })
    }
}

// Emitting (on the wrapper) — the turbofish is the signal's return type:
self.emit_by_name::<()>("renamed", &[&old_title, &new_title]);

// Typed connection:
item.connect_closure(
    "renamed",
    false,
    glib::closure_local!(|_item: TodoItem, old: &str, new: &str| {
        println!("{old} -> {new}");
    }),
);

// Untyped connection — values arrive as glib::Value, index 0 is the emitter:
item.connect_local("renamed", false, |values| {
    let old = values[1].get::<String>().unwrap();
    println!("was {old}");
    None                             // return value for the signal, if any
});

// Property-change notification (generated per derived property):
item.connect_title_notify(|item| {
    println!("title is now {}", item.title());
});
```

Built-in widget signals have generated typed connectors (`button.connect_clicked(...)`) — reach for `connect_closure`/`connect_local` only for custom or detail signals.

## Composite Templates

```rust
mod imp {
    use super::*;

    #[derive(Default, gtk::CompositeTemplate)]
    #[template(resource = "/com/example/MyApp/window.ui")]
    pub struct MyWindow {
        #[template_child]
        pub status_label: TemplateChild<gtk::Label>,   // resolved after build
        #[template_child]
        pub save_button: TemplateChild<gtk::Button>,
    }

    #[glib::object_subclass]
    impl ObjectSubclass for MyWindow {
        const NAME: &'static str = "MyWindow";
        type Type = super::MyWindow;
        type ParentType = adw::ApplicationWindow;

        fn class_init(klass: &mut Self::Class) {
            klass.bind_template();
            klass.bind_template_callbacks();
        }

        fn instance_init(obj: &glib::subclass::InitializingObject<Self>) {
            obj.init_template();
        }
    }

    #[gtk::template_callbacks]
    impl MyWindow {
        #[template_callback]     // matches handler="on_save_clicked" in the .ui file
        fn on_save_clicked(&self) {
            self.status_label.set_label("saved");
        }
    }
    // ObjectImpl / WidgetImpl / ... as in Subclassing above
}
```

- `TemplateChild<T>` dereferences to the widget; the template owns it, so there is no cycle to break.
- For `&self` callbacks, set `swapped="true"` on the `<signal>` tag in the UI file (otherwise the first parameter is the emitting widget).
- The template `class` attribute in the `.ui` file must equal `ObjectSubclass::NAME`; each `#[template_child]` field name must match an `id`.
- `#[template(file = "...")]` and `#[template(string = "...")]` are the non-resource variants.

**Getting the `.ui` into the binary** — with plain cargo, `build.rs` compiles the GResource and a macro embeds it:

```toml
[build-dependencies]
glib-build-tools = "0.22"
```

```rust
// build.rs
fn main() {
    glib_build_tools::compile_resources(
        &["resources"],                          // source dir(s)
        "resources/resources.gresource.xml",
        "myapp.gresource",                       // output, lands in OUT_DIR
    );
}

// main.rs — register before the first template instantiation
fn main() -> glib::ExitCode {
    gio::resources_register_include!("myapp.gresource").expect("register resources");
    // ... build the Application as usual
}
```

Meson-driven projects compile the same `gresource.xml` via `gnome.compile_resources` instead (see Build below). Blueprint (`.blp`) compiles to these `.ui` files; syntax in `gtk-patterns-reference.md`.

## List Models and ListView

Same architecture as every language: `gio::ListStore` of GObject items, a factory, a selection model, `gtk::ListView`. Rust's cleanest factory is **expression-based** — the expression follows whatever item the recycled row currently shows, so there is nothing to unbind:

```rust
let store = gio::ListStore::new::<TodoItem>();
store.append(&TodoItem::new("Buy groceries"));

let factory = gtk::SignalListItemFactory::new();
factory.connect_setup(|_factory, obj| {
    let list_item = obj.downcast_ref::<gtk::ListItem>().unwrap();
    let label = gtk::Label::builder().xalign(0.0).build();
    list_item.set_child(Some(&label));
    // item -> title, rebinding automatically as rows are recycled
    list_item
        .property_expression("item")
        .chain_property::<TodoItem>("title")
        .bind(&label, "label", gtk::Widget::NONE);
});

let selection = gtk::SingleSelection::new(Some(store));   // or MultiSelection / NoSelection
let list_view = gtk::ListView::new(Some(selection.clone()), Some(factory));

selection.connect_selected_item_notify(|selection| {
    if let Some(item) = selection.selected_item().and_downcast::<TodoItem>() {
        open(&item);
    }
});
```

Signals pass `glib::Object`; `downcast_ref::<gtk::ListItem>()` first, then `item().and_downcast::<TodoItem>()` for your type.

**Manual bind/unbind** — needed when `bind` does more than an expression can (connects handlers, builds per-item widgets). Rows are recycled, not destroyed: whatever `bind` creates, `unbind` must release, or a recycled row keeps its binding to the *old* item — the old item stays alive (a binding holds both ends) and its changes keep writing into a row now showing a different item:

```rust
factory.connect_bind(|_factory, obj| {
    let list_item = obj.downcast_ref::<gtk::ListItem>().unwrap();
    let label = list_item.child().and_downcast::<gtk::Label>().unwrap();
    let item = list_item.item().and_downcast::<TodoItem>().unwrap();

    let binding = item.bind_property("title", &label, "label").sync_create().build();
    unsafe { list_item.set_data("title-binding", binding) };   // stash for unbind
});

factory.connect_unbind(|_factory, obj| {
    let list_item = obj.downcast_ref::<gtk::ListItem>().unwrap();
    let binding: glib::Binding = unsafe { list_item.steal_data("title-binding").unwrap() };
    binding.unbind();
});
```

(`set_data`/`steal_data` are `unsafe` because they are type-checked only at runtime; a subclassed row widget holding `RefCell<Vec<glib::Binding>>` is the safe alternative when the row is worth a type.)

**Filtering and sorting** wrap the store; the view sees one combined model:

```rust
let filter = gtk::CustomFilter::new(|obj| {
    !obj.downcast_ref::<TodoItem>().unwrap().completed()
});
let filtered = gtk::FilterListModel::new(Some(store), Some(filter));

let sorter = gtk::CustomSorter::new(|a, b| {
    let a = a.downcast_ref::<TodoItem>().unwrap();
    let b = b.downcast_ref::<TodoItem>().unwrap();
    a.title().cmp(&b.title()).into()
});
let sorted = gtk::SortListModel::new(Some(filtered), Some(sorter));
let selection = gtk::SingleSelection::new(Some(sorted));
```

`gtk::GridView` takes the same selection model and factory; only the layout differs.

## Async and Threads

**Gio futures on the main loop for I/O** — no thread, no hand-off. `glib::spawn_future_local` runs a non-`Send` future on the main context (callable only from the main thread):

```rust
glib::spawn_future_local(glib::clone!(
    #[weak]
    label,
    async move {
        let file = gio::File::for_path("/etc/hostname");
        match file.load_contents_future().await {
            Ok((contents, _etag)) => {
                label.set_label(&String::from_utf8_lossy(&contents));
            }
            Err(err) if err.matches(gio::IOErrorEnum::Cancelled) => {}
            Err(err) => eprintln!("load failed: {err}"),
        }
    }
));
```

**Cancellation:** gio `*_future()` methods hold an internal `Cancellable` and cancel it when the future drops — so aborting the task cancels the I/O:

```rust
let handle = glib::spawn_future_local(async move { /* ... */ });
handle.abort();                       // e.g. from close_request

// Or share an external Cancellable (e.g. with a Cancel button):
let cancellable = gio::Cancellable::new();
glib::spawn_future_local(gio::CancellableFuture::new(
    async move { /* ... */ },
    cancellable.clone(),
));
cancellable.cancel();
```

The callback-style API (`load_contents_async(Some(&cancellable), ...)`) takes the `Cancellable` directly.

**Threads for CPU-bound work** — results come back over an `async-channel` (the successor to the removed `glib::MainContext::channel`), received by a future on the main loop:

```toml
[dependencies]
async-channel = "2"
```

```rust
let (sender, receiver) = async_channel::bounded::<u64>(1);

std::thread::spawn(move || {
    let result = heavy_computation();          // worker thread
    sender.send_blocking(result).expect("channel closed");
});

glib::spawn_future_local(glib::clone!(
    #[weak]
    label,
    async move {
        while let Ok(result) = receiver.recv().await {
            label.set_label(&result.to_string());   // main loop: widget calls safe
        }
    }
));
```

The compiler enforces the threading rule mechanically: widgets are not `Send`, so a worker thread *cannot* capture one — hand results over a channel, or use `glib::idle_add_once` (the `Send`-bound idle variant) for a one-shot hop. Reach for a tokio runtime only when a dependency requires it; GLib's main loop already executes futures.

## Error Handling

Fallible GLib/gio calls return `Result<T, glib::Error>`; match specific codes with `err.matches(gio::IOErrorEnum::Cancelled)` (see the load in Async above).

Signal handlers return `()` — `?` cannot propagate out of a callback. Do the fallible work in an inner `fn`/`async fn` that returns `Result`, and handle or log at the boundary:

```rust
button.connect_clicked(|_| {
    fn save() -> Result<(), glib::Error> { /* ?-friendly body */ Ok(()) }
    if let Err(err) = save() {
        eprintln!("save failed: {err}");
    }
});
```

## Actions

App/window basics via `ActionEntry` are in the boilerplate above. Stateful and parameterized, same builder:

```rust
let entries = [
    // Toggle with state
    gio::ActionEntry::builder("dark-mode")
        .state(false.to_variant())
        .change_state(|_app: &adw::Application, action, value| {
            if let Some(value) = value {
                action.set_state(value);
                let _is_dark = value.get::<bool>().expect("bool state");
            }
        })
        .build(),
    // Parameterized
    gio::ActionEntry::builder("open-item")
        .parameter_type(Some(glib::VariantTy::STRING))
        .activate(|_app: &adw::Application, _action, parameter| {
            let _id = parameter.and_then(|p| p.get::<String>()).expect("string parameter");
        })
        .build(),
];
app.add_action_entries(entries);

// Trigger from code
app.activate_action("open-item", Some(&"item-123".to_variant()));
```

The typed-`O` parameter on the closures is the object the entries are added to (window entries take `&MyWindow`). Bare `gio::SimpleAction` forms: `gtk-patterns-reference.md`.

## XDG Directories

```rust
let data_dir = glib::user_data_dir().join("myapp");       // ~/.local/share/myapp
let config_dir = glib::user_config_dir().join("myapp");   // ~/.config/myapp
let cache_dir = glib::user_cache_dir().join("myapp");     // ~/.cache/myapp
std::fs::create_dir_all(&data_dir)?;
```

## Build

**Plain cargo carries a full app** further than in any other GTK language: resources embed via `build.rs` (Templates above), and `cargo run` is the whole loop. The gap is *installed assets* — GSettings schemas, desktop file, icons, translations all need install rules cargo lacks. During development, point at uncompiled assets: `glib-compile-schemas data/ && GSETTINGS_SCHEMA_DIR=data/ cargo run`.

**Meson driving cargo** is the GNOME-style answer once installed assets matter: Meson owns configuration, data install rules, and i18n (the language-neutral rules in `gtk-packaging-reference.md` and `gtk-i18n-reference.md` apply unchanged), and invokes `cargo build` from a `custom_target` for the binary. The friction is real: the two build systems disagree about incrementality (Meson re-runs cargo on every build and copies the artifact out), offline/Flatpak builds need the cargo dependency tree vendored, and build options must be threaded through by hand. GNOME Builder's Rust project template is the maintained reference wiring — start from it rather than composing the `custom_target` from scratch. Flatpak toolchain and vendoring: `gtk-packaging-reference.md`.

## GVariant

**A `glib::Variant` inside a Rust tuple is boxed as `v`.** This silently
produces the wrong D-Bus signature, and the peer rejects the message with no
useful error:

```rust
// Yields "(ivav)" — NOT the "(ia{sv}av)" the interface declares.
let bad = (0i32, dict_variant, children).to_variant();

// Build container types explicitly instead:
let good = glib::Variant::tuple_from_iter([
    0i32.to_variant(),
    dict_variant,                                        // stays a{sv}
    glib::Variant::array_from_iter::<glib::Variant>(children),  // av
]);
let rows = glib::Variant::array_from_iter_with_type(
    glib::VariantTy::new("(ia{sv})").unwrap(), items);   // a(ia{sv})
```

Assert on `variant.type_().as_str()` in a unit test — `glib::Variant` needs no
display and no `gtk::init()`, so the whole encode/decode layer is testable
headless.

**`ToVariant` lives in the prelude**, not the crate root: `use
gtk::glib::prelude::ToVariant`.

**There is no `Variant::from_object_path`.** Use the newtype, or an object path
silently degrades to a plain string and the peer rejects it:

```rust
glib::variant::ObjectPath::try_from("/org/example/Thing".to_string())?.to_variant()
```

Build `a{sv}` with `glib::VariantDict::new(None)` → `insert()` → `end()`, and
read one back with `VariantDict::new(Some(&dict)).lookup_value(name, None)`.

## Testing

`cargo test`; harness code, event draining, and headless/CI setup in `gtk-testing-reference.md`. Summary: glib/gio-only code (models, controllers) tests with no display and no init; any `gtk::` type needs `gtk::init()` and a display; widget tests all belong in **one** `#[test]` (`--test-threads=1` only serialises, it does not make tests share a thread); headless CI runs under `xvfb-run dbus-run-session`.
