//! The end screen (`comic-reader`, Reaching the end): turning past the last page marks
//! the publication finished, writes the place at once, and offers the next issue of the
//! series when the library holds one, the last page again, and the library. The rule
//! for when it shows is `reading/end.rs`.

use std::cell::RefCell;
use std::rc::Rc;
use std::time::Instant;

use adw::prelude::*;
use gtk::glib;

use crate::reader_window::{self, Reader};
use crate::reading::end;
use crate::session::LOG_DOMAIN;
use crate::strings::{tr, tr_args};

/// The end screen's widgets: what it says and the next issue it offers.
pub struct EndScreen {
    pub page: adw::StatusPage,
    next: gtk::Button,
    /// The next issue the button opens, while there is one.
    target: RefCell<Option<storyarc_core::domain::Publication>>,
}

/// Built once per window, filled when it is reached.
pub fn end_screen() -> EndScreen {
    let next = gtk::Button::builder()
        .css_classes(["pill", "suggested-action"])
        .halign(gtk::Align::Center)
        .visible(false)
        .build();
    let back = gtk::Button::builder()
        .label(tr("reader.end.back", "Back to the last page"))
        .css_classes(["pill"])
        .halign(gtk::Align::Center)
        .action_name("win.last-page")
        .build();
    let library = gtk::Button::builder()
        .label(tr("reader.end.library", "Library"))
        .css_classes(["pill"])
        .halign(gtk::Align::Center)
        .action_name("app.library")
        .build();
    let actions = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .halign(gtk::Align::Center)
        .build();
    actions.append(&next);
    actions.append(&back);
    actions.append(&library);
    let page = adw::StatusPage::builder()
        .icon_name("object-select-symbolic")
        .title(tr("reader.end.finished", "Finished"))
        .child(&actions)
        .css_classes(["storyarc-reader"])
        .build();
    EndScreen {
        page,
        next,
        target: RefCell::default(),
    }
}

/// The next issue opens in its own reader, as a cover in the library would open it.
pub fn install(reader: &Rc<Reader>) {
    let weak = Rc::downgrade(reader);
    reader.end.next.connect_clicked(move |_| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        let target = reader.end.target.borrow().clone();
        let (Some(target), Some(shared)) = (target, reader.shared.upgrade()) else {
            return;
        };
        if let Some(path) = target.identity.normalized_path.as_deref()
            && let Err(reason) =
                crate::launch::open_publication(&shared, std::path::Path::new(path))
        {
            shared.toast(&reason);
        }
    });
}

impl Reader {
    /// Turned past the last page: the publication is finished, its last page written at
    /// once, and the end screen offers the next issue of the series when the library
    /// holds one.
    pub(crate) fn show_end(&self) {
        let count = self.pages.get().count;
        {
            let mut progress = self.progress.borrow_mut();
            progress.turned(count.saturating_sub(1), Instant::now());
            if let Err(failure) = progress.flush() {
                glib::g_warning!(LOG_DOMAIN, "{failure}");
            }
        }
        let library = self
            .shared
            .upgrade()
            .map(|shared| shared.sources.publications())
            .unwrap_or_default();
        let next = end::next_in_series(&self.publication.record, &library).cloned();
        match &next {
            Some(next) => {
                self.end.next.set_label(&tr_args(
                    "reader.end.next %s",
                    "Next: %s",
                    &[&next.display_title],
                ));
                self.end.next.set_visible(true);
            }
            None => self.end.next.set_visible(false),
        }
        *self.end.target.borrow_mut() = next;
        self.at_end.set(true);
        self.content.set_visible_child_name("end");
        self.counter.set_label(&reader_window::finished_word());
        self.chrome.borrow_mut().pointer_moved(Instant::now());
        self.apply_chrome();
        if let Some(shared) = self.shared.upgrade() {
            shared.progress_changed();
        }
    }

    /// Back from the end screen to the pages, in whichever form the reader reads them.
    pub(crate) fn leave_end(&self) {
        if self.at_end.replace(false) {
            self.content.set_visible_child_name(self.surface_name());
        }
    }
}
