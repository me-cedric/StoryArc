//! Which dialect a body is, and the address rules both dialects share (StoryArcKit's
//! `OpdsDocument` and `OpenSearchDescription`).

use reqwest::Url;

use super::atom::{Node, walk};
use super::model::OpdsFeed;
use super::{OpdsError, Received, atom, json};

/// Reads a body as a feed, deciding the dialect from its first character rather than from a
/// content type: several servers send a good Atom feed as `application/octet-stream`.
pub fn parse(body: &[u8], content_type: Option<&str>, base: &Url) -> Result<OpdsFeed, OpdsError> {
    let Some(first) = body.iter().find(|b| !b.is_ascii_whitespace()) else {
        return Err(OpdsError::Empty);
    };
    let text = String::from_utf8_lossy(body);
    match first {
        b'{' => json::parse(&text, base),
        b'<' if looks_like_html(&text) => Err(OpdsError::NotAFeed(Received::Html)),
        b'<' => atom::parse(&text, base),
        _ => Err(OpdsError::NotAFeed(Received::Unrecognised(
            content_type.map(str::to_owned),
        ))),
    }
}

/// An HTML page, including XHTML: the usual answer from a wrong path or a login wall.
fn looks_like_html(text: &str) -> bool {
    let head: String = text.chars().take(512).collect::<String>().to_lowercase();
    head.contains("<!doctype html")
        || head.contains("<html")
        || (head.contains("<?xml") && head.contains("xhtml"))
}

/// What a reader typed, as an address: `https://` assumed when no scheme is given.
pub fn address_from_typed(typed: &str) -> Option<Url> {
    let trimmed = typed.trim();
    if trimmed.is_empty() || trimmed.contains(' ') {
        return None;
    }
    let completed = if trimmed.contains("://") {
        trimmed.to_owned()
    } else {
        format!("https://{trimmed}")
    };
    let url = Url::parse(&completed).ok()?;
    url.host_str().filter(|host| !host.is_empty())?;
    matches!(url.scheme(), "http" | "https").then_some(url)
}

/// `href` against `base`, kept only when it is a web address.
pub(crate) fn resolve(href: &str, base: &Url) -> Option<Url> {
    let url = base.join(href.trim()).ok()?;
    matches!(url.scheme(), "http" | "https").then_some(url)
}

/// A search template resolved against `base` with its braces left in place.
pub(crate) fn resolve_template(href: &str, base: &Url) -> Option<String> {
    Some(
        resolve(href, base)?
            .as_str()
            .replace("%7B", "{")
            .replace("%7D", "}"),
    )
}

/// The search URL for `terms`: `{searchTerms}`, `{?query}` and `{query}` filled in.
pub fn fill_search(template: &str, terms: &str) -> Option<Url> {
    let encoded: String = url_encode(terms);
    let filled = if let Some(at) = template.find("{?query}") {
        let separator = if template[..at].contains('?') {
            "&"
        } else {
            "?"
        };
        template.replace("{?query}", &format!("{separator}query={encoded}"))
    } else {
        template
            .replace("{searchTerms}", &encoded)
            .replace("{query}", &encoded)
    };
    // Optional OpenSearch parameters the app does not set are dropped, with their braces.
    let mut cleaned = String::with_capacity(filled.len());
    let mut skipping = false;
    for c in filled.chars() {
        match c {
            '{' => skipping = true,
            '}' => skipping = false,
            _ if !skipping => cleaned.push(c),
            _ => {}
        }
    }
    Url::parse(&cleaned).ok()
}

fn url_encode(text: &str) -> String {
    text.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}

/// The template an OpenSearch description offers, preferring an OPDS or Atom result type.
pub fn open_search_template(body: &[u8], base: &Url) -> Option<String> {
    let text = String::from_utf8_lossy(body);
    let mut offers: Vec<(String, String)> = Vec::new();
    walk(&text, |node| {
        if let Node::Start(element) = node
            && element.name == "Url"
        {
            offers.push((
                element.get("type").unwrap_or_default().to_owned(),
                element.get("template").unwrap_or_default().to_owned(),
            ));
        }
    })
    .ok()?;
    let usable: Vec<_> = offers.into_iter().filter(|(_, t)| !t.is_empty()).collect();
    let chosen = usable
        .iter()
        .find(|(kind, _)| kind.to_lowercase().contains("opds"))
        .or_else(|| {
            usable
                .iter()
                .find(|(kind, _)| kind.to_lowercase().contains("atom"))
        })
        .or_else(|| usable.iter().find(|(kind, _)| kind.is_empty()))
        .or_else(|| {
            usable
                .iter()
                .find(|(kind, _)| !kind.to_lowercase().contains("html"))
        })?;
    resolve_template(&chosen.1, base)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base() -> Url {
        Url::parse("https://library.example/opds/").unwrap()
    }

    #[test]
    fn a_typed_address_gets_https_and_a_bad_one_is_refused() {
        assert_eq!(
            address_from_typed(" library.example/opds ")
                .unwrap()
                .as_str(),
            "https://library.example/opds"
        );
        assert!(address_from_typed("http://127.0.0.1:4444/opds").is_some());
        assert!(address_from_typed("").is_none());
        assert!(address_from_typed("ftp://x/").is_none());
        assert!(address_from_typed("two words").is_none());
    }

    #[test]
    fn a_template_keeps_its_braces_and_fills_each_shape() {
        let template = resolve_template("search?q={searchTerms}", &base()).unwrap();
        assert_eq!(
            template,
            "https://library.example/opds/search?q={searchTerms}"
        );
        assert_eq!(
            fill_search(&template, "long field").unwrap().as_str(),
            "https://library.example/opds/search?q=long%20field"
        );
        let json = resolve_template("/opds/search{?query}", &base()).unwrap();
        assert_eq!(
            fill_search(&json, "harbour").unwrap().as_str(),
            "https://library.example/opds/search?query=harbour"
        );
        assert_eq!(
            fill_search("https://x/s?q={searchTerms}&p={startPage?}", "a")
                .unwrap()
                .as_str(),
            "https://x/s?q=a&p="
        );
    }

    #[test]
    fn an_open_search_description_offers_its_atom_template() {
        let xml = r#"<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
          <Url type="text/html" template="/web?q={searchTerms}"/>
          <Url type="application/atom+xml;profile=opds-catalog" template="/opds/search/{searchTerms}"/>
        </OpenSearchDescription>"#;
        assert_eq!(
            open_search_template(xml.as_bytes(), &base()).unwrap(),
            "https://library.example/opds/search/{searchTerms}"
        );
    }
}
