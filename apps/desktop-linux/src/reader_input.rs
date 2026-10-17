//! A reader window's pointer and keys (tasks 2.27 and 2.28): motion reveals the chrome,
//! a click on an edge turns, a double click zooms, a drag turns or pans, a pinch and
//! Control with the wheel zoom, the wheel turns or scrolls, a right click opens the
//! reader menu, and the page keys of the table turn. The decisions are `keys.rs` and
//! `reading/`; this file only reads GTK's events.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use adw::prelude::*;
use gtk::{gdk, glib};

use crate::keys::{self, ClickAction, Modifiers};
use crate::reader_window::Reader;
use crate::reading::{DragTurn, Size, ZoomModel};

/// How far one wheel notch scrolls a page that is larger than the window.
const WHEEL_SCROLL: f64 = 48.0;

pub fn install_pointer(reader: &Rc<Reader>) {
    let motion = gtk::EventControllerMotion::new();
    let weak = Rc::downgrade(reader);
    motion.connect_motion(move |_, _, _| {
        if let Some(reader) = weak.upgrade() {
            reader.pointer_moved();
        }
    });
    reader.window.add_controller(motion);
    install_clicks(reader);
    install_drag(reader);
    install_pinch(reader);
    install_wheel(reader);
    install_context_menu(reader);
}

/// A single click acts once the double-click time has passed without a second one, so
/// a double click zooms rather than turning twice (`desktop-experience`, Double click).
fn install_clicks(reader: &Rc<Reader>) {
    let click = gtk::GestureClick::builder()
        .button(gdk::BUTTON_PRIMARY)
        .build();
    let pending: Rc<RefCell<Option<glib::SourceId>>> = Rc::default();
    let weak = Rc::downgrade(reader);
    let waiting = pending.clone();
    click.connect_pressed(move |_, presses, _, _| {
        if presses != 2 {
            return;
        }
        if let Some(source) = waiting.borrow_mut().take() {
            source.remove();
        }
        if let Some(reader) = weak.upgrade() {
            reader.set_zoom(reader.page_view.zoom().double_clicked());
        }
    });
    let weak = Rc::downgrade(reader);
    click.connect_released(move |gesture, presses, x, _| {
        let (Some(reader), Some(widget)) = (weak.upgrade(), gesture.widget()) else {
            return;
        };
        if presses != 1 {
            return;
        }
        let width = f64::from(widget.width());
        let delay = gtk::Settings::default()
            .map_or(400, |settings| settings.gtk_double_click_time())
            .max(0);
        let weak = Rc::downgrade(&reader);
        let fired = pending.clone();
        let source = glib::timeout_add_local_once(
            Duration::from_millis(u64::try_from(delay).unwrap_or(400)),
            move || {
                fired.borrow_mut().take();
                let Some(reader) = weak.upgrade() else {
                    return;
                };
                let zones_on = reader.preferences.borrow().click_zones;
                let direction = reader.publication.direction;
                match keys::click_action(keys::zone(x, width), direction, zones_on) {
                    ClickAction::Turn(action) => reader.turn(action),
                    ClickAction::ToggleChrome => reader.toggle_chrome(),
                }
            },
        );
        if let Some(previous) = pending.borrow_mut().replace(source) {
            previous.remove();
        }
    });
    reader.page_view.add_controller(click);
}

/// A drag pans a page larger than the window; on a fitted page it slides the page with
/// the pointer and turns it past the threshold (`desktop-experience`, Dragging to turn).
fn install_drag(reader: &Rc<Reader>) {
    let drag = gtk::GestureDrag::builder()
        .button(gdk::BUTTON_PRIMARY)
        .build();
    let last = Rc::new(Cell::new((0.0, 0.0)));
    let panning = Rc::new(Cell::new(false));
    let weak = Rc::downgrade(reader);
    let (begin_last, begin_panning) = (last.clone(), panning.clone());
    drag.connect_drag_begin(move |_, _, _| {
        begin_last.set((0.0, 0.0));
        if let Some(reader) = weak.upgrade() {
            begin_panning.set(reader.page_view.overflows());
        }
    });
    let weak = Rc::downgrade(reader);
    let update_panning = panning.clone();
    drag.connect_drag_update(move |_, dx, dy| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        if update_panning.get() {
            let (x, y) = last.get();
            last.set((dx, dy));
            let view = &reader.page_view;
            let zoom =
                view.zoom()
                    .panned(Size::new(dx - x, dy - y), view.fitted(), view.viewport());
            view.set_zoom(zoom);
        } else {
            reader.page_view.set_slide(dx);
        }
    });
    let weak = Rc::downgrade(reader);
    drag.connect_drag_end(move |_, dx, _| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        if panning.get() {
            return;
        }
        reader.page_view.set_slide(0.0);
        let width = reader.page_view.viewport().width;
        if let Some(action) = DragTurn::action(dx, width, reader.right_to_left()) {
            reader.turn(action);
        }
    });
    reader.page_view.add_controller(drag);
}

fn install_pinch(reader: &Rc<Reader>) {
    let pinch = gtk::GestureZoom::new();
    let start = Rc::new(Cell::new(ZoomModel::default()));
    let weak = Rc::downgrade(reader);
    let begin = start.clone();
    pinch.connect_begin(move |_, _| {
        if let Some(reader) = weak.upgrade() {
            begin.set(reader.page_view.zoom());
        }
    });
    let weak = Rc::downgrade(reader);
    pinch.connect_scale_changed(move |_, scale| {
        if let Some(reader) = weak.upgrade() {
            reader.set_zoom(start.get().magnified(scale));
        }
    });
    reader.page_view.add_controller(pinch);
}

/// Control and the wheel zoom; the wheel scrolls a page larger than the window and turns
/// a fitted one a notch at a time (`desktop-experience`, Plain wheel on a page that fits).
fn install_wheel(reader: &Rc<Reader>) {
    let scroll = gtk::EventControllerScroll::new(gtk::EventControllerScrollFlags::VERTICAL);
    let weak = Rc::downgrade(reader);
    scroll.connect_scroll(move |controller, _, dy| {
        let Some(reader) = weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        let view = &reader.page_view;
        if controller
            .current_event_state()
            .contains(gdk::ModifierType::CONTROL_MASK)
        {
            reader.set_zoom(view.zoom().wheeled(-dy));
            return glib::Propagation::Stop;
        }
        if view.overflows() {
            let step = match controller.unit() {
                gdk::ScrollUnit::Wheel => WHEEL_SCROLL,
                _ => 1.0,
            };
            let zoom =
                view.zoom()
                    .panned(Size::new(0.0, -dy * step), view.fitted(), view.viewport());
            view.set_zoom(zoom);
            return glib::Propagation::Stop;
        }
        let action = reader.wheel.borrow_mut().scrolled(dy);
        if let Some(action) = action {
            reader.turn(action);
        }
        glib::Propagation::Stop
    });
    reader.page_view.add_controller(scroll);
}

fn install_context_menu(reader: &Rc<Reader>) {
    let context = gtk::GestureClick::builder()
        .button(gdk::BUTTON_SECONDARY)
        .build();
    let popover = gtk::PopoverMenu::from_model(Some(&reader.menu));
    popover.set_parent(&reader.page_view);
    popover.set_has_arrow(false);
    context.connect_pressed(move |_, _, x, y| {
        popover.set_pointing_to(Some(&gdk::Rectangle::new(x as i32, y as i32, 1, 1)));
        popover.popup();
    });
    reader.page_view.add_controller(context);
}

/// The keys of the table that have no modifier: they are not application accelerators,
/// so a text field keeps them, and the reader maps them itself.
pub fn install_keys(reader: &Rc<Reader>) {
    let controller = gtk::EventControllerKey::new();
    // Capture: an arrow turns the page before a focused header button can take it to
    // move the focus, which ate the first turn on a walk under cage. A text field in
    // focus still keeps every key (`focused_text` below).
    controller.set_propagation_phase(gtk::PropagationPhase::Capture);
    let weak = Rc::downgrade(reader);
    controller.connect_key_pressed(move |_, key, _, state| {
        let Some(reader) = weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        let focused_text = gtk::prelude::GtkWindowExt::focus(&reader.window)
            .is_some_and(|widget| widget.is::<gtk::Editable>() || widget.is::<gtk::Text>());
        let mapped = match key {
            gdk::Key::Left => keys::Key::Left,
            gdk::Key::Right => keys::Key::Right,
            gdk::Key::Up => keys::Key::Up,
            gdk::Key::Down => keys::Key::Down,
            gdk::Key::space => keys::Key::Space,
            gdk::Key::Page_Up => keys::Key::PageUp,
            gdk::Key::Page_Down => keys::Key::PageDown,
            gdk::Key::Home => keys::Key::Home,
            gdk::Key::End => keys::Key::End,
            gdk::Key::Escape => keys::Key::Escape,
            _ => keys::Key::Other,
        };
        if mapped == keys::Key::Escape && !focused_text {
            if reader.full_screen.get().leaves_on_escape() {
                reader.toggle_full_screen();
                return glib::Propagation::Stop;
            }
            return glib::Propagation::Proceed;
        }
        let modifiers = Modifiers {
            shift: state.contains(gdk::ModifierType::SHIFT_MASK),
            control: state.contains(gdk::ModifierType::CONTROL_MASK),
            alt: state.contains(gdk::ModifierType::ALT_MASK),
        };
        match keys::page_action(
            mapped,
            modifiers,
            reader.publication.direction,
            focused_text,
        ) {
            Some(action) => {
                reader.turn(action);
                glib::Propagation::Stop
            }
            None => glib::Propagation::Proceed,
        }
    });
    reader.window.add_controller(controller);
}
