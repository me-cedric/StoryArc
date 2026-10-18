//! The full player (`audio-playback`, *The full player*; `ebook-reader`, *The same controls as
//! a narrated book*): the cover or the coverless artwork, the publication and the chapter, the
//! position with its slider, skip back, play or pause, skip forward, the chapter list, the
//! sleep timer and the speed. It shows the one player's session, so opening it never restarts,
//! reloads or moves the audio, and closing it leaves the audio playing. Space plays or pauses
//! and the arrows skip. One window for the app.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use adw::prelude::*;
use gtk::{gio, glib};

use crate::app::Shared;
use crate::audio::PlayState;
use crate::playback::{self, SleepTimer};
use crate::player::{self, Player, Showing};
use crate::strings::{tr, tr_args};

thread_local! {
    /// The window, and the widgets it shows, which live as long as it is open.
    static OPEN: RefCell<Option<(adw::ApplicationWindow, Rc<Full>)>> = const { RefCell::new(None) };
}

struct Full {
    cover: gtk::Picture,
    coverless: gtk::Box,
    format: gtk::Label,
    kind: gtk::Image,
    title: gtk::Label,
    chapter: gtk::Label,
    slider: gtk::Scale,
    elapsed: gtk::Label,
    total: gtk::Label,
    back: gtk::Button,
    play: gtk::Button,
    forward: gtk::Button,
    chapters: gtk::MenuButton,
    sleep: gtk::MenuButton,
    speed: gtk::MenuButton,
    moving: Cell<bool>,
}

/// The full player, when it is open.
pub fn window() -> Option<adw::ApplicationWindow> {
    OPEN.with(|open| open.borrow().as_ref().map(|(window, _)| window.clone()))
}

/// Opens the full player, or brings it forward.
pub fn present(shared: &Shared) {
    if let Some(window) = window() {
        window.present();
        return;
    }
    let player = shared.player();
    let full = Rc::new(build());
    let window = adw::ApplicationWindow::builder()
        .application(&shared.application())
        .title(tr("player.nowPlaying", "Now playing"))
        .default_width(420)
        .default_height(660)
        .content(&content(&full))
        .build();
    wire(&full, &player);
    full.show(&player.showing());
    let weak = Rc::downgrade(&full);
    player.connect(move |showing| {
        if let Some(full) = weak.upgrade() {
            full.show(showing);
        }
    });
    let keys = gtk::EventControllerKey::new();
    let on_player = Rc::downgrade(&player);
    keys.connect_key_pressed(move |_, key, _, _| {
        let Some(player) = on_player.upgrade() else {
            return glib::Propagation::Proceed;
        };
        use gtk::gdk::Key;
        match key {
            Key::space => player.toggle(),
            Key::Left => player.skip_by(false),
            Key::Right => player.skip_by(true),
            _ => return glib::Propagation::Proceed,
        }
        glib::Propagation::Stop
    });
    window.add_controller(keys);
    // The lists as window actions, for the keyboard and the walks.
    for (name, menu) in [("chapters", &full.chapters), ("sleep", &full.sleep), ("speed", &full.speed)] {
        let action = gio::SimpleAction::new(name, None);
        let menu = menu.clone();
        action.connect_activate(move |_, _| menu.popup());
        window.add_action(&action);
    }
    window.connect_close_request(|_| {
        OPEN.with(|open| open.borrow_mut().take());
        glib::Propagation::Proceed
    });
    OPEN.with(|open| *open.borrow_mut() = Some((window.clone(), full.clone())));
    window.present();
}

fn round_button(icon: &str, label: &str) -> gtk::Button {
    let button = gtk::Button::builder()
        .icon_name(icon)
        .tooltip_text(label)
        .css_classes(["circular", "flat"])
        .valign(gtk::Align::Center)
        .build();
    button.update_property(&[gtk::accessible::Property::Label(label)]);
    button
}

fn build() -> Full {
    let cover = gtk::Picture::builder()
        .content_fit(gtk::ContentFit::Contain)
        .width_request(220)
        .height_request(220)
        .css_classes(["card"])
        .build();
    cover.set_accessible_role(gtk::AccessibleRole::Presentation);
    let kind = gtk::Image::builder().pixel_size(96).build();
    let format = gtk::Label::builder().css_classes(["title-3"]).build();
    let coverless = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .width_request(220)
        .height_request(220)
        .valign(gtk::Align::Center)
        .halign(gtk::Align::Center)
        .css_classes(["card"])
        .build();
    let inner = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .valign(gtk::Align::Center)
        .vexpand(true)
        .build();
    inner.append(&kind);
    inner.append(&format);
    coverless.append(&inner);
    coverless.set_accessible_role(gtk::AccessibleRole::Presentation);
    let slider = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 1.0, 1.0);
    slider.set_draw_value(false);
    slider.set_hexpand(true);
    slider.update_property(&[gtk::accessible::Property::Label(&tr("player.position", "Position"))]);
    let menu = |icon: &str, label: &str| {
        let button = gtk::MenuButton::builder()
            .icon_name(icon)
            .tooltip_text(label)
            .popover(&gtk::Popover::new())
            .build();
        button.update_property(&[gtk::accessible::Property::Label(label)]);
        button
    };
    let play = round_button("media-playback-start-symbolic", &tr("player.play", "Play"));
    play.remove_css_class("flat");
    play.add_css_class("suggested-action");
    play.set_size_request(64, 64);
    Full {
        cover,
        coverless,
        format,
        kind,
        title: gtk::Label::builder()
            .wrap(true)
            .justify(gtk::Justification::Center)
            .css_classes(["title-2"])
            .build(),
        chapter: gtk::Label::builder()
            .wrap(true)
            .justify(gtk::Justification::Center)
            .css_classes(["dim-label"])
            .build(),
        slider,
        elapsed: gtk::Label::builder().css_classes(["numeric", "caption", "dim-label"]).xalign(0.0).hexpand(true).build(),
        total: gtk::Label::builder().css_classes(["numeric", "caption", "dim-label"]).xalign(1.0).build(),
        back: round_button("media-seek-backward-symbolic", &tr_args("player.skip.back %s", "%s back", &[&"15 s"])),
        play,
        forward: round_button("media-seek-forward-symbolic", &tr_args("player.skip.forward %s", "%s forward", &[&"30 s"])),
        chapters: menu("view-list-symbolic", &tr("player.chapters", "Chapters")),
        sleep: menu("weather-clear-night-symbolic", &tr("player.sleep", "Sleep timer")),
        speed: menu("power-profile-performance-symbolic", &tr("player.speed", "Speed")),
        moving: Cell::new(false),
    }
}

fn content(full: &Full) -> adw::ToolbarView {
    let artwork = gtk::Overlay::builder().halign(gtk::Align::Center).child(&full.cover).build();
    artwork.add_overlay(&full.coverless);
    let clocks = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    clocks.append(&full.elapsed);
    clocks.append(&full.total);
    let transport = gtk::Box::builder().spacing(28).halign(gtk::Align::Center).build();
    transport.append(&full.back);
    transport.append(&full.play);
    transport.append(&full.forward);
    let settings = gtk::Box::builder().spacing(16).halign(gtk::Align::Center).build();
    settings.append(&full.chapters);
    settings.append(&full.sleep);
    settings.append(&full.speed);
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(32)
        .margin_end(32)
        .build();
    column.append(&artwork);
    column.append(&full.title);
    column.append(&full.chapter);
    column.append(&full.slider);
    column.append(&clocks);
    column.append(&transport);
    column.append(&settings);
    let view = adw::ToolbarView::new();
    view.add_top_bar(&adw::HeaderBar::new());
    view.set_content(Some(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .child(&column)
            .build(),
    ));
    view
}

fn wire(full: &Rc<Full>, player: &Rc<Player>) {
    for (button, forward) in [(&full.back, false), (&full.forward, true)] {
        let weak = Rc::downgrade(player);
        button.connect_clicked(move |_| {
            if let Some(player) = weak.upgrade() {
                player.skip_by(forward);
            }
        });
    }
    let weak = Rc::downgrade(player);
    full.play.connect_clicked(move |_| {
        if let Some(player) = weak.upgrade() {
            player.toggle();
        }
    });
    let (weak, on) = (Rc::downgrade(player), Rc::downgrade(full));
    full.slider.connect_value_changed(move |slider| {
        let (Some(player), Some(full)) = (weak.upgrade(), on.upgrade()) else {
            return;
        };
        if !full.moving.get() {
            player.seek(Duration::from_secs_f64(slider.value().max(0.0)));
        }
    });
    // The lists are built when they open, from what the player holds then.
    let weak = Rc::downgrade(player);
    if let Some(popover) = full.chapters.popover() {
        popover.connect_show(move |popover| {
            if let Some(player) = weak.upgrade() {
                popover.set_child(Some(&chapter_list(&player, popover)));
            }
        });
    }
    let weak = Rc::downgrade(player);
    if let Some(popover) = full.sleep.popover() {
        popover.connect_show(move |popover| {
            if let Some(player) = weak.upgrade() {
                popover.set_child(Some(&sleep_list(&player, popover)));
            }
        });
    }
    let weak = Rc::downgrade(player);
    if let Some(popover) = full.speed.popover() {
        popover.connect_show(move |popover| {
            if let Some(player) = weak.upgrade() {
                popover.set_child(Some(&speed_list(&player, popover)));
            }
        });
    }
}

/// The chapter list: each chapter as one control that states its name, its length or what is
/// left of it, and its mark (`audio-playback`, *Chapters*).
pub fn chapter_rows(showing: &Showing) -> Vec<String> {
    let current = showing.chapter.unwrap_or(0);
    showing
        .chapters
        .iter()
        .enumerate()
        .map(|(index, chapter)| {
            let mark = playback::mark(&showing.chapters, index, current, showing.position, false);
            playback::chapter_row(chapter, index, mark)
        })
        .collect()
}

fn chapter_list(player: &Rc<Player>, popover: &gtk::Popover) -> gtk::Widget {
    let showing = player.showing();
    let list = gtk::ListBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .css_classes(["boxed-list"])
        .build();
    for (index, row) in chapter_rows(&showing).into_iter().enumerate() {
        let item = adw::ActionRow::builder()
            .title(glib::markup_escape_text(&row))
            .activatable(true)
            .build();
        let (weak, popover) = (Rc::downgrade(player), popover.clone());
        item.connect_activated(move |_| {
            if let Some(player) = weak.upgrade() {
                player.play_chapter(index);
            }
            popover.popdown();
        });
        list.append(&item);
    }
    if showing.chapters.is_empty() {
        let length = showing.duration.map(player::clock).unwrap_or_default();
        return gtk::Label::builder()
            .label(length)
            .margin_top(12)
            .margin_bottom(12)
            .build()
            .upcast();
    }
    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .propagate_natural_height(true)
        .propagate_natural_width(true)
        .max_content_height(420)
        .min_content_width(320)
        .child(&list)
        .build()
        .upcast()
}

fn choice_list(choices: Vec<(String, Rc<dyn Fn()>)>, popover: &gtk::Popover) -> gtk::Widget {
    let column = gtk::Box::new(gtk::Orientation::Vertical, 2);
    for (label, run) in choices {
        let button = gtk::Button::builder().label(label).css_classes(["flat"]).build();
        let popover = popover.clone();
        button.connect_clicked(move |_| {
            run();
            popover.popdown();
        });
        column.append(&button);
    }
    column.upcast()
}

fn sleep_list(player: &Rc<Player>, popover: &gtk::Popover) -> gtk::Widget {
    let set = |timer: Option<SleepTimer>| -> Rc<dyn Fn()> {
        let weak = Rc::downgrade(player);
        Rc::new(move || {
            if let Some(player) = weak.upgrade() {
                player.set_sleep(timer);
            }
        })
    };
    let mut choices = vec![(tr("player.sleep.off", "Off"), set(None))];
    for minutes in playback::SLEEP_MINUTES {
        choices.push((
            tr_args("desktop.w4.player.sleepMinutes", "%@ minutes", &[&minutes]),
            set(Some(SleepTimer::After(Duration::from_secs(minutes * 60)))),
        ));
    }
    if player.can_sleep_at_end_of_chapter() {
        choices.push((
            tr("player.sleep.endOfChapter", "End of chapter"),
            set(Some(SleepTimer::EndOfChapter)),
        ));
    }
    choice_list(choices, popover)
}

fn speed_list(player: &Rc<Player>, popover: &gtk::Popover) -> gtk::Widget {
    let choices = playback::SPEEDS
        .iter()
        .map(|rate| {
            let weak = Rc::downgrade(player);
            let rate = *rate;
            let run: Rc<dyn Fn()> = Rc::new(move || {
                if let Some(player) = weak.upgrade() {
                    player.set_speed(rate);
                }
            });
            (playback::speed_text(rate), run)
        })
        .collect();
    choice_list(choices, popover)
}

/// What the sleep timer's control says: its name, or what is left.
pub fn sleep_label(showing: &Showing) -> String {
    match showing.sleep {
        None => tr("player.sleep", "Sleep timer"),
        Some(sleep) if sleep.timer == SleepTimer::EndOfChapter => {
            tr("player.sleep.endOfChapter", "End of chapter")
        }
        Some(sleep) => tr_args("player.sleep.remaining %s", "%s left", &[&player::clock(sleep.remaining)]),
    }
}

/// What the skip controls say: the interval for a narrator, a sentence for a voice.
pub fn skip_labels(voice: bool) -> (String, String) {
    if voice {
        (
            tr("player.skip.sentence.previous", "Previous sentence"),
            tr("player.skip.sentence.next", "Next sentence"),
        )
    } else {
        (
            tr_args("player.skip.back %s", "%s back", &[&"15 s"]),
            tr_args("player.skip.forward %s", "%s forward", &[&"30 s"]),
        )
    }
}

impl Full {
    fn show(&self, showing: &Showing) {
        self.title.set_text(&showing.title);
        self.chapter.set_text(&showing.subtitle);
        self.chapter.set_visible(!showing.subtitle.is_empty());
        match &showing.cover {
            Some(path) => {
                self.cover.set_file(Some(&gio::File::for_path(path)));
                self.coverless.set_visible(false);
            }
            None => {
                self.cover.set_paintable(None::<&gtk::gdk::Paintable>);
                self.coverless.set_visible(true);
            }
        }
        self.kind.set_icon_name(Some(if showing.voice {
            "x-office-document-symbolic"
        } else {
            "audio-headphones-symbolic"
        }));
        self.format.set_text(&showing.format);
        let playing = showing.state == PlayState::Playing;
        let word = if playing { tr("player.pause", "Pause") } else { tr("player.play", "Play") };
        self.play.set_icon_name(if playing {
            "media-playback-pause-symbolic"
        } else {
            "media-playback-start-symbolic"
        });
        self.play.set_tooltip_text(Some(&word));
        self.play.update_property(&[gtk::accessible::Property::Label(&word)]);
        let (back, forward) = skip_labels(showing.voice);
        for (button, label) in [(&self.back, back), (&self.forward, forward)] {
            button.set_tooltip_text(Some(&label));
            button.update_property(&[gtk::accessible::Property::Label(&label)]);
        }
        // A voice has no clock: the slider and the times are absent rather than dead.
        let timed = !showing.voice;
        self.slider.set_visible(timed);
        self.elapsed.set_visible(timed);
        self.total.set_visible(timed);
        self.moving.set(true);
        if let Some(duration) = showing.duration {
            self.slider.set_range(0.0, duration.as_secs_f64().max(1.0));
            self.total.set_text(&player::clock(duration));
        }
        self.slider.set_value(showing.position.as_secs_f64());
        self.moving.set(false);
        self.elapsed.set_text(&player::clock(showing.position));
        self.slider
            .update_property(&[gtk::accessible::Property::ValueText(&player::clock(showing.position))]);
        self.chapters.set_visible(!showing.chapters.is_empty());
        let sleep = sleep_label(showing);
        self.sleep.set_label(&sleep);
        self.sleep.update_property(&[gtk::accessible::Property::Label(&sleep)]);
        let speed = playback::speed_text(showing.speed);
        self.speed.set_label(&speed);
        self.speed.update_property(&[gtk::accessible::Property::Label(&format!(
            "{}, {speed}",
            tr("player.speed", "Speed")
        ))]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::playback::{Chapter, Countdown};

    /// `audio-playback`, *Chapters* and *Sleep timer*, and `ebook-reader`, sentence skip: the
    /// rows the full player lists, the timer's words, and the skip words for each source.
    #[test]
    fn the_full_player_states_its_chapters_timer_and_skips() {
        let showing = Showing {
            chapters: vec![
                Chapter { title: Some("One".into()), part: 0, start: Duration::ZERO, end: Some(Duration::from_secs(60)) },
                Chapter { title: Some("Two".into()), part: 0, start: Duration::from_secs(60), end: Some(Duration::from_secs(150)) },
            ],
            chapter: Some(1),
            position: Duration::from_secs(90),
            sleep: Countdown::of(SleepTimer::After(Duration::from_secs(300)), None),
            ..Showing::default()
        };
        assert_eq!(chapter_rows(&showing), ["One · 1:00 · Finished", "Two · 1:00 left · In progress"]);
        assert_eq!(sleep_label(&showing), "5:00 left");
        assert_eq!(sleep_label(&Showing::default()), "Sleep timer");
        assert_eq!(skip_labels(true).1, "Next sentence");
        assert_eq!(skip_labels(false).0, "15 s back");
    }
}
