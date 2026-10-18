//! The theme surface of the EPUB window (`ebook-reader`, *One sheet, two depths*): a popover
//! that opens on the six presets as named swatches in their own colours, with one action to the
//! reader's typography below them, then the brightness and the light and dark pair the page
//! follows. Picking a preset applies it and closes the surface. The second depth is the text
//! panel; under *Original* the axes the publisher's stylesheet governs are shown insensitive with
//! the reason beside them, not hidden. The values and the messages are `epub_look.rs`.

use std::cell::{OnceCell, RefCell};
use std::rc::Rc;

use adw::prelude::*;
use gtk::gdk;

use crate::epub_look::{
    Alignment, LINE_HEIGHT, Look, MARGINS, PARAGRAPH_SPACING, Preset, SIZE_STEPS, Typeface, Values,
};
use crate::strings::{tr, tr_args};

/// Changes the look, saves it and puts it on the page.
pub type Change = Rc<dyn Fn(&dyn Fn(&mut Look))>;

/// The header button that opens the surface. The surface is built again each time it opens,
/// so it always opens on the presets and shows what is in force.
pub fn button(look: &Rc<RefCell<Look>>, change: &Change) -> gtk::MenuButton {
    let title = tr("desktop.w4.epub.theme", "Theme");
    let popover = gtk::Popover::new();
    let menu = gtk::MenuButton::builder()
        .icon_name("preferences-desktop-appearance-symbolic")
        .tooltip_text(&title)
        .popover(&popover)
        .build();
    menu.update_property(&[gtk::accessible::Property::Label(&title)]);
    let (look, change) = (look.clone(), change.clone());
    popover.connect_show(move |popover| {
        popover.set_child(Some(&surface(popover, &look, &change, false)));
    });
    menu
}

fn surface(
    popover: &gtk::Popover,
    look: &Rc<RefCell<Look>>,
    change: &Change,
    on_text: bool,
) -> gtk::Widget {
    let stack = gtk::Stack::builder()
        .transition_type(gtk::StackTransitionType::SlideLeft)
        .vhomogeneous(false)
        .build();
    stack.add_named(&presets(popover, look, change, &stack), Some("presets"));
    let text = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .propagate_natural_height(true)
        .max_content_height(560)
        .child(&text_panel(popover, look, change))
        .build();
    stack.add_named(&text, Some("text"));
    stack.set_visible_child_name(if on_text { "text" } else { "presets" });
    stack.set_size_request(340, -1);
    stack.upcast()
}

/// One class a preset, in the preset's own colours, added to the display once.
fn swatch_class(preset: Preset) -> String {
    thread_local! {
        static PROVIDER: OnceCell<gtk::CssProvider> = const { OnceCell::new() };
    }
    PROVIDER.with(|cell| {
        cell.get_or_init(|| {
            let css: String = Preset::ALL
                .into_iter()
                .map(|preset| {
                    let (background, text) = preset.colours();
                    format!(
                        ".storyarc-swatch-{} {{ background: {background}; color: {text}; border-radius: 10px; }}\n",
                        preset.key()
                    )
                })
                .chain(std::iter::once(
                    ".storyarc-swatch:checked { outline: 3px solid @accent_color; outline-offset: 1px; }\n".to_owned(),
                ))
                .collect();
            let provider = gtk::CssProvider::new();
            provider.load_from_string(&css);
            if let Some(display) = gdk::Display::default() {
                gtk::style_context_add_provider_for_display(
                    &display,
                    &provider,
                    gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
                );
            }
            provider
        });
    });
    format!("storyarc-swatch-{}", preset.key())
}

fn presets(
    popover: &gtk::Popover,
    look: &Rc<RefCell<Look>>,
    change: &Change,
    stack: &gtk::Stack,
) -> gtk::Box {
    let current = *look.borrow();
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(14)
        .margin_top(12)
        .margin_bottom(12)
        .margin_start(12)
        .margin_end(12)
        .build();
    let grid = gtk::Grid::builder()
        .row_spacing(10)
        .column_spacing(10)
        .halign(gtk::Align::Center)
        .build();
    let mut first: Option<gtk::ToggleButton> = None;
    for (at, preset) in Preset::ALL.into_iter().enumerate() {
        let inner = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(2)
            .build();
        let specimen = gtk::Label::new(Some(&tr("desktop.w4.epub.specimen", "Aa")));
        specimen.add_css_class(if preset == Preset::Bold {
            "title-1"
        } else {
            "title-2"
        });
        inner.append(&specimen);
        inner.append(
            &gtk::Label::builder()
                .label(preset.title())
                .css_classes(["caption"])
                .build(),
        );
        if preset == current.preset && current.is_modified() {
            inner.append(
                &gtk::Label::builder()
                    .label(tr("theme.modified", "Modified"))
                    .css_classes(["caption", "dim-label"])
                    .build(),
            );
        }
        let swatch = gtk::ToggleButton::builder()
            .child(&inner)
            .active(preset == current.preset)
            .width_request(96)
            .height_request(76)
            .css_classes(["storyarc-swatch", swatch_class(preset).as_str()])
            .build();
        swatch.update_property(&[gtk::accessible::Property::Label(&preset.title())]);
        match &first {
            Some(group) => swatch.set_group(Some(group)),
            None => first = Some(swatch.clone()),
        }
        let (change, popover) = (change.clone(), popover.clone());
        swatch.connect_clicked(move |_| {
            change(&|look| look.preset = preset);
            popover.popdown();
        });
        grid.attach(&swatch, (at % 3) as i32, (at / 3) as i32, 1, 1);
    }
    column.append(&grid);

    let customise = gtk::Button::builder()
        .label(tr("theme.customise", "Customise"))
        .css_classes(["pill"])
        .build();
    let on_stack = stack.clone();
    customise.connect_clicked(move |_| on_stack.set_visible_child_name("text"));
    column.append(&customise);

    let group = adw::PreferencesGroup::new();
    let brightness = scale(
        (0.5, 1.0),
        0.05,
        current.brightness,
        &tr("theme.brightness", "Brightness"),
    );
    let on_change = change.clone();
    brightness.connect_value_changed(move |scale| {
        let value = scale.value();
        on_change(&|look| look.brightness = value);
    });
    let row = adw::ActionRow::builder()
        .title(tr("theme.brightness", "Brightness"))
        .build();
    row.add_suffix(&brightness);
    group.add(&row);

    let follows = adw::SwitchRow::builder()
        .title(tr(
            "desktop.w4.epub.followsAppearance",
            "Follow the system's appearance",
        ))
        .active(current.follows)
        .build();
    let titles: Vec<String> = Preset::ALL.into_iter().map(Preset::title).collect();
    let titles: Vec<&str> = titles.iter().map(String::as_str).collect();
    let pair = |title: String, preset: Preset| {
        adw::ComboRow::builder()
            .title(title)
            .model(&gtk::StringList::new(&titles))
            .selected(Preset::ALL.iter().position(|p| *p == preset).unwrap_or(0) as u32)
            .visible(current.follows)
            .build()
    };
    let light = pair(
        tr("appearance.linkTheme.light", "Light theme"),
        current.light,
    );
    let dark = pair(tr("appearance.linkTheme.dark", "Dark theme"), current.dark);
    let (on_change, on_light, on_dark) = (change.clone(), light.clone(), dark.clone());
    follows.connect_active_notify(move |row| {
        let active = row.is_active();
        on_light.set_visible(active);
        on_dark.set_visible(active);
        on_change(&|look| look.follows = active);
    });
    for (row, is_dark) in [(&light, false), (&dark, true)] {
        let on_change = change.clone();
        row.connect_selected_notify(move |row| {
            let preset = Preset::ALL[(row.selected() as usize).min(Preset::ALL.len() - 1)];
            on_change(&|look| {
                if is_dark {
                    look.dark = preset;
                } else {
                    look.light = preset;
                }
            });
        });
    }
    group.add(&follows);
    group.add(&light);
    group.add(&dark);
    column.append(&group);
    column
}

fn scale(range: (f64, f64), step: f64, value: f64, label: &str) -> gtk::Scale {
    let scale = gtk::Scale::with_range(gtk::Orientation::Horizontal, range.0, range.1, step);
    scale.set_draw_value(false);
    scale.set_value(value);
    scale.set_size_request(150, -1);
    scale.set_valign(gtk::Align::Center);
    scale.update_property(&[gtk::accessible::Property::Label(label)]);
    scale
}

/// A slider row over one of the phones' axes, ten steps across its range. A drag sends a
/// message only when it reaches another step.
fn axis_row(
    title: String,
    range: (f64, f64),
    value: f64,
    change: &Change,
    set: fn(&mut Values, f64),
) -> adw::ActionRow {
    let step = (range.1 - range.0) / 10.0;
    let slider = scale(range, step, value, &title);
    let last = std::cell::Cell::new(value);
    let change = change.clone();
    slider.connect_value_changed(move |slider| {
        let snapped = range.0 + ((slider.value() - range.0) / step).round() * step;
        let snapped = (snapped * 100.0).round() / 100.0;
        if (snapped - last.get()).abs() < f64::EPSILON {
            return;
        }
        last.set(snapped);
        change(&|look| set(&mut look.values, snapped));
    });
    let row = adw::ActionRow::builder().title(title).build();
    row.add_suffix(&slider);
    row
}

fn text_panel(popover: &gtk::Popover, look: &Rc<RefCell<Look>>, outer: &Change) -> gtk::Box {
    let current = *look.borrow();
    let values = current.values;
    let reset = gtk::Button::builder()
        .label(tr_args(
            "theme.restore.named %s",
            "Restore %s",
            &[&current.preset.title()],
        ))
        .halign(gtk::Align::Center)
        .sensitive(current.is_modified())
        .build();
    // Every edit here also says whether there is anything to restore.
    let change: &Change = &{
        let (outer, look, reset) = (outer.clone(), look.clone(), reset.clone());
        Rc::new(move |edit: &dyn Fn(&mut Look)| {
            outer(edit);
            reset.set_sensitive(look.borrow().is_modified());
        }) as Change
    };
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .margin_top(12)
        .margin_bottom(12)
        .margin_start(12)
        .margin_end(12)
        .build();

    let always = adw::PreferencesGroup::new();
    let percent = |size: u32| {
        tr_args(
            "theme.fontSize.percent %d",
            "%d%% of the publisher’s size",
            &[&size],
        )
    };
    let size = adw::ActionRow::builder()
        .title(tr("theme.axis.fontSize", "Text size"))
        .subtitle(percent(values.font_size))
        .build();
    let smaller = gtk::Button::builder()
        .icon_name("zoom-out-symbolic")
        .valign(gtk::Align::Center)
        .tooltip_text(tr("theme.fontSize.smaller", "Smaller"))
        .sensitive(values.font_size > SIZE_STEPS[0])
        .css_classes(["flat"])
        .build();
    let larger = gtk::Button::builder()
        .icon_name("zoom-in-symbolic")
        .valign(gtk::Align::Center)
        .tooltip_text(tr("theme.fontSize.larger", "Larger"))
        .sensitive(values.font_size < SIZE_STEPS[SIZE_STEPS.len() - 1])
        .css_classes(["flat"])
        .build();
    for (button, up) in [(&smaller, false), (&larger, true)] {
        button.update_property(&[gtk::accessible::Property::Label(
            &button.tooltip_text().unwrap_or_default(),
        )]);
        let (look, change, size) = (look.clone(), change.clone(), size.clone());
        let (smaller, larger) = (smaller.clone(), larger.clone());
        button.connect_clicked(move |_| {
            change(&|look| look.values = look.values.step_size(up));
            let now = look.borrow().values.font_size;
            size.set_subtitle(&percent(now));
            smaller.set_sensitive(now > SIZE_STEPS[0]);
            larger.set_sensitive(now < SIZE_STEPS[SIZE_STEPS.len() - 1]);
        });
    }
    size.add_suffix(&smaller);
    size.add_suffix(&larger);
    always.add(&size);

    let faces: Vec<String> = Typeface::ALL.into_iter().map(Typeface::title).collect();
    let faces: Vec<&str> = faces.iter().map(String::as_str).collect();
    let typeface = adw::ComboRow::builder()
        .title(tr("theme.axis.fontFamily", "Typeface"))
        .model(&gtk::StringList::new(&faces))
        .selected(
            Typeface::ALL
                .iter()
                .position(|f| *f == values.typeface)
                .unwrap_or(0) as u32,
        )
        .build();
    let on_change = change.clone();
    typeface.connect_selected_notify(move |row| {
        let face = Typeface::ALL[(row.selected() as usize).min(Typeface::ALL.len() - 1)];
        on_change(&|look| look.values.typeface = face);
    });
    always.add(&typeface);
    let bold = adw::SwitchRow::builder()
        .title(tr("theme.axis.boldText", "Bold text"))
        .active(values.bold)
        .build();
    let on_change = change.clone();
    bold.connect_active_notify(move |row| {
        let active = row.is_active();
        on_change(&|look| look.values.bold = active);
    });
    always.add(&bold);
    always.add(&axis_row(
        tr("theme.axis.margins", "Margins"),
        MARGINS,
        values.margins,
        change,
        |values, value| values.margins = value,
    ));
    column.append(&always);

    let publisher = current.preset.keeps_publisher_styles();
    let dependent = adw::PreferencesGroup::builder()
        .sensitive(!publisher)
        .build();
    if publisher {
        dependent.set_description(Some(&tr(
            "theme.publisherStyles.reason",
            "Original keeps the book exactly as it was published, so these controls cannot reach the page. Text size still can.",
        )));
    }
    dependent.add(&axis_row(
        tr("theme.axis.lineSpacing", "Line spacing"),
        LINE_HEIGHT,
        values.line_height,
        change,
        |values, value| values.line_height = value,
    ));
    dependent.add(&axis_row(
        tr("theme.axis.paragraphSpacing", "Paragraph spacing"),
        PARAGRAPH_SPACING,
        values.paragraph_spacing,
        change,
        |values, value| values.paragraph_spacing = value,
    ));
    let alignments: Vec<String> = Alignment::ALL.into_iter().map(Alignment::title).collect();
    let alignments: Vec<&str> = alignments.iter().map(String::as_str).collect();
    let alignment = adw::ComboRow::builder()
        .title(tr("theme.axis.textAlignment", "Text alignment"))
        .model(&gtk::StringList::new(&alignments))
        .selected(
            Alignment::ALL
                .iter()
                .position(|a| *a == values.alignment)
                .unwrap_or(0) as u32,
        )
        .build();
    let on_change = change.clone();
    alignment.connect_selected_notify(move |row| {
        let chosen = Alignment::ALL[(row.selected() as usize).min(Alignment::ALL.len() - 1)];
        on_change(&|look| look.values.alignment = chosen);
    });
    dependent.add(&alignment);
    let hyphens = adw::SwitchRow::builder()
        .title(tr("theme.axis.hyphenation", "Hyphenation"))
        .active(values.hyphens)
        .build();
    let on_change = change.clone();
    hyphens.connect_active_notify(move |row| {
        let active = row.is_active();
        on_change(&|look| look.values.hyphens = active);
    });
    dependent.add(&hyphens);
    column.append(&dependent);

    let layout = adw::PreferencesGroup::new();
    let scroll = adw::SwitchRow::builder()
        .title(tr(
            "desktop.w4.epub.scroll",
            "Scroll instead of turning pages",
        ))
        .active(current.scroll)
        .build();
    let on_change = change.clone();
    scroll.connect_active_notify(move |row| {
        let active = row.is_active();
        on_change(&|look| look.scroll = active);
    });
    layout.add(&scroll);
    column.append(&layout);

    let (look, change, popover) = (look.clone(), outer.clone(), popover.clone());
    reset.connect_clicked(move |_| {
        change(&|look| look.values = Values::default());
        // Every control shows the preset's values again.
        popover.set_child(Some(&surface(&popover, &look, &change, true)));
    });
    column.append(&reset);
    column
}

#[cfg(test)]
mod tests {
    use super::*;

    fn all(widget: &gtk::Widget) -> Vec<gtk::Widget> {
        let mut found = vec![widget.clone()];
        let mut child = widget.first_child();
        while let Some(next) = child {
            found.extend(all(&next));
            child = next.next_sibling();
        }
        found
    }

    fn of<T: IsA<gtk::Widget>>(widget: &gtk::Widget) -> Vec<T> {
        all(widget)
            .into_iter()
            .filter_map(|w| w.downcast::<T>().ok())
            .collect()
    }

    /// `ebook-reader`, *One sheet, two depths*, *The theme surface opens on the presets*, *Themes
    /// are named, not numbered*, *An axis is inert while publisher styles are on* and *Getting
    /// back to the preset*, on the widgets themselves. Needs a display: `headless-proof.sh
    /// epub_theme_ui` runs it under cage.
    #[test]
    fn the_surface_opens_on_named_presets_and_its_second_depth_obeys_original() {
        crate::display_test::on_display(surface_on_a_display);
    }

    fn surface_on_a_display() {
        let look = Rc::new(RefCell::new(Look {
            preset: Preset::Calm,
            ..Look::default()
        }));
        let on_look = look.clone();
        let change: Change = Rc::new(move |edit| edit(&mut on_look.borrow_mut()));
        let popover = gtk::Popover::new();
        let stack = surface(&popover, &look, &change, false)
            .downcast::<gtk::Stack>()
            .unwrap();
        assert_eq!(stack.visible_child_name().as_deref(), Some("presets"));

        let presets = stack.child_by_name("presets").unwrap();
        let swatches: Vec<gtk::ToggleButton> = of(&presets);
        assert_eq!(swatches.len(), 6);
        let names: Vec<String> = swatches
            .iter()
            .map(|swatch| {
                of::<gtk::Label>(swatch.upcast_ref())
                    .iter()
                    .map(|label| label.text().to_string())
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .collect();
        for (name, preset) in names.iter().zip(Preset::ALL) {
            assert!(name.contains(&preset.title()), "{name}");
        }
        assert!(swatches[4].is_active() && !swatches[2].is_active());

        // A preset applies and closes; the typography stays.
        swatches[0].emit_clicked();
        assert_eq!(look.borrow().preset, Preset::Original);

        // The second depth: under Original the dependent axes are insensitive and say why.
        let text = surface(&popover, &look, &change, true)
            .downcast::<gtk::Stack>()
            .unwrap();
        assert_eq!(text.visible_child_name().as_deref(), Some("text"));
        let groups: Vec<adw::PreferencesGroup> = of(&text.child_by_name("text").unwrap());
        assert!(groups[0].is_sensitive());
        assert!(!groups[1].is_sensitive() && groups[1].description().is_some());
        look.borrow_mut().preset = Preset::Paper;
        let text = surface(&popover, &look, &change, true)
            .downcast::<gtk::Stack>()
            .unwrap();
        let groups: Vec<adw::PreferencesGroup> = of(&text.child_by_name("text").unwrap());
        assert!(groups[1].is_sensitive());

        // A larger size marks the preset modified; the reset puts every axis back.
        let larger = of::<gtk::Button>(&text.child_by_name("text").unwrap())
            .into_iter()
            .find(|b| b.icon_name().as_deref() == Some("zoom-in-symbolic"))
            .unwrap();
        larger.emit_clicked();
        assert_eq!(look.borrow().values.font_size, 115);
        assert!(look.borrow().is_modified());
        let reset = of::<gtk::Button>(&text.child_by_name("text").unwrap())
            .into_iter()
            .find(|b| {
                b.label()
                    .is_some_and(|l| l.contains(&Preset::Paper.title()))
            })
            .unwrap();
        assert!(reset.is_sensitive());
        reset.emit_clicked();
        assert!(!look.borrow().is_modified());
    }
}
