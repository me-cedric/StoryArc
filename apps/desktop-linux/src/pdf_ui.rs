//! What a PDF adds to the reader window (task 4.11; `ebook-reader`, PDF rendering): a text
//! pane over the page's text layer, where the reader selects and copies; search in the
//! document behind `win.find`, with Find Next and Find Previous walking the hits; and the
//! outline as a popover that jumps. Each is absent when the document has nothing for it:
//! a scanned PDF offers no text pane and no search, and a PDF with no outline no outline
//! button. The pure part, which hit comes next, is `PdfHits`.

use std::cell::RefCell;
use std::rc::{Rc, Weak};

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::pdf::{PdfMatch, PdfOutlineEntry};

use crate::reader_window::{self, Reader};
use crate::strings::{tr, tr_args};

/// The hits of one search and which of them the reader is on.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PdfHits {
    pages: Vec<u32>,
    current: Option<usize>,
}

impl PdfHits {
    pub fn new(hits: &[PdfMatch]) -> Self {
        Self {
            pages: hits.iter().map(|hit| hit.page).collect(),
            current: None,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.pages.is_empty()
    }

    /// The next hit after the reader's page (or after the current hit), wrapping; its
    /// page, and the words "n of N".
    pub fn next(&mut self, from_page: u32) -> Option<u32> {
        if self.pages.is_empty() {
            return None;
        }
        let index = match self.current {
            Some(current) => (current + 1) % self.pages.len(),
            None => self
                .pages
                .iter()
                .position(|page| *page >= from_page)
                .unwrap_or(0),
        };
        self.current = Some(index);
        Some(self.pages[index])
    }

    pub fn previous(&mut self, from_page: u32) -> Option<u32> {
        if self.pages.is_empty() {
            return None;
        }
        let index = match self.current {
            Some(0) | None if self.pages.iter().all(|page| *page >= from_page) => {
                self.pages.len() - 1
            }
            Some(current) if current > 0 => current - 1,
            Some(_) => self.pages.len() - 1,
            None => self
                .pages
                .iter()
                .rposition(|page| *page < from_page)
                .unwrap_or(0),
        };
        self.current = Some(index);
        Some(self.pages[index])
    }

    /// "n of N", or the count alone before the reader moved to a hit.
    pub fn words(&self) -> String {
        match self.current {
            Some(index) => tr_args(
                "desktop.w4.pdf.hitOfHits______",
                "%@ of %@",
                &[&(index + 1), &self.pages.len()],
            ),
            None => tr_args("desktop.w4.pdf.hits___", "%@ found", &[&self.pages.len()]),
        }
    }
}

/// Holds the reader weakly: the reader's own page-shown hook holds the chrome, so a strong
/// reference back would be a cycle that outlives the window.
struct PdfChrome {
    reader: Weak<Reader>,
    text: gtk::TextView,
    text_pane: gtk::Revealer,
    search_bar: gtk::SearchBar,
    search_entry: gtk::SearchEntry,
    hit_words: gtk::Label,
    hits: RefCell<PdfHits>,
    /// The page whose text the pane shows, so a turn refreshes it once.
    shown: RefCell<Option<u32>>,
}

/// Installs the PDF chrome on a reader whose publication is a PDF.
pub fn install(reader: &Rc<Reader>, header: &adw::HeaderBar) {
    let has_text = reader.publication.has_text_layer();
    let outline = reader.publication.outline();

    let text = gtk::TextView::builder()
        .editable(false)
        .cursor_visible(false)
        .wrap_mode(gtk::WrapMode::WordChar)
        .left_margin(16)
        .right_margin(16)
        .top_margin(12)
        .bottom_margin(12)
        .build();
    text.update_property(&[gtk::accessible::Property::Label(&tr(
        "desktop.w4.pdf.pageText",
        "Page text",
    ))]);
    let text_scroll = gtk::ScrolledWindow::builder()
        .child(&text)
        .width_request(320)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .build();
    let text_pane = gtk::Revealer::builder()
        .child(&text_scroll)
        .transition_type(gtk::RevealerTransitionType::SlideLeft)
        .reveal_child(false)
        .build();

    let search_entry = gtk::SearchEntry::builder()
        .placeholder_text(tr("desktop.w4.pdf.search", "Search in the document"))
        .hexpand(true)
        .build();
    let hit_words = gtk::Label::builder()
        .css_classes(["dim-label", "numeric"])
        .build();
    let search_box = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    search_box.append(&search_entry);
    search_box.append(&hit_words);
    search_box.append(
        &gtk::Button::builder()
            .icon_name("go-up-symbolic")
            .action_name("win.find-previous")
            .tooltip_text(tr("desktop.w4.pdf.findPrevious", "Previous match"))
            .build(),
    );
    search_box.append(
        &gtk::Button::builder()
            .icon_name("go-down-symbolic")
            .action_name("win.find-next")
            .tooltip_text(tr("desktop.w4.pdf.findNext", "Next match"))
            .build(),
    );
    let search_bar = gtk::SearchBar::builder()
        .child(&search_box)
        .show_close_button(true)
        .build();
    search_bar.connect_entry(&search_entry);
    reader.toolbar.add_top_bar(&search_bar);

    let chrome = Rc::new(PdfChrome {
        reader: Rc::downgrade(reader),
        text,
        text_pane,
        search_bar,
        search_entry,
        hit_words,
        hits: RefCell::default(),
        shown: RefCell::default(),
    });

    if has_text {
        install_text_pane(&chrome, reader, header);
        install_search(&chrome, reader);
        if crate::player::speech_available() {
            install_read_aloud(reader, header);
        }
    } else {
        install_no_text_note(reader);
    }
    if !outline.is_empty() {
        install_outline(reader, header, &outline);
    }
}

/// The text pane sits beside the page; a toggle in the header shows it. Its text follows
/// the reader's page, read on a worker.
fn install_text_pane(chrome: &Rc<PdfChrome>, reader: &Rc<Reader>, header: &adw::HeaderBar) {
    let toggle = gtk::ToggleButton::builder()
        .icon_name("format-justify-fill-symbolic")
        .tooltip_text(tr("desktop.w4.pdf.pageText", "Page text"))
        .build();
    header.pack_start(&toggle);
    reader.pane_slot.set_child(Some(&chrome.text_pane));
    let on = Rc::downgrade(chrome);
    toggle.connect_toggled(move |toggle| {
        let Some(chrome) = on.upgrade() else {
            return;
        };
        chrome.text_pane.set_reveal_child(toggle.is_active());
        if toggle.is_active() {
            chrome.show_text();
        }
    });
    // The reader's hook owns the chrome from here on.
    let keep = chrome.clone();
    reader.on_page_shown.borrow_mut().push(Box::new(move || {
        if keep.text_pane.reveals_child() {
            keep.show_text();
        }
    }));
}

impl PdfChrome {
    fn show_text(self: &Rc<Self>) {
        let Some(reader) = self.reader.upgrade() else {
            return;
        };
        let page = reader.page();
        if *self.shown.borrow() == Some(page) {
            return;
        }
        *self.shown.borrow_mut() = Some(page);
        let publication = reader.publication.clone();
        let weak = Rc::downgrade(self);
        glib::MainContext::default().spawn_local(async move {
            let text = gio::spawn_blocking(move || publication.page_text(page as usize))
                .await
                .unwrap_or_default();
            let Some(chrome) = weak.upgrade() else {
                return;
            };
            if *chrome.shown.borrow() != Some(page) {
                return;
            }
            let words = if text.trim().is_empty() {
                tr("desktop.w4.pdf.noTextOnPage", "This page has no text.")
            } else {
                text
            };
            chrome.text.buffer().set_text(&words);
        });
    }

    fn search(self: &Rc<Self>) {
        let query = self.search_entry.text().trim().to_owned();
        if query.is_empty() {
            *self.hits.borrow_mut() = PdfHits::default();
            self.hit_words.set_text("");
            return;
        }
        let Some(reader) = self.reader.upgrade() else {
            return;
        };
        let publication = reader.publication.clone();
        let weak = Rc::downgrade(self);
        let asked = query.clone();
        glib::MainContext::default().spawn_local(async move {
            let hits = gio::spawn_blocking(move || publication.search(&query))
                .await
                .unwrap_or_default();
            let Some(chrome) = weak.upgrade() else {
                return;
            };
            if chrome.search_entry.text().trim() != asked {
                return;
            }
            let hits = PdfHits::new(&hits);
            chrome.hit_words.set_text(&if hits.is_empty() {
                tr("desktop.w4.pdf.noHits", "Not found")
            } else {
                hits.words()
            });
            *chrome.hits.borrow_mut() = hits;
        });
    }

    fn step(self: &Rc<Self>, forward: bool) {
        let Some(reader) = self.reader.upgrade() else {
            return;
        };
        let page = reader.page();
        let target = {
            let mut hits = self.hits.borrow_mut();
            let target = if forward {
                hits.next(page)
            } else {
                hits.previous(page)
            };
            if target.is_some() {
                self.hit_words.set_text(&hits.words());
            }
            target
        };
        if let Some(target) = target {
            reader.jump_to(target as usize);
        }
    }
}

fn install_search(chrome: &Rc<PdfChrome>, reader: &Rc<Reader>) {
    let window = &reader.window;
    let on = Rc::downgrade(chrome);
    reader_window::add(window, reader, "find", move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.search_bar.set_search_mode(true);
            let focused = chrome.search_entry.grab_focus();
            glib::g_message!(
                crate::session::LOG_DOMAIN,
                "pdf search: shown {}, entry focused {focused}",
                chrome.search_bar.is_search_mode()
            );
        }
    });
    let on = Rc::downgrade(chrome);
    reader_window::add(window, reader, "find-next", move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.step(true);
        }
    });
    let on = Rc::downgrade(chrome);
    reader_window::add(window, reader, "find-previous", move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.step(false);
        }
    });
    let on = Rc::downgrade(chrome);
    chrome.search_entry.connect_search_changed(move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.search();
        }
    });
    let on = Rc::downgrade(chrome);
    chrome.search_entry.connect_activate(move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.step(true);
        }
    });
    let on = Rc::downgrade(chrome);
    chrome.search_entry.connect_stop_search(move |_| {
        if let Some(chrome) = on.upgrade() {
            chrome.search_bar.set_search_mode(false);
        }
    });
}

/// Reads the page's text aloud through the one player (`ebook-reader`, Reading aloud).
/// Present only where a speech engine is and the document has text.
fn install_read_aloud(reader: &Rc<Reader>, header: &adw::HeaderBar) {
    let label = tr("desktop.w4.player.readAloud", "Read aloud");
    let button = gtk::Button::builder()
        .icon_name("audio-speakers-symbolic")
        .action_name("win.read-aloud")
        .tooltip_text(&label)
        .build();
    button.update_property(&[gtk::accessible::Property::Label(&label)]);
    header.pack_end(&button);
    let window = reader.window.clone();
    reader_window::add(&window, reader, "read-aloud", |reader| {
        let Some(shared) = reader.shared.upgrade() else {
            return;
        };
        let publication = reader.publication.clone();
        let page = reader.page();
        let title = publication.title.clone();
        let weak = Rc::downgrade(&shared);
        glib::MainContext::default().spawn_local(async move {
            let text = gio::spawn_blocking(move || publication.page_text(page as usize))
                .await
                .unwrap_or_default();
            let Some(shared) = weak.upgrade() else {
                return;
            };
            let sentences = crate::player::sentences_of_markup(&text);
            if let Err(reason) = shared.player().read_aloud(&title, sentences) {
                shared.toast(&reason);
            }
        });
    });
}

/// A scanned PDF: the one sentence the spec asks for, where a reader would look for text.
fn install_no_text_note(reader: &Rc<Reader>) {
    reader.banner.set_title(&tr(
        "desktop.w4.pdf.imagesOnly",
        "This file is images of pages, so there is no text to select or search.",
    ));
    reader.banner.set_revealed(true);
    let banner = reader.banner.clone();
    glib::timeout_add_local_once(std::time::Duration::from_secs(6), move || {
        banner.set_revealed(false);
    });
}

/// The outline as a popover list, each entry at its depth, jumping to its page.
fn install_outline(reader: &Rc<Reader>, header: &adw::HeaderBar, outline: &[PdfOutlineEntry]) {
    let list = gtk::ListBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .css_classes(["navigation-sidebar"])
        .build();
    list.update_property(&[gtk::accessible::Property::Label(&tr(
        "desktop.w4.pdf.outline",
        "Outline",
    ))]);
    let mut pages = Vec::new();
    fill_outline(&list, outline, 0, &mut pages);
    let scroll = gtk::ScrolledWindow::builder()
        .child(&list)
        .max_content_height(480)
        .propagate_natural_height(true)
        .propagate_natural_width(true)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .build();
    let popover = gtk::Popover::builder().child(&scroll).build();
    let button = gtk::MenuButton::builder()
        .icon_name("view-list-bullet-symbolic")
        .tooltip_text(tr("desktop.w4.pdf.outline", "Outline"))
        .popover(&popover)
        .build();
    header.pack_start(&button);
    let weak = Rc::downgrade(reader);
    list.connect_row_activated(move |_, row| {
        let (Some(reader), Some(page)) = (weak.upgrade(), pages.get(row.index().max(0) as usize))
        else {
            return;
        };
        if let Some(page) = page {
            reader.jump_to(*page as usize);
        }
        popover.popdown();
    });
}

fn fill_outline(
    list: &gtk::ListBox,
    entries: &[PdfOutlineEntry],
    depth: usize,
    pages: &mut Vec<Option<u32>>,
) {
    for entry in entries {
        let label = gtk::Label::builder()
            .label(&entry.title)
            .xalign(0.0)
            .wrap(true)
            .margin_start(i32::try_from(depth * 16).unwrap_or(0))
            .margin_top(6)
            .margin_bottom(6)
            .build();
        let row = gtk::ListBoxRow::builder()
            .child(&label)
            .activatable(entry.page.is_some())
            .build();
        row.update_property(&[gtk::accessible::Property::Label(&entry.title)]);
        list.append(&row);
        pages.push(entry.page);
        fill_outline(list, &entry.children, depth + 1, pages);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hits(pages: &[u32]) -> PdfHits {
        PdfHits::new(
            &pages
                .iter()
                .map(|page| PdfMatch {
                    page: *page,
                    rects: Vec::new(),
                })
                .collect::<Vec<_>>(),
        )
    }

    #[test]
    fn next_starts_at_the_readers_page_and_wraps() {
        let mut hits = hits(&[0, 1, 2, 5]);
        assert_eq!(hits.next(2), Some(2));
        assert_eq!(hits.next(2), Some(5));
        assert_eq!(hits.next(2), Some(0));
        assert_eq!(hits.words(), "1 of 4");
    }

    #[test]
    fn previous_walks_back_and_wraps_to_the_last() {
        let mut hits = hits(&[0, 1, 2, 5]);
        assert_eq!(hits.previous(3), Some(2));
        assert_eq!(hits.previous(3), Some(1));
        assert_eq!(hits.previous(3), Some(0));
        assert_eq!(hits.previous(3), Some(5));
        let mut first = hits_at_start();
        assert_eq!(first.previous(0), Some(5));
    }

    fn hits_at_start() -> PdfHits {
        hits(&[0, 1, 2, 5])
    }

    #[test]
    fn no_hits_says_so_and_steps_nowhere() {
        let mut none = hits(&[]);
        assert!(none.is_empty());
        assert_eq!(none.next(0), None);
        assert_eq!(none.previous(0), None);
        assert_eq!(hits(&[3]).words(), "1 found");
    }
}
