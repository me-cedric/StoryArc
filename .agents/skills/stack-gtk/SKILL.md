---
name: stack-gtk
description: "GTK 4 and libadwaita rules for widgets, navigation, threading, actions, lists, settings, accessibility and gtk4-rs. Applies when you edit a GTK desktop app."
---
# GTK rules

## Platform
- Build on GTK 4 and libadwaita. Use `adw::Application` and `adw::ApplicationWindow`. Do not use GTK 3 API.
- Set the version floor on purpose. In gtk4-rs, enable only the crate features that match it, such as `v4_14` and `v1_5`. Do not call newer API.
- Use one reverse-DNS application ID. Use the same ID in `adw::Application`, the desktop file, the metainfo file and the icon name.
- Follow the GNOME HIG. Use a header bar and a primary menu. Use `adw::NavigationView` or `adw::NavigationSplitView` for navigation.
- Make the layout adaptive with `adw::Breakpoint`. Do not set a fixed window size that blocks a narrow window.
- Show settings in `adw::PreferencesDialog` (libadwaita 1.5) or `adw::PreferencesWindow`. Show About in `adw::AboutDialog` or `adw::AboutWindow`.
- Show a confirmation in `adw::AlertDialog` (1.5) or `adw::MessageDialog`. Do not use `gtk::MessageDialog`.
- Request the narrowest sandbox permissions in the Flatpak manifest.

## Look and feel
- Use libadwaita style classes and named colours, such as `@accent_bg_color`, `@window_bg_color` and `@view_bg_color`. Do not hard-code hex colours.
- Follow the system colour scheme through `adw::StyleManager`. Do not add an in-app theme switch.
- Use symbolic icons by name from the icon theme.
- Give each icon-only button a tooltip and an accessible label.
- Set a mnemonic or an accelerator on each primary action. Keep every action reachable by keyboard.

## Structure
- Define each action with `gio::ActionEntry`. Name it `app.<name>` or `win.<name>`. Set accelerators with `set_accels_for_action`.
- Build menus with `gio::Menu`.
- Show lists with `gio::ListStore`, `gtk::ListView` and a `SignalListItemFactory`. Use `GridView` for grids and `DropDown` for choices.
- Do not use `TreeView`, `ComboBox`, `IconView` or `CellRenderer`. GTK 4.10 deprecated them.
- Use `gtk::FileDialog`, `ColorDialog` and `FontDialog` (GTK 4.10) in place of the chooser dialogs.
- Define a complex widget with a template (`.ui` or Blueprint) and a subclass.
- Store user settings in `gio::Settings` backed by a compiled GSettings schema.
- Bundle UI files, CSS and icons in a `gio::Resource`.

## Threading
- Do not block the main thread. Run blocking I/O in `gio::spawn_blocking` or a worker thread.
- Change a widget only on the main thread. Send results back through a channel or a task on the main context.
- Use `gio` async APIs with `glib::spawn_future_local` for I/O that has one.
- Give each long task a `gio::Cancellable`. Cancel it when the widget is destroyed or the user leaves.

## gtk4-rs
- Write each custom widget as a `glib::wrapper!` type with a private `imp` module. Use `#[derive(glib::Properties)]` and `#[derive(CompositeTemplate)]` with `#[template_child]`.
- Capture widgets weakly in closures: `glib::clone!(#[weak] widget, move |_| ...)`. A strong capture in a signal handler leaks the widget.
- Do not hold a `RefCell` borrow across an `await` or a signal emit. The handler can re-enter the widget.
- Keep logic out of widget code. `cargo test` then covers it without a display.
- Before you finish, run `cargo fmt` and `cargo clippy -- -D warnings`.
- Read more in the upstream source `gtk` (skill `developing-gtk-apps`) when the host lists it in `upstream`.
