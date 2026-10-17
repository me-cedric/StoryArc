//! The app's own address scheme (task 5.8; `desktop-experience`, Opening a link or a
//! command). Two forms open something: `storyarc://publication/<title or id>` and
//! `storyarc://source/<name or id>`, the name percent-encoded. Anything else, an unknown
//! kind, a path of several parts, no name, is refused whole. A query or a fragment after
//! a name is ignored: the link is a name to open and never a command, so nothing here
//! reads a setting, runs a program or writes data. Pure: `launch.rs` passes the
//! library's records and sources. The Windows `StoryArcLink` reads the same way.

use gtk::glib;
use storyarc_core::domain::Publication;

pub const SCHEME: &str = "storyarc";

/// What a link turns into once it is held against the library.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LinkAction {
    /// The link names a publication the library holds: it opens in a reader window.
    OpenPublication(String),
    /// The link names a source the app holds: the library shows it.
    ShowSource(String),
    /// The link names a publication or a source the app does not hold: the app says so,
    /// with the name asked for, and changes nothing.
    NotFound(String),
    /// The link names nothing to open, or something else than a name: nothing runs and
    /// nothing changes.
    Refused,
}

/// Whether a command-line argument or an opened URI is a link rather than a path.
pub fn is_link(argument: &str) -> bool {
    argument.len() > SCHEME.len() + 1
        && argument[..SCHEME.len() + 1].eq_ignore_ascii_case("storyarc:")
}

/// `sources` are `(id, name)` pairs: the folder libraries and the network libraries.
pub fn resolve(link: &str, records: &[Publication], sources: &[(String, String)]) -> LinkAction {
    let Ok(uri) = glib::Uri::parse(link, glib::UriFlags::NONE) else {
        return LinkAction::Refused;
    };
    if !uri.scheme().eq_ignore_ascii_case(SCHEME) {
        return LinkAction::Refused;
    }
    let path = uri.path();
    let mut segments = path.split('/').filter(|segment| !segment.is_empty());
    let (Some(segment), None) = (segments.next(), segments.next()) else {
        return LinkAction::Refused;
    };
    let name = glib::Uri::unescape_string(segment, None)
        .map(|text| text.trim().to_owned())
        .unwrap_or_default();
    if name.is_empty() {
        return LinkAction::Refused;
    }
    let is = |candidate: &str| candidate.eq_ignore_ascii_case(&name);
    match uri.host().as_deref() {
        Some("publication") => records
            .iter()
            .find(|record| {
                record.identity.normalized_path.as_deref().is_some_and(is)
                    || is(&record.display_title)
            })
            .and_then(|record| record.identity.normalized_path.clone())
            .map_or(
                LinkAction::NotFound(name.clone()),
                LinkAction::OpenPublication,
            ),
        Some("source") => sources
            .iter()
            .find(|(id, source_name)| is(id) || is(source_name))
            .map_or(LinkAction::NotFound(name.clone()), |(id, _)| {
                LinkAction::ShowSource(id.clone())
            }),
        _ => LinkAction::Refused,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    fn record(path: &str, title: &str) -> Publication {
        Publication::new(
            PublicationIdentity::path(path),
            PublicationFormat::Cbz,
            title,
            MetadataOrigin::Inferred,
        )
    }

    fn resolve(link: &str) -> LinkAction {
        let records = [
            record("/comics/Saga 1.cbz", "Saga 1"),
            record("/comics/Strip.cbt", "Strip"),
        ];
        let sources = [("comics".to_owned(), "Comics".to_owned())];
        super::resolve(link, &records, &sources)
    }

    #[test]
    fn a_plain_link_to_a_title_the_library_holds_opens_it() {
        assert_eq!(
            resolve("storyarc://publication/Saga%201"),
            LinkAction::OpenPublication("/comics/Saga 1.cbz".into())
        );
        assert_eq!(
            resolve("storyarc://source/Comics"),
            LinkAction::ShowSource("comics".into())
        );
    }

    #[test]
    fn an_unknown_title_or_source_is_named_and_nothing_opens() {
        assert_eq!(
            resolve("storyarc://publication/Nothing%20Like%20It"),
            LinkAction::NotFound("Nothing Like It".into())
        );
        assert_eq!(
            resolve("storyarc://source/Elsewhere"),
            LinkAction::NotFound("Elsewhere".into())
        );
    }

    #[test]
    fn a_link_carrying_a_command_or_naming_nothing_is_refused() {
        for link in [
            "storyarc://settings/reset",
            "storyarc://clear-history",
            "storyarc://publication",
            "storyarc://publication/Saga%201/delete",
            "storyarc://run/sh",
            "storyarc:",
            "https://publication/Saga%201",
        ] {
            assert_eq!(resolve(link), LinkAction::Refused, "{link}");
        }
    }

    #[test]
    fn a_query_after_a_name_is_ignored_and_only_the_name_opens() {
        assert_eq!(
            resolve("storyarc://publication/Strip?delete=all&exec=calc#now"),
            LinkAction::OpenPublication("/comics/Strip.cbt".into())
        );
    }

    #[test]
    fn a_link_is_told_from_a_path() {
        assert!(is_link("storyarc://publication/Saga%201"));
        assert!(is_link("STORYARC://x"));
        assert!(!is_link("/comics/Saga 1.cbz"));
        assert!(!is_link("--library"));
        assert!(!is_link("storyarc:"));
    }
}
