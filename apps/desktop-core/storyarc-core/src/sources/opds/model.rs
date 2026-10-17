//! What a catalogue page holds, in both dialects, mirrored from StoryArcKit's `OpdsFeed`.

use reqwest::Url;

use crate::domain::PublicationFormat;

/// Which dialect a page arrived in, detected from the body (`opds-catalog`, *Adding a
/// catalogue*: the version is detected, never declared by the reader).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpdsVersion {
    /// OPDS 1.2, Atom.
    Atom,
    /// OPDS 2.0, JSON.
    Json,
}

/// One page of a catalogue.
#[derive(Debug, Clone, PartialEq)]
pub struct OpdsFeed {
    pub version: OpdsVersion,
    pub title: String,
    pub navigation: Vec<OpdsSection>,
    pub publications: Vec<OpdsEntry>,
    /// OPDS 2.0's named groups. An unnamed group's contents join the page.
    pub groups: Vec<OpdsGroup>,
    pub facets: Vec<OpdsFacet>,
    pub next: Option<Url>,
    /// A search URL with `{searchTerms}` or `{?query}` left in it.
    pub search_template: Option<String>,
    /// An OpenSearch description document to fetch for the template.
    pub search_description: Option<Url>,
}

impl OpdsFeed {
    /// Whether this page holds publications rather than sections: what to show first.
    pub fn is_acquisition(&self) -> bool {
        !self.publications.is_empty() || self.groups.iter().any(|g| !g.publications.is_empty())
    }

    /// Whether there is nothing on this page at all, groups counted.
    pub fn is_empty(&self) -> bool {
        self.navigation.is_empty() && self.publications.is_empty() && self.groups.is_empty()
    }
}

/// A named run of a catalogue.
#[derive(Debug, Clone, PartialEq)]
pub struct OpdsGroup {
    pub title: String,
    pub navigation: Vec<OpdsSection>,
    pub publications: Vec<OpdsEntry>,
    /// The group's own feed, for "see all".
    pub more: Option<Url>,
}

/// A section the reader can enter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpdsSection {
    pub title: String,
    pub href: Url,
    pub count: Option<u64>,
}

/// A filter a feed offers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpdsFacet {
    pub group: String,
    pub title: String,
    pub href: Url,
    pub count: Option<u64>,
    pub is_active: bool,
}

/// A publication as the catalogue describes it.
#[derive(Debug, Clone, PartialEq)]
pub struct OpdsEntry {
    pub id: String,
    pub title: String,
    pub authors: Vec<String>,
    pub summary: Option<String>,
    pub series: Option<String>,
    pub series_index: Option<f64>,
    /// As the feed wrote it, RFC 3339 or a date.
    pub updated: Option<String>,
    pub cover: Option<Url>,
    pub thumbnail: Option<Url>,
    pub acquisitions: Vec<OpdsAcquisition>,
}

/// One way of obtaining a publication.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpdsAcquisition {
    pub href: Url,
    pub media_type: String,
    pub kind: AcquisitionKind,
    /// The size the feed declares: `length` in Atom, `size` in JSON.
    pub length: Option<u64>,
}

/// How a link obtains a publication.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AcquisitionKind {
    Open,
    Direct,
    Borrow,
    Buy,
    Subscribe,
    Sample,
    /// LCP, Adobe, or any other flow the app does not follow.
    Indirect,
}

impl AcquisitionKind {
    /// Whether the app can act on it: only a direct link is something to fetch.
    pub fn is_fetchable(self) -> bool {
        matches!(self, Self::Open | Self::Direct | Self::Sample)
    }

    /// The kind an acquisition relation names.
    pub fn named(relation: &str) -> Option<Self> {
        match relation {
            "http://opds-spec.org/acquisition" => Some(Self::Direct),
            "http://opds-spec.org/acquisition/open-access" => Some(Self::Open),
            "http://opds-spec.org/acquisition/borrow" => Some(Self::Borrow),
            "http://opds-spec.org/acquisition/buy" => Some(Self::Buy),
            "http://opds-spec.org/acquisition/subscribe" => Some(Self::Subscribe),
            "http://opds-spec.org/acquisition/sample" => Some(Self::Sample),
            _ => None,
        }
    }
}

/// A type that marks a protected publication whatever its relation says.
pub(crate) fn is_protected_type(media_type: &str) -> bool {
    media_type == "application/vnd.adobe.adept+xml"
        || media_type.contains("vnd.readium.lcp.license")
        || media_type.ends_with("+lcp")
}

impl OpdsEntry {
    /// The acquisition a single press opens: EPUB, then the comic containers, then PDF
    /// (StoryArcKit's `CatalogueAcquisition.best`).
    pub fn best_acquisition(&self) -> Option<&OpdsAcquisition> {
        self.readable_acquisitions().into_iter().next()
    }

    /// Every acquisition the app can act on, best first, the feed's order breaking ties.
    pub fn readable_acquisitions(&self) -> Vec<&OpdsAcquisition> {
        let mut readable: Vec<_> = self
            .acquisitions
            .iter()
            .filter(|a| a.kind.is_fetchable())
            .filter(|a| {
                PublicationFormat::from_media_type(&a.media_type).is_some_and(|f| f.is_openable())
            })
            .collect();
        readable.sort_by_key(|a| rank(&a.media_type));
        readable
    }

    /// The formats offered for download that the app cannot open, named, sorted, once each:
    /// what an entry marked unreadable lists.
    pub fn unreadable_formats(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .acquisitions
            .iter()
            .filter(|a| a.kind.is_fetchable())
            .filter_map(
                |a| match PublicationFormat::from_media_type(&a.media_type) {
                    Some(format) if format.is_openable() => None,
                    Some(format) => Some(format.display_name().to_owned()),
                    None => (!a.media_type.is_empty()).then(|| a.media_type.clone()),
                },
            )
            .collect();
        names.sort();
        names.dedup();
        names
    }

    /// The ways of obtaining this the app will not follow, each named once, in feed order.
    pub fn unsupported_kinds(&self) -> Vec<AcquisitionKind> {
        let mut seen = Vec::new();
        for kind in self.acquisitions.iter().map(|a| a.kind) {
            if !kind.is_fetchable() && !seen.contains(&kind) {
                seen.push(kind);
            }
        }
        seen
    }
}

fn rank(media_type: &str) -> u8 {
    match PublicationFormat::from_media_type(media_type) {
        Some(PublicationFormat::Epub) => 0,
        Some(PublicationFormat::Cbz | PublicationFormat::Cbt | PublicationFormat::Cbr) => 1,
        Some(PublicationFormat::Pdf) => 2,
        _ => 3,
    }
}
