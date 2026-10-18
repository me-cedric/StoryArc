//! The guarded WebKitGTK view the EPUB renderer runs in (task 4.10). The rules are in
//! `epub_host.rs`; this file gives them to `webkit6`: the scheme on a `WebContext`, the
//! rule list through a `UserContentFilterStore`, the header on every answer, the policy
//! on every navigation, and the `storyarc` message door the renderer posts to.
//!
//! The test at the end is the egress proof of ADR-0015 on this desktop. It needs a
//! display, so it skips by name without one and `scripts/headless-proof.sh` runs it under
//! cage in the Ubuntu 24.04 container.

use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;

use gtk::{gio, glib};
use webkit::prelude::*;
use webkit::soup;

use crate::epub_host::{self, Answer, CSP, Navigation, RULE_LIST, RULE_LIST_ID, Route, SCHEME};
use crate::strings::{tr, tr_args};

/// What the view serves: one book's documents and resources.
pub trait Served {
    /// A resource's bytes and media type, by container path, or `None` when the book
    /// has no such path.
    fn resource(&self, path: &str) -> Option<(Vec<u8>, String)>;
    fn manifest_json(&self) -> String;
    fn positions_json(&self) -> String;
    /// Where the reader opens, as a locator, when the reader has been here before.
    fn locator_json(&self) -> Option<String>;
    /// The axes the first page is laid out with, as the renderer's preferences.
    fn preferences_json(&self) -> Option<String> {
        None
    }
}

/// One request the scheme handler answered, kept for the record the design asks for:
/// whether subresources and media come through the handler, and with which `Range`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RequestNote {
    pub method: String,
    pub path: String,
    pub range: Option<String>,
    pub status: u32,
}

/// Which guards the view carries. The app always carries all of them; the egress test
/// also builds a view with none, to prove its collector hears an unguarded page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Guards {
    pub filter: bool,
    pub header: bool,
    pub policy: bool,
}

impl Guards {
    pub const ALL: Self = Self {
        filter: true,
        header: true,
        policy: true,
    };
    #[cfg(test)]
    pub const NONE: Self = Self {
        filter: false,
        header: false,
        policy: false,
    };
}

pub struct EpubView {
    pub web_view: webkit::WebView,
    /// The record the egress test prints; the app keeps it and reads it nowhere yet.
    #[allow(dead_code)]
    pub requests: Rc<RefCell<Vec<RequestNote>>>,
    manager: webkit::UserContentManager,
}

impl EpubView {
    /// Builds the view over `served`. `filter_dir` is where the compiled rule list is
    /// kept between runs. Fails only when the filter cannot be compiled, because a view
    /// without its filter never opens a book.
    pub async fn build(
        served: Rc<dyn Served>,
        filter_dir: &Path,
        guards: Guards,
    ) -> Result<Self, String> {
        let requests: Rc<RefCell<Vec<RequestNote>>> = Rc::default();
        let context = webkit::WebContext::new();
        let notes = requests.clone();
        context.register_uri_scheme(SCHEME, move |request| {
            answer(request, served.as_ref(), guards.header, &notes);
        });
        // The renderer fetches the manifest and the book's resources from the scheme, so
        // the scheme is an origin fetch may use and a secure one; neither opens a way out.
        if let Some(security) = context.security_manager() {
            security.register_uri_scheme_as_cors_enabled(SCHEME);
            security.register_uri_scheme_as_secure(SCHEME);
        }

        let manager = webkit::UserContentManager::new();
        if guards.filter {
            let store = webkit::UserContentFilterStore::new(&filter_dir.to_string_lossy());
            let filter = store
                .save_future(
                    RULE_LIST_ID,
                    &glib::Bytes::from_static(RULE_LIST.as_bytes()),
                )
                .await
                .map_err(|error| format!("the content filter did not compile: {error}"))?;
            manager.add_filter(&filter);
        }
        manager.register_script_message_handler("storyarc", None);

        let settings = webkit::Settings::new();
        settings.set_enable_developer_extras(false);
        settings.set_enable_javascript(true);
        settings.set_javascript_can_open_windows_automatically(false);
        settings.set_allow_file_access_from_file_urls(false);
        settings.set_allow_universal_access_from_file_urls(false);

        let web_view = webkit::WebView::builder()
            .web_context(&context)
            .network_session(&webkit::NetworkSession::new_ephemeral())
            .user_content_manager(&manager)
            .settings(&settings)
            .build();
        if guards.policy {
            web_view.connect_decide_policy(decide);
        }
        Ok(Self {
            web_view,
            requests,
            manager,
        })
    }

    /// Loads the reader page, which opens the book.
    pub fn open_reader(&self) {
        self.web_view.load_uri(&epub_host::reader_uri());
    }

    /// Hands one message to the renderer.
    pub fn send(&self, message_json: &str) {
        self.web_view.evaluate_javascript(
            &epub_host::receive_script(message_json),
            None,
            None,
            None::<&gio::Cancellable>,
            |_| {},
        );
    }

    /// Every message the renderer posts, as the JSON text it posted.
    pub fn connect_message(&self, on_message: impl Fn(String) + 'static) {
        self.manager
            .connect_script_message_received(Some("storyarc"), move |_, value| {
                on_message(value.to_str().to_string());
            });
    }
}

fn answer(
    request: &webkit::URISchemeRequest,
    served: &dyn Served,
    header: bool,
    notes: &RefCell<Vec<RequestNote>>,
) {
    let uri = request.uri().map(|uri| uri.to_string()).unwrap_or_default();
    let range = request
        .http_headers()
        .and_then(|headers| headers.one("Range"))
        .map(|value| value.to_string());
    let found = match Route::of(&uri) {
        Some(Route::Reader) => Some((
            epub_host::reader_page(
                &served.positions_json(),
                served.locator_json().as_deref(),
                served.preferences_json().as_deref(),
            )
                .into_bytes(),
            "text/html".to_owned(),
        )),
        Some(Route::Bundle) => Some((epub_host::BUNDLE.to_vec(), "text/javascript".to_owned())),
        Some(Route::Manifest) => Some((
            served.manifest_json().into_bytes(),
            "application/webpub+json".to_owned(),
        )),
        Some(Route::Resource(path)) => served.resource(&path),
        None => None,
    };
    let path = uri
        .split_once("://")
        .and_then(|(_, rest)| rest.split_once('/'))
        .map(|(_, path)| format!("/{path}"))
        .unwrap_or(uri.clone());
    let Some((body, media_type)) = found else {
        notes.borrow_mut().push(RequestNote {
            method: request
                .http_method()
                .map(|m| m.to_string())
                .unwrap_or_default(),
            path,
            range,
            status: 404,
        });
        let mut error =
            glib::Error::new(gio::IOErrorEnum::NotFound, "no such resource in the book");
        request.finish_error(&mut error);
        return;
    };
    let answer = Answer::of(body, range.as_deref());
    notes.borrow_mut().push(RequestNote {
        method: request
            .http_method()
            .map(|m| m.to_string())
            .unwrap_or_default(),
        path,
        range,
        status: answer.status,
    });
    let length = i64::try_from(answer.body.len()).unwrap_or(-1);
    let stream = gio::MemoryInputStream::from_bytes(&glib::Bytes::from_owned(answer.body));
    let response = webkit::URISchemeResponse::new(&stream, length);
    response.set_status(answer.status, None);
    response.set_content_type(&media_type);
    let headers = soup::MessageHeaders::new(soup::MessageHeadersType::Response);
    if header {
        headers.append("Content-Security-Policy", CSP);
    }
    headers.append("Accept-Ranges", "bytes");
    headers.append("Cache-Control", "no-store");
    if let Some((first, last, total)) = answer.range {
        headers.set_content_range(
            i64::try_from(first).unwrap_or(0),
            i64::try_from(last).unwrap_or(0),
            i64::try_from(total).unwrap_or(0),
        );
    }
    response.set_http_headers(headers);
    request.finish_with_response(&response);
}

/// A navigation inside the scheme goes ahead; a web link opens in the system's browser
/// and the book stays; anything else is dropped. Responses are left to WebKit.
fn decide(
    view: &webkit::WebView,
    decision: &webkit::PolicyDecision,
    kind: webkit::PolicyDecisionType,
) -> bool {
    if kind != webkit::PolicyDecisionType::NavigationAction
        && kind != webkit::PolicyDecisionType::NewWindowAction
    {
        return false;
    }
    let uri = decision
        .downcast_ref::<webkit::NavigationPolicyDecision>()
        .and_then(|navigation| navigation.navigation_action())
        .and_then(|action| action.request())
        .and_then(|request| request.uri())
        .map(|uri| uri.to_string())
        .unwrap_or_default();
    match epub_host::navigation_for(&uri) {
        Navigation::Allow if kind == webkit::PolicyDecisionType::NavigationAction => {
            decision.use_();
        }
        Navigation::OpenOutside => {
            decision.ignore();
            if let Some((uri, host)) = outward(&uri) {
                confirm_leaving(view.upcast_ref(), uri, &host);
            }
        }
        _ => decision.ignore(),
    }
    true
}

#[cfg(test)]
mod tests {
    //! The egress proof. One test function, because GTK binds to the first thread that
    //! initialises it and the test harness gives each test its own thread.

    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    use super::*;

    /// The listener on the far side: counts every connection that arrives, whatever it
    /// carries, because a connection accepted at all is an arrival (ADR-0015).
    struct Collector {
        origin: String,
        arrivals: Arc<AtomicUsize>,
    }

    impl Collector {
        fn start() -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").expect("a loopback port");
            let origin = format!("http://{}", listener.local_addr().expect("an address"));
            let arrivals = Arc::new(AtomicUsize::new(0));
            let count = arrivals.clone();
            std::thread::spawn(move || {
                for stream in listener.incoming().flatten() {
                    count.fetch_add(1, Ordering::SeqCst);
                    let mut stream = stream;
                    let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
                    let mut sink = [0u8; 1024];
                    let _ = stream.read(&mut sink);
                    let _ = stream.write_all(
                        b"HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\n\r\n",
                    );
                }
            });
            Self { origin, arrivals }
        }

        fn arrivals(&self) -> usize {
            self.arrivals.load(Ordering::SeqCst)
        }
    }

    /// A book whose one page is the eight-vector page, plus a page of ordinary
    /// subresources and a media file for the range record.
    struct EgressBook;

    const EGRESS_PAGE: &str = include_str!("../../desktop-web/epub/test/egress.html");

    const RESOURCES_PAGE: &str = r#"<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="style.css"><script src="script.js"></script></head>
<body><img src="picture.png" alt=""><audio src="sound.mp3" preload="auto"></audio>
<script>fetch("data.json").then(function(){}).catch(function(){});</script></body></html>"#;

    impl Served for EgressBook {
        fn resource(&self, path: &str) -> Option<(Vec<u8>, String)> {
            let (body, media_type): (Vec<u8>, &str) = match path {
                "egress.html" => (EGRESS_PAGE.as_bytes().to_vec(), "text/html"),
                "resources.html" => (RESOURCES_PAGE.as_bytes().to_vec(), "text/html"),
                "style.css" => (b"body{color:#333}".to_vec(), "text/css"),
                "script.js" => (b"window.loaded=true;".to_vec(), "text/javascript"),
                "data.json" => (b"{}".to_vec(), "application/json"),
                "picture.png" => (vec![0x89, b'P', b'N', b'G'], "image/png"),
                "sound.mp3" => (vec![0u8; 64 * 1024], "audio/mpeg"),
                _ => return None,
            };
            Some((body, media_type.to_owned()))
        }
        fn manifest_json(&self) -> String {
            "{}".to_owned()
        }
        fn positions_json(&self) -> String {
            "[]".to_owned()
        }
        fn locator_json(&self) -> Option<String> {
            None
        }
    }

    fn pump(seconds: f64) {
        let context = glib::MainContext::default();
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        while Instant::now() < end {
            context.iteration(false);
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    fn build(guards: Guards, dir: &Path) -> EpubView {
        glib::MainContext::default()
            .block_on(EpubView::build(Rc::new(EgressBook), dir, guards))
            .expect("a view")
    }

    fn page_uri(page: &str, collector: &Collector) -> String {
        format!(
            "{SCHEME}://{}/{page}?collector={}",
            epub_host::BOOK_HOST,
            collector.origin
        )
    }

    #[test]
    fn the_eight_vector_page_reaches_nothing_through_the_guarded_view() {
        crate::display_test::on_display(egress_on_a_display);
    }

    fn egress_on_a_display() {
        let dir = tempfile::tempdir().expect("a folder for the filter store");
        let window = gtk::Window::new();

        // Control: with no guard the page reaches the collector, so the collector hears
        // and the page fires. Without this, zero would prove nothing.
        let control = Collector::start();
        let open = build(Guards::NONE, dir.path());
        window.set_child(Some(&open.web_view));
        window.present();
        open.web_view.load_uri(&page_uri("egress.html", &control));
        pump(6.0);
        let heard = control.arrivals();
        eprintln!("control: {heard} arrivals of 8 attempts through an unguarded view");
        assert!(
            heard >= 1,
            "the collector heard nothing from an unguarded page"
        );

        // The proof: the same page through the guarded view, zero arrivals.
        let collector = Collector::start();
        let guarded = build(Guards::ALL, dir.path());
        window.set_child(Some(&guarded.web_view));
        guarded
            .web_view
            .load_uri(&page_uri("egress.html", &collector));
        pump(6.0);
        let arrivals = collector.arrivals();
        eprintln!("guarded: {arrivals} arrivals of 8 attempts");
        assert_eq!(arrivals, 0, "a vector left the guarded view");

        // The record the design asks for: do subresources and media come through the
        // handler, and does WebKitGTK ask for ranges? Printed with --nocapture.
        guarded.requests.borrow_mut().clear();
        guarded
            .web_view
            .load_uri(&page_uri("resources.html", &collector));
        pump(4.0);
        let notes = guarded.requests.borrow();
        for note in notes.iter() {
            eprintln!(
                "handler: {} {} range={:?} -> {}",
                note.method, note.path, note.range, note.status
            );
        }
        for expected in [
            "/resources.html",
            "/style.css",
            "/script.js",
            "/picture.png",
            "/data.json",
        ] {
            assert!(
                notes
                    .iter()
                    .any(|note| note.path.split('?').next() == Some(expected)),
                "{expected} did not come through the scheme handler"
            );
        }
        assert_eq!(
            collector.arrivals(),
            0,
            "the resources page reached the collector"
        );
        drop(notes);

        // The pinned bundle over the core's manifest and positions: the corpus book opens
        // through the guarded view and the renderer reports where it is.
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/ebooks/fixture.epub");
        let source = storyarc_core::io::source::FileSource::open(&path).expect("the fixture");
        let publication = storyarc_core::epub::WebPublication::open(
            std::sync::Arc::new(source),
            &epub_host::manifest_uri(),
        )
        .expect("the manifest and positions");
        let positions = publication.positions().len();
        let book: Rc<dyn Served> = Rc::new(crate::epub_window::Book::new(publication, None));
        let reader = glib::MainContext::default()
            .block_on(EpubView::build(book, dir.path(), Guards::ALL))
            .expect("a view");
        let messages: Rc<RefCell<Vec<String>>> = Rc::default();
        let heard = messages.clone();
        reader.connect_message(move |json| heard.borrow_mut().push(json));
        window.set_child(Some(&reader.web_view));
        reader.open_reader();
        pump(10.0);
        let messages = messages.borrow();
        for message in messages.iter() {
            eprintln!("renderer: {}", &message[..message.len().min(160)]);
        }
        assert!(
            messages.iter().any(|m| m.contains("\"type\":\"ready\"")),
            "the renderer never said ready over the scheme: {messages:?}"
        );
        // The first locator follows the first frame's layout, which the software renderer
        // of a headless container reaches late or not at all; it is recorded, not required.
        eprintln!(
            "renderer: locator within ten seconds: {}",
            messages.iter().any(|m| m.contains("\"type\":\"locator\""))
        );
        assert!(
            !messages.iter().any(|m| m.contains("host-error")),
            "{messages:?}"
        );
        assert_eq!(positions, 2, "the fixture has two positions");
        for note in reader.requests.borrow().iter() {
            eprintln!("book: {} {} -> {}", note.method, note.path, note.status);
        }
    }
}

/// A link out of the book: its address and host when it is `http` or `https` with a host; any other scheme is
/// dropped rather than handed on.
pub(crate) fn outward(href: &str) -> Option<(String, String)> {
    let uri = glib::Uri::parse(href, glib::UriFlags::NONE).ok()?;
    let host = uri.host()?.to_string();
    let web = matches!(uri.scheme().to_ascii_lowercase().as_str(), "http" | "https");
    (web && !host.is_empty()).then(|| (href.to_owned(), host))
}

/// Names the host a link goes to and opens the system browser only on a yes: the reader leaves the book on a
/// publication's say-so (`ebook-reader`, *Following a link out of the publication*).
pub(crate) fn confirm_leaving(parent: &gtk::Widget, uri: String, host: &str) {
    use adw::prelude::*;
    let dialog = adw::AlertDialog::new(
        Some(&tr_args(
            "desktop.w4.epub.leave.title___",
            "Open a page on %@?",
            &[&host],
        )),
        Some(&uri),
    );
    dialog.add_responses(&[
        (
            "stay",
            &tr("desktop.w4.epub.leave.stay", "Stay in the Book"),
        ),
        ("open", &tr("desktop.w4.epub.leave.open", "Open in Browser")),
    ]);
    dialog.set_close_response("stay");
    dialog.set_default_response(Some("stay"));
    let window = parent.root().and_downcast::<gtk::Window>();
    dialog.connect_response(None, move |_, response| {
        if response == "open" {
            gtk::UriLauncher::new(&uri).launch(window.as_ref(), None::<&gio::Cancellable>, |_| {});
        }
    });
    dialog.present(Some(parent));
}

#[cfg(test)]
mod link_tests {
    use super::outward;

    #[test]
    fn only_a_web_address_with_a_host_leaves_the_book() {
        let (_, host) = outward("https://example.org/a").expect("https is followed");
        assert_eq!(host, "example.org");
        assert!(outward("HTTP://example.org").is_some());
        for refused in [
            "file:///etc/hosts",
            "mailto:a@b.org",
            "javascript:alert(1)",
            "storyarc://open",
            "http://",
        ] {
            assert!(outward(refused).is_none(), "{refused} was followed");
        }
    }
}
