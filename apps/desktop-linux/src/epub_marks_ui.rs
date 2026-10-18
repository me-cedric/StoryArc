//! The EPUB window's ways around the book (`ebook-reader`, *Navigation and annotation*): the
//! contents, the bookmark at the page, the list of bookmarks and highlights, search in the book
//! with its hits in context, the bar a selection raises, the note on a highlight, and a
//! footnote shown where the reader is. The records and messages are `epub_marks.rs`; the moves
//! go through `EpubReader::go`, which keeps the way back.

use std::cell::OnceCell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, glib};

use crate::epub_marks::{COLOURS, start_of};
use crate::epub_window::EpubReader;
use crate::strings::{tr, tr_args};

pub(crate) fn colour_name(colour: &str) -> String {
    match colour {
        "green" => tr("annotations.colour.green", "Green"),
        "blue" => tr("annotations.colour.blue", "Blue"),
        "pink" => tr("annotations.colour.pink", "Pink"),
        "purple" => tr("annotations.colour.purple", "Purple"),
        _ => tr("annotations.colour.yellow", "Yellow"),
    }
}

/// One class a highlight colour, added to the display once.
pub(crate) fn colour_class(colour: &str) -> String {
    thread_local! {
        static PROVIDER: OnceCell<gtk::CssProvider> = const { OnceCell::new() };
    }
    PROVIDER.with(|cell| {
        cell.get_or_init(|| {
            let css: String = COLOURS
                .iter()
                .map(|colour| {
                    format!(".storyarc-highlight-{colour} {{ background: {colour}; min-width: 18px; min-height: 18px; border-radius: 9999px; }}\n")
                })
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
    format!("storyarc-highlight-{colour}")
}

fn labelled_menu(icon: &str, title: &str) -> (gtk::MenuButton, gtk::Popover) {
    let popover = gtk::Popover::new();
    let menu = gtk::MenuButton::builder()
        .icon_name(icon)
        .tooltip_text(title)
        .popover(&popover)
        .build();
    menu.update_property(&[gtk::accessible::Property::Label(title)]);
    (menu, popover)
}

/// A list of rows, each a place to go; the popover closes on the way.
fn place_list() -> gtk::ListBox {
    gtk::ListBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .css_classes(["boxed-list"])
        .build()
}

fn place_row(title: &str, subtitle: Option<&str>) -> adw::ActionRow {
    let row = adw::ActionRow::builder()
        .title(glib::markup_escape_text(title))
        .activatable(true)
        .build();
    if let Some(subtitle) = subtitle.filter(|s| !s.is_empty()) {
        row.set_subtitle(&glib::markup_escape_text(subtitle));
    }
    row
}

fn scrolled(child: &impl IsA<gtk::Widget>) -> gtk::ScrolledWindow {
    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .propagate_natural_height(true)
        .propagate_natural_width(true)
        .max_content_height(480)
        .min_content_width(320)
        .child(child)
        .build()
}

fn empty(text: &str) -> gtk::Label {
    gtk::Label::builder()
        .label(text)
        .wrap(true)
        .max_width_chars(36)
        .css_classes(["dim-label"])
        .margin_top(12)
        .margin_bottom(12)
        .build()
}

/// The publication's contents (`ebook-reader`, *Table of contents*, *Moving somewhere else*).
/// A book that declares none says so, and the progress line still says where the reader is.
pub fn contents_button(reader: &Rc<EpubReader>) -> gtk::MenuButton {
    let (menu, popover) = labelled_menu("view-list-symbolic", &tr("contents.title", "Contents"));
    let toc = reader.contents();
    if toc.is_empty() {
        popover.set_child(Some(&empty(&tr(
            "contents.empty",
            "This book declares no table of contents.",
        ))));
        return menu;
    }
    let list = place_list();
    for (title, href, media_type) in toc {
        let title = title.unwrap_or_else(|| tr("contents.untitled", "Untitled section"));
        let row = place_row(&title, None);
        let (weak, popover) = (Rc::downgrade(reader), popover.clone());
        row.connect_activated(move |_| {
            if let Some(reader) = weak.upgrade() {
                reader.go(&start_of(&href, media_type.as_deref()));
            }
            popover.popdown();
        });
        list.append(&row);
    }
    popover.set_child(Some(&scrolled(&list)));
    menu
}

/// The bookmark at the page: it adds one, or removes the one there (`ebook-reader`, *Bookmarks*).
pub fn bookmark_button(reader: &Rc<EpubReader>) -> gtk::Button {
    let button = gtk::Button::builder()
        .icon_name("bookmark-new-symbolic")
        .sensitive(false)
        .build();
    let weak = Rc::downgrade(reader);
    button.connect_clicked(move |_| {
        if let Some(reader) = weak.upgrade() {
            reader.toggle_bookmark();
        }
    });
    show_bookmark(&button, false);
    button
}

/// The bookmark button as it reads at the page: filled and *Remove bookmark* when one is there.
pub fn show_bookmark(button: &gtk::Button, marked: bool) {
    let (icon, title) = if marked {
        ("user-bookmarks-symbolic", tr("bookmarks.remove", "Remove bookmark"))
    } else {
        ("bookmark-new-symbolic", tr("bookmarks.add", "Bookmark this page"))
    };
    button.set_icon_name(icon);
    button.set_tooltip_text(Some(&title));
    button.update_property(&[gtk::accessible::Property::Label(&title)]);
}

/// The bookmarks and the highlights, each a way to its place. Built when it opens, so it shows
/// what is kept now.
pub fn marks_button(reader: &Rc<EpubReader>) -> gtk::MenuButton {
    let (menu, popover) = labelled_menu("emblem-documents-symbolic", &tr("bookmarks.title", "Bookmarks"));
    let weak = Rc::downgrade(reader);
    popover.connect_show(move |popover| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        let column = gtk::Box::builder()
            .orientation(gtk::Orientation::Vertical)
            .spacing(12)
            .margin_top(6)
            .margin_bottom(6)
            .width_request(320)
            .build();
        let marks = reader.marks.borrow().clone();
        column.append(&gtk::Label::builder().label(tr("bookmarks.title", "Bookmarks")).css_classes(["heading"]).xalign(0.0).build());
        if marks.bookmarks.is_empty() {
            column.append(&empty(&tr("reader.bookmark.empty", "No pages bookmarked yet.")));
        } else {
            let list = place_list();
            for mark in &marks.bookmarks {
                let title = if mark.place.chapter.is_empty() {
                    tr("bookmarks.unnamed", "Unnamed chapter")
                } else {
                    mark.place.chapter.clone()
                };
                let row = place_row(&title, None);
                let (weak, popover, locator) = (Rc::downgrade(&reader), popover.clone(), mark.place.locator.clone());
                row.connect_activated(move |_| {
                    if let Some(reader) = weak.upgrade() {
                        reader.go(&locator);
                    }
                    popover.popdown();
                });
                list.append(&row);
            }
            column.append(&list);
        }
        column.append(&gtk::Label::builder().label(tr("annotations.title", "Notes")).css_classes(["heading"]).xalign(0.0).build());
        if marks.highlights.is_empty() {
            column.append(&empty(&tr(
                "annotations.empty",
                "Nothing marked yet. Select a word or a passage and a menu offers a colour.",
            )));
        } else {
            let list = place_list();
            for highlight in &marks.highlights {
                let row = place_row(&highlight.text, Some(&highlight.note));
                let dot = gtk::Box::builder().valign(gtk::Align::Center).css_classes([colour_class(&highlight.colour)]).build();
                dot.update_property(&[gtk::accessible::Property::Label(&colour_name(&highlight.colour))]);
                row.add_prefix(&dot);
                let (weak, popover, locator) = (Rc::downgrade(&reader), popover.clone(), highlight.place.locator.clone());
                row.connect_activated(move |_| {
                    if let Some(reader) = weak.upgrade() {
                        reader.go(&locator);
                    }
                    popover.popdown();
                });
                list.append(&row);
            }
            column.append(&list);
        }
        popover.set_child(Some(&scrolled(&column)));
    });
    menu
}

/// What a search shows while it runs and after: the status line and the hits.
pub struct SearchView {
    pub status: gtk::Label,
    pub hits: gtk::ListBox,
    pub popover: gtk::Popover,
}

/// Search in the book (`ebook-reader`, *Search within a publication*): the hits come chapter by
/// chapter, each in context, and choosing one goes there with a way back.
pub fn search_button(reader: &Rc<EpubReader>) -> (gtk::MenuButton, SearchView) {
    let (menu, popover) = labelled_menu("system-search-symbolic", &tr("search.field", "Search in this book"));
    let entry = gtk::SearchEntry::builder()
        .placeholder_text(tr("search.field", "Search in this book"))
        .build();
    entry.update_property(&[gtk::accessible::Property::Label(&tr("search.field", "Search in this book"))]);
    let status = gtk::Label::builder().wrap(true).xalign(0.0).css_classes(["dim-label"]).visible(false).build();
    let hits = place_list();
    hits.set_visible(false);
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(8)
        .build();
    column.append(&entry);
    column.append(&status);
    column.append(&scrolled(&hits));
    popover.set_child(Some(&column));
    popover.set_default_widget(Some(&entry));
    // Escape in the field closes the search, as it closes every other popover.
    let on_popover = popover.clone();
    entry.connect_stop_search(move |_| on_popover.popdown());
    let weak = Rc::downgrade(reader);
    entry.connect_activate(move |entry| {
        if let Some(reader) = weak.upgrade() {
            reader.search(entry.text().as_str());
        }
    });
    (menu, SearchView { status, hits, popover })
}

impl SearchView {
    pub fn start(&self, query: &str) {
        while let Some(row) = self.hits.first_child() {
            self.hits.remove(&row);
        }
        self.hits.set_visible(false);
        self.status.set_visible(!query.is_empty());
        self.status.set_text(&tr("search.running", "Searching…"));
    }

    pub fn add(&self, reader: &Rc<EpubReader>, hits: Vec<crate::epub_marks::Hit>) {
        for hit in hits {
            let text = format!("{}{}{}", hit.before, hit.matched, hit.after);
            let row = place_row(hit.chapter.as_deref().unwrap_or(""), None);
            row.set_title(&format!(
                "{}<b>{}</b>{}",
                glib::markup_escape_text(&hit.before),
                glib::markup_escape_text(&hit.matched),
                glib::markup_escape_text(&hit.after)
            ));
            row.set_title_lines(2);
            if let Some(chapter) = &hit.chapter {
                row.set_subtitle(&glib::markup_escape_text(chapter));
            }
            row.upcast_ref::<gtk::Widget>().update_property(&[gtk::accessible::Property::Label(&text)]);
            let (weak, popover) = (Rc::downgrade(reader), self.popover.clone());
            row.connect_activated(move |_| {
                if let Some(reader) = weak.upgrade() {
                    reader.go(&hit.locator);
                }
                popover.popdown();
            });
            self.hits.append(&row);
            self.hits.set_visible(true);
        }
    }

    pub fn done(&self, query: &str) {
        if self.hits.first_child().is_some() {
            self.status.set_visible(false);
        } else {
            self.status.set_text(&tr_args("search.none %s", "Nothing found for “%s”.", &[&query]));
        }
    }
}

/// The bar a selection raises: keep it as a highlight in a colour, or let it go.
pub fn selection_bar(reader: &Rc<EpubReader>) -> gtk::Revealer {
    let bar = gtk::Box::builder()
        .spacing(10)
        .halign(gtk::Align::Center)
        .margin_top(6)
        .margin_bottom(6)
        .build();
    bar.append(&gtk::Label::new(Some(&tr("desktop.w4.epub.highlight", "Highlight"))));
    let revealer = gtk::Revealer::builder().child(&bar).reveal_child(false).build();
    for colour in COLOURS {
        let name = colour_name(colour);
        let swatch = gtk::Button::builder()
            .child(&gtk::Box::builder().css_classes([colour_class(colour)]).build())
            .tooltip_text(&name)
            .css_classes(["flat", "circular"])
            .build();
        swatch.update_property(&[gtk::accessible::Property::Label(&name)]);
        let weak = Rc::downgrade(reader);
        swatch.connect_clicked(move |_| {
            if let Some(reader) = weak.upgrade() {
                reader.highlight_selection(colour);
            }
        });
        bar.append(&swatch);
    }
    let cancel = gtk::Button::with_label(&tr("annotations.cancel", "Cancel"));
    let on_revealer = revealer.clone();
    cancel.connect_clicked(move |_| on_revealer.set_reveal_child(false));
    bar.append(&cancel);
    revealer
}

/// The note on a highlight the reader clicked: write it, or remove the highlight.
pub fn note_dialog(reader: &Rc<EpubReader>, id: &str) {
    let Some(highlight) = reader.marks.borrow().highlights.iter().find(|h| h.id == id).cloned() else {
        return;
    };
    let dialog = adw::AlertDialog::builder()
        .heading(tr("annotations.note", "Note"))
        .body(&highlight.text)
        .build();
    let text = gtk::TextView::builder()
        .wrap_mode(gtk::WrapMode::WordChar)
        .height_request(96)
        .css_classes(["card"])
        .build();
    text.buffer().set_text(&highlight.note);
    text.update_property(&[gtk::accessible::Property::Label(&tr("annotations.note", "Note"))]);
    dialog.set_extra_child(Some(&text));
    dialog.add_response("remove", &tr("annotations.remove", "Remove"));
    dialog.set_response_appearance("remove", adw::ResponseAppearance::Destructive);
    dialog.add_response("cancel", &tr("annotations.cancel", "Cancel"));
    dialog.add_response("save", &tr("annotations.save", "Save"));
    dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("save"));
    dialog.set_close_response("cancel");
    let (weak, id) = (Rc::downgrade(reader), highlight.id);
    dialog.connect_response(None, move |_, response| {
        let Some(reader) = weak.upgrade() else {
            return;
        };
        let buffer = text.buffer();
        let note = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false);
        match response {
            "save" => reader.edit_marks(&|marks| marks.set_note(&id, note.as_str())),
            "remove" => reader.edit_marks(&|marks| marks.remove_highlight(&id)),
            _ => {}
        }
    });
    dialog.present(Some(&reader.window));
}

/// A footnote, shown in place as a popover over the page rather than by leaving it
/// (`ebook-reader`, *Following an internal link*).
pub fn footnote(reader: &EpubReader, text: &str) {
    let Some(page) = reader.web_view() else {
        return;
    };
    let label = gtk::Label::builder()
        .label(text)
        .wrap(true)
        .max_width_chars(48)
        .selectable(true)
        .margin_top(6)
        .margin_bottom(6)
        .margin_start(6)
        .margin_end(6)
        .build();
    let popover = gtk::Popover::builder().child(&label).build();
    popover.set_parent(&page);
    popover.connect_closed(|popover| {
        let popover = popover.clone();
        glib::idle_add_local_once(move || popover.unparent());
    });
    popover.popup();
}
