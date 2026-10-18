//! A selection in a text PDF's page text (`ebook-reader`, *Text-based PDF*): the same four
//! things a reflowable selection offers — a highlight in five colours, a note, copy, and search
//! in the document — kept as the EPUB's own highlight record (`epub_marks::Marks`, under the
//! publication's key) and drawn in the page text whenever that page shows. The page itself is an
//! image, so the text pane beside it is where the reader selects.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use adw::prelude::*;
use gtk::gdk;
use serde_json::json;

use crate::epub_marks::{COLOURS, Marks, Place};
use crate::epub_marks_ui::{colour_class, colour_name};
use crate::strings::{tr, tr_args};

/// A selection on a page as the record keeps it: the page as its resource, the selected text,
/// and where in the page's text it starts.
pub fn place(page: u32, count: u32, text: &str, start: usize) -> Place {
    let resource = format!("page/{}", page + 1);
    let progression = if count > 1 {
        f64::from(page) / f64::from(count - 1)
    } else {
        0.0
    };
    Place {
        locator: json!({
            "href": resource,
            "type": "application/pdf",
            "locations": { "position": page + 1, "progression": progression },
            "text": { "highlight": text },
            "start": start,
        })
        .to_string(),
        resource,
        progression,
        chapter: tr_args("reader.pageLabel %d %d", "Page %1$d of %2$d", &[&(page + 1), &count]),
    }
}

/// The highlights of one page as character ranges in its text, with their colours: at the
/// offset the record kept when the text is still there, else where the text first appears.
pub fn ranges(marks: &Marks, page: u32, text: &str) -> Vec<(usize, usize, String)> {
    let resource = format!("page/{}", page + 1);
    let chars: Vec<char> = text.chars().collect();
    marks
        .highlights
        .iter()
        .filter(|highlight| highlight.place.resource == resource)
        .filter_map(|highlight| {
            let wanted: Vec<char> = highlight.text.chars().collect();
            if wanted.is_empty() {
                return None;
            }
            let kept = serde_json::from_str::<serde_json::Value>(&highlight.place.locator)
                .ok()
                .and_then(|locator| locator["start"].as_u64())
                .map(|start| start as usize);
            let at = kept
                .filter(|start| chars.get(*start..*start + wanted.len()) == Some(&wanted[..]))
                .or_else(|| chars.windows(wanted.len()).position(|window| window == &wanted[..]))?;
            Some((at, at + wanted.len(), highlight.colour.clone()))
        })
        .collect()
}


/// One action of the selection bar.
type Action = fn(&Rc<PdfMarking>);

/// The text pane's selection actions, over the page text the pane shows.
pub struct PdfMarking {
    pub text: gtk::TextView,
    pub bar: gtk::Revealer,
    marks: RefCell<Marks>,
    page: Cell<u32>,
    count: u32,
    /// Keeps the marks; the app writes them to the marks file, a test keeps them in memory.
    save: Box<dyn Fn(&Marks)>,
    /// Searches the document for a text.
    search: Box<dyn Fn(&str)>,
}

impl PdfMarking {
    pub fn new(
        text: &gtk::TextView,
        marks: Marks,
        count: u32,
        save: impl Fn(&Marks) + 'static,
        search: impl Fn(&str) + 'static,
    ) -> Rc<Self> {
        let buffer = text.buffer();
        for colour in COLOURS {
            if buffer.tag_table().lookup(colour).is_none() {
                let tag = gtk::TextTag::builder()
                    .name(colour)
                    .background_rgba(&gdk::RGBA::parse(colour).unwrap_or(gdk::RGBA::BLACK).with_alpha(0.45))
                    .build();
                buffer.tag_table().add(&tag);
            }
        }
        let bar = gtk::Box::builder().spacing(6).halign(gtk::Align::Center).margin_top(6).margin_bottom(6).build();
        let revealer = gtk::Revealer::builder().child(&bar).reveal_child(false).build();
        let marking = Rc::new(Self {
            text: text.clone(),
            bar: revealer,
            marks: RefCell::new(marks),
            page: Cell::new(0),
            count,
            save: Box::new(save),
            search: Box::new(search),
        });
        bar.append(&gtk::Label::new(Some(&tr("desktop.w4.epub.highlight", "Highlight"))));
        for colour in COLOURS {
            let name = colour_name(colour);
            let swatch = gtk::Button::builder()
                .child(&gtk::Box::builder().css_classes([colour_class(colour)]).build())
                .tooltip_text(&name)
                .css_classes(["flat", "circular"])
                .build();
            swatch.update_property(&[gtk::accessible::Property::Label(&name)]);
            let weak = Rc::downgrade(&marking);
            swatch.connect_clicked(move |_| {
                if let Some(marking) = weak.upgrade() {
                    marking.highlight(colour);
                }
            });
            bar.append(&swatch);
        }
        let actions: [(String, Action); 3] = [
            (tr("reader.pdf.note", "Note"), |marking| marking.note()),
            (tr("annotations.copy", "Copy"), |marking| marking.copy()),
            (tr("reader.pdf.searchSelection", "Search for this"), |marking| marking.search_selection()),
        ];
        for (label, run) in actions {
            let button = gtk::Button::builder().label(label).css_classes(["flat"]).build();
            let weak = Rc::downgrade(&marking);
            button.connect_clicked(move |_| {
                if let Some(marking) = weak.upgrade() {
                    run(&marking);
                }
            });
            bar.append(&button);
        }
        let weak = Rc::downgrade(&marking);
        buffer.connect_has_selection_notify(move |buffer| {
            if let Some(marking) = weak.upgrade() {
                marking.bar.set_reveal_child(buffer.has_selection());
            }
        });
        marking
    }

    /// The page's text is in the pane: its highlights are drawn.
    pub fn page_shown(&self, page: u32) {
        self.page.set(page);
        let buffer = self.text.buffer();
        let (start, end) = buffer.bounds();
        for colour in COLOURS {
            buffer.remove_tag_by_name(colour, &start, &end);
        }
        let text = buffer.text(&start, &end, false);
        for (from, to, colour) in ranges(&self.marks.borrow(), page, &text) {
            let (from, to) = (buffer.iter_at_offset(from as i32), buffer.iter_at_offset(to as i32));
            buffer.apply_tag_by_name(&colour, &from, &to);
        }
    }

    fn selection(&self) -> Option<(String, usize)> {
        let buffer = self.text.buffer();
        let (from, to) = buffer.selection_bounds()?;
        let text = buffer.text(&from, &to, false).trim().to_owned();
        (!text.is_empty()).then(|| {
            let lead = buffer.text(&from, &to, false).chars().take_while(|c| c.is_whitespace()).count();
            (text, from.offset() as usize + lead)
        })
    }

    fn clear_selection(&self) {
        let buffer = self.text.buffer();
        let at = buffer.iter_at_mark(&buffer.get_insert());
        buffer.select_range(&at, &at);
        self.bar.set_reveal_child(false);
    }

    /// Keeps the selection as a highlight in a colour, and draws it. Its id comes back for a note.
    pub fn highlight(&self, colour: &str) -> Option<String> {
        let (text, start) = self.selection()?;
        let place = place(self.page.get(), self.count, &text, start);
        let id = self.marks.borrow_mut().highlight(&text, place, colour);
        (self.save)(&self.marks.borrow());
        self.clear_selection();
        self.page_shown(self.page.get());
        Some(id)
    }

    /// Highlights the selection and asks for its note.
    fn note(self: &Rc<Self>) {
        let Some(id) = self.highlight(COLOURS[0]) else {
            return;
        };
        let dialog = adw::AlertDialog::builder().heading(tr("reader.pdf.note", "Note")).build();
        let field = gtk::TextView::builder().wrap_mode(gtk::WrapMode::WordChar).height_request(96).css_classes(["card"]).build();
        field.update_property(&[gtk::accessible::Property::Label(&tr("reader.pdf.note", "Note"))]);
        dialog.set_extra_child(Some(&field));
        dialog.add_response("cancel", &tr("reader.pdf.note.cancel", "Cancel"));
        dialog.add_response("save", &tr("reader.pdf.note.save", "Save"));
        dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
        dialog.set_default_response(Some("save"));
        dialog.set_close_response("cancel");
        let weak = Rc::downgrade(self);
        dialog.connect_response(Some("save"), move |_, _| {
            let Some(marking) = weak.upgrade() else {
                return;
            };
            let buffer = field.buffer();
            let note = buffer.text(&buffer.start_iter(), &buffer.end_iter(), false);
            marking.set_note(&id, note.as_str());
        });
        dialog.present(Some(&self.text));
    }

    pub fn set_note(&self, id: &str, note: &str) {
        self.marks.borrow_mut().set_note(id, note);
        (self.save)(&self.marks.borrow());
    }

    pub fn copy(&self) {
        if let Some((text, _)) = self.selection() {
            self.text.clipboard().set_text(&text);
        }
    }

    pub fn search_selection(&self) {
        if let Some((text, _)) = self.selection() {
            (self.search)(&text);
        }
    }

    #[cfg(test)]
    pub fn marks(&self) -> Marks {
        self.marks.borrow().clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The record keeps the page and where the text starts; the page draws it there, or where
    /// the text first appears when the page's text has moved.
    #[test]
    fn a_pdf_highlight_is_the_epub_record_and_finds_its_text_again() {
        let mut marks = Marks::default();
        let text = "One two three. Two again, two.";
        marks.highlight("two", place(1, 3, "two", 26), "green");
        marks.highlight("Two", place(1, 3, "Two", 15), "pink");
        marks.highlight("elsewhere", place(2, 3, "elsewhere", 0), "blue");
        assert_eq!(
            ranges(&marks, 1, text),
            [(26, 29, "green".to_owned()), (15, 18, "pink".to_owned())]
        );
        // The offset no longer matches: the first appearance is drawn.
        assert_eq!(ranges(&marks, 1, "xx two"), [(3, 6, "green".to_owned())]);
        let place = place(1, 3, "two", 26);
        assert_eq!(place.resource, "page/2");
        assert_eq!(place.chapter, "Page 2 of 3");
        assert!(place.locator.contains("\"application/pdf\""));
        assert_eq!(Marks::from_json(&marks.to_json()), marks);
    }

    /// `ebook-reader`, *Text-based PDF*: a selection in the page text raises the bar; a colour
    /// keeps it and draws it; a note is written on it; copy and search take its text. Needs a
    /// display: `headless-proof.sh pdf_marks` runs it under cage.
    #[test]
    fn a_selection_in_the_page_text_is_highlighted_noted_copied_and_searched() {
        crate::display_test::on_display(selection_on_a_display);
    }

    fn selection_on_a_display() {
        let view = gtk::TextView::new();
        view.buffer().set_text("Chapter two begins here. It goes on.");
        let searched: Rc<RefCell<Vec<String>>> = Rc::default();
        let saved = Rc::new(Cell::new(0));
        let (on_search, on_save) = (searched.clone(), saved.clone());
        let marking = PdfMarking::new(
            &view,
            Marks::default(),
            3,
            move |_| on_save.set(on_save.get() + 1),
            move |text| on_search.borrow_mut().push(text.to_owned()),
        );
        marking.page_shown(1);
        let buffer = view.buffer();
        buffer.select_range(&buffer.iter_at_offset(8), &buffer.iter_at_offset(19));
        assert!(marking.bar.reveals_child());
        marking.search_selection();
        assert_eq!(searched.borrow().as_slice(), ["two begins"]);
        marking.copy();
        let id = marking.highlight("green").expect("a highlight");
        assert!(!marking.bar.reveals_child());
        let marks = marking.marks();
        assert_eq!(marks.highlights.len(), 1);
        assert_eq!((marks.highlights[0].text.as_str(), marks.highlights[0].colour.as_str()), ("two begins", "green"));
        assert!(buffer.iter_at_offset(10).has_tag(&buffer.tag_table().lookup("green").unwrap()));
        marking.set_note(&id, "a note");
        assert_eq!(marking.marks().highlights[0].note, "a note");
        assert_eq!(saved.get(), 2);
    }
}
