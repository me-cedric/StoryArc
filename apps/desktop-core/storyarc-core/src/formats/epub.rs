//! Reads an EPUB's structure: metadata, reading order, table of contents, cover. Mirrored
//! from `EpubReader.swift`, `EpubMetadata.swift` and `EpubSpineCover.swift`.
//!
//! **Not a rendering engine.** Laying out reflowable XHTML is the pinned Readium bundle's
//! job (design.md, Decision 6). What this does instead is everything the *library* needs:
//! an EPUB is a ZIP holding XML, so the container is our own reader (ADR-0008) and the XML
//! is scraped flat, and a shelf of EPUBs can be indexed with no dependency at all.
//!
//! The four combinations `publication-formats` promises — EPUB 2 and 3, reflowable and
//! fixed-layout — differ in exactly the places a parser gets wrong, so each is handled
//! explicitly: EPUB 2 has an NCX where EPUB 3 has a nav document, and names its cover with
//! a metadata `meta` where EPUB 3 uses a manifest property.

use std::collections::HashMap;
use std::sync::Arc;

use super::page_ordering::PageOrdering;
use super::xml;
use super::zip::{ZipEntry, ZipError, ZipReader};
use crate::io::RandomAccessSource;

/// One item in a publication's reading order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpubSpineItem {
    /// Path inside the container, resolved against the package document.
    pub href: String,
    pub media_type: String,
    /// EPUB 3 lets a single item opt out of the publication's layout.
    pub is_fixed_layout: Option<bool>,
}

/// One entry in the table of contents, from a nav document or an NCX.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpubTocEntry {
    pub title: String,
    pub href: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EpubError {
    /// Not an EPUB: the `mimetype` entry is missing or says something else.
    NotEpub,
    /// `META-INF/container.xml` is missing or names no root file.
    NoPackageDocument,
    Malformed(String),
}

impl std::fmt::Display for EpubError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotEpub => f.write_str("not an EPUB"),
            Self::NoPackageDocument => f.write_str("no package document"),
            Self::Malformed(reason) => write!(f, "malformed EPUB: {reason}"),
        }
    }
}

impl std::error::Error for EpubError {}

/// What an EPUB says about itself.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct EpubMetadata {
    pub title: Option<String>,
    pub author: Option<String>,
    pub language: Option<String>,
    pub identifier: Option<String>,
    pub publisher: Option<String>,
    pub description: Option<String>,
    /// The series it belongs to, and where in it. EPUB 3 states this as a
    /// `belongs-to-collection` refined by `group-position`; Calibre's `calibre:series` meta
    /// became the convention where EPUB 2 has nothing — so both are read, and the EPUB 3
    /// form wins where a file carries both, because it is the one the format defines.
    pub series: Option<String>,
    pub series_index: Option<String>,
    /// Every `dc:identifier`, in file order: an ISBN is often the second or third one.
    pub identifiers: Vec<String>,
}

pub struct EpubReader {
    /// The package document's path, which every other href resolves against.
    pub package_path: String,
    pub version: u32,
    pub metadata: EpubMetadata,
    /// Reading order, as the spine declares it.
    pub spine: Vec<EpubSpineItem>,
    pub toc: Vec<EpubTocEntry>,
    /// The cover image's path inside the container, when the publication names one.
    pub cover_href: Option<String>,
    /// True when the publication is pre-paginated: images with positions, so `ebook-reader`
    /// requires the image reader and forbids typography controls that cannot do anything.
    pub is_fixed_layout: bool,
    /// The spine's own `page-progression-direction`: `"rtl"`, `"ltr"` or `None`.
    pub page_progression_direction: Option<String>,
    /// Whether the table of contents came from an EPUB 3 nav document.
    pub has_nav_document: bool,
    reader: ZipReader,
    path_to_entry: HashMap<String, ZipEntry>,
}

struct Package {
    version: u32,
    metadata: EpubMetadata,
    spine: Vec<EpubSpineItem>,
    cover_href: Option<String>,
    nav_href: Option<String>,
    ncx_href: Option<String>,
    is_fixed_layout: bool,
    page_progression_direction: Option<String>,
}

struct Item {
    href: String,
    media_type: String,
    properties: String,
}

impl EpubReader {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, EpubError> {
        let reader = ZipReader::open(source).map_err(|_| EpubError::NotEpub)?;
        let index: HashMap<String, ZipEntry> = reader
            .entries()
            .iter()
            .map(|entry| (entry.path.clone(), entry.clone()))
            .collect();
        let data = |entry: &ZipEntry| -> Result<Vec<u8>, EpubError> {
            reader
                .data(entry)
                .map_err(|error: ZipError| EpubError::Malformed(error.to_string()))
        };

        // The container spec's one hard requirement, and the cheapest way to tell an EPUB
        // from any other ZIP before parsing XML.
        let mimetype = index.get("mimetype").ok_or(EpubError::NotEpub)?;
        let mimetype = String::from_utf8(data(mimetype)?).map_err(|_| EpubError::NotEpub)?;
        if mimetype.trim() != "application/epub+zip" {
            return Err(EpubError::NotEpub);
        }

        let container = index
            .get("META-INF/container.xml")
            .ok_or(EpubError::NoPackageDocument)?;
        let container_xml = String::from_utf8_lossy(&data(container)?).into_owned();
        let package_path = xml::attribute_of_first(&container_xml, "rootfile", "full-path")
            .ok_or(EpubError::NoPackageDocument)?;
        let package_entry = index
            .get(&package_path)
            .ok_or(EpubError::NoPackageDocument)?;
        let package_xml = String::from_utf8_lossy(&data(package_entry)?).into_owned();
        let base = directory_of(&package_path);
        let package = Self::parse_package(&package_xml, base);

        // The table of contents lives in a different file, in a different format, depending
        // on the version. Missing is not an error: a publication with no declared contents
        // still reads front to back.
        let nav_entry = package.nav_href.as_ref().and_then(|href| index.get(href));
        let ncx_entry = package.ncx_href.as_ref().and_then(|href| index.get(href));
        let (toc, has_nav_document) = if let Some(entry) = nav_entry {
            let nav = String::from_utf8_lossy(&data(entry)?).into_owned();
            (Self::parse_nav(&nav, directory_of(&entry.path)), true)
        } else if let Some(entry) = ncx_entry {
            let ncx = String::from_utf8_lossy(&data(entry)?).into_owned();
            (Self::parse_ncx(&ncx, directory_of(&entry.path)), false)
        } else {
            (Vec::new(), false)
        };

        Ok(Self {
            package_path,
            version: package.version,
            metadata: package.metadata,
            spine: package.spine,
            toc,
            cover_href: package.cover_href,
            is_fixed_layout: package.is_fixed_layout,
            page_progression_direction: package.page_progression_direction,
            has_nav_document,
            reader,
            path_to_entry: index,
        })
    }

    /// One item's bytes, by its container path.
    pub fn data_at(&self, href: &str) -> Result<Vec<u8>, EpubError> {
        let entry = self
            .path_to_entry
            .get(href)
            .ok_or_else(|| EpubError::Malformed(format!("no entry at {href}")))?;
        self.reader
            .data(entry)
            .map_err(|error| EpubError::Malformed(error.to_string()))
    }

    /// The cover image's bytes, when the publication has one.
    pub fn cover_data(&self) -> Option<Vec<u8>> {
        self.data_at(self.cover_href.as_deref()?).ok()
    }

    /// The publication's cover path: the one it declares, or the image its first page shows.
    ///
    /// `publication-formats`: "WHEN an EPUB declares a cover image THEN that image is used;
    /// otherwise the first page of the spine is rendered as the cover." Most publications
    /// that declare no cover still *open* on one — a `cover.xhtml` holding a single image —
    /// so the first spine item is read and the image it shows becomes the cover. A first
    /// spine item that shows no image at all leaves the publication without a cover:
    /// rasterising arbitrary XHTML means a web view, which is a reading decision rather
    /// than a thumbnail one.
    pub fn cover_or_spine_href(&self) -> Option<String> {
        if let Some(cover) = &self.cover_href {
            return Some(cover.clone());
        }
        let first = self.spine.first()?;
        // The item's own bytes may be missing from a damaged container. That is not worth
        // an error either: it means there is no cover to be had.
        let xhtml = self.data_at(&first.href).ok()?;
        let base = directory_of(&first.href);
        image_references(&xhtml)
            .into_iter()
            .filter(|reference| PageOrdering::is_page(reference))
            .map(|reference| resolve(&reference, base))
            // Only a path the container actually holds. A remote `src`, or one that walked
            // out of the container, is not a cover.
            .find(|resolved| self.path_to_entry.contains_key(resolved))
    }

    // ── Package document ──────────────────────────────────────────────────

    fn parse_package(text: &str, base: &str) -> Package {
        let version = xml::attribute_of_first(text, "package", "version")
            .and_then(|v| v.split('.').next()?.parse::<u32>().ok())
            .unwrap_or(3);

        // A manifest item is (id, href, media-type, properties). Everything else in the
        // package refers to items by id, so this map comes first.
        let mut items: Vec<(String, Item)> = Vec::new();
        for element in xml::elements_named(text, "item") {
            let (Some(id), Some(href)) = (element.get("id"), element.get("href")) else {
                continue;
            };
            items.push((
                id.clone(),
                Item {
                    href: resolve(href, base),
                    media_type: element.get("media-type").cloned().unwrap_or_default(),
                    properties: element.get("properties").cloned().unwrap_or_default(),
                },
            ));
        }
        let item = |id: &str| {
            items
                .iter()
                .find(|(key, _)| key == id)
                .map(|(_, item)| item)
        };

        let metas = xml::elements_named(text, "meta");
        let is_fixed_layout = metas
            .iter()
            .find(|m| m.get("property").map(String::as_str) == Some("rendition:layout"))
            .and_then(xml::text_of)
            .is_some_and(|value| value == "pre-paginated");

        let spine = xml::elements_named(text, "itemref")
            .iter()
            .filter_map(|element| {
                let item = item(element.get("idref")?)?;
                // `rendition:layout-pre-paginated` on an itemref overrides the publication's
                // own layout for that one item.
                let properties = element.get("properties").cloned().unwrap_or_default();
                let item_layout = if properties.contains("rendition:layout-pre-paginated") {
                    Some(true)
                } else if properties.contains("rendition:layout-reflowable") {
                    Some(false)
                } else {
                    None
                };
                Some(EpubSpineItem {
                    href: item.href.clone(),
                    media_type: item.media_type.clone(),
                    is_fixed_layout: item_layout,
                })
            })
            .collect();

        // EPUB 3 marks the cover with a manifest property; EPUB 2 names an item id from a
        // metadata meta. Both are checked, in that order, because a version number is not a
        // promise about which convention a file actually used.
        let cover_href = items
            .iter()
            .find(|(_, item)| item.properties.contains("cover-image"))
            .map(|(_, item)| item.href.clone())
            .or_else(|| {
                let id = metas
                    .iter()
                    .find(|m| m.get("name").map(String::as_str) == Some("cover"))?
                    .get("content")?;
                Some(item(id)?.href.clone())
            });

        let nav_href = items
            .iter()
            .find(|(_, item)| item.properties.contains("nav"))
            .map(|(_, item)| item.href.clone());
        // The NCX is reached through the spine's `toc` attribute, not by media type — a
        // publication may carry an NCX it does not use.
        let ncx_href = xml::attribute_of_first(text, "spine", "toc")
            .and_then(|id| item(&id).map(|item| item.href.clone()))
            .or_else(|| {
                items
                    .iter()
                    .find(|(_, item)| item.media_type == "application/x-dtbncx+xml")
                    .map(|(_, item)| item.href.clone())
            });
        let page_progression_direction =
            xml::attribute_of_first(text, "spine", "page-progression-direction");

        let series = Self::series(&metas);
        let either =
            |a: &str, b: &str| xml::first_text(text, a).or_else(|| xml::first_text(text, b));
        Package {
            version,
            metadata: EpubMetadata {
                title: either("dc:title", "title"),
                author: either("dc:creator", "creator"),
                language: either("dc:language", "language"),
                identifier: either("dc:identifier", "identifier"),
                publisher: either("dc:publisher", "publisher"),
                description: either("dc:description", "description"),
                series: series.as_ref().map(|(name, _)| name.clone()),
                series_index: series.and_then(|(_, position)| position),
                identifiers: xml::texts_of(text, "dc:identifier"),
            },
            spine,
            cover_href,
            nav_href,
            ncx_href,
            is_fixed_layout,
            page_progression_direction,
        }
    }

    /// The series a publication belongs to, from whichever of the two conventions it uses.
    /// The defined form wins where both are present.
    fn series(metas: &[xml::Attributes]) -> Option<(String, Option<String>)> {
        let property =
            |m: &xml::Attributes, value: &str| m.get("property").map(String::as_str) == Some(value);
        if let Some(collection) = metas.iter().find(|m| property(m, "belongs-to-collection"))
            && let Some(name) = xml::text_of(collection)
        {
            let refines = collection.get("id").map(|id| format!("#{id}"));
            let position = metas
                .iter()
                .find(|m| {
                    property(m, "group-position")
                        && (refines.is_none() || m.get("refines") == refines.as_ref())
                })
                .and_then(xml::text_of);
            return Some((name, position));
        }
        let named =
            |m: &xml::Attributes, value: &str| m.get("name").map(String::as_str) == Some(value);
        let calibre = metas.iter().find(|m| named(m, "calibre:series"))?;
        let name = calibre.get("content")?.trim();
        if name.is_empty() {
            return None;
        }
        let index = metas
            .iter()
            .find(|m| named(m, "calibre:series_index"))
            .and_then(|m| m.get("content"))
            .map(|v| v.trim().to_owned())
            .filter(|v| !v.is_empty());
        Some((name.to_owned(), index))
    }

    /// The EPUB 3 nav document: the `<nav epub:type="toc">` list. Only anchors inside the
    /// toc nav count — a landmarks or page-list nav would put "Start of content" in the
    /// table of contents.
    fn parse_nav(text: &str, base: &str) -> Vec<EpubTocEntry> {
        let scoped = text
            .find("epub:type=\"toc\"")
            .and_then(|start| {
                let rest = &text[start..];
                rest.find("</nav>").map(|end| &rest[..end])
            })
            .unwrap_or(text);
        Self::anchors(scoped, base)
    }

    /// The EPUB 2 NCX: `navPoint` with a `navLabel/text` and a `content/@src`.
    fn parse_ncx(text: &str, base: &str) -> Vec<EpubTocEntry> {
        let mut entries = Vec::new();
        let mut rest = text;
        while let Some(start) = rest.find("<navPoint") {
            rest = &rest[start + "<navPoint".len()..];
            let Some(end) = rest.find("</navPoint>").or_else(|| rest.find("/>")) else {
                break;
            };
            let block = &rest[..end];
            let label = between(block, "<text>", "</text>").map(str::trim);
            let src = xml::attribute_of_first(block, "content", "src");
            if let (Some(label), Some(src)) = (label, src)
                && !label.is_empty()
            {
                entries.push(EpubTocEntry {
                    title: xml::unescape(label),
                    href: resolve(&src, base),
                });
            }
        }
        entries
    }

    fn anchors(text: &str, base: &str) -> Vec<EpubTocEntry> {
        let mut entries = Vec::new();
        let mut rest = text;
        while let Some(open) = rest.find("<a ") {
            rest = &rest[open..];
            let Some(close) = rest.find("</a>") else {
                break;
            };
            let element = &rest[..close + "</a>".len()];
            rest = &rest[close + "</a>".len()..];
            let Some(href) = xml::attribute_of_first(element, "a", "href") else {
                continue;
            };
            let Some(title) = between(element, ">", "</a>").map(str::trim) else {
                continue;
            };
            if title.is_empty() {
                continue;
            }
            entries.push(EpubTocEntry {
                title: xml::unescape(title),
                href: resolve(&href, base),
            });
        }
        entries
    }
}

fn between<'a>(text: &'a str, from: &str, to: &str) -> Option<&'a str> {
    let start = text.find(from)? + from.len();
    let end = text[start..].find(to)? + start;
    Some(&text[start..end])
}

/// The directory an href inside `path` resolves against.
fn directory_of(path: &str) -> &str {
    match path.rfind('/') {
        Some(slash) => &path[..slash],
        None => "",
    }
}

/// An href relative to the document that declared it, with any fragment dropped — a table
/// of contents entry may point at an anchor inside a file.
fn resolve(href: &str, base: &str) -> String {
    let without_fragment = href.split('#').next().unwrap_or(href);
    if let Some(absolute) = without_fragment.strip_prefix('/') {
        return absolute.to_owned();
    }
    if base.is_empty() {
        return without_fragment.to_owned();
    }
    let mut segments: Vec<&str> = base.split('/').filter(|s| !s.is_empty()).collect();
    for part in without_fragment.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                segments.pop();
            }
            other => segments.push(other),
        }
    }
    segments.join("/")
}

/// Every way an XHTML page can point at an image, in the order they are looked for.
///
/// `src` covers `<img>`, `href` and `xlink:href` cover SVG `<image>`, and `url(...)` covers
/// a page whose only picture is a CSS background. Nothing here parses XHTML: a cover page is
/// one element deep and a DOM would be more code for the same answer.
pub fn image_references(xhtml: &[u8]) -> Vec<String> {
    let Ok(text) = std::str::from_utf8(xhtml) else {
        return Vec::new();
    };
    let mut found: Vec<String> = Vec::new();
    for attribute in ["src=", "xlink:href=", "href=", "url("] {
        let mut rest = text;
        while let Some(start) = rest.find(attribute) {
            rest = &rest[start + attribute.len()..];
            let Some(value) = quoted(rest) else { continue };
            if !value.is_empty() && !found.contains(&value) {
                found.push(value);
            }
        }
    }
    found
}

/// The value that opens where a scan has stopped: `"…"`, `'…'`, or up to `)`.
fn quoted(rest: &str) -> Option<String> {
    let opening = rest.chars().next()?;
    if opening == '"' || opening == '\'' {
        let body = &rest[1..];
        let closing = body.find(opening)?;
        return Some(body[..closing].to_owned());
    }
    // `url(` with no quotes, which CSS allows.
    let closing = rest.find(')')?;
    Some(rest[..closing].trim().to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemorySource;

    #[test]
    fn hrefs_resolve_against_their_document_and_drop_fragments() {
        assert_eq!(resolve("ch1.xhtml#top", "OEBPS"), "OEBPS/ch1.xhtml");
        assert_eq!(
            resolve("../images/a.png", "OEBPS/text"),
            "OEBPS/images/a.png"
        );
        assert_eq!(resolve("/abs.xhtml", "OEBPS"), "abs.xhtml");
        assert_eq!(resolve("./a.xhtml", ""), "./a.xhtml");
        assert_eq!(directory_of("OEBPS/package.opf"), "OEBPS");
        assert_eq!(directory_of("package.opf"), "");
    }

    #[test]
    fn image_references_are_found_under_every_spelling() {
        let xhtml = br#"<img src="cover.png"/><image xlink:href='p1.jpg'/><div style="background:url(bg.webp)"/>"#;
        assert_eq!(image_references(xhtml), ["cover.png", "p1.jpg", "bg.webp"]);
    }

    #[test]
    fn bytes_that_are_not_even_a_zip_are_refused() {
        let source: Arc<dyn RandomAccessSource> = Arc::new(MemorySource::new(vec![0x41; 1024]));
        assert_eq!(EpubReader::open(source).err(), Some(EpubError::NotEpub));
    }
}
