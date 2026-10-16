//! Minimal XML reading, shared by `ComicInfo` and the EPUB reader.
//!
//! ponytail: attribute scraping rather than a DOM, exactly as the Swift readers argue. A
//! package document and a `ComicInfo.xml` are flat lists of uniquely-named elements with
//! attributes, so a real parser would be more code for identical answers — and would be the
//! `quick-xml` dependency design.md lists as Assumed, which this keeps unneeded. If nested
//! structure is ever required (a hierarchical table of contents, say), switch to a parser
//! rather than growing this.

use std::collections::HashMap;

/// One element's attributes, plus its text under the key no attribute can use.
pub(crate) type Attributes = HashMap<String, String>;

pub(crate) const TEXT_KEY: &str = "#text";

/// Every element with a given name, in document order, with its attributes and text.
pub(crate) fn elements_named(text: &str, name: &str) -> Vec<Attributes> {
    let mut found = Vec::new();
    let open_tag = format!("<{name}");
    let close_tag = format!("</{name}>");
    let mut rest = text;
    while let Some(open) = rest.find(&open_tag) {
        rest = &rest[open + open_tag.len()..];
        // Guard against `<items>` matching a search for `<item>`.
        if rest
            .chars()
            .next()
            .is_some_and(|next| next.is_alphanumeric())
        {
            continue;
        }
        let Some(end) = rest.find('>') else { break };
        let start_tag = &rest[..end];
        let mut attributes = parse_attributes(start_tag);
        // Element text, for `<meta property="...">value</meta>` and `<dc:title>`. A
        // self-closing element has none, and must not borrow the next element's.
        let after = &rest[end + 1..];
        let is_self_closing = start_tag.trim_end().ends_with('/');
        if !is_self_closing && let Some(closing) = after.find(&close_tag) {
            attributes.insert(TEXT_KEY.to_owned(), after[..closing].to_owned());
        }
        found.push(attributes);
        rest = after;
    }
    found
}

/// The trimmed, non-empty text of an element's attributes map.
pub(crate) fn text_of(attributes: &Attributes) -> Option<String> {
    let raw = attributes.get(TEXT_KEY)?.trim();
    (!raw.is_empty()).then(|| raw.to_owned())
}

/// The text of the first element with this name.
pub(crate) fn first_text(text: &str, name: &str) -> Option<String> {
    elements_named(text, name).first().and_then(text_of)
}

/// The non-empty text of every element with this name, in file order.
pub(crate) fn texts_of(text: &str, name: &str) -> Vec<String> {
    elements_named(text, name)
        .iter()
        .filter_map(text_of)
        .collect()
}

/// An attribute of the first element with this name.
pub(crate) fn attribute_of_first(text: &str, element: &str, name: &str) -> Option<String> {
    elements_named(text, element)
        .first()
        .and_then(|attributes| attributes.get(name).cloned())
}

/// `name="value"` pairs out of a start tag's body.
pub(crate) fn parse_attributes(fragment: &str) -> Attributes {
    let mut attributes = Attributes::new();
    let mut rest = fragment;
    while let Some(equals) = rest.find('=') {
        let name = rest[..equals].trim_matches(|c: char| c.is_whitespace() || c == '/' || c == '?');
        let after = &rest[equals + 1..];
        let Some(quote) = after.chars().next().filter(|&q| q == '"' || q == '\'') else {
            break;
        };
        let after = &after[1..];
        let Some(closing) = after.find(quote) else {
            break;
        };
        if !name.is_empty() && !name.contains(' ') {
            attributes.insert(name.to_owned(), unescape(&after[..closing]));
        }
        rest = &after[closing + 1..];
    }
    attributes
}

/// The text between `<name>` and `</name>`, for a flat element with no attributes.
pub(crate) fn element_body<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let open = format!("<{name}>");
    let close = format!("</{name}>");
    let start = text.find(&open)? + open.len();
    let end = text[start..].find(&close)? + start;
    Some(&text[start..end])
}

/// The five predefined XML entities. A summary with an ampersand in it is ordinary, and
/// showing `&amp;` in a library is not.
pub(crate) fn unescape(value: &str) -> String {
    value
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn elements_carry_attributes_and_text() {
        let xml = r#"<items><item id="a" href='x.xhtml'/><item id="b">Body</item></items>"#;
        let items = elements_named(xml, "item");
        assert_eq!(items.len(), 2);
        assert_eq!(items[0]["href"], "x.xhtml");
        assert_eq!(text_of(&items[1]).as_deref(), Some("Body"));
        assert_eq!(first_text(xml, "item").as_deref(), None);
    }

    #[test]
    fn a_flat_element_body_is_read_and_unescaped() {
        let xml = "<Root><Series> Bone </Series><Summary>A &amp; B</Summary></Root>";
        assert_eq!(element_body(xml, "Series"), Some(" Bone "));
        assert_eq!(unescape(element_body(xml, "Summary").unwrap()), "A & B");
        assert_eq!(element_body(xml, "Missing"), None);
    }
}
