//! The mini player (task 4.14): a bar in a `GtkRevealer` at the foot of the library
//! window, the floor's stand-in for `AdwBottomSheet` (design.md, Decision 4). It shows the
//! cover, the title, what is playing and where, and carries the transport: skip back,
//! play or pause, skip forward, stop, and a position slider. Every control states a name
//! and its value for Orca (`audio-playback`, Reaching the player without sight).

use std::cell::Cell;
use std::rc::Rc;
use std::time::Duration;

use adw::prelude::*;
use gtk::gio;

use crate::app::Shared;
use crate::audio::PlayState;
use crate::player::{self, Showing};
use crate::strings::{tr, tr_args};

struct Bar {
    revealer: gtk::Revealer,
    cover: gtk::Picture,
    title: gtk::Label,
    subtitle: gtk::Label,
    clock: gtk::Label,
    play: gtk::Button,
    slider: gtk::Scale,
    /// Set while the bar moves the slider itself, so the move is not taken as a seek.
    moving: Cell<bool>,
}

/// Builds the bar and binds it to the app's player; the library window adds it as a
/// bottom bar. Hidden until something plays, and again once playback stops.
pub fn bar(shared: &Shared, window: &adw::ApplicationWindow) -> gtk::Revealer {
    let cover = gtk::Picture::builder()
        .width_request(44)
        .height_request(44)
        .content_fit(gtk::ContentFit::Cover)
        .css_classes(["card"])
        .build();
    cover.update_property(&[gtk::accessible::Property::Label(&tr(
        "detail.cover",
        "Cover",
    ))]);
    let title = gtk::Label::builder()
        .xalign(0.0)
        .ellipsize(gtk::pango::EllipsizeMode::End)
        .css_classes(["heading"])
        .build();
    let subtitle = gtk::Label::builder()
        .xalign(0.0)
        .ellipsize(gtk::pango::EllipsizeMode::End)
        .css_classes(["dim-label", "caption"])
        .build();
    let words = gtk::Box::new(gtk::Orientation::Vertical, 2);
    words.set_hexpand(true);
    words.set_valign(gtk::Align::Center);
    words.append(&title);
    words.append(&subtitle);

    let back = transport_button(
        "media-seek-backward-symbolic",
        "win.skip-back",
        &tr_args("player.skip.back %s", "%s back", &[&"15 s"]),
    );
    let play = transport_button(
        "media-playback-start-symbolic",
        "win.play-pause",
        &tr("player.play", "Play"),
    );
    play.add_css_class("circular");
    let forward = transport_button(
        "media-seek-forward-symbolic",
        "win.skip-forward",
        &tr_args("player.skip.forward %s", "%s forward", &[&"30 s"]),
    );
    let stop = transport_button(
        "window-close-symbolic",
        "win.stop-playback",
        &tr("player.stop", "Stop"),
    );
    let clock = gtk::Label::builder()
        .css_classes(["numeric", "dim-label", "caption"])
        .build();
    let slider = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 1.0, 1.0);
    slider.set_hexpand(true);
    slider.set_draw_value(false);
    slider.update_property(&[gtk::accessible::Property::Label(&tr(
        "player.position",
        "Position",
    ))]);

    let controls = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    controls.set_valign(gtk::Align::Center);
    controls.append(&back);
    controls.append(&play);
    controls.append(&forward);

    let top = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    top.append(&cover);
    top.append(&words);
    top.append(&controls);
    top.append(&stop);
    let bottom = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    bottom.append(&slider);
    bottom.append(&clock);
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(6)
        .margin_start(12)
        .margin_end(12)
        .margin_top(8)
        .margin_bottom(8)
        .css_classes(["toolbar"])
        .build();
    column.append(&top);
    column.append(&bottom);
    column.update_property(&[gtk::accessible::Property::Label(&tr(
        "player.nowPlaying",
        "Now playing",
    ))]);
    let revealer = gtk::Revealer::builder()
        .child(&column)
        .transition_type(gtk::RevealerTransitionType::SlideUp)
        .reveal_child(false)
        .build();

    let bar = Rc::new(Bar {
        revealer: revealer.clone(),
        cover,
        title,
        subtitle,
        clock,
        play,
        slider,
        moving: Cell::new(false),
    });
    let player = shared.player();
    bar.show(&player.showing());
    // The player's listener owns the bar: both live as long as the app.
    let on = bar.clone();
    player.connect(move |showing| on.show(showing));
    let seek_to = Rc::downgrade(&player);
    let on = Rc::downgrade(&bar);
    bar.slider.connect_value_changed(move |slider| {
        let (Some(bar), Some(player)) = (on.upgrade(), seek_to.upgrade()) else {
            return;
        };
        if !bar.moving.get() {
            player.seek(Duration::from_secs_f64(slider.value().max(0.0)));
        }
    });
    install_actions(shared, window);
    revealer
}

fn transport_button(icon: &str, action: &str, label: &str) -> gtk::Button {
    let button = gtk::Button::builder()
        .icon_name(icon)
        .action_name(action)
        .tooltip_text(label)
        .css_classes(["flat"])
        .build();
    button.update_property(&[gtk::accessible::Property::Label(label)]);
    button
}

impl Bar {
    fn show(&self, showing: &Showing) {
        let present = showing.state != PlayState::Stopped;
        self.revealer.set_reveal_child(present);
        if !present {
            return;
        }
        self.title.set_text(&showing.title);
        self.subtitle.set_text(&showing.subtitle);
        let (icon, word) = if showing.state == PlayState::Playing {
            ("media-playback-pause-symbolic", tr("player.pause", "Pause"))
        } else {
            ("media-playback-start-symbolic", tr("player.play", "Play"))
        };
        self.play.set_icon_name(icon);
        self.play.set_tooltip_text(Some(&word));
        self.play
            .update_property(&[gtk::accessible::Property::Label(&word)]);
        match &showing.cover {
            Some(path) => self.cover.set_file(Some(&gio::File::for_path(path))),
            None => self.cover.set_paintable(None::<&gtk::gdk::Paintable>),
        }
        self.slider.set_sensitive(showing.can_skip);
        self.moving.set(true);
        if let Some(duration) = showing.duration {
            self.slider.set_range(0.0, duration.as_secs_f64().max(1.0));
            self.clock.set_text(&format!(
                "{} / {}",
                player::clock(showing.position),
                player::clock(duration)
            ));
        } else {
            self.clock.set_text(&player::clock(showing.position));
        }
        self.slider.set_value(showing.position.as_secs_f64());
        self.slider
            .update_property(&[gtk::accessible::Property::ValueText(&player::clock(
                showing.position,
            ))]);
        self.moving.set(false);
    }
}

/// The transport as window actions of the library window, which the bar's buttons and
/// the shortcuts dialog's Player section name.
type Transport = fn(&Rc<player::Player>);

fn install_actions(shared: &Shared, window: &adw::ApplicationWindow) {
    let actions: [(&str, Transport); 6] = [
        ("play-pause", |player| player.toggle()),
        ("skip-back", |player| player.skip(player::SKIP_BACK)),
        ("skip-forward", |player| player.skip(player::SKIP_FORWARD)),
        ("stop-playback", |player| player.stop()),
        ("next-part", |player| player.next()),
        ("previous-part", |player| player.previous()),
    ];
    for (name, run) in actions {
        let action = gio::SimpleAction::new(name, None);
        let weak = Rc::downgrade(shared);
        action.connect_activate(move |_, _| {
            if let Some(shared) = weak.upgrade() {
                run(&shared.player());
            }
        });
        window.add_action(&action);
    }
}
