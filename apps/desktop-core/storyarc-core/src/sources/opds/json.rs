//! OPDS 2.0: JSON, read the way StoryArcKit's `OpdsJson` reads it, over `serde_json::Value`
//! because servers write the same field in several shapes: a relation as a string or a list,
//! an author as a string, an object or a list of either.

use reqwest::Url;
use serde_json::Value;

use super::document::{resolve, resolve_template};
use super::model::{
    AcquisitionKind, OpdsAcquisition, OpdsEntry, OpdsFacet, OpdsFeed, OpdsGroup, OpdsSection,
    OpdsVersion, is_protected_type,
};
use super::{OpdsError, Received};

pub(crate) fn parse(text: &str, base: &Url) -> Result<OpdsFeed, OpdsError> {
    let wire: Value =
        serde_json::from_str(text).map_err(|error| OpdsError::Malformed(error.to_string()))?;
    let Some(title) = wire
        .get("metadata")
        .and_then(|metadata| metadata.get("title"))
        .and_then(Value::as_str)
    else {
        return Err(OpdsError::NotAFeed(Received::Unrecognised(Some(
            "application/json".into(),
        ))));
    };
    let groups = list(&wire, "groups");
    let unnamed: Vec<&Value> = groups
        .iter()
        .copied()
        .filter(|g| group_title(g).is_none())
        .collect();

    let navigation = list(&wire, "navigation")
        .into_iter()
        .chain(unnamed.iter().flat_map(|g| list(g, "navigation")))
        .filter_map(|link| section(link, base))
        .collect();
    let publications = list(&wire, "publications")
        .into_iter()
        .chain(unnamed.iter().flat_map(|g| list(g, "publications")))
        .filter_map(|publication| entry(publication, base))
        .collect();
    let named_groups = groups
        .iter()
        .filter_map(|group| {
            Some(OpdsGroup {
                title: group_title(group)?.to_owned(),
                navigation: list(group, "navigation")
                    .into_iter()
                    .filter_map(|link| section(link, base))
                    .collect(),
                publications: list(group, "publications")
                    .into_iter()
                    .filter_map(|publication| entry(publication, base))
                    .collect(),
                more: list(group, "links")
                    .into_iter()
                    .find(|link| relations(link).iter().any(|rel| rel == "self"))
                    .and_then(|link| href(link, base)),
            })
        })
        .collect();
    let facets = list(&wire, "facets")
        .into_iter()
        .flat_map(|facet| {
            let group = facet
                .get("metadata")
                .and_then(|metadata| metadata.get("title"))
                .and_then(Value::as_str)
                .map(str::to_owned);
            list(facet, "links").into_iter().filter_map(move |link| {
                let title = link.get("title").and_then(Value::as_str)?;
                Some(OpdsFacet {
                    group: group.clone().unwrap_or_else(|| title.to_owned()),
                    title: title.to_owned(),
                    href: href(link, base)?,
                    count: number_of_items(link),
                    is_active: false,
                })
            })
        })
        .collect();
    let links = list(&wire, "links");
    let search = links
        .iter()
        .find(|link| relations(link).iter().any(|rel| rel == "search"));
    let is_templated = search
        .and_then(|link| link.get("templated"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let search_href = search
        .and_then(|link| link.get("href"))
        .and_then(Value::as_str);

    Ok(OpdsFeed {
        version: OpdsVersion::Json,
        title: title.to_owned(),
        navigation,
        publications,
        groups: named_groups,
        facets,
        next: links
            .iter()
            .find(|link| relations(link).iter().any(|rel| rel == "next"))
            .and_then(|link| href(link, base)),
        search_template: if is_templated {
            search_href.and_then(|raw| resolve_template(raw, base))
        } else {
            None
        },
        search_description: if is_templated {
            None
        } else {
            search_href.and_then(|raw| resolve(raw, base))
        },
    })
}

fn list<'a>(value: &'a Value, key: &str) -> Vec<&'a Value> {
    value
        .get(key)
        .and_then(Value::as_array)
        .map(|items| items.iter().collect())
        .unwrap_or_default()
}

fn group_title(group: &Value) -> Option<&str> {
    group.get("metadata")?.get("title")?.as_str()
}

fn href(link: &Value, base: &Url) -> Option<Url> {
    resolve(link.get("href")?.as_str()?, base)
}

/// `rel` as a string or a list of strings.
fn relations(link: &Value) -> Vec<String> {
    match link.get("rel") {
        Some(Value::String(rel)) => vec![rel.clone()],
        Some(Value::Array(rels)) => rels
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect(),
        _ => Vec::new(),
    }
}

fn number_of_items(link: &Value) -> Option<u64> {
    link.get("properties")?.get("numberOfItems")?.as_u64()
}

fn section(link: &Value, base: &Url) -> Option<OpdsSection> {
    Some(OpdsSection {
        title: link.get("title")?.as_str()?.to_owned(),
        href: href(link, base)?,
        count: number_of_items(link),
    })
}

/// Names out of a contributor in any of its shapes.
fn names(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::String(name)) => vec![name.clone()],
        Some(Value::Object(object)) => object
            .get("name")
            .and_then(|name| match name {
                Value::String(name) => Some(name.clone()),
                // A localised name: the first language the server wrote.
                Value::Object(languages) => languages
                    .values()
                    .find_map(Value::as_str)
                    .map(str::to_owned),
                _ => None,
            })
            .into_iter()
            .collect(),
        Some(Value::Array(items)) => items.iter().flat_map(|item| names(Some(item))).collect(),
        _ => Vec::new(),
    }
}

fn entry(publication: &Value, base: &Url) -> Option<OpdsEntry> {
    let metadata = publication.get("metadata")?;
    let title = metadata.get("title")?.as_str()?.to_owned();
    let mut images = list(publication, "images");
    images.sort_by_key(|image| {
        std::cmp::Reverse(image.get("width").and_then(Value::as_u64).unwrap_or(0))
    });
    let series = metadata.get("belongsTo").and_then(|b| b.get("series"));
    let first_series = match series {
        Some(Value::Array(items)) => items.first(),
        other => other,
    };
    Some(OpdsEntry {
        id: metadata
            .get("identifier")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| title.clone()),
        authors: names(metadata.get("author")),
        summary: metadata
            .get("description")
            .and_then(Value::as_str)
            .map(str::to_owned),
        series: names(first_series).into_iter().next(),
        series_index: first_series
            .and_then(|s| s.get("position"))
            .and_then(Value::as_f64),
        updated: metadata
            .get("modified")
            .and_then(Value::as_str)
            .map(str::to_owned),
        cover: images.first().and_then(|image| href(image, base)),
        thumbnail: images.last().and_then(|image| href(image, base)),
        acquisitions: list(publication, "links")
            .into_iter()
            .filter_map(|link| acquisition(link, base))
            .collect(),
        title,
    })
}

fn acquisition(link: &Value, base: &Url) -> Option<OpdsAcquisition> {
    let href = href(link, base)?;
    let media_type = link
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    let relations = relations(link);
    let has_indirect_child = link
        .get("properties")
        .and_then(|p| p.get("indirectAcquisition"))
        .and_then(Value::as_array)
        .is_some_and(|items| !items.is_empty());
    let kind = if has_indirect_child || is_protected_type(&media_type) {
        AcquisitionKind::Indirect
    } else if let Some(named) = relations.iter().find_map(|rel| AcquisitionKind::named(rel)) {
        named
    } else if relations.is_empty() {
        AcquisitionKind::Direct
    } else if relations
        .iter()
        .any(|rel| rel.starts_with("http://opds-spec.org/acquisition"))
    {
        AcquisitionKind::Indirect
    } else {
        return None;
    };
    Some(OpdsAcquisition {
        href,
        media_type,
        kind,
        length: link.get("size").and_then(Value::as_u64),
    })
}
