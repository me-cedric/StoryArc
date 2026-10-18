//! The reader's marks in one EPUB, with no GTK in them (`ebook-reader`, *Bookmarks*, *Highlights
//! and notes*, *Search within a publication*, *Following an internal link*, *Returning from any
//! jump*): the bookmarks and highlights kept per device, the messages that draw them, the search
//! hits as the renderer posts them, and when a move counts as a jump to come back from.
//!
//! The Linux copy of the Mac's `EpubMarks`. The records carry the phones' fields (`Bookmark` and
//! `Annotation`) in the same JSON names, kept in one file under the publication's identity.

use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Map, Value, json};

/// The highlight colours, in the phones' order and names.
pub const COLOURS: [&str; 5] = ["yellow", "green", "blue", "pink", "purple"];

/// The decoration of the sentence being spoken; never a reader's highlight.
pub const SPOKEN_ID: &str = "spoken";
const SPOKEN_TINT: &str = "lightskyblue";

/// Where a reader is, in the terms a mark records.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub locator: String,
    /// The resource, without a fragment.
    pub resource: String,
    pub progression: f64,
    pub chapter: String,
}

impl Place {
    pub fn of(locator: &str, chapter: &str) -> Self {
        let value: Value = serde_json::from_str(locator).unwrap_or_default();
        Self {
            locator: locator.to_owned(),
            resource: resource(&value),
            progression: value["locations"]["progression"].as_f64().unwrap_or(0.0),
            chapter: chapter.to_owned(),
        }
    }
}

/// A locator's resource, without its fragment.
fn resource(locator: &Value) -> String {
    let href = locator["href"].as_str().unwrap_or("");
    href.split('#').next().unwrap_or("").to_owned()
}

#[derive(Clone, Debug, PartialEq)]
pub struct Bookmark {
    pub id: String,
    pub place: Place,
    pub created: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Highlight {
    pub id: String,
    pub place: Place,
    pub text: String,
    pub colour: String,
    pub note: String,
    pub created: u64,
}

/// One search hit, in context.
#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    pub chapter: Option<String>,
    pub before: String,
    pub matched: String,
    pub after: String,
    pub locator: String,
}

impl Hit {
    /// The hits of one `search-results` message.
    pub fn all_of(message: &Value) -> Vec<Self> {
        message["results"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|raw| {
                let locator = raw.get("locator").unwrap_or(raw);
                let text = &locator["text"];
                locator.get("href")?;
                Some(Self {
                    chapter: locator["title"].as_str().map(str::to_owned),
                    before: text["before"].as_str().unwrap_or("").to_owned(),
                    matched: text["highlight"].as_str().unwrap_or("").to_owned(),
                    after: text["after"].as_str().unwrap_or("").to_owned(),
                    locator: locator.to_string(),
                })
            })
            .collect()
    }
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_secs())
}

/// An id no other mark of this device has: the time in nanoseconds and a counter.
fn new_id() -> String {
    use std::sync::atomic::{AtomicU32, Ordering};
    static COUNTER: AtomicU32 = AtomicU32::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_nanos());
    format!("{nanos:x}-{:x}", COUNTER.fetch_add(1, Ordering::Relaxed))
}

/// Two progressions closer than this are the same page for a bookmark.
const SAME_PAGE: f64 = 0.005;

/// Every mark of one publication.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Marks {
    pub bookmarks: Vec<Bookmark>,
    pub highlights: Vec<Highlight>,
}

impl Marks {
    /// The bookmark at a place, if there is one.
    pub fn bookmark_at(&self, place: &Place) -> Option<&Bookmark> {
        self.bookmarks.iter().find(|mark| {
            mark.place.resource == place.resource
                && (mark.place.progression - place.progression).abs() < SAME_PAGE
        })
    }

    /// Adds a bookmark at the place, or removes the one already there. True when one was added.
    pub fn toggle_bookmark(&mut self, place: Place, order: &[String]) -> bool {
        if let Some(id) = self.bookmark_at(&place).map(|mark| mark.id.clone()) {
            self.bookmarks.retain(|mark| mark.id != id);
            return false;
        }
        self.bookmarks.push(Bookmark {
            id: new_id(),
            place,
            created: now(),
        });
        let at = |place: &Place| {
            (
                order
                    .iter()
                    .position(|href| *href == place.resource)
                    .unwrap_or(usize::MAX),
                place.progression,
            )
        };
        self.bookmarks.sort_by(|a, b| {
            at(&a.place)
                .partial_cmp(&at(&b.place))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        true
    }

    /// Keeps a selection as a highlight in a colour.
    pub fn highlight(&mut self, text: &str, place: Place, colour: &str) -> String {
        let id = new_id();
        self.highlights.push(Highlight {
            id: id.clone(),
            place,
            text: text.to_owned(),
            colour: colour.to_owned(),
            note: String::new(),
            created: now(),
        });
        id
    }

    /// Writes a note on a highlight; an empty note removes the note and keeps the highlight.
    pub fn set_note(&mut self, id: &str, note: &str) {
        if let Some(highlight) = self.highlights.iter_mut().find(|h| h.id == id) {
            note.trim().clone_into(&mut highlight.note);
        }
    }

    pub fn remove_highlight(&mut self, id: &str) {
        self.highlights.retain(|highlight| highlight.id != id);
    }

    /// The `highlights` message: every highlight, and the spoken sentence in its own tint. It
    /// replaces what the page had.
    pub fn highlights_message(&self, spoken: Option<&str>, seq: u64) -> String {
        let mut items: Vec<Value> = self
            .highlights
            .iter()
            .map(|highlight| {
                json!({
                    "id": highlight.id,
                    "locator": serde_json::from_str::<Value>(&highlight.place.locator).unwrap_or_default(),
                    "color": highlight.colour,
                })
            })
            .collect();
        if let Some(spoken) = spoken.and_then(|spoken| serde_json::from_str::<Value>(spoken).ok()) {
            items.push(json!({ "id": SPOKEN_ID, "locator": spoken, "color": SPOKEN_TINT }));
        }
        json!({ "type": "highlights", "seq": seq, "items": items }).to_string()
    }

    fn place_json(place: &Place) -> Value {
        json!({
            "locator": place.locator,
            "resource": place.resource,
            "progression": place.progression,
            "chapter": place.chapter,
        })
    }

    fn place_of(value: &Value) -> Place {
        Place {
            locator: value["locator"].as_str().unwrap_or("{}").to_owned(),
            resource: value["resource"].as_str().unwrap_or("").to_owned(),
            progression: value["progression"].as_f64().unwrap_or(0.0),
            chapter: value["chapter"].as_str().unwrap_or("").to_owned(),
        }
    }

    pub fn to_json(&self) -> Value {
        let bookmarks: Vec<Value> = self
            .bookmarks
            .iter()
            .map(|mark| {
                let mut value = Self::place_json(&mark.place);
                value["id"] = mark.id.clone().into();
                value["createdAt"] = mark.created.into();
                value["excerpt"] = "".into();
                value
            })
            .collect();
        let annotations: Vec<Value> = self
            .highlights
            .iter()
            .map(|highlight| {
                let mut value = Self::place_json(&highlight.place);
                value["id"] = highlight.id.clone().into();
                value["createdAt"] = highlight.created.into();
                value["text"] = highlight.text.clone().into();
                value["colour"] = highlight.colour.clone().into();
                value["note"] = highlight.note.clone().into();
                value
            })
            .collect();
        json!({ "bookmarks": bookmarks, "annotations": annotations })
    }

    pub fn from_json(value: &Value) -> Self {
        let list = |key: &str| value[key].as_array().cloned().unwrap_or_default();
        Self {
            bookmarks: list("bookmarks")
                .iter()
                .filter_map(|raw| {
                    Some(Bookmark {
                        id: raw["id"].as_str()?.to_owned(),
                        place: Self::place_of(raw),
                        created: raw["createdAt"].as_u64().unwrap_or(0),
                    })
                })
                .collect(),
            highlights: list("annotations")
                .iter()
                .filter_map(|raw| {
                    let colour = raw["colour"].as_str().filter(|c| COLOURS.contains(c))?;
                    Some(Highlight {
                        id: raw["id"].as_str()?.to_owned(),
                        place: Self::place_of(raw),
                        text: raw["text"].as_str().unwrap_or("").to_owned(),
                        colour: colour.to_owned(),
                        note: raw["note"].as_str().unwrap_or("").to_owned(),
                        created: raw["createdAt"].as_u64().unwrap_or(0),
                    })
                })
                .collect(),
        }
    }
}

/// Every publication's marks on this device, by publication key, as the file holds them.
pub fn read_all(text: &str) -> Map<String, Value> {
    serde_json::from_str::<Value>(text)
        .ok()
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default()
}

/// A move to another resource the app did not ask for is a link followed in the book: the place
/// it left becomes the way back. Within one resource it is a page turn.
pub fn is_jump(previous: &str, next: &Value) -> bool {
    let before: Value = serde_json::from_str(previous).unwrap_or_default();
    let after = resource(next);
    !after.is_empty() && after != resource(&before)
}

/// The `go` message, or `None` when the locator is not JSON.
pub fn go_message(seq: u64, locator: &str) -> Option<String> {
    let locator = serde_json::from_str::<Value>(locator).ok()?;
    Some(json!({ "type": "go", "seq": seq, "locator": locator }).to_string())
}

/// The `search` message; a newer id silences an older search.
pub fn search_message(seq: u64, id: u64, query: &str) -> String {
    json!({ "type": "search", "seq": seq, "id": id, "query": query }).to_string()
}

/// A locator for the start of a resource, as the renderer goes to it.
pub fn start_of(href: &str, media_type: Option<&str>) -> String {
    json!({
        "href": href,
        "type": media_type.unwrap_or("application/xhtml+xml"),
        "locations": {},
    })
    .to_string()
}

/// A sentence of a chapter, as a locator the renderer finds again by its text.
pub fn spoken_locator(sentence: &str, href: &str) -> String {
    json!({
        "href": href,
        "type": "application/xhtml+xml",
        "locations": {},
        "text": { "highlight": sentence },
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(href: &str, progression: f64) -> Place {
        Place::of(
            &json!({"href": href, "locations": {"progression": progression}}).to_string(),
            "One",
        )
    }

    /// `ebook-reader`, *Bookmarks*: a mark at the page toggles, sorts in reading order and
    /// survives the file.
    #[test]
    fn a_bookmark_toggles_at_its_page_and_keeps_reading_order() {
        let order = vec!["a.xhtml".to_owned(), "b.xhtml".to_owned()];
        let mut marks = Marks::default();
        assert!(marks.toggle_bookmark(at("b.xhtml", 0.5), &order));
        assert!(marks.toggle_bookmark(at("a.xhtml#n1", 0.2), &order));
        assert_eq!(marks.bookmarks[0].place.resource, "a.xhtml");
        assert!(marks.bookmark_at(&at("b.xhtml", 0.502)).is_some());
        assert!(!marks.toggle_bookmark(at("b.xhtml", 0.501), &order));
        assert_eq!(marks.bookmarks.len(), 1);
        assert_eq!(Marks::from_json(&marks.to_json()), marks);
    }

    /// *Highlights and notes*: a selection kept in a colour, a note written and cleared, the
    /// message that draws them with the spoken sentence, and a removal.
    #[test]
    fn a_highlight_takes_a_note_and_draws_with_the_spoken_sentence() {
        let mut marks = Marks::default();
        let id = marks.highlight("the quiet sea", at("a.xhtml", 0.1), "green");
        marks.set_note(&id, "  remember  ");
        assert_eq!(marks.highlights[0].note, "remember");
        let message: Value = serde_json::from_str(
            &marks.highlights_message(Some(&spoken_locator("A sentence.", "a.xhtml")), 3),
        )
        .unwrap();
        assert_eq!(message["type"], "highlights");
        assert_eq!(message["items"][0]["color"], "green");
        assert_eq!(message["items"][0]["locator"]["href"], "a.xhtml");
        assert_eq!(message["items"][1]["id"], SPOKEN_ID);
        assert_eq!(
            message["items"][1]["locator"]["text"]["highlight"],
            "A sentence."
        );
        assert_eq!(Marks::from_json(&marks.to_json()), marks);
        marks.set_note(&id, "");
        assert!(marks.highlights[0].note.is_empty());
        marks.remove_highlight(&id);
        assert!(marks.highlights.is_empty());
        let all = read_all(&json!({"k": marks.to_json()}).to_string());
        assert!(all.contains_key("k"));
        assert!(read_all("not json").is_empty());
    }

    /// *Search within a publication*: the renderer's results, in context, each a locator.
    #[test]
    fn search_results_read_as_hits_in_context() {
        let message = json!({"type": "search-results", "id": 1, "results": [
            {"locator": {"href": "a.xhtml", "title": "One", "locations": {"progression": 0.3},
             "text": {"before": "the ", "highlight": "whale", "after": " rose"}}},
            {"locator": {"title": "no href"}}
        ]});
        let hits = Hit::all_of(&message);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].chapter.as_deref(), Some("One"));
        assert_eq!(
            (hits[0].before.as_str(), hits[0].matched.as_str()),
            ("the ", "whale")
        );
        assert!(hits[0].locator.contains("a.xhtml"));
    }

    /// *Following an internal link* and *Returning from any jump*: a move to another resource is
    /// a jump; a turn inside one is not.
    #[test]
    fn a_move_to_another_resource_is_a_jump_and_a_turn_is_not() {
        let here = json!({"href": "a.xhtml", "locations": {}}).to_string();
        assert!(is_jump(&here, &json!({"href": "notes.xhtml#n3"})));
        assert!(!is_jump(&here, &json!({"href": "a.xhtml#p2"})));
        assert!(start_of("c.xhtml", None).contains("\"href\":\"c.xhtml\""));
    }
}
