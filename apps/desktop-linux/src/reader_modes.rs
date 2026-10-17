//! How pages change in a reader window, and moving by chapter (`page-transitions`,
//! Transition modes; `comic-reader`, Page transitions, Continuous scroll, Chapter
//! navigation). A turn slides the page in along the reading direction, or fades it in;
//! with reduced motion the slide becomes the fade, and with animations off nothing moves.
//! Scroll lays every page on one axis and keeps the exact place. The choice applies at
//! once on the same page and is remembered for the series. The rules are
//! `reading/modes.rs` and `reading/chapters.rs`.

use std::rc::Rc;
use std::time::Instant;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::library::LibraryIndex;

use crate::keys::{PageAction, PageModel};
use crate::reader_window::{self, Reader, add};
use crate::reading::chapters;
use crate::reading::modes::{Animation, Axis, Mode, ModeChoice, ScrollPlace};
use crate::{reader_adjust, reader_browser};

/// How long a turn's slide or fade lasts.
const TURN_MILLISECONDS: u32 = 220;
/// Pages more than this many windows away let go of their pixels in Scroll.
const SCROLL_KEEP: f64 = 2.0;

fn reduced_motion() -> bool {
    !gtk::Settings::default().is_some_and(|settings| settings.is_gtk_enable_animations())
}

impl Reader {
    /// The content stack's child for the pages: the page view, or the scroll strip.
    pub(crate) fn surface_name(&self) -> &'static str {
        if self.mode.get().mode == Mode::Scroll {
            "scroll"
        } else {
            "page"
        }
    }

    /// The page slides in from the side reading moves toward, or fades in.
    pub(crate) fn animate_turn(&self, action: PageAction) {
        let animation = self.mode.get().mode.animation(reduced_motion());
        let width = f64::from(self.page_view.width());
        let forward = matches!(action, PageAction::Next | PageAction::Last);
        let from_right = forward != self.right_to_left();
        let view = self.page_view.clone();
        let (from, apply): (f64, Box<dyn Fn(f64)>) = match animation {
            Animation::None => return,
            Animation::Slide if matches!(action, PageAction::Next | PageAction::Previous) => (
                if from_right { width } else { -width },
                Box::new(move |value| view.set_slide(value)),
            ),
            Animation::Slide | Animation::Fade => {
                (0.0, Box::new(move |value| view.set_opacity(value)))
            }
        };
        let to = if from == 0.0 { 1.0 } else { 0.0 };
        apply(from);
        let target = adw::CallbackAnimationTarget::new(apply);
        adw::TimedAnimation::builder()
            .widget(&self.page_view)
            .value_from(from)
            .value_to(to)
            .duration(TURN_MILLISECONDS)
            .easing(adw::Easing::EaseOutCubic)
            .target(&target)
            .build()
            .play();
    }

    /// The reader picked a page turn, an axis or the gap: it applies at once on the same
    /// page and is remembered for the series.
    pub(crate) fn set_mode(self: &Rc<Self>, choice: ModeChoice) {
        if choice.mode.unavailable_reason().is_some() || choice == self.mode.get() {
            return;
        }
        let page = self.page();
        self.keep_scroll_place();
        self.mode.set(choice);
        if let Some(shared) = self.shared.upgrade() {
            shared.choose_mode(&self.publication.record, choice);
        }
        self.enter_mode(page);
        reflect(&self.window, choice);
    }

    /// Shows the pages in the window's mode, on `page`.
    pub(crate) fn enter_mode(self: &Rc<Self>, page: u32) {
        if self.at_end.get() {
            return;
        }
        let choice = self.mode.get();
        if choice.mode != Mode::Scroll {
            self.content.set_visible_child_name("page");
            self.page_view.set_slide(0.0);
            self.page_view.set_opacity(1.0);
            self.land_on(page as usize);
            return;
        }
        self.content.set_visible_child_name("scroll");
        let publication = self.publication.clone();
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let sizes = gio::spawn_blocking(move || publication.page_sizes())
                .await
                .unwrap_or_default();
            let Some(reader) = weak.upgrade() else {
                return;
            };
            let choice = reader.mode.get();
            reader.scroll.build(
                reader.publication.page_count as usize,
                &sizes,
                choice.axis,
                choice.gap,
            );
            let place = reader
                .shared
                .upgrade()
                .and_then(|shared| shared.modes.borrow().place(&reader.publication.id))
                .filter(|place| place.page == page)
                .unwrap_or(ScrollPlace {
                    page,
                    fraction: 0.0,
                });
            // The strip has its size once it is laid out; the place waits for that.
            let weak = Rc::downgrade(&reader);
            glib::timeout_add_local_once(std::time::Duration::from_millis(120), move || {
                if let Some(reader) = weak.upgrade() {
                    reader.scroll.go_to(place);
                    reader.scroll_changed();
                }
            });
        });
    }

    /// The strip moved: the page at the top is the reader's place, the pages near the
    /// window decode, and the far ones let go of their pixels.
    pub(crate) fn scroll_changed(self: &Rc<Self>) {
        if self.mode.get().mode != Mode::Scroll || self.at_end.get() {
            return;
        }
        let place = self.scroll.place();
        let current = self.pages.get();
        if place.page != current.page {
            let next = PageModel::new(place.page, current.count);
            self.pages.set(next);
            self.progress.borrow_mut().turned(next.page, Instant::now());
        }
        self.counter
            .set_label(&reader_window::page_of(place.page, current.count));
        let near = self.scroll.near(1.0);
        for index in &near {
            let decoded = self.decoded.borrow().get(index).cloned();
            match decoded {
                Some(crate::page_view::PageImage::Ready(texture)) => {
                    self.scroll.show_page(*index, &texture);
                }
                Some(_) => {}
                None => self.request(*index),
            }
        }
        let keep = self.scroll.near(SCROLL_KEEP);
        self.decoded
            .borrow_mut()
            .retain(|index, _| keep.contains(index));
        self.scroll.release_except(&keep);
    }

    pub(crate) fn scroll_to_page(self: &Rc<Self>, page: usize) {
        self.scroll.go_to(ScrollPlace {
            page: u32::try_from(page).unwrap_or(0),
            fraction: 0.0,
        });
        self.scroll_changed();
    }

    /// A key or a click in Scroll: the next page's top, the previous one's, the first or
    /// the last. Past the end of the last page, the end screen.
    pub(crate) fn scroll_turn(self: &Rc<Self>, action: PageAction) {
        self.forget_return();
        let place = self.scroll.place();
        let count = self.publication.page_count as usize;
        let page = place.page as usize;
        let target = match action {
            PageAction::Next if page + 1 >= count || self.scroll.at_end() => {
                self.show_end();
                return;
            }
            PageAction::Next => page + 1,
            PageAction::Previous if place.fraction > 0.05 => page,
            PageAction::Previous => page.saturating_sub(1),
            PageAction::First => 0,
            PageAction::Last => count.saturating_sub(1),
        };
        self.scroll_to_page(target);
    }

    /// Keeps where Scroll is, exactly, for the next time the publication opens.
    pub(crate) fn keep_scroll_place(&self) {
        if self.mode.get().mode != Mode::Scroll {
            return;
        }
        if let Some(shared) = self.shared.upgrade() {
            shared
                .modes
                .borrow_mut()
                .keep_place(&self.publication.id, self.scroll.place());
            crate::session::save_modes(&shared.modes.borrow());
        }
    }

    /// The next chapter's first page, or the next issue of the series past the last one
    /// (`comic-reader`, Chapter navigation).
    pub(crate) fn next_chapter(self: &Rc<Self>) {
        match chapters::next_chapter(self.page() as usize, &self.publication.markers) {
            Some(start) => self.jump_to(start),
            None => self.open_neighbour(true),
        }
    }

    pub(crate) fn previous_chapter(self: &Rc<Self>) {
        match chapters::previous_chapter(self.page() as usize, &self.publication.markers) {
            Some(start) => self.jump_to(start),
            None => self.open_neighbour(false),
        }
    }

    /// Opens the next or the previous issue of the series in its own reader.
    fn open_neighbour(&self, next: bool) {
        let Some(shared) = self.shared.upgrade() else {
            return;
        };
        let library = shared.sources.publications();
        let record = &self.publication.record;
        let neighbour = if next {
            LibraryIndex::next(record, &library)
        } else {
            LibraryIndex::previous(record, &library)
        };
        if let Some(path) = neighbour.and_then(|p| p.identity.normalized_path.clone())
            && let Err(reason) = crate::launch::open_publication(&shared, path.as_ref())
        {
            shared.toast(&reason);
        }
    }
}

/// The page turn, axis and gap actions, chapter moves, the page browser and the image
/// adjustments, then the window's own mode.
pub fn install(window: &adw::ApplicationWindow, reader: &Rc<Reader>) {
    let choice = reader.mode.get();
    stateful(
        window,
        reader,
        "page-turn",
        choice.mode.key(),
        |reader, key| {
            if let Some(mode) = Mode::from_key(key) {
                reader.set_mode(ModeChoice {
                    mode,
                    ..reader.mode.get()
                });
            }
        },
    );
    let curl = gio::SimpleAction::new("page-turn-curl", None);
    curl.set_enabled(false);
    window.add_action(&curl);
    let axis = match choice.axis {
        Axis::Vertical => "vertical",
        Axis::Horizontal => "horizontal",
    };
    stateful(window, reader, "scroll-axis", axis, |reader, key| {
        let axis = if key == "horizontal" {
            Axis::Horizontal
        } else {
            Axis::Vertical
        };
        reader.set_mode(ModeChoice {
            axis,
            ..reader.mode.get()
        });
    });
    let gap = gio::SimpleAction::new_stateful("scroll-gap", None, &choice.gap.to_variant());
    let weak = Rc::downgrade(reader);
    gap.connect_activate(move |action, _| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        let on = !action
            .state()
            .and_then(|s| s.get::<bool>())
            .unwrap_or(false);
        reader.set_mode(ModeChoice {
            gap: on,
            ..reader.mode.get()
        });
    });
    window.add_action(&gap);
    add(window, reader, "layout-scroll", |reader| {
        reader.set_mode(ModeChoice {
            mode: Mode::Scroll,
            ..reader.mode.get()
        });
    });
    add(window, reader, "next-chapter", |reader| {
        reader.next_chapter()
    });
    add(window, reader, "previous-chapter", |reader| {
        reader.previous_chapter();
    });
    add(window, reader, "go-to-page", |reader| {
        reader_browser::present(reader);
    });
    add(window, reader, "adjust-image", |reader| {
        reader_adjust::present(reader);
    });
    let weak = Rc::downgrade(reader);
    reader.scroll.on_scrolled(move || {
        if let Some(reader) = weak.upgrade() {
            reader.scroll_changed();
        }
    });
    reflect(window, choice);
    if choice.mode == Mode::Scroll {
        reader.enter_mode(reader.page());
    }
}

fn stateful(
    window: &adw::ApplicationWindow,
    reader: &Rc<Reader>,
    name: &str,
    initial: &str,
    chosen: fn(&Rc<Reader>, &str),
) {
    let action =
        gio::SimpleAction::new_stateful(name, Some(glib::VariantTy::STRING), &initial.to_variant());
    let weak = Rc::downgrade(reader);
    action.connect_activate(move |_, target| {
        if let (Some(reader), Some(key)) = (weak.upgrade(), target.and_then(|t| t.get::<String>()))
        {
            chosen(&reader, &key);
        }
    });
    window.add_action(&action);
}

/// Sets the menu's marks to the window's mode; the axis and the gap only mean something
/// in Scroll, so they are inert in the other modes.
fn reflect(window: &adw::ApplicationWindow, choice: ModeChoice) {
    let action = |name: &str| {
        window
            .lookup_action(name)
            .and_downcast::<gio::SimpleAction>()
    };
    if let Some(turn) = action("page-turn") {
        turn.set_state(&choice.mode.key().to_variant());
    }
    let scrolling = choice.mode == Mode::Scroll;
    if let Some(axis) = action("scroll-axis") {
        axis.set_state(
            &match choice.axis {
                Axis::Vertical => "vertical",
                Axis::Horizontal => "horizontal",
            }
            .to_variant(),
        );
        axis.set_enabled(scrolling);
    }
    if let Some(gap) = action("scroll-gap") {
        gap.set_state(&choice.gap.to_variant());
        gap.set_enabled(scrolling);
    }
}
