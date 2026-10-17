//! One EPUB reader window (task 4.10): the guarded web view of `epub_view.rs` over the
//! manifest and positions the core builds (`storyarc_core::epub::WebPublication`), a
//! header bar, a position line, the arrow and page keys, and the reader's place written
//! to the progress store as the position number both phones would show.
//!
//! Themes, search, highlights and the table of contents are later tasks of the lane; the
//! renderer already answers their messages (`apps/desktop-web/epub/README.md`).

use std::cell::{Cell, RefCell};
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
use crate::epub_view::{EpubView, Guards, Served};
use crate::opening;
use crate::player;
use crate::progress::ProgressWriter;
use crate::session::{CoreProgress, LOG_DOMAIN};
use crate::strings::{tr, tr_args};
use crate::window_state::{MIN_HEIGHT, MIN_WIDTH};

/// How often the window looks at the progress clock.
const TICK: Duration = Duration::from_millis(500);

/// The open book as the web view serves it.
pub(crate) struct Book {
    publication: WebPublication,
    locator: Option<String>,
}

impl Book {
    pub(crate) fn new(publication: WebPublication, locator: Option<String>) -> Self {
        Self {
            publication,
            locator,
        }
    }
}

impl Served for Book {
    fn resource(&self, path: &str) -> Option<(Vec<u8>, String)> {
        let bytes = self.publication.resource(path).ok()?;
        let media_type = self
            .publication
            .media_type(path)
            .map(str::to_owned)
            .unwrap_or_else(|| epub_host::media_type_for(path).to_owned());
        Some((bytes, media_type))
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
}

/// Whether a path is a book this window reads.
pub fn is_epub(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("epub"))
}

struct EpubReader {
    window: adw::ApplicationWindow,
    book: Rc<Book>,
    /// The resource the reader is in, from the last locator.
    href: RefCell<Option<String>>,
    view: RefCell<Option<Rc<EpubView>>>,
    position: gtk::Label,
    progress: RefCell<ProgressWriter<CoreProgress>>,
    count: u32,
    seq: Cell<u64>,
}

impl EpubReader {
    fn send(&self, kind: &str) {
        let seq = self.seq.get() + 1;
        self.seq.set(seq);
        if let Some(view) = self.view.borrow().as_ref() {
            view.send(&format!(r#"{{"type":"{kind}","seq":{seq}}}"#));
        }
    }

    /// One message from the renderer: the place it is at, or a link that leaves.
    fn received(&self, json: &str) {
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
                let position = u32::try_from(position).unwrap_or(u32::MAX).max(1);
                self.position.set_text(&tr_args(
                    "reader.pageOfCount",
                    "%d of %d",
                    &[&position, &self.count],
                ));
                self.progress
                    .borrow_mut()
                    .turned(position - 1, Instant::now());
            }
            "link" => {
                if let Some(href) = message["href"].as_str() {
                    gtk::UriLauncher::new(href).launch(
                        Some(&self.window),
                        None::<&gio::Cancellable>,
                        |_| {},
                    );
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

    /// Reads the chapter the reader is in aloud, through the one player (`ebook-reader`,
    /// Reading aloud). Present only where a speech engine is.
    fn read_aloud(&self, shared: &Shared) {
        let href = self.href.borrow().clone();
        let Some(href) = href.or_else(|| {
            self.book
                .publication
                .manifest()
                .reading_order
                .first()
                .map(|link| link.href.clone())
        }) else {
            return;
        };
        let Ok(markup) = self.book.publication.resource(&href) else {
            return;
        };
        let sentences = player::sentences_of_markup(&String::from_utf8_lossy(&markup));
        if let Err(reason) = shared
            .player()
            .read_aloud(&self.window.title().unwrap_or_default(), sentences)
        {
            shared.toast(&reason);
        }
    }
}

/// Opens `path` in an EPUB window, or brings forward the one that reads it. The error
/// names the file and the reason, for the library to show in grey.
pub fn open(shared: &Shared, path: &Path) -> Result<(), String> {
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
    let book = Rc::new(Book::new(publication, locator));
    let served: Rc<dyn Served> = book.clone();

    let app = shared.application();
    let header = adw::HeaderBar::new();
    let position = gtk::Label::builder()
        .css_classes(["dim-label", "numeric"])
        .build();
    position.update_property(&[gtk::accessible::Property::Label(&tr_args(
        "reader.pageOfCount",
        "%d of %d",
        &[&1, &count],
    ))]);
    let bottom = gtk::CenterBox::builder()
        .center_widget(&position)
        .margin_top(6)
        .margin_bottom(6)
        .build();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.add_bottom_bar(&bottom);
    toolbar.set_content(Some(&gtk::Spinner::builder().spinning(true).build()));
    let window = adw::ApplicationWindow::builder()
        .application(&app)
        .title(&title)
        .content(&toolbar)
        .default_width(900)
        .default_height(720)
        .build();
    window.set_size_request(MIN_WIDTH, MIN_HEIGHT);

    let progress = CoreProgress::new(store, record.identity.clone(), count);
    let reader = Rc::new(EpubReader {
        window: window.clone(),
        book,
        href: RefCell::new(None),
        view: RefCell::new(None),
        position,
        progress: RefCell::new(ProgressWriter::new(progress, id.clone())),
        count,
        seq: Cell::new(0),
    });

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
    window.connect_close_request(move |_| {
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
            Key::Right | Key::Page_Down | Key::space => reader.send("next"),
            Key::Left | Key::Page_Up => reader.send("previous"),
            _ => return glib::Propagation::Proceed,
        }
        glib::Propagation::Stop
    });
    reader.window.add_controller(keys);
}
