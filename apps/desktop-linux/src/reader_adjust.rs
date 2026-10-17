//! The image adjustments (`comic-reader`, Image adjustments): brightness, contrast and
//! sharpness, invert, greyscale and trimming a page's borders, kept per series and
//! applied to every page of it at once. Trimming can be undone for the page the reader is
//! on. The pixels are the core's (`storyarc_core::image::adjusted`); the rules for what is
//! kept are `reading/adjust.rs`. A drag on a slider decodes once it rests, not at every
//! step.

use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use adw::prelude::*;
use gtk::glib;
use storyarc_core::domain::ImageAdjustments;

use crate::reader_window::Reader;
use crate::strings::tr;

/// How long a slider rests before the pages decode again.
const REST: Duration = Duration::from_millis(250);

pub fn present(reader: &Rc<Reader>) {
    let Some(shared) = reader.shared.upgrade() else {
        return;
    };
    let record = reader.publication.record.clone();
    let current = shared.adjustments.borrow().for_publication(&record);
    let state = Rc::new(RefCell::new(current));
    let rest: Rc<RefCell<Option<glib::SourceId>>> = Rc::default();

    let apply = {
        let (weak, state, rest) = (Rc::downgrade(reader), state.clone(), rest.clone());
        Rc::new(move |immediately: bool| {
            if let Some(source) = rest.borrow_mut().take() {
                source.remove();
            }
            let run = {
                let (weak, state) = (weak.clone(), state.clone());
                move || {
                    let Some(reader) = weak.upgrade() else {
                        return;
                    };
                    let Some(shared) = reader.shared.upgrade() else {
                        return;
                    };
                    let value = *state.borrow();
                    shared.update_adjustments(|all| {
                        all.choose(&reader.publication.record, value);
                    });
                    reader.adjustments_changed();
                }
            };
            if immediately {
                run();
            } else {
                let fired = rest.clone();
                let source = glib::timeout_add_local_once(REST, move || {
                    fired.borrow_mut().take();
                    run();
                });
                *rest.borrow_mut() = Some(source);
            }
        })
    };

    let page = adw::PreferencesPage::new();
    let tone = adw::PreferencesGroup::builder()
        .title(tr("reader.adjust.tone", "Tone"))
        .build();
    let sliders = [
        (
            tr("reader.adjust.brightness", "Brightness"),
            -1.0,
            1.0,
            current.brightness,
            0usize,
        ),
        (
            tr("reader.adjust.contrast", "Contrast"),
            -1.0,
            1.0,
            current.contrast,
            1,
        ),
        (
            tr("reader.adjust.sharpness", "Sharpness"),
            0.0,
            1.0,
            current.sharpness,
            2,
        ),
    ];
    let mut scales = Vec::new();
    for (title, low, high, value, which) in sliders {
        let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, low, high, 0.05);
        scale.set_draw_value(false);
        scale.set_value(value);
        scale.set_size_request(220, -1);
        scale.set_valign(gtk::Align::Center);
        scale.update_property(&[gtk::accessible::Property::Label(&title)]);
        let (state, apply) = (state.clone(), apply.clone());
        scale.connect_value_changed(move |scale| {
            {
                let mut adjustments = state.borrow_mut();
                match which {
                    0 => adjustments.brightness = scale.value(),
                    1 => adjustments.contrast = scale.value(),
                    _ => adjustments.sharpness = scale.value(),
                }
            }
            apply(false);
        });
        let row = adw::ActionRow::builder().title(&title).build();
        row.add_suffix(&scale);
        tone.add(&row);
        scales.push(scale);
    }
    page.add(&tone);

    let looks = adw::PreferencesGroup::builder()
        .title(tr("reader.adjust.look", "Look"))
        .build();
    let invert = switch(
        &tr("reader.adjust.invert", "Invert colours"),
        current.is_inverted,
    );
    let grey = switch(
        &tr("reader.adjust.greyscale", "Greyscale"),
        current.is_greyscale,
    );
    let trim = switch(
        &tr("reader.adjust.trim", "Trim page borders"),
        current.crops_borders,
    );
    let trim_here = switch(
        &tr("reader.adjust.trimHere", "Trim this page"),
        shared
            .adjustments
            .borrow()
            .is_trimmed_here(&reader.publication.id, reader.page() as usize),
    );
    trim_here.set_sensitive(current.crops_borders);
    for row in [&invert, &grey, &trim, &trim_here] {
        looks.add(row);
    }
    page.add(&looks);

    let reset = gtk::Button::builder()
        .label(tr("reader.adjust.reset", "Reset"))
        .css_classes(["pill"])
        .halign(gtk::Align::Center)
        .build();
    let reset_group = adw::PreferencesGroup::new();
    reset_group.add(&reset);
    page.add(&reset_group);

    {
        let (state, apply, trim_here) = (state.clone(), apply.clone(), trim_here.clone());
        invert.connect_active_notify({
            let (state, apply) = (state.clone(), apply.clone());
            move |row| {
                state.borrow_mut().is_inverted = row.is_active();
                apply(true);
            }
        });
        grey.connect_active_notify({
            let (state, apply) = (state.clone(), apply.clone());
            move |row| {
                state.borrow_mut().is_greyscale = row.is_active();
                apply(true);
            }
        });
        trim.connect_active_notify(move |row| {
            state.borrow_mut().crops_borders = row.is_active();
            trim_here.set_sensitive(row.is_active());
            apply(true);
        });
    }
    {
        let weak = Rc::downgrade(reader);
        trim_here.connect_active_notify(move |row| {
            let Some(reader) = weak.upgrade() else {
                return;
            };
            let Some(shared) = reader.shared.upgrade() else {
                return;
            };
            let page = reader.page() as usize;
            shared.update_adjustments(|all| {
                all.set_trim_here(&reader.publication.id, page, row.is_active());
            });
            reader.adjustments_changed();
        });
    }
    {
        let (state, apply) = (state.clone(), apply.clone());
        let (invert, grey, trim) = (invert.clone(), grey.clone(), trim.clone());
        reset.connect_clicked(move |_| {
            *state.borrow_mut() = ImageAdjustments::default();
            for scale in &scales {
                scale.set_value(0.0);
            }
            invert.set_active(false);
            grey.set_active(false);
            trim.set_active(false);
            apply(true);
        });
    }

    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&page));
    let dialog = adw::Dialog::builder()
        .title(tr("reader.adjust.title", "Image Adjustments"))
        .content_width(460)
        .content_height(560)
        .child(&toolbar)
        .build();
    // A rest still pending when the dialog closes is applied, not dropped.
    let closing = apply.clone();
    dialog.connect_closed(move |_| {
        if rest.borrow().is_some() {
            closing(true);
        }
    });
    dialog.present(Some(&reader.window));
}

fn switch(title: &str, active: bool) -> adw::SwitchRow {
    adw::SwitchRow::builder()
        .title(title)
        .active(active)
        .build()
}
