//! OPDS 1.2: Atom, read the way StoryArcKit's `OpdsAtom` reads it.
//!
//! Element and attribute names are taken by their local part, so `opds:facetGroup`,
//! `thr:count` and an unprefixed `count` are all found however a server declared them.

use quick_xml::Reader;
use quick_xml::XmlVersion;
use quick_xml::escape::resolve_predefined_entity;
use quick_xml::events::{BytesStart, Event};
use reqwest::Url;

use super::OpdsError;
use super::document::{resolve, resolve_template};
use super::model::{
    AcquisitionKind, OpdsAcquisition, OpdsEntry, OpdsFacet, OpdsFeed, OpdsSection, OpdsVersion,
    is_protected_type,
};

/// One element's local name and its attributes by local name.
pub(crate) struct Element {
    pub name: String,
    pub attributes: Vec<(String, String)>,
}

impl Element {
    pub(crate) fn get(&self, name: &str) -> Option<&str> {
        self.attributes
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }

    fn of(start: &BytesStart<'_>) -> Self {
        let name = start.local_name().as_ref().to_owned();
        let attributes = start
            .attributes()
            .flatten()
            .map(|attribute| {
                let key = attribute.key.local_name().as_ref().to_owned();
                let value = attribute
                    .normalized_value(XmlVersion::Implicit1_0)
                    .map(|value| value.into_owned())
                    .unwrap_or_default();
                (key, value)
            })
            .collect();
        Self { name, attributes }
    }
}

/// What a document is made of, flattened: starts (an empty element is a start and an end),
/// ends, and text with its entity references resolved.
pub(crate) enum Node {
    Start(Element),
    End(String),
    Text(String),
}

/// Walks `text` as XML, calling `visit` with each node. `Err` with the reader's message when
/// the XML is not well-formed.
pub(crate) fn walk(text: &str, mut visit: impl FnMut(Node)) -> Result<(), String> {
    let mut reader = Reader::from_str(text);
    loop {
        match reader.read_event().map_err(|error| error.to_string())? {
            Event::Start(start) => visit(Node::Start(Element::of(&start))),
            Event::Empty(start) => {
                let element = Element::of(&start);
                let name = element.name.clone();
                visit(Node::Start(element));
                visit(Node::End(name));
            }
            Event::End(end) => visit(Node::End(end.local_name().as_ref().to_owned())),
            Event::Text(content) => visit(Node::Text(content.xml10_content().into_owned())),
            Event::CData(content) => visit(Node::Text(content.xml10_content().into_owned())),
            Event::GeneralRef(reference) => {
                let resolved = match reference.resolve_char_ref() {
                    Ok(Some(character)) => character.to_string(),
                    _ => resolve_predefined_entity(&reference)
                        .unwrap_or_default()
                        .to_owned(),
                };
                visit(Node::Text(resolved));
            }
            Event::Eof => return Ok(()),
            _ => {}
        }
    }
}

#[derive(Default)]
struct PartialEntry {
    id: String,
    title: String,
    authors: Vec<String>,
    summary: Option<String>,
    series: Option<String>,
    updated: Option<String>,
    cover: Option<Url>,
    thumbnail: Option<Url>,
    acquisitions: Vec<OpdsAcquisition>,
    section: Option<(Url, Option<u64>)>,
}

struct PendingLink {
    href: Url,
    relation: String,
    media_type: String,
    length: Option<u64>,
    is_indirect: bool,
}

/// Parses an Atom feed. `NotAFeed` when the root is not a `feed`.
pub(crate) fn parse(text: &str, base: &Url) -> Result<OpdsFeed, OpdsError> {
    let mut feed = OpdsFeed {
        version: OpdsVersion::Atom,
        title: String::new(),
        navigation: Vec::new(),
        publications: Vec::new(),
        groups: Vec::new(),
        facets: Vec::new(),
        next: None,
        search_template: None,
        search_description: None,
    };
    let mut saw_feed = false;
    let mut entry: Option<PartialEntry> = None;
    let mut pending: Option<PendingLink> = None;
    let mut text_run = String::new();

    walk(text, |node| match node {
        Node::Start(element) => {
            text_run.clear();
            match element.name.as_str() {
                "feed" => saw_feed = true,
                "entry" => entry = Some(PartialEntry::default()),
                "link" => link(&element, base, &mut feed, entry.as_mut(), &mut pending),
                "indirectAcquisition" => {
                    if let Some(link) = pending.as_mut() {
                        link.is_indirect = true;
                    }
                }
                _ => {}
            }
        }
        Node::Text(text) => text_run.push_str(&text),
        Node::End(name) => {
            let value = text_run.trim().to_owned();
            text_run.clear();
            if name == "entry" {
                if let Some(current) = entry.take() {
                    finish_entry(current, &mut feed);
                }
            } else if name == "link" {
                if let (Some(link), Some(current)) = (pending.take(), entry.as_mut()) {
                    finalise(link, current);
                }
            } else if let Some(current) = entry.as_mut() {
                close_inside_entry(&name, value, current);
            } else if name == "title" && feed.title.is_empty() {
                feed.title = value;
            }
        }
    })
    .map_err(OpdsError::Malformed)?;

    if !saw_feed {
        return Err(OpdsError::NotAFeed(super::Received::Unrecognised(None)));
    }
    Ok(feed)
}

fn close_inside_entry(name: &str, value: String, entry: &mut PartialEntry) {
    match name {
        "title" => entry.title = value,
        "id" => entry.id = value,
        "name" if !value.is_empty() => entry.authors.push(value),
        "summary" | "content" if entry.summary.is_none() && !value.is_empty() => {
            entry.summary = Some(value)
        }
        "updated" if !value.is_empty() => entry.updated = Some(value),
        "series" if !value.is_empty() => entry.series = Some(value),
        _ => {}
    }
}

fn finish_entry(entry: PartialEntry, feed: &mut OpdsFeed) {
    if entry.title.is_empty() {
        return;
    }
    if entry.acquisitions.is_empty()
        && let Some((href, count)) = entry.section.clone()
    {
        feed.navigation.push(OpdsSection {
            title: entry.title,
            href,
            count,
        });
        return;
    }
    feed.publications.push(OpdsEntry {
        id: if entry.id.is_empty() {
            entry.title.clone()
        } else {
            entry.id
        },
        title: entry.title,
        authors: entry.authors,
        summary: entry.summary,
        series: entry.series,
        series_index: None,
        updated: entry.updated,
        cover: entry.cover,
        thumbnail: entry.thumbnail,
        acquisitions: entry.acquisitions,
    });
}

fn link(
    element: &Element,
    base: &Url,
    feed: &mut OpdsFeed,
    entry: Option<&mut PartialEntry>,
    pending: &mut Option<PendingLink>,
) {
    let Some(raw) = element.get("href") else {
        return;
    };
    let Some(href) = resolve(raw, base) else {
        return;
    };
    let relation = element.get("rel").unwrap_or_default();
    let media_type = element.get("type").unwrap_or_default();
    let title = element.get("title").unwrap_or_default();
    let count = element.get("count").and_then(|value| value.parse().ok());

    if let Some(entry) = entry {
        if media_type.contains("application/atom+xml")
            && !matches!(relation, "self" | "up" | "start")
        {
            entry.section = Some((href.clone(), count));
        }
        match relation {
            "http://opds-spec.org/image" | "http://opds-spec.org/cover" => entry.cover = Some(href),
            "http://opds-spec.org/image/thumbnail" | "http://opds-spec.org/thumbnail" => {
                entry.thumbnail = Some(href)
            }
            _ => {
                *pending = Some(PendingLink {
                    href,
                    relation: relation.to_owned(),
                    media_type: media_type.to_owned(),
                    length: element.get("length").and_then(|value| value.parse().ok()),
                    is_indirect: is_protected_type(media_type),
                })
            }
        }
        return;
    }

    match relation {
        "next" => feed.next = Some(href),
        "search" => {
            if raw.contains("{searchTerms}") {
                feed.search_template = resolve_template(raw, base);
            } else {
                feed.search_description = Some(href);
            }
        }
        "http://opds-spec.org/facet" => feed.facets.push(OpdsFacet {
            group: element.get("facetGroup").unwrap_or(title).to_owned(),
            title: title.to_owned(),
            href,
            count,
            is_active: element.get("activeFacet") == Some("true"),
        }),
        _ => {
            if !media_type.contains("application/atom+xml")
                || title.is_empty()
                || matches!(
                    relation,
                    "self" | "start" | "up" | "first" | "last" | "previous"
                )
            {
                return;
            }
            feed.navigation.push(OpdsSection {
                title: title.to_owned(),
                href,
                count,
            });
        }
    }
}

fn finalise(link: PendingLink, entry: &mut PartialEntry) {
    let kind = if link.is_indirect {
        AcquisitionKind::Indirect
    } else if let Some(named) = AcquisitionKind::named(&link.relation) {
        named
    } else if link
        .relation
        .starts_with("http://opds-spec.org/acquisition")
    {
        AcquisitionKind::Indirect
    } else {
        return;
    };
    entry.acquisitions.push(OpdsAcquisition {
        href: link.href,
        media_type: link.media_type,
        kind,
        length: link.length,
    });
}
