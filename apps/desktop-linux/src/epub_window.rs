//! One EPUB reader window (task 4.10): the guarded web view of `epub_view.rs` over the
//! manifest and positions the core builds (`storyarc_core::epub::WebPublication`), a
//! header bar, a position line, the arrow and page keys, and the reader's place written
//! to the progress store as the position number both phones would show.
//!
//! The theme surface and the reader's typography are `epub_theme_ui.rs` over `epub_look.rs`;
//! the contents, bookmarks, highlights, notes, search and the way back after a jump are
//! `epub_marks_ui.rs` over `epub_marks.rs`.

use std::cell::{Cell, OnceCell, RefCell};
use std::path::Path;
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::epub::WebPublication;
use storyarc_core::io::source::FileSource;
use storyarc_core::sources::PublicationIndexer;

use crate::app::Shared;
use crate::epub_host;
use crate::epub_look::{self, Look};
use crate::epub_marks::{self, Hit, Marks, Place};
use crate::epub_marks_ui;
use crate::epub_theme_ui;
use crate::epub_view::{EpubView, Guards, Served};
use crate::epub_view::{confirm_leaving, outward};
use crate::opening;
use crate::player;
use crate::progress::ProgressWriter;
use crate::session::{CoreProgress, LOG_DOMAIN};
use crate::strings::tr;
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH};

/// How long after the app asks for a move the renderer's locators are that move's.
const OWN_MOVE: Duration = Duration::from_millis(1500);

/// How often the window looks at the progress clock.
const TICK: Duration = Duration::from_millis(500);

/// The open book as the web view serves it.
pub(crate) struct Book {
    publication: WebPublication,
    locator: Option<String>,
    /// The look the first page is laid out with (`epub_look.rs`).
    preferences: Option<String>,
}

impl Book {
    pub(crate) fn new(publication: WebPublication, locator: Option<String>) -> Self {
        Self {
            publication,
            locator,
            preferences: None,
        }
    }
}

impl Served for Book {
    fn resource(&self, path: &str) -> Option<(Vec<u8>, String)> {
        if let Some(face) = epub_look::font_resource(path) {
            return Some(face);
        }
        let bytes = self.publication.resource(path).ok()?;
        let media_type = self
            .publication
            .media_type(path)
            .map(str::to_owned)
            .unwrap_or_else(|| epub_host::media_type_for(path).to_owned());
        Some((epub_look::linking(bytes, &media_type), media_type))
    }
    fn manifest_json(&self) -> String {
        self.publication.manifest_json()
    }
    fn positions_json(&self) -> String {
        self.publication.positions_json()
    }
    fn locator_json(&self) -> Option<String> {
        self.locator.clone()
    }
    fn preferences_json(&self) -> Option<String> {
        self.preferences.clone()
    }
}

/// Whether a path is a book this window reads.
pub fn is_epub(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("epub"))
}

pub(crate) struct EpubReader {
    pub(crate) window: adw::ApplicationWindow,
    book: Rc<Book>,
    /// The resource the reader is in, from the last locator.
    href: RefCell<Option<String>>,
    view: RefCell<Option<Rc<EpubView>>>,
    position: gtk::Label,
    progress: RefCell<ProgressWriter<CoreProgress>>,
    seq: Cell<u64>,
    /// The theme and the typography in force, kept per device.
    look: Rc<RefCell<Look>>,
    /// The bookmarks and highlights of this book, kept under `marks_key`.
    pub(crate) marks: RefCell<Marks>,
    marks_key: String,
    /// Where the reader is, as the renderer's locator JSON.
    locator: RefCell<Option<String>>,
    /// Where the last jump came from: *Returning from any jump*.
    return_locator: RefCell<Option<String>>,
    /// When the app last asked for a move, so a move the renderer made on its own is a link.
    /// A turn across chapters can post more than one locator, so the mark lasts a moment.
    moving_itself: Cell<Option<Instant>>,
    ready: Cell<bool>,
    back: gtk::Button,
    bookmark: OnceCell<gtk::Button>,
    search: OnceCell<epub_marks_ui::SearchView>,
    search_id: Cell<u64>,
    search_query: RefCell<String>,
    /// The text and the locator a selection raised, waiting for a colour.
    selection: RefCell<Option<(String, String)>>,
    selection_bar: OnceCell<gtk::Revealer>,
    /// The book's file, its speed key and series, for the voice.
    path: std::path::PathBuf,
    voice_key: String,
    series: Option<String>,
    /// The sentence the voice speaks in this book, as the locator drawn over the page.
    spoken: RefCell<Option<String>>,
    read_button: OnceCell<gtk::Button>,
    player_button: OnceCell<gtk::Button>,
}

impl EpubReader {
    fn next_seq(&self) -> u64 {
        let seq = self.seq.get() + 1;
        self.seq.set(seq);
        seq
    }

    fn send_json(&self, json: &str) {
        if let Some(view) = self.view.borrow().as_ref() {
            view.send(json);
        }
    }

    fn send(&self, kind: &str) {
        let seq = self.next_seq();
        self.send_json(&format!(r#"{{"type":"{kind}","seq":{seq}}}"#));
    }

    /// Changes the look, keeps it, and sends the page the preset with the typography over it:
    /// a `theme` message replaces every axis.
    fn change_look(&self, edit: &dyn Fn(&mut Look)) {
        let look = {
            let mut look = self.look.borrow_mut();
            edit(&mut look);
            *look
        };
        crate::session::save_epub_look(&look);
        let seq = self.next_seq();
        self.send_json(&look.theme_message(seq));
    }

    /// The preset the system appearance asks for, when the reader chose to follow it.
    fn follow_appearance(&self) {
        let dark = adw::StyleManager::default().is_dark();
        let wanted = self.look.borrow().preset_for(dark);
        if let Some(preset) = wanted.filter(|preset| *preset != self.look.borrow().preset) {
            self.change_look(&|look| look.preset = preset);
        }
    }

    /// The page, once the view is built.
    pub(crate) fn web_view(&self) -> Option<gtk::Widget> {
        self.view
            .borrow()
            .as_ref()
            .map(|view| view.web_view.clone().upcast())
    }

    /// Turns the page; not a jump to come back from.
    fn turn(&self, next: bool) {
        self.moving_itself.set(Some(Instant::now()));
        self.send(if next { "next" } else { "previous" });
    }

    /// Goes to a locator, keeping where the reader was so they can come back.
    pub(crate) fn go(&self, locator: &str) {
        *self.return_locator.borrow_mut() = self.locator.borrow().clone();
        self.back
            .set_visible(self.return_locator.borrow().is_some());
        self.moving_itself.set(Some(Instant::now()));
        self.send_go(locator);
    }

    fn send_go(&self, locator: &str) {
        if let Some(message) = epub_marks::go_message(self.next_seq(), locator) {
            self.send_json(&message);
        }
    }

    /// Back to where the last jump left; using it is not itself a place to return from.
    fn go_back(&self) {
        let Some(locator) = self.return_locator.borrow_mut().take() else {
            return;
        };
        self.back.set_visible(false);
        self.moving_itself.set(Some(Instant::now()));
        self.send_go(&locator);
    }

    /// The table of contents: each entry's title, resource and media type.
    pub(crate) fn contents(&self) -> Vec<(Option<String>, String, Option<String>)> {
        self.book
            .publication
            .manifest()
            .toc
            .iter()
            .map(|link| {
                (
                    link.title.clone(),
                    link.href.clone(),
                    link.media_type.clone(),
                )
            })
            .collect()
    }

    /// The chapter a resource belongs to, by the contents, or the book's title.
    fn chapter_of(&self, resource: &str) -> String {
        self.book
            .publication
            .manifest()
            .toc
            .iter()
            .find(|link| link.href.split('#').next() == Some(resource))
            .and_then(|link| link.title.clone())
            .unwrap_or_else(|| self.window.title().unwrap_or_default().to_string())
    }

    fn place(&self) -> Option<Place> {
        let locator = self.locator.borrow().clone()?;
        let place = Place::of(&locator, "");
        let chapter = self.chapter_of(&place.resource);
        Some(Place { chapter, ..place })
    }

    fn reading_order(&self) -> Vec<String> {
        self.book
            .publication
            .manifest()
            .reading_order
            .iter()
            .map(|link| link.href.clone())
            .collect()
    }

    pub(crate) fn toggle_bookmark(&self) {
        let Some(place) = self.place() else {
            return;
        };
        let order = self.reading_order();
        self.edit_marks(&|marks| {
            marks.toggle_bookmark(place.clone(), &order);
        });
    }

    /// Changes the marks, keeps them, and draws them again.
    pub(crate) fn edit_marks(&self, edit: &dyn Fn(&mut Marks)) {
        edit(&mut self.marks.borrow_mut());
        crate::session::save_epub_marks(&self.marks_key, &self.marks.borrow());
        self.sync_highlights();
        self.show_bookmark();
    }

    fn show_bookmark(&self) {
        if let Some(button) = self.bookmark.get() {
            let marked = self
                .place()
                .is_some_and(|place| self.marks.borrow().bookmark_at(&place).is_some());
            button.set_sensitive(self.locator.borrow().is_some());
            epub_marks_ui::show_bookmark(button, marked);
        }
    }

    /// The page is on screen: the highlights are drawn, and a voice already reading this book
    /// is taken again at the sentence it has reached (`ebook-reader`, *Leaving the publication
    /// while it speaks*).
    fn adopt_voice(&self) {
        let spoken = self.spoken.borrow().clone();
        self.sync_highlights();
        if let Some(locator) = spoken {
            self.moving_itself.set(Some(Instant::now()));
            self.send_go(&locator);
        }
    }

    /// Draws every highlight; the message replaces what the page had.
    fn sync_highlights(&self) {
        let seq = self.next_seq();
        let message = self
            .marks
            .borrow()
            .highlights_message(self.spoken.borrow().as_deref(), seq);
        self.send_json(&message);
    }

    /// Searches the book; a newer search silences an older one, as the renderer promises.
    pub(crate) fn search(&self, query: &str) {
        let query = query.trim().to_owned();
        let id = self.search_id.get() + 1;
        self.search_id.set(id);
        if let Some(view) = self.search.get() {
            view.start(&query);
        }
        if query.is_empty() {
            return;
        }
        query.clone_into(&mut self.search_query.borrow_mut());
        let seq = self.next_seq();
        self.send_json(&epub_marks::search_message(seq, id, &query));
    }

    /// Keeps the waiting selection as a highlight and draws it.
    pub(crate) fn highlight_selection(&self, colour: &str) {
        let Some((text, locator)) = self.selection.borrow_mut().take() else {
            return;
        };
        if let Some(bar) = self.selection_bar.get() {
            bar.set_reveal_child(false);
        }
        let place = Place::of(&locator, "");
        let place = Place {
            chapter: self.chapter_of(&place.resource),
            ..place
        };
        self.edit_marks(&|marks| {
            marks.highlight(&text, place.clone(), colour);
        });
    }

    /// The renderer's place: the progress line, the store, and whether it was a jump.
    fn moved(&self, locator: &serde_json::Value) {
        let moving_itself = self
            .moving_itself
            .get()
            .is_some_and(|asked| asked.elapsed() < OWN_MOVE);
        let previous = self.locator.borrow().clone();
        if !moving_itself
            && let Some(previous) = previous
            && epub_marks::is_jump(&previous, locator)
        {
            *self.return_locator.borrow_mut() = Some(previous);
            self.back.set_visible(true);
        }
        *self.locator.borrow_mut() = Some(locator.to_string());
        self.show_bookmark();
    }

    /// One message from the renderer: the place it is at, or a link that leaves.
    fn received(self: &Rc<Self>, json: &str) {
        let Ok(message) = serde_json::from_str::<serde_json::Value>(json) else {
            return;
        };
        match message["type"].as_str().unwrap_or("") {
            "locator" => {
                let Some(position) = message["locator"]["locations"]["position"].as_u64() else {
                    return;
                };
                if let Some(href) = message["locator"]["href"].as_str() {
                    *self.href.borrow_mut() = Some(href.to_owned());
                }
                if !self.ready.replace(true) {
                    self.adopt_voice();
                }
                self.moved(&message["locator"]);
                let position = u32::try_from(position).unwrap_or(u32::MAX).max(1);
                let locations = &message["locator"]["locations"];
                self.position.set_text(&epub_look::progress_line(
                    locations["totalProgression"].as_f64().unwrap_or(0.0),
                    locations["progression"].as_f64().unwrap_or(0.0),
                ));
                self.progress
                    .borrow_mut()
                    .turned(position - 1, Instant::now());
            }
            "link" => {
                if let Some((uri, host)) = message["href"].as_str().and_then(outward) {
                    confirm_leaving(self.window.upcast_ref(), uri, &host);
                }
            }
            "ready" => {
                if !self.ready.replace(true) {
                    self.adopt_voice();
                }
            }
            "selection" => {
                let text = message["text"].as_str().unwrap_or("").trim().to_owned();
                let shown = !text.is_empty() && message["locator"].is_object();
                *self.selection.borrow_mut() =
                    shown.then(|| (text, message["locator"].to_string()));
                if let Some(bar) = self.selection_bar.get() {
                    bar.set_reveal_child(shown);
                }
            }
            "footnote" => {
                if let Some(text) = message["text"].as_str().filter(|t| !t.trim().is_empty()) {
                    epub_marks_ui::footnote(self, text);
                }
            }
            "highlight-activated" => {
                if let Some(id) = message["id"]
                    .as_str()
                    .filter(|id| *id != epub_marks::SPOKEN_ID)
                {
                    epub_marks_ui::note_dialog(self, id);
                }
            }
            "search-results" => {
                if message["id"].as_u64() != Some(self.search_id.get()) {
                    return;
                }
                if let Some(view) = self.search.get() {
                    view.add(self, Hit::all_of(&message));
                    if message["done"].as_bool() == Some(true) {
                        view.done(&self.search_query.borrow());
                    }
                }
            }
            "host-error" | "navigation-failed" => {
                glib::g_warning!(LOG_DOMAIN, "epub renderer: {json}");
            }
            _ => {}
        }
    }

    fn flush(&self) {
        if let Err(failure) = self.progress.borrow_mut().flush() {
            glib::g_warning!(LOG_DOMAIN, "{failure}");
        }
    }

    /// Reads the book aloud from the chapter the reader is in, chapter after chapter, through
    /// the one player (`ebook-reader`, Reading aloud), or stops the voice reading it.
    fn read_aloud(&self, shared: &Shared) {
        let player = shared.player();
        if player.voice_book().as_deref() == Some(self.path.as_path()) {
            player.stop();
            return;
        }
        let order = self.reading_order();
        let here = self
            .locator
            .borrow()
            .as_deref()
            .map(|locator| Place::of(locator, "").resource)
            .unwrap_or_default();
        let part = order.iter().position(|href| *href == here).unwrap_or(0);
        let chapters = order
            .iter()
            .map(|href| {
                let markup = self.book.publication.resource(href).unwrap_or_default();
                player::SpokenChapter {
                    href: href.clone(),
                    title: self.chapter_of(href),
                    sentences: player::sentences_of_markup(&String::from_utf8_lossy(&markup)),
                }
            })
            .collect();
        let book = player::VoiceBook {
            title: self.window.title().unwrap_or_default().to_string(),
            path: self.path.clone(),
            key: self.voice_key.clone(),
            series: self.series.clone(),
            chapters,
            part,
        };
        if let Err(reason) = player.read_aloud(book) {
            shared.toast(&reason);
        }
    }

    /// The page follows the voice reading this book: its sentence is drawn and brought into
    /// view, with no way back kept, because the reader did not jump. A voice that stops, or
    /// reads another book, leaves the page as it is (`ebook-reader`, *Starting playback*).
    fn follow_voice(&self, showing: &player::Showing) {
        let mine = showing.voice
            && showing.state != crate::audio::PlayState::Stopped
            && showing.book.as_deref() == Some(self.path.as_path());
        if let Some(button) = self.read_button.get() {
            let label = if mine {
                tr("desktop.w4.epub.stopReadingAloud", "Stop reading aloud")
            } else {
                tr("desktop.w4.player.readAloud", "Read aloud")
            };
            button.set_icon_name(if mine {
                "media-playback-stop-symbolic"
            } else {
                "audio-speakers-symbolic"
            });
            button.set_tooltip_text(Some(&label));
            button.update_property(&[gtk::accessible::Property::Label(&label)]);
        }
        if let Some(button) = self.player_button.get() {
            button.set_visible(mine);
        }
        let spoken = mine
            .then_some(showing.spoken.as_ref())
            .flatten()
            .map(|(href, sentence)| epub_marks::spoken_locator(sentence, href));
        if spoken == *self.spoken.borrow() {
            return;
        }
        *self.spoken.borrow_mut() = spoken.clone();
        if !self.ready.get() {
            return;
        }
        self.sync_highlights();
        if let Some(locator) = spoken {
            self.moving_itself.set(Some(Instant::now()));
            self.send_go(&locator);
        }
    }
}

/// Opens `path` in an EPUB window, or brings forward the one that reads it. The error
/// names the file and the reason, for the library to show in grey.
/// `notice`, when given, is said once in the window: a voice that stopped for this book.
pub fn open(shared: &Shared, path: &Path, notice: Option<String>) -> Result<(), String> {
    let id = path.to_string_lossy().into_owned();
    if let Some((_, window)) = shared
        .epub_windows
        .borrow()
        .iter()
        .find(|(open, _)| *open == id)
    {
        window.present();
        return Ok(());
    }
    let name = opening::name(path);
    let record = PublicationIndexer::index_path(path, None).map_err(|e| format!("{name}: {e}"))?;
    let source = Arc::new(FileSource::open(path).map_err(|e| format!("{name}: {e}"))?);
    let publication = WebPublication::open(source, &epub_host::manifest_uri())
        .map_err(|e| format!("{name}: {e}"))?;
    let count = u32::try_from(publication.positions().len())
        .unwrap_or(u32::MAX)
        .max(1);
    let store = shared.progress_store();
    let locator = CoreProgress::page(&store, &record.identity)
        .and_then(|index| publication.positions().get(index as usize))
        .and_then(|locator| serde_json::to_string(locator).ok());
    let title = match publication.manifest().metadata.title.trim() {
        "" => record.display_title.clone(),
        title => title.to_owned(),
    };
    let mut look = crate::session::load_epub_look();
    if let Some(preset) = look.preset_for(adw::StyleManager::default().is_dark()) {
        look.preset = preset;
    }
    let mut book = Book::new(publication, locator);
    book.preferences = Some(look.preferences_json());
    let book = Rc::new(book);
    let served: Rc<dyn Served> = book.clone();

    let app = shared.application();
    let header = adw::HeaderBar::new();
    let position = gtk::Label::builder()
        .css_classes(["dim-label", "numeric"])
        .build();
    position.set_text(&epub_look::progress_line(0.0, 0.0));
    let bottom = gtk::CenterBox::builder()
        .center_widget(&position)
        .margin_top(6)
        .margin_bottom(6)
        .build();
    let toolbar = adw::ToolbarView::new();
    let toasts = adw::ToastOverlay::new();
    toasts.set_child(Some(&toolbar));
    if let Some(notice) = notice {
        toasts.add_toast(adw::Toast::new(&notice));
    }
    toolbar.add_top_bar(&header);
    let foot = gtk::Box::new(gtk::Orientation::Vertical, 0);
    foot.append(&bottom);
    toolbar.add_bottom_bar(&foot);
    toolbar.set_content(Some(&gtk::Spinner::builder().spinning(true).build()));
    let window = adw::ApplicationWindow::builder()
        .application(&app)
        .title(&title)
        .content(&toasts)
        .default_width(900)
        .default_height(720)
        .build();
    window.set_size_request(MIN_WIDTH, MIN_HEIGHT);

    let marks_key = record
        .identity
        .content_digest
        .clone()
        .or_else(|| record.identity.normalized_path.clone())
        .unwrap_or_else(|| id.clone());
    let back = gtk::Button::builder()
        .icon_name("edit-undo-symbolic")
        .label(tr("desktop.w4.epub.back", "Back"))
        .tooltip_text(tr("desktop.w4.epub.back", "Back"))
        .visible(false)
        .css_classes(["flat"])
        .build();
    bottom.set_end_widget(Some(&back));
    let progress = CoreProgress::new(store, record.identity.clone(), count);
    let reader = Rc::new(EpubReader {
        window: window.clone(),
        book,
        href: RefCell::new(None),
        view: RefCell::new(None),
        position,
        progress: RefCell::new(ProgressWriter::new(progress, id.clone())),
        seq: Cell::new(0),
        look: Rc::new(RefCell::new(look)),
        marks: RefCell::new(crate::session::load_epub_marks(&marks_key)),
        marks_key,
        locator: RefCell::new(None),
        return_locator: RefCell::new(None),
        moving_itself: Cell::new(None),
        ready: Cell::new(false),
        back: back.clone(),
        bookmark: OnceCell::new(),
        search: OnceCell::new(),
        search_id: Cell::new(0),
        search_query: RefCell::new(String::new()),
        selection: RefCell::new(None),
        selection_bar: OnceCell::new(),
        path: path.to_path_buf(),
        voice_key: player::speed_key(&record.identity, path),
        series: record.series.clone(),
        spoken: RefCell::new(None),
        read_button: OnceCell::new(),
        player_button: OnceCell::new(),
    });
    let weak = Rc::downgrade(&reader);
    back.connect_clicked(move |_| {
        if let Some(reader) = weak.upgrade() {
            reader.go_back();
        }
    });
    let contents = epub_marks_ui::contents_button(&reader);
    header.pack_start(&contents);
    let bookmark = epub_marks_ui::bookmark_button(&reader);
    header.pack_start(&bookmark);
    let _ = reader.bookmark.set(bookmark);
    let marks = epub_marks_ui::marks_button(&reader);
    header.pack_start(&marks);
    let (search, search_view) = epub_marks_ui::search_button(&reader);
    header.pack_end(&search);
    let _ = reader.search.set(search_view);
    let selection_bar = epub_marks_ui::selection_bar(&reader);
    foot.prepend(&selection_bar);
    let _ = reader.selection_bar.set(selection_bar);

    let filter_dir = glib::user_data_dir()
        .join(crate::APP_ID)
        .join("content-filters");
    let weak = Rc::downgrade(&reader);
    let on_toolbar = toolbar.clone();
    glib::MainContext::default().spawn_local(async move {
        match EpubView::build(served, &filter_dir, Guards::ALL).await {
            Ok(view) => {
                let Some(reader) = weak.upgrade() else {
                    return;
                };
                let view = Rc::new(view);
                view.web_view.set_vexpand(true);
                view.web_view.set_hexpand(true);
                on_toolbar.set_content(Some(&view.web_view));
                let on = Rc::downgrade(&reader);
                view.connect_message(move |json| {
                    if let Some(reader) = on.upgrade() {
                        reader.received(&json);
                    }
                });
                view.open_reader();
                *reader.view.borrow_mut() = Some(view);
            }
            Err(reason) => {
                glib::g_warning!(LOG_DOMAIN, "{reason}");
                on_toolbar.set_content(Some(
                    &adw::StatusPage::builder()
                        .icon_name("dialog-warning-symbolic")
                        .title(reason)
                        .build(),
                ));
            }
        }
    });

    install_keys(&reader);
    let weak = Rc::downgrade(&reader);
    let change: epub_theme_ui::Change = Rc::new(move |edit| {
        if let Some(reader) = weak.upgrade() {
            reader.change_look(edit);
        }
    });
    let theme = epub_theme_ui::button(&reader.look, &change);
    header.pack_end(&theme);
    // The surfaces as window actions: `win.find`, `win.bookmark` and `win.back` take the
    // app's own keys (Control F, Control D, Alt Left), and the walks reach every one.
    for (name, menu) in [
        ("find", &search),
        ("contents", &contents),
        ("marks", &marks),
        ("theme", &theme),
    ] {
        let action = gio::SimpleAction::new(name, None);
        let menu = menu.clone();
        action.connect_activate(move |_, _| menu.popup());
        window.add_action(&action);
    }
    for (name, back) in [("bookmark", false), ("back", true)] {
        let action = gio::SimpleAction::new(name, None);
        let weak = Rc::downgrade(&reader);
        action.connect_activate(move |_, _| {
            if let Some(reader) = weak.upgrade() {
                if back {
                    reader.go_back();
                } else {
                    reader.toggle_bookmark();
                }
            }
        });
        window.add_action(&action);
    }
    let weak = Rc::downgrade(&reader);
    let appearance = adw::StyleManager::default().connect_dark_notify(move |_| {
        if let Some(reader) = weak.upgrade() {
            reader.follow_appearance();
        }
    });
    if player::speech_available() {
        let read = gtk::Button::builder()
            .icon_name("audio-speakers-symbolic")
            .action_name("win.read-aloud")
            .tooltip_text(tr("desktop.w4.player.readAloud", "Read aloud"))
            .build();
        read.update_property(&[gtk::accessible::Property::Label(&tr(
            "desktop.w4.player.readAloud",
            "Read aloud",
        ))]);
        header.pack_end(&read);
        let _ = reader.read_button.set(read);
        let show = gtk::Button::builder()
            .icon_name("audio-headphones-symbolic")
            .tooltip_text(tr("player.open", "Open the player"))
            .visible(false)
            .build();
        show.update_property(&[gtk::accessible::Property::Label(&tr(
            "player.open",
            "Open the player",
        ))]);
        let weak_shared = Rc::downgrade(shared);
        show.connect_clicked(move |_| {
            if let Some(shared) = weak_shared.upgrade() {
                crate::player_window::present(&shared);
            }
        });
        header.pack_end(&show);
        let _ = reader.player_button.set(show);
        let weak = Rc::downgrade(&reader);
        let player = shared.player();
        player.connect(move |showing| {
            if let Some(reader) = weak.upgrade() {
                reader.follow_voice(showing);
            }
        });
        reader.follow_voice(&player.showing());
        let action = gio::SimpleAction::new("read-aloud", None);
        let weak = Rc::downgrade(&reader);
        let weak_shared = Rc::downgrade(shared);
        action.connect_activate(move |_, _| {
            if let (Some(reader), Some(shared)) = (weak.upgrade(), weak_shared.upgrade()) {
                reader.read_aloud(&shared);
            }
        });
        window.add_action(&action);
    }
    let weak = Rc::downgrade(&reader);
    glib::timeout_add_local(TICK, move || {
        let Some(reader) = weak.upgrade() else {
            return glib::ControlFlow::Break;
        };
        reader.progress.borrow_mut().tick(Instant::now());
        glib::ControlFlow::Continue
    });
    crate::launch::install_drop(window.upcast_ref(), shared);

    let weak_shared = Rc::downgrade(shared);
    let close_id = id.clone();
    let on_close = reader.clone();
    let appearance = RefCell::new(Some(appearance));
    window.connect_close_request(move |_| {
        if let Some(handler) = appearance.borrow_mut().take() {
            adw::StyleManager::default().disconnect(handler);
        }
        on_close.flush();
        if let Some(shared) = weak_shared.upgrade() {
            shared
                .epub_windows
                .borrow_mut()
                .retain(|(open, _)| *open != close_id);
            shared.progress_changed();
        }
        glib::Propagation::Proceed
    });
    shared.epub_windows.borrow_mut().push((id, window.clone()));
    window.present();
    crate::launch::record_recent(path);
    Ok(())
}

/// Right, Page Down and Space go on; Left and Page Up go back. The web view takes the
/// other keys, so the book's own text stays reachable.
fn install_keys(reader: &Rc<EpubReader>) {
    let keys = gtk::EventControllerKey::new();
    keys.set_propagation_phase(gtk::PropagationPhase::Capture);
    let weak = Rc::downgrade(reader);
    keys.connect_key_pressed(move |_, key, _, _| {
        let Some(reader) = weak.upgrade() else {
            return glib::Propagation::Proceed;
        };
        use gtk::gdk::Key;
        match key {
            Key::Right | Key::Page_Down | Key::space => reader.turn(true),
            Key::Left | Key::Page_Up => reader.turn(false),
            _ => return glib::Propagation::Proceed,
        }
        glib::Propagation::Stop
    });
    reader.window.add_controller(keys);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::epub_view::Guards;
    use storyarc_core::io::source::FileSource;

    fn pump_until(seconds: f64, mut done: impl FnMut() -> bool) -> bool {
        let context = glib::MainContext::default();
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        while Instant::now() < end {
            if done() {
                return true;
            }
            context.iteration(false);
            std::thread::sleep(Duration::from_millis(5));
        }
        done()
    }

    /// The host messages the Mac sends, from this window's builders, through the guarded view
    /// to the pinned renderer over the corpus book: the opening look, a search with its hits
    /// in context, a move to a chapter, a theme and the highlights. Needs a display:
    /// `headless-proof.sh epub_window` runs it under cage.
    #[test]
    fn the_renderer_answers_the_windows_look_search_go_and_highlights() {
        crate::display_test::on_display(renderer_on_a_display);
    }

    fn renderer_on_a_display() {
        let dir = tempfile::tempdir().expect("a folder for the filter store");
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/ebooks/fixture.epub");
        let source = Arc::new(FileSource::open(&path).expect("the fixture"));
        let publication =
            WebPublication::open(source, &epub_host::manifest_uri()).expect("the manifest");
        let toc: Vec<String> = publication
            .manifest()
            .toc
            .iter()
            .map(|l| l.href.clone())
            .collect();
        let mut look = Look::default();
        look.values.typeface = epub_look::Typeface::Literata;
        let mut book = Book::new(publication, None);
        book.preferences = Some(look.preferences_json());
        let served: Rc<dyn Served> = Rc::new(book);
        let view = glib::MainContext::default()
            .block_on(EpubView::build(served, dir.path(), Guards::ALL))
            .expect("a view");
        let heard: Rc<RefCell<Vec<serde_json::Value>>> = Rc::default();
        let on_heard = heard.clone();
        view.connect_message(move |json| {
            if let Ok(value) = serde_json::from_str(&json) {
                on_heard.borrow_mut().push(value);
            }
        });
        let window = gtk::Window::new();
        window.set_default_size(800, 600);
        window.set_child(Some(&view.web_view));
        window.present();
        view.open_reader();
        let has = |kind: &str| {
            let heard = heard.clone();
            let kind = kind.to_owned();
            move || heard.borrow().iter().any(|m| m["type"] == kind.as_str())
        };
        assert!(
            pump_until(15.0, has("ready")),
            "never ready: {:?}",
            heard.borrow()
        );

        // The table of contents is the manifest's, and both chapters are in it.
        assert_eq!(toc, ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"]);

        // Search: hits in both chapters, each a locator with its text in context, then done.
        view.send(&epub_marks::search_message(1, 7, "paragraph 3"));
        let done = || {
            heard
                .borrow()
                .iter()
                .any(|m| m["type"] == "search-results" && m["done"] == true)
        };
        assert!(
            pump_until(10.0, done),
            "no search end: {:?}",
            heard.borrow()
        );
        let hits: Vec<Hit> = heard
            .borrow()
            .iter()
            .filter(|m| m["type"] == "search-results" && m["id"] == 7)
            .flat_map(Hit::all_of)
            .collect();
        assert!(hits.len() >= 2, "{hits:?} {:?}", view.requests.borrow());
        assert!(
            hits.iter()
                .all(|hit| hit.matched.eq_ignore_ascii_case("paragraph 3"))
        );
        assert!(hits.iter().any(|hit| hit.locator.contains("ch2.xhtml")));

        // A move to the second chapter, a theme with the reader's face, and the highlights.
        view.send(
            &epub_marks::go_message(2, &epub_marks::start_of("OEBPS/ch2.xhtml", None)).unwrap(),
        );
        let moved = pump_until(5.0, || {
            heard.borrow().iter().any(|m| {
                m["type"] == "locator"
                    && m["locator"]["href"]
                        .as_str()
                        .is_some_and(|h| h.contains("ch2"))
            })
        });
        view.send(&look.theme_message(3));
        let themed = pump_until(5.0, has("theme"));
        let mut marks = Marks::default();
        let id = marks.highlight("paragraph 3", Place::of(&hits[0].locator, "One"), "yellow");
        view.send(&marks.highlights_message(None, 4));
        let drawn = pump_until(5.0, || {
            heard.borrow().iter().any(|m| {
                m["type"] == "highlights"
                    && m["ids"]
                        .as_array()
                        .is_some_and(|ids| ids.iter().any(|i| *i == id.as_str()))
            })
        });
        assert!(
            moved && themed && drawn,
            "moved {moved}, themed {themed}, drawn {drawn}: {:?}",
            heard.borrow()
        );

        // The voice's sentence: drawn in its own tint and brought into view, as `follow_voice`
        // sends it (`ebook-reader`, *Starting playback*).
        let spoken = epub_marks::spoken_locator("Chapter 1, paragraph 12.", "OEBPS/ch1.xhtml");
        view.send(&marks.highlights_message(Some(&spoken), 5));
        view.send(&epub_marks::go_message(6, &spoken).unwrap());
        let followed = pump_until(5.0, || {
            let heard = heard.borrow();
            heard.iter().any(|m| {
                m["type"] == "highlights"
                    && m["ids"]
                        .as_array()
                        .is_some_and(|ids| ids.iter().any(|i| *i == epub_marks::SPOKEN_ID))
            }) && heard
                .iter()
                .rev()
                .find(|m| m["type"] == "locator")
                .is_some_and(|m| {
                    m["locator"]["href"]
                        .as_str()
                        .is_some_and(|h| h.contains("ch1"))
                })
        });
        assert!(
            followed,
            "the spoken sentence was not drawn and followed: {:?}",
            heard.borrow()
        );
        let properties = heard
            .borrow()
            .iter()
            .rfind(|m| m["type"] == "theme")
            .map(|m| m["properties"].to_string())
            .unwrap_or_default();
        eprintln!("renderer: theme properties {properties}");
        assert!(properties.contains("Literata"), "{properties}");
        pump_until(3.0, || false);
        let served: Vec<String> = view
            .requests
            .borrow()
            .iter()
            .map(|n| format!("{} {}", n.path, n.status))
            .collect();
        eprintln!("book: served {served:?}");
        assert!(
            served
                .iter()
                .any(|s| s == "/.storyarc/storyarc-fonts/faces.css 200"),
            "{served:?}"
        );
        assert!(
            !heard.borrow().iter().any(|m| m["type"] == "host-error"),
            "{:?}",
            heard.borrow()
        );
    }
}
