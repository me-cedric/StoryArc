//! The Readium Web Publication Manifest, as `@readium/shared` parses it, built from what
//! `EpubReader` already yields. Only the keys the bundle reads are written.

use serde::Serialize;

use crate::formats::EpubReader;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Manifest {
    #[serde(rename = "@context")]
    pub context: &'static str,
    pub metadata: Metadata,
    pub links: Vec<Link>,
    #[serde(rename = "readingOrder")]
    pub reading_order: Vec<Link>,
    pub resources: Vec<Link>,
    pub toc: Vec<Link>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Metadata {
    #[serde(rename = "@type")]
    pub kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub identifier: Option<String>,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    pub language: Vec<String>,
    /// `fixed` or `reflowable`: the bundle's image reader against its text reader.
    pub layout: &'static str,
    /// `ltr`, `rtl` or `auto`, from the spine's `page-progression-direction`.
    #[serde(rename = "readingProgression")]
    pub reading_progression: &'static str,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Link {
    pub href: String,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rel: Option<&'static str>,
}

/// One position: a Readium locator with the three numbers the bundle reads.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Locator {
    pub href: String,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub locations: Locations,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Locations {
    pub position: u64,
    pub progression: f64,
    #[serde(rename = "totalProgression")]
    pub total_progression: f64,
}

pub(super) fn build(reader: &EpubReader, self_url: &str) -> Manifest {
    let title_of = |href: &str| {
        reader
            .toc
            .iter()
            .find(|entry| entry.href == href)
            .map(|entry| entry.title.clone())
    };
    let media_type = |value: &str| (!value.is_empty()).then(|| value.to_owned());
    let reading_order: Vec<Link> = reader
        .spine
        .iter()
        .map(|item| Link {
            href: item.href.clone(),
            media_type: media_type(&item.media_type),
            title: title_of(&item.href),
            rel: None,
        })
        .collect();
    let resources = reader
        .resources
        .iter()
        .filter(|resource| !reader.spine.iter().any(|item| item.href == resource.href))
        .map(|resource| Link {
            href: resource.href.clone(),
            media_type: media_type(&resource.media_type),
            title: None,
            rel: (reader.cover_href.as_deref() == Some(resource.href.as_str())).then_some("cover"),
        })
        .collect();
    let toc = reader
        .toc
        .iter()
        .map(|entry| Link {
            href: entry.href.clone(),
            media_type: None,
            title: Some(entry.title.clone()),
            rel: None,
        })
        .collect();
    Manifest {
        context: "https://readium.org/webpub-manifest/context.jsonld",
        metadata: Metadata {
            kind: "http://schema.org/Book",
            identifier: reader.metadata.identifier.clone(),
            title: reader.metadata.title.clone().unwrap_or_default(),
            author: reader.metadata.author.clone(),
            language: reader.metadata.language.iter().cloned().collect(),
            layout: if reader.is_fixed_layout {
                "fixed"
            } else {
                "reflowable"
            },
            reading_progression: match reader.page_progression_direction.as_deref() {
                Some("rtl") => "rtl",
                Some("ltr") => "ltr",
                _ => "auto",
            },
        },
        links: vec![Link {
            href: self_url.to_owned(),
            media_type: Some("application/webpub+json".to_owned()),
            title: None,
            rel: Some("self"),
        }],
        reading_order,
        resources,
        toc,
    }
}
