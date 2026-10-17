//! What the EPUB web view is owed, as pure rules (task 4.10; design.md, Decision 6).
//!
//! The renderer is the pinned Readium bundle of `apps/desktop-web/epub`. The host serves
//! it, the book's resources and the reader page through one custom URI scheme, and denies
//! every other way out three times over: a content filter with the same rules as iOS, a
//! Content-Security-Policy header on every answer, and a navigation policy that hands a
//! web link to the system's browser. `desktop-experience`, A book stays off the network
//! on every desktop. The GTK side is `epub_view.rs`; this file tests on any host.

/// The scheme the web view loads everything from: `storyarc-epub://<book>/<path>`.
pub const SCHEME: &str = "storyarc-epub";

/// The host part under which the open book is served. One web view reads one book, so
/// one host is enough and a second book gets its own web view.
pub const BOOK_HOST: &str = "book";

/// The paths the host itself answers, under a folder no EPUB may use (a container path
/// never starts with a dot folder of this name).
pub const READER_PATH: &str = "/.storyarc/reader.html";
pub const BUNDLE_PATH: &str = "/.storyarc/storyarc-epub.js";
pub const MANIFEST_PATH: &str = "/.storyarc/manifest.json";

/// The built renderer, committed by `apps/desktop-web/epub` and embedded here because
/// the Linux build runs no node.
pub const BUNDLE: &[u8] = include_bytes!("../../desktop-web/epub/dist/storyarc-epub.js");

/// The same rule list as iOS (`PublicationEgress.rules`): block everything, then let the
/// app's own scheme, `about:`, `data:` and `blob:` through. WebKitGTK compiles the same
/// JSON as WebKit on iOS does.
pub const RULE_LIST: &str = r#"[
  { "trigger": { "url-filter": ".*" }, "action": { "type": "block" } },
  { "trigger": { "url-filter": "^storyarc-epub://" }, "action": { "type": "ignore-previous-rules" } },
  { "trigger": { "url-filter": "^about:" }, "action": { "type": "ignore-previous-rules" } },
  { "trigger": { "url-filter": "^data:" }, "action": { "type": "ignore-previous-rules" } },
  { "trigger": { "url-filter": "^blob:" }, "action": { "type": "ignore-previous-rules" } }
]"#;

/// The identifier the compiled filter is stored under.
pub const RULE_LIST_ID: &str = "com.mecedric.StoryArc.publication-egress";

/// The Content-Security-Policy every answer carries: nothing but the scheme itself,
/// inline script and style (the renderer and the book need both), and `data:` and `blob:`
/// for what the renderer makes. No form, no base, no plugin, no connection elsewhere.
pub const CSP: &str = "default-src 'none'; \
script-src storyarc-epub: 'unsafe-inline'; \
style-src storyarc-epub: 'unsafe-inline'; \
img-src storyarc-epub: data: blob:; \
font-src storyarc-epub: data:; \
media-src storyarc-epub: blob:; \
connect-src storyarc-epub: blob:; \
frame-src storyarc-epub: blob:; \
child-src storyarc-epub: blob:; \
form-action 'none'; base-uri 'none'";

/// What a request under the scheme asks for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Route {
    /// The reader page that loads the bundle around the book.
    Reader,
    /// The bundle itself.
    Bundle,
    /// The manifest the core built.
    Manifest,
    /// A resource of the book, by its container path (no leading slash).
    Resource(String),
}

impl Route {
    /// Reads a URI of the scheme. Anything not under the book's host, or not under the
    /// scheme, is `None`, and the caller answers not found.
    pub fn of(uri: &str) -> Option<Self> {
        let rest = uri.strip_prefix(SCHEME)?.strip_prefix("://")?;
        let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
        if host != BOOK_HOST {
            return None;
        }
        let path = path.split(['?', '#']).next().unwrap_or("");
        let path = format!("/{path}");
        Some(match path.as_str() {
            READER_PATH => Self::Reader,
            BUNDLE_PATH => Self::Bundle,
            MANIFEST_PATH => Self::Manifest,
            _ => Self::Resource(percent_decode(&path[1..])),
        })
    }
}

/// `%xx` escapes undone, so a container path with a space is found in the ZIP.
fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(value) = u8::from_str_radix(&text[i + 1..i + 3], 16)
        {
            out.push(value);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// The URI the web view loads to read the book.
pub fn reader_uri() -> String {
    format!("{SCHEME}://{BOOK_HOST}{READER_PATH}")
}

/// The URI the manifest is served at, which is also the manifest's own `self` link.
pub fn manifest_uri() -> String {
    format!("{SCHEME}://{BOOK_HOST}{MANIFEST_PATH}")
}

/// The media type for a path the package does not describe, from its extension.
pub fn media_type_for(path: &str) -> &'static str {
    let extension = path.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    match extension.as_str() {
        "xhtml" | "xht" => "application/xhtml+xml",
        "html" | "htm" => "text/html",
        "css" => "text/css",
        "js" | "mjs" => "text/javascript",
        "json" => "application/json",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "otf" => "font/otf",
        "ttf" => "font/ttf",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        "mp3" => "audio/mpeg",
        "m4a" | "mp4" => "audio/mp4",
        "ogg" | "oga" => "audio/ogg",
        "ncx" => "application/x-dtbncx+xml",
        "opf" => "application/oebps-package+xml",
        _ => "application/octet-stream",
    }
}

/// One answer to a request: the bytes to send, the status, and the content range when
/// the request asked for one. WebKitGTK may ask for a range of a media file; the host
/// answers it the way an HTTP server would, so the renderer's audio and video seek.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Answer {
    pub status: u32,
    pub body: Vec<u8>,
    /// `(first, last, total)` for a 206, as `Content-Range: bytes first-last/total`.
    pub range: Option<(u64, u64, u64)>,
}

impl Answer {
    /// The whole resource, or the part a `Range: bytes=first-last` header asks for. A
    /// range that cannot be satisfied answers 416 with no body, as HTTP does.
    pub fn of(body: Vec<u8>, range_header: Option<&str>) -> Self {
        let total = body.len() as u64;
        let Some(range) = range_header.and_then(|header| parse_range(header, total)) else {
            if range_header.is_some() {
                return Self {
                    status: 416,
                    body: Vec::new(),
                    range: None,
                };
            }
            return Self {
                status: 200,
                body,
                range: None,
            };
        };
        let (first, last) = range;
        Self {
            status: 206,
            body: body[first as usize..=last as usize].to_vec(),
            range: Some((first, last, total)),
        }
    }
}

/// `bytes=first-last`, `bytes=first-` or `bytes=-suffix`, clamped to the resource, or
/// `None` when it names nothing inside it.
fn parse_range(header: &str, total: u64) -> Option<(u64, u64)> {
    let spec = header.trim().strip_prefix("bytes=")?.trim();
    if total == 0 || spec.contains(',') {
        return None;
    }
    let (first, last) = spec.split_once('-')?;
    let (first, last) = if first.is_empty() {
        let suffix: u64 = last.trim().parse().ok()?;
        if suffix == 0 {
            return None;
        }
        (total.saturating_sub(suffix), total - 1)
    } else {
        let first: u64 = first.trim().parse().ok()?;
        let last: u64 = if last.trim().is_empty() {
            total - 1
        } else {
            last.trim().parse::<u64>().ok()?.min(total - 1)
        };
        (first, last)
    };
    (first <= last && first < total).then_some((first, last))
}

/// The reader page: the bundle, the host door, and `StoryArcEpub.open` over the manifest
/// and positions the core built. The locator, when the reader has one, is where it opens.
/// Everything inline except the bundle, so the page needs the scheme and nothing else.
pub fn reader_page(positions_json: &str, locator_json: Option<&str>) -> String {
    let locator = locator_json.unwrap_or("null");
    format!(
        r#"<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StoryArc</title>
<style>html,body{{margin:0;height:100%;overflow:hidden;background:transparent}}#book{{position:absolute;inset:0}}</style>
<script src="{BUNDLE_PATH}"></script>
</head><body><div id="book"></div>
<script>
(async function () {{
  "use strict";
  var post = function (message) {{
    window.webkit.messageHandlers.storyarc.postMessage(JSON.stringify(message));
  }};
  try {{
    var response = await fetch("{MANIFEST_PATH}");
    var manifest = await response.json();
    var reader = StoryArcEpub.open({{
      container: document.getElementById("book"),
      manifest: manifest,
      positions: {positions_json},
      locator: {locator},
      post: post
    }});
    window.__storyarc = reader;
  }} catch (error) {{
    post({{ type: "host-error", seq: 0, message: String(error && error.message || error) }});
  }}
}})();
</script></body></html>
"#
    )
}

/// The JavaScript that hands one host message to the renderer.
pub fn receive_script(message_json: &str) -> String {
    format!("window.__storyarc && window.__storyarc.receive({message_json});")
}

/// Whether a navigation the page asks for may happen inside the web view. Only the
/// scheme itself and `about:blank` may; a web link goes to the system's browser and
/// anything else is dropped (`ebook-reader`, Following a link out of the publication).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Navigation {
    Allow,
    OpenOutside,
    Drop,
}

pub fn navigation_for(uri: &str) -> Navigation {
    let scheme = uri.split(':').next().unwrap_or("").to_ascii_lowercase();
    match scheme.as_str() {
        s if s == SCHEME => Navigation::Allow,
        "about" | "blob" => Navigation::Allow,
        "http" | "https" => Navigation::OpenOutside,
        _ => Navigation::Drop,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_rule_list_blocks_everything_and_then_lets_the_scheme_through() {
        let rules: serde_json::Value = serde_json::from_str(RULE_LIST).expect("valid JSON");
        let rules = rules.as_array().expect("an array");
        assert_eq!(rules[0]["trigger"]["url-filter"], ".*");
        assert_eq!(rules[0]["action"]["type"], "block");
        let allowed: Vec<&str> = rules[1..]
            .iter()
            .map(|rule| rule["trigger"]["url-filter"].as_str().unwrap())
            .collect();
        assert_eq!(
            allowed,
            ["^storyarc-epub://", "^about:", "^data:", "^blob:"]
        );
        assert!(
            rules[1..]
                .iter()
                .all(|rule| rule["action"]["type"] == "ignore-previous-rules")
        );
    }

    #[test]
    fn the_header_names_no_source_but_the_scheme() {
        for directive in CSP.split(';').map(str::trim).filter(|d| !d.is_empty()) {
            let mut words = directive.split_whitespace();
            let name = words.next().unwrap();
            for source in words {
                assert!(
                    matches!(
                        source,
                        "'none'"
                            | "'self'"
                            | "'unsafe-inline'"
                            | "storyarc-epub:"
                            | "data:"
                            | "blob:"
                    ),
                    "{name} allows {source}"
                );
            }
        }
        assert!(CSP.starts_with("default-src 'none'"));
        assert!(CSP.contains("form-action 'none'"));
    }

    #[test]
    fn routes_read_the_host_the_path_and_the_escapes() {
        assert_eq!(Route::of(&reader_uri()), Some(Route::Reader));
        assert_eq!(
            Route::of("storyarc-epub://book/.storyarc/storyarc-epub.js?v=1"),
            Some(Route::Bundle)
        );
        assert_eq!(Route::of(&manifest_uri()), Some(Route::Manifest));
        assert_eq!(
            Route::of("storyarc-epub://book/OEBPS/ch%201.xhtml#p2"),
            Some(Route::Resource("OEBPS/ch 1.xhtml".into()))
        );
        assert_eq!(Route::of("storyarc-epub://other/OEBPS/a.xhtml"), None);
        assert_eq!(Route::of("https://book/OEBPS/a.xhtml"), None);
    }

    #[test]
    fn media_types_come_from_the_extension_when_the_package_has_none() {
        assert_eq!(media_type_for("OEBPS/ch1.xhtml"), "application/xhtml+xml");
        assert_eq!(media_type_for("fonts/A.WOFF2"), "font/woff2");
        assert_eq!(media_type_for("mystery"), "application/octet-stream");
    }

    #[test]
    fn a_range_answers_the_part_and_a_bad_one_416() {
        let body: Vec<u8> = (0..10).collect();
        let whole = Answer::of(body.clone(), None);
        assert_eq!(
            (whole.status, whole.body.len(), whole.range),
            (200, 10, None)
        );
        let part = Answer::of(body.clone(), Some("bytes=2-4"));
        assert_eq!(part.status, 206);
        assert_eq!(part.body, vec![2, 3, 4]);
        assert_eq!(part.range, Some((2, 4, 10)));
        let tail = Answer::of(body.clone(), Some("bytes=7-"));
        assert_eq!(
            (tail.body.clone(), tail.range),
            (vec![7, 8, 9], Some((7, 9, 10)))
        );
        let suffix = Answer::of(body.clone(), Some("bytes=-3"));
        assert_eq!(suffix.body, vec![7, 8, 9]);
        let past = Answer::of(body.clone(), Some("bytes=2-99"));
        assert_eq!(past.range, Some((2, 9, 10)));
        let bad = Answer::of(body, Some("bytes=12-"));
        assert_eq!((bad.status, bad.body.len()), (416, 0));
    }

    #[test]
    fn the_reader_page_needs_the_scheme_and_nothing_else() {
        let page = reader_page("[]", Some(r#"{"href":"a"}"#));
        assert!(page.contains(&format!(r#"src="{BUNDLE_PATH}""#)));
        assert!(page.contains(&format!(r#"fetch("{MANIFEST_PATH}")"#)));
        assert!(page.contains(r#"locator: {"href":"a"}"#));
        assert!(!page.contains("http://") && !page.contains("https://"));
        assert!(reader_page("[]", None).contains("locator: null"));
        assert_eq!(
            receive_script(r#"{"type":"next"}"#),
            r#"window.__storyarc && window.__storyarc.receive({"type":"next"});"#
        );
    }

    #[test]
    fn a_web_link_opens_outside_and_the_rest_is_dropped() {
        assert_eq!(navigation_for(&reader_uri()), Navigation::Allow);
        assert_eq!(navigation_for("about:blank"), Navigation::Allow);
        assert_eq!(
            navigation_for("HTTPS://example.org/x"),
            Navigation::OpenOutside
        );
        assert_eq!(navigation_for("file:///etc/passwd"), Navigation::Drop);
        assert_eq!(navigation_for("javascript:alert(1)"), Navigation::Drop);
    }

    #[test]
    fn the_bundle_is_the_pinned_build() {
        assert!(
            BUNDLE.starts_with(b"/*!"),
            "the BSD banner leads the bundle"
        );
        assert!(BUNDLE.len() > 100_000);
    }
}
