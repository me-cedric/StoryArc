//! OPDS catalogues (task 3.4 of `desktop-clients`).
//!
//! Three kinds of case. The parsing cases are StoryArcKit's `OpdsParsingTests`, fixture for
//! fixture and expectation for expectation, so the two readers answer the same feed alike.
//! The fixture cases run against `pnpm opds` (`scripts/opds-server.mjs`, port 4444, or
//! `STORYARC_OPDS_URL`) and skip with a line on stderr when it does not answer. The origin,
//! downgrade and certificate cases bring their own servers on ephemeral ports.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};

use storyarc_core::net::{Challenge, Credential, HttpClient, TrustStore, Url};
use storyarc_core::runtime::Runtime;
use storyarc_core::sources::opds::{
    AcquisitionKind, OpdsCatalogue, OpdsError, OpdsFeed, OpdsVersion, Received, SearchOutcome,
    parse,
};

fn base() -> Url {
    Url::parse("https://library.example/opds/").unwrap()
}

fn feed(text: &str) -> OpdsFeed {
    parse(text.as_bytes(), None, &base()).unwrap()
}

fn http() -> HttpClient {
    HttpClient::new(&Runtime::new().unwrap(), TrustStore::new()).unwrap()
}

// ---- StoryArcKit's OpdsParsingTests, OPDS 1.2 -----------------------------------------------

const ATOM_NAVIGATION: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>Example Library</title>
  <link rel="self" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
  <link rel="start" href="/opds/" type="application/atom+xml;profile=opds-catalog"/>
  <link rel="search" href="/opds/search?q={searchTerms}"
        type="application/atom+xml"/>
  <link rel="subsection" href="unread" title="Unread" opds:count="12"
        type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <link rel="subsection" href="series" title="Series"
        type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
</feed>"#;

const ATOM_ACQUISITION: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Unread</title>
  <link rel="next" href="unread?page=2" type="application/atom+xml"/>
  <link rel="http://opds-spec.org/facet" href="?lang=en" title="English"
        opds:facetGroup="Language" opds:activeFacet="true" thr:count="40"
        xmlns:opds="http://opds-spec.org/2010/catalog"
        xmlns:thr="http://purl.org/syndication/thread/1.0"/>
  <entry>
    <title>The Long Field</title>
    <id>urn:uuid:1</id>
    <updated>2026-08-01T10:00:00Z</updated>
    <author><name>Ada Lovelace</name></author>
    <summary>A field, at length.</summary>
    <link rel="http://opds-spec.org/image" href="cover/1.jpg" type="image/jpeg"/>
    <link rel="http://opds-spec.org/image/thumbnail" href="thumb/1.jpg" type="image/jpeg"/>
    <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
          type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition" href="download/1.pdf"
          type="application/pdf"/>
  </entry>
  <entry>
    <title>Borrowed Only</title>
    <id>urn:uuid:2</id>
    <link rel="http://opds-spec.org/acquisition/borrow" href="borrow/2"
          type="application/epub+zip"/>
  </entry>
  <entry>
    <id>urn:uuid:3</id>
  </entry>
</feed>"#;

#[test]
fn atom_navigation_feed_yields_sections() {
    let feed = feed(ATOM_NAVIGATION);
    assert_eq!(feed.version, OpdsVersion::Atom);
    assert_eq!(feed.title, "Example Library");
    assert!(feed.publications.is_empty());
    let titles: Vec<_> = feed.navigation.iter().map(|s| s.title.as_str()).collect();
    assert_eq!(titles, ["Unread", "Series"]);
    assert_eq!(
        feed.navigation[0].href.as_str(),
        "https://library.example/opds/unread"
    );
    assert_eq!(
        feed.search_template.as_deref(),
        Some("https://library.example/opds/search?q={searchTerms}")
    );
}

#[test]
fn self_start_and_up_are_not_sections_and_a_count_is_read_when_given() {
    let feed = feed(ATOM_NAVIGATION);
    assert_eq!(feed.navigation.len(), 2);
    assert_eq!(feed.navigation[0].count, Some(12));
    assert_eq!(feed.navigation[1].count, None);
}

#[test]
fn atom_acquisition_feed_yields_entries() {
    let feed = feed(ATOM_ACQUISITION);
    assert!(feed.is_acquisition());
    let titles: Vec<_> = feed.publications.iter().map(|e| e.title.as_str()).collect();
    assert_eq!(
        titles,
        ["The Long Field", "Borrowed Only"],
        "an untitled entry is dropped"
    );
    assert_eq!(
        feed.next.as_ref().unwrap().as_str(),
        "https://library.example/opds/unread?page=2"
    );
    let first = &feed.publications[0];
    assert_eq!(first.authors, ["Ada Lovelace"]);
    assert_eq!(first.summary.as_deref(), Some("A field, at length."));
    assert!(
        first
            .cover
            .as_ref()
            .unwrap()
            .path()
            .ends_with("cover/1.jpg")
    );
    assert!(first.thumbnail.as_ref().unwrap().path().contains("thumb"));
    assert!(first.updated.is_some());
    let types: Vec<_> = first
        .acquisitions
        .iter()
        .map(|a| a.media_type.as_str())
        .collect();
    assert_eq!(types, ["application/epub+zip", "application/pdf"]);
    assert!(
        first
            .acquisitions
            .iter()
            .all(|a| a.kind == AcquisitionKind::Direct)
    );
}

#[test]
fn facets_carry_their_group_and_active_state() {
    let feed = feed(ATOM_ACQUISITION);
    let facet = &feed.facets[0];
    assert_eq!(facet.group, "Language");
    assert_eq!(facet.title, "English");
    assert!(facet.is_active);
    assert_eq!(facet.count, Some(40));
}

#[test]
fn a_borrow_link_is_named_rather_than_dropped() {
    let feed = feed(ATOM_ACQUISITION);
    let borrowed = feed.publications.last().unwrap();
    let kinds: Vec<_> = borrowed.acquisitions.iter().map(|a| a.kind).collect();
    assert_eq!(kinds, [AcquisitionKind::Borrow]);
    assert!(!kinds[0].is_fetchable());
    assert_eq!(borrowed.unsupported_kinds(), [AcquisitionKind::Borrow]);
}

fn one_link(link: &str) -> AcquisitionKind {
    let xml = format!(
        r#"<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog"><title>t</title><entry><title>e</title>{link}</entry></feed>"#
    );
    feed(&xml).publications[0].acquisitions[0].kind
}

#[test]
fn open_access_unknown_relations_and_protected_types_are_told_apart() {
    assert_eq!(
        one_link(
            r#"<link rel="http://opds-spec.org/acquisition/open-access" href="free.epub" type="application/epub+zip"/>"#
        ),
        AcquisitionKind::Open
    );
    assert_eq!(
        one_link(
            r#"<link rel="http://opds-spec.org/acquisition/lend-later" href="x" type="application/epub+zip"/>"#
        ),
        AcquisitionKind::Indirect
    );
    assert_eq!(
        one_link(
            r#"<link rel="http://opds-spec.org/acquisition" href="x.lcpl" type="application/vnd.readium.lcp.license.v1.0+json"/>"#
        ),
        AcquisitionKind::Indirect
    );
    assert_eq!(
        one_link(
            r#"<link rel="http://opds-spec.org/acquisition" href="x.acsm" type="application/vnd.adobe.adept+xml"/>"#
        ),
        AcquisitionKind::Indirect
    );
}

#[test]
fn an_indirect_acquisition_child_marks_the_link_indirect_and_keeps_its_type() {
    let xml = r#"<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
    <title>t</title><entry><title>e</title>
    <link rel="http://opds-spec.org/acquisition" href="x.epub" type="application/epub+zip">
      <opds:indirectAcquisition type="application/vnd.readium.lcp.license.v1.0+json"/>
    </link></entry></feed>"#;
    let acquisition = &feed(xml).publications[0].acquisitions[0];
    assert_eq!(acquisition.kind, AcquisitionKind::Indirect);
    assert_eq!(acquisition.media_type, "application/epub+zip");
    // The common case, a self-closing link with no child, is untouched.
    let kinds: Vec<_> = feed(ATOM_ACQUISITION).publications[0]
        .acquisitions
        .iter()
        .map(|a| a.kind)
        .collect();
    assert_eq!(kinds, [AcquisitionKind::Direct, AcquisitionKind::Direct]);
}

#[test]
fn an_entry_with_one_atom_link_and_no_acquisition_is_a_section() {
    let xml = r#"<feed xmlns="http://www.w3.org/2005/Atom" xmlns:thr="http://purl.org/syndication/thread/1.0">
      <title>Calibre-Web</title>
      <entry><title>Unread</title><id>urn:uuid:unread</id>
        <link rel="subsection" href="unread" thr:count="12"
              type="application/atom+xml;profile=opds-catalog;kind=navigation"/></entry>
      <entry><title>The Long Field</title><id>urn:uuid:1</id>
        <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
              type="application/epub+zip"/></entry>
    </feed>"#;
    let feed = feed(xml);
    assert_eq!(feed.navigation.len(), 1);
    assert_eq!(feed.navigation[0].title, "Unread");
    assert!(feed.navigation[0].href.path().ends_with("/unread"));
    assert_eq!(feed.navigation[0].count, Some(12));
    assert_eq!(feed.publications[0].title, "The Long Field");

    let both = r#"<feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
    <entry><title>Both</title><id>urn:uuid:2</id>
    <link rel="related" href="series" type="application/atom+xml" title="Series"/>
    <link rel="http://opds-spec.org/acquisition" href="x.epub" type="application/epub+zip"/>
    </entry></feed>"#;
    let both = parse(both.as_bytes(), None, &base()).unwrap();
    assert!(both.navigation.is_empty());
    assert_eq!(both.publications[0].title, "Both");
}

#[test]
fn a_search_link_without_a_template_is_a_description_document() {
    let xml = r#"<feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
    <link rel="search" href="opensearch.xml" type="application/opensearchdescription+xml"/></feed>"#;
    let feed = feed(xml);
    assert!(feed.search_template.is_none());
    assert!(
        feed.search_description
            .unwrap()
            .path()
            .ends_with("opensearch.xml")
    );
}

// ---- StoryArcKit's OpdsParsingTests, OPDS 2.0 (OpdsFixtures.opds2) ---------------------------

const OPDS2: &str = r#"{
  "metadata": { "title": "Example Library" },
  "links": [
    { "rel": "self", "href": "/opds", "type": "application/opds+json" },
    { "rel": ["next"], "href": "/opds?page=2", "type": "application/opds+json" },
    { "rel": "search", "href": "/opds/search{?query}", "templated": true }
  ],
  "navigation": [
    { "title": "Unread", "href": "/opds/unread", "type": "application/opds+json",
      "properties": { "numberOfItems": 12 } }
  ],
  "groups": [
    {
      "metadata": { "title": "Recently added" },
      "links": [ { "rel": "self", "href": "/opds/recent", "type": "application/opds+json" } ],
      "navigation": [ { "title": "Series", "href": "/opds/series", "type": "application/opds+json" } ],
      "publications": [
        { "metadata": { "identifier": "urn:uuid:9", "title": "Grouped Title", "author": "Grace Hopper" },
          "links": [ { "href": "/download/9.epub", "type": "application/epub+zip",
                       "rel": "http://opds-spec.org/acquisition" } ] }
      ]
    },
    {
      "publications": [
        { "metadata": { "identifier": "urn:uuid:10", "title": "Untitled Group Member" },
          "links": [ { "href": "/download/10.epub", "type": "application/epub+zip" } ] }
      ]
    }
  ],
  "facets": [
    { "metadata": { "title": "Language" },
      "links": [ { "title": "English", "href": "/opds?lang=en", "properties": { "numberOfItems": 40 } } ] }
  ],
  "publications": [
    {
      "metadata": {
        "title": "Harbour Lights 02",
        "author": [{ "name": "Ada Lovelace" }, "Alan Turing"],
        "belongsTo": { "series": { "name": "Harbour Lights", "position": 2 } },
        "modified": "2026-08-01T10:00:00Z",
        "description": "Second."
      },
      "images": [ { "href": "/cover/2.jpg", "width": 1200 }, { "href": "/thumb/2.jpg", "width": 200 } ],
      "links": [ { "href": "/download/2.epub", "type": "application/epub+zip", "size": 5565 } ]
    }
  ]
}"#;

#[test]
fn a_json_feed_is_detected_and_read() {
    let feed = feed(OPDS2);
    assert_eq!(feed.version, OpdsVersion::Json);
    assert_eq!(feed.title, "Example Library");
    assert_eq!(
        feed.next.unwrap().as_str(),
        "https://library.example/opds?page=2"
    );
    assert_eq!(
        feed.search_template.as_deref(),
        Some("https://library.example/opds/search{?query}")
    );
    assert!(feed.search_description.is_none());
}

#[test]
fn a_named_group_is_its_own_section_and_an_unnamed_one_joins_the_page() {
    let feed = feed(OPDS2);
    assert_eq!(feed.groups.len(), 1);
    let group = &feed.groups[0];
    assert_eq!(group.title, "Recently added");
    assert_eq!(group.publications[0].title, "Grouped Title");
    assert_eq!(group.navigation[0].title, "Series");
    assert_eq!(
        group.more.as_ref().unwrap().as_str(),
        "https://library.example/opds/recent"
    );
    let navigation: Vec<_> = feed.navigation.iter().map(|s| s.title.as_str()).collect();
    assert_eq!(navigation, ["Unread"]);
    let titles: Vec<_> = feed.publications.iter().map(|e| e.title.as_str()).collect();
    assert_eq!(titles, ["Harbour Lights 02", "Untitled Group Member"]);
    assert!(!feed.is_empty());
    assert!(feed.is_acquisition());
}

#[test]
fn authors_images_series_and_sizes_are_read_whichever_shape_they_take() {
    let feed = feed(OPDS2);
    let entry = &feed.publications[0];
    assert_eq!(entry.authors, ["Ada Lovelace", "Alan Turing"]);
    assert_eq!(feed.groups[0].publications[0].authors, ["Grace Hopper"]);
    assert!(entry.cover.as_ref().unwrap().path().starts_with("/cover"));
    assert!(
        entry
            .thumbnail
            .as_ref()
            .unwrap()
            .path()
            .starts_with("/thumb")
    );
    assert_eq!(entry.series.as_deref(), Some("Harbour Lights"));
    assert_eq!(entry.series_index, Some(2.0));
    assert_eq!(entry.acquisitions[0].kind, AcquisitionKind::Direct);
    assert_eq!(entry.acquisitions[0].length, Some(5565));
}

// ---- what arrived instead ------------------------------------------------------------------

#[test]
fn what_arrived_instead_of_a_feed_is_named() {
    let page = "<!DOCTYPE html><html><head><title>Log in</title></head></html>";
    assert_eq!(
        parse(page.as_bytes(), None, &base()).unwrap_err(),
        OpdsError::NotAFeed(Received::Html)
    );
    let xhtml = "<?xml version=\"1.0\"?>\n<html xmlns=\"http://www.w3.org/1999/xhtml\"><body>Nope</body></html>";
    assert_eq!(
        parse(xhtml.as_bytes(), None, &base()).unwrap_err(),
        OpdsError::NotAFeed(Received::Html)
    );
    assert_eq!(
        parse(b"   \n", None, &base()).unwrap_err(),
        OpdsError::Empty
    );
    assert_eq!(
        parse(br#"{"ok":true}"#, None, &base()).unwrap_err(),
        OpdsError::NotAFeed(Received::Unrecognised(Some("application/json".into())))
    );
    assert_eq!(
        parse(b"a,b\n1,2", Some("text/csv"), &base()).unwrap_err(),
        OpdsError::NotAFeed(Received::Unrecognised(Some("text/csv".into())))
    );
    // Several servers send `application/octet-stream` for a good Atom feed.
    let good = parse(
        ATOM_NAVIGATION.as_bytes(),
        Some("application/octet-stream"),
        &base(),
    )
    .unwrap();
    assert_eq!(good.title, "Example Library");
}

// ---- the acquisition the app takes ---------------------------------------------------------

#[test]
fn epub_is_taken_over_pdf_and_an_unreadable_entry_names_its_formats() {
    let feed = feed(ATOM_ACQUISITION);
    let best = feed.publications[0].best_acquisition().unwrap();
    assert_eq!(best.media_type, "application/epub+zip");
    let comic = r#"<feed xmlns="http://www.w3.org/2005/Atom"><title>t</title><entry><title>e</title>
      <link rel="http://opds-spec.org/acquisition" href="a.pdf" type="application/pdf"/>
      <link rel="http://opds-spec.org/acquisition" href="a.cbz" type="application/vnd.comicbook+zip"/>
      </entry><entry><title>f</title>
      <link rel="http://opds-spec.org/acquisition" href="a.cb7" type="application/vnd.comicbook+7z"/>
      <link rel="http://opds-spec.org/acquisition" href="a.mobi" type="application/x-mobipocket-ebook"/>
      </entry></feed>"#;
    let feed = parse(comic.as_bytes(), None, &base()).unwrap();
    assert_eq!(
        feed.publications[0].best_acquisition().unwrap().media_type,
        "application/vnd.comicbook+zip",
        "a comic offered as CBZ and PDF is a comic"
    );
    assert!(feed.publications[1].best_acquisition().is_none());
    assert_eq!(
        feed.publications[1].unreadable_formats(),
        ["CB7", "application/x-mobipocket-ebook"]
    );
}

// ---- against `pnpm opds` -------------------------------------------------------------------

fn fixture() -> Option<Url> {
    let root =
        std::env::var("STORYARC_OPDS_URL").unwrap_or_else(|_| "http://127.0.0.1:4444".into());
    let url = Url::parse(&root).ok()?.join("/opds").ok()?;
    match OpdsCatalogue::new(&http(), url.clone(), None).and_then(|catalogue| catalogue.validate())
    {
        Ok(feed) if feed.title == "StoryArc Test Catalogue" => Some(url),
        _ => {
            eprintln!("skipped: no OPDS fixture at {root} (pnpm opds)");
            None
        }
    }
}

#[test]
fn the_fixture_root_is_confirmed_by_its_title_and_dialect() {
    let Some(root) = fixture() else { return };
    let catalogue = OpdsCatalogue::new(&http(), root, None).unwrap();
    let feed = catalogue.validate().unwrap();
    assert_eq!(feed.version, OpdsVersion::Atom);
    let sections: Vec<_> = feed.navigation.iter().map(|s| s.title.as_str()).collect();
    assert_eq!(sections, ["All publications", "Series", "Members only"]);
    assert!(feed.search_template.is_some());

    let json = catalogue
        .feed(&catalogue.root().join("/opds2").unwrap())
        .unwrap();
    assert_eq!(json.version, OpdsVersion::Json);
    let groups: Vec<_> = json.groups.iter().map(|g| g.title.as_str()).collect();
    assert_eq!(groups, ["Recently added", "Comics"]);
    assert!(
        json.groups[0]
            .more
            .as_ref()
            .unwrap()
            .path()
            .ends_with("/opds2/all")
    );
}

#[test]
fn the_fixture_pages_until_no_next_link_remains() {
    let Some(root) = fixture() else { return };
    let catalogue = OpdsCatalogue::new(&http(), root.clone(), None).unwrap();
    let mut page = catalogue.feed(&root.join("/opds/all").unwrap()).unwrap();
    let mut seen = page.publications.len();
    let mut pages = 1;
    while let Some(next) = page.next.clone() {
        page = catalogue.feed(&next).unwrap();
        seen += page.publications.len();
        pages += 1;
    }
    assert!(pages > 1, "the fixture pages at six a page");
    assert!(seen > 6);
    assert!(
        page.facets
            .iter()
            .any(|f| f.group == "Language" && f.is_active)
    );
}

#[test]
fn a_401_names_its_scheme_and_the_credential_opens_it() {
    let Some(root) = fixture() else { return };
    let anonymous = OpdsCatalogue::new(&http(), root.clone(), None).unwrap();
    assert_eq!(
        anonymous.feed(&root.join("/private").unwrap()).unwrap_err(),
        OpdsError::Unauthorized(Some(Challenge::Basic))
    );
    assert_eq!(
        anonymous.feed(&root.join("/bearer").unwrap()).unwrap_err(),
        OpdsError::Unauthorized(Some(Challenge::Bearer))
    );
    let basic = Credential::Basic {
        username: "ada".into(),
        password: "lovelace".into(),
    };
    let signed = OpdsCatalogue::new(&http(), root.clone(), Some(basic)).unwrap();
    assert_eq!(
        signed.feed(&root.join("/private").unwrap()).unwrap().title,
        "Members only"
    );
    let bearer = Credential::Bearer("storyarc-token".into());
    let token = OpdsCatalogue::new(&http(), root.clone(), Some(bearer)).unwrap();
    assert_eq!(
        token.feed(&root.join("/bearer").unwrap()).unwrap().title,
        "Token only"
    );
}

#[test]
fn the_fixture_names_a_page_an_empty_body_and_a_404() {
    let Some(root) = fixture() else { return };
    let catalogue = OpdsCatalogue::new(&http(), root.clone(), None).unwrap();
    let at = |path: &str| catalogue.feed(&root.join(path).unwrap()).unwrap_err();
    assert_eq!(at("/page"), OpdsError::NotAFeed(Received::Html));
    assert_eq!(at("/empty"), OpdsError::Empty);
    assert_eq!(at("/no-such-route"), OpdsError::Http(404));
}

#[test]
fn search_asks_the_server_and_a_redirect_on_the_same_origin_is_followed() {
    let Some(root) = fixture() else { return };
    let catalogue = OpdsCatalogue::new(&http(), root.clone(), None).unwrap();
    let feed = catalogue.validate().unwrap();
    let SearchOutcome::Server(found) = catalogue.search(&feed, "tidal").unwrap() else {
        panic!("the fixture advertises search");
    };
    assert!(!found.publications.is_empty());
    assert!(
        found
            .publications
            .iter()
            .all(|e| e.title.to_lowercase().contains("tidal"))
    );

    let all = catalogue.feed(&root.join("/opds/all").unwrap()).unwrap();
    let file = all
        .publications
        .iter()
        .flat_map(|e| &e.acquisitions)
        // Not the fixture's slow entry, which takes 45 seconds and declares no size.
        .find(|a| a.href.path().starts_with("/files/") && a.length.is_some())
        .unwrap();
    let name = file.href.path().trim_start_matches("/files/");
    let direct = catalogue.bytes(&file.href).unwrap().body;
    let redirected = catalogue
        .bytes(&root.join(&format!("/redirect/{name}")).unwrap())
        .unwrap()
        .body;
    assert_eq!(direct, redirected);
    assert_eq!(Some(direct.len() as u64), file.length);
}

#[test]
fn a_catalogue_without_search_says_it_filters_locally() {
    let feed = feed(ATOM_ACQUISITION);
    let catalogue = OpdsCatalogue::new(&http(), base(), None).unwrap();
    assert_eq!(
        catalogue.search(&feed, "anything").unwrap(),
        SearchOutcome::LocalOnly
    );
}

// ---- the credential goes to its own origin only --------------------------------------------

/// A server that records each request's path and `Authorization` header and answers with
/// `answer(path)`: a status, extra headers and a body.
fn recorder(answer: impl Fn(&str) -> (u16, String, String) + Send + 'static) -> (u16, Seen) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::clone(&seen);
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let (path, authorization) = read_request(&stream);
            log.lock().unwrap().push((path.clone(), authorization));
            let (status, headers, body) = answer(&path);
            let mut stream = stream;
            let _ = write!(
                stream,
                "HTTP/1.1 {status} X\r\n{headers}Content-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
        }
    });
    (port, seen)
}

fn read_request(stream: &TcpStream) -> (String, Option<String>) {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    let path = line
        .split_whitespace()
        .nth(1)
        .unwrap_or_default()
        .to_owned();
    let mut authorization = None;
    loop {
        let mut header = String::new();
        if reader.read_line(&mut header).unwrap_or(0) == 0 || header == "\r\n" {
            break;
        }
        if let Some((name, value)) = header.split_once(':')
            && name.eq_ignore_ascii_case("authorization")
        {
            authorization = Some(value.trim().to_owned());
        }
    }
    (path, authorization)
}

/// What a recorder saw: each path with its `Authorization` header.
type Seen = Arc<Mutex<Vec<(String, Option<String>)>>>;

const TINY_FEED: &str = r#"<feed xmlns="http://www.w3.org/2005/Atom"><title>Tiny</title></feed>"#;

#[test]
fn a_credential_is_sent_to_the_catalogue_and_not_across_a_redirect_to_another_origin() {
    let (elsewhere, elsewhere_seen) = recorder(|_| (200, String::new(), TINY_FEED.into()));
    let (home, home_seen) = recorder(move |path| match path {
        "/hop" => (
            302,
            format!("Location: http://localhost:{elsewhere}/landed\r\n"),
            String::new(),
        ),
        _ => (200, String::new(), TINY_FEED.into()),
    });
    let root = Url::parse(&format!("http://127.0.0.1:{home}/opds")).unwrap();
    let credential = Credential::Bearer("storyarc-token".into());
    let catalogue = OpdsCatalogue::new(&http(), root.clone(), Some(credential)).unwrap();
    assert_eq!(catalogue.validate().unwrap().title, "Tiny");
    assert_eq!(
        catalogue.feed(&root.join("/hop").unwrap()).unwrap().title,
        "Tiny"
    );

    let home_seen = home_seen.lock().unwrap();
    assert!(
        home_seen
            .iter()
            .all(|(_, auth)| auth.as_deref() == Some("Bearer storyarc-token"))
    );
    let elsewhere_seen = elsewhere_seen.lock().unwrap();
    assert_eq!(elsewhere_seen.len(), 1);
    assert_eq!(elsewhere_seen[0], ("/landed".to_owned(), None));
}

#[test]
fn an_https_catalogue_never_follows_a_link_down_to_http() {
    let catalogue = OpdsCatalogue::new(&http(), base(), None).unwrap();
    assert_eq!(
        catalogue
            .feed(&Url::parse("http://library.example/opds/all").unwrap())
            .unwrap_err(),
        OpdsError::Downgrade
    );
}

// ---- a certificate the system does not trust -----------------------------------------------

/// An HTTPS server on an ephemeral port with a certificate made now, for `localhost`.
fn self_signed_server() -> (u16, String) {
    let generated = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let der = generated.cert.der().to_vec();
    let print = storyarc_core::net::fingerprint(&der);
    let key = rustls::pki_types::PrivateKeyDer::Pkcs8(generated.signing_key.serialize_der().into());
    let config = Arc::new(
        rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![der.into()], key)
        .unwrap(),
    );
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let Ok(connection) = rustls::ServerConnection::new(Arc::clone(&config)) else {
                continue;
            };
            let mut tls = rustls::StreamOwned::new(connection, stream);
            let mut request = Vec::new();
            let mut byte = [0u8; 1];
            while !request.ends_with(b"\r\n\r\n") {
                match tls.read(&mut byte) {
                    Ok(1) => request.push(byte[0]),
                    _ => break,
                }
            }
            if request.ends_with(b"\r\n\r\n") {
                let _ = write!(
                    tls,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/atom+xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{TINY_FEED}",
                    TINY_FEED.len()
                );
                let _ = tls.flush();
                tls.conn.send_close_notify();
                let _ = tls.flush();
            }
        }
    });
    (port, print)
}

#[test]
fn an_untrusted_certificate_is_refused_with_its_fingerprint_and_accepted_once_pinned() {
    let (port, print) = self_signed_server();
    let trust = TrustStore::new();
    let client = HttpClient::new(&Runtime::new().unwrap(), trust.clone()).unwrap();
    let root = Url::parse(&format!("https://localhost:{port}/opds")).unwrap();
    let catalogue = OpdsCatalogue::new(&client, root, None).unwrap();

    let OpdsError::Untrusted(refusal) = catalogue.validate().unwrap_err() else {
        panic!("a self-signed certificate is refused by default");
    };
    assert_eq!(refusal.host, "localhost");
    assert_eq!(refusal.fingerprint, print);
    assert_eq!(refusal.fingerprint.len(), 95, "32 bytes, colon-separated");

    // The reader saw the fingerprint and the warning, and pinned it.
    trust.pin(&refusal.host, &refusal.fingerprint);
    assert_eq!(catalogue.validate().unwrap().title, "Tiny");

    // A pin is that certificate's: another one is refused again.
    let (other_port, _) = self_signed_server();
    let other = OpdsCatalogue::new(
        &client,
        Url::parse(&format!("https://localhost:{other_port}/opds")).unwrap(),
        None,
    )
    .unwrap();
    assert!(matches!(other.validate(), Err(OpdsError::Untrusted(_))));
}
