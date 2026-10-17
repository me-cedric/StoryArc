//! Publication detail (task 2.35d, as 2.23d): a pushed page with the cover wash, one
//! primary action, a menu, and one line that names where the file lives. A publication
//! with no cover shows the placeholder; one on a folder that is offline or needs access
//! says so in grey and its primary action waits for the folder.

use storyarc_core::domain::Publication;
use storyarc_core::library::{ProgressSummary, ReadState};

use crate::folders::Access;

/// From this window width the page stands beside the library (`publication-detail`, The
/// page on a large screen); below it the page is pushed over the library.
pub const TWO_PANES_FROM: i32 = 1024;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Placement {
    #[default]
    Pushed,
    Beside,
}

impl Placement {
    pub fn for_width(width: i32) -> Self {
        if width >= TWO_PANES_FROM {
            Self::Beside
        } else {
            Self::Pushed
        }
    }
}

/// The one primary action.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Primary {
    Read,
    Continue {
        percent: u32,
    },
    ReadAgain,
    /// The folder cannot be read now: the button is shown and disabled.
    Unavailable,
}

impl Primary {
    pub fn label(self) -> String {
        match self {
            Self::Read | Self::Unavailable => "Read".into(),
            Self::Continue { percent } => format!("Continue Reading · {percent}%"),
            Self::ReadAgain => "Read Again".into(),
        }
    }

    pub fn is_enabled(self) -> bool {
        self != Self::Unavailable
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Detail {
    pub title: String,
    /// Series and number, then the authors, when the record has them.
    pub subtitle: Option<String>,
    pub primary: Primary,
    /// Where the file lives: the folder library's name and the path.
    pub location: String,
    /// The grey note for a folder that cannot be read now.
    pub note: Option<&'static str>,
    pub page_count: Option<usize>,
}

impl Detail {
    /// `source` is the folder library the publication came from and its access now, when
    /// it came from one.
    pub fn of(
        publication: &Publication,
        progress: ProgressSummary,
        source: Option<(String, Access)>,
    ) -> Self {
        let access = source
            .as_ref()
            .map_or(Access::Readable, |(_, access)| *access);
        let primary = if access != Access::Readable {
            Primary::Unavailable
        } else {
            match progress.state {
                ReadState::Unread => Primary::Read,
                ReadState::InProgress => Primary::Continue {
                    percent: (progress.fraction.clamp(0.0, 1.0) * 100.0).round() as u32,
                },
                ReadState::Finished => Primary::ReadAgain,
            }
        };
        let series =
            publication
                .series
                .as_deref()
                .map(|series| match publication.number.as_deref() {
                    Some(number) => format!("{series} #{number}"),
                    None => series.to_owned(),
                });
        let authors = (!publication.authors.is_empty()).then(|| publication.authors.join(", "));
        let subtitle = match (series, authors) {
            (Some(series), Some(authors)) => Some(format!("{series} · {authors}")),
            (one, other) => one.or(other),
        };
        let path = publication
            .identity
            .normalized_path
            .clone()
            .unwrap_or_default();
        let location = match &source {
            Some((name, _)) => format!("In {name} · {path}"),
            None => path,
        };
        Self {
            title: publication.display_title.clone(),
            subtitle,
            primary,
            location,
            note: access.note(),
            page_count: publication.page_count,
        }
    }
}

#[cfg(test)]
mod tests {
    use storyarc_core::domain::{MetadataOrigin, PublicationFormat, PublicationIdentity};

    use super::*;
    use crate::library::adapter::tests::reading;

    fn publication() -> Publication {
        let mut publication = Publication::new(
            PublicationIdentity::path("/home/reader/Comics/Saga 1.cbz"),
            PublicationFormat::Cbz,
            "Saga 1",
            MetadataOrigin::Inferred,
        );
        publication.series = Some("Saga".into());
        publication.number = Some("1".into());
        publication
    }

    #[test]
    fn a_publication_with_no_cover_and_no_history_offers_read_and_names_its_folder() {
        let detail = Detail::of(
            &publication(),
            ProgressSummary::UNREAD,
            Some(("Comics".into(), Access::Readable)),
        );
        assert_eq!(detail.primary, Primary::Read);
        assert_eq!(detail.primary.label(), "Read");
        assert_eq!(detail.subtitle.as_deref(), Some("Saga #1"));
        assert_eq!(
            detail.location,
            "In Comics · /home/reader/Comics/Saga 1.cbz"
        );
        assert_eq!(detail.note, None);
    }

    #[test]
    fn a_publication_with_progress_continues_where_the_reader_was() {
        let p = publication();
        let summary = ProgressSummary::of(Some(&reading(&p, 4, 11, 10)));
        let detail = Detail::of(&p, summary, None);
        assert_eq!(detail.primary, Primary::Continue { percent: 40 });
        assert_eq!(detail.primary.label(), "Continue Reading · 40%");
        let finished =
            reading(&p, 10, 11, 10).finished(true, storyarc_core::domain::Timestamp(100));
        let again = Detail::of(&p, ProgressSummary::of(Some(&finished)), None);
        assert_eq!(again.primary, Primary::ReadAgain);
    }

    #[test]
    fn from_1024_the_page_stands_beside_the_library_and_below_it_is_pushed() {
        assert_eq!(Placement::for_width(1024), Placement::Beside);
        assert_eq!(Placement::for_width(1600), Placement::Beside);
        assert_eq!(Placement::for_width(1023), Placement::Pushed);
        assert_eq!(Placement::for_width(360), Placement::Pushed);
        assert_eq!(Placement::default(), Placement::Pushed);
    }

    #[test]
    fn a_publication_on_an_offline_folder_says_so_and_waits() {
        let detail = Detail::of(
            &publication(),
            ProgressSummary::UNREAD,
            Some(("Comics".into(), Access::Offline)),
        );
        assert_eq!(detail.primary, Primary::Unavailable);
        assert!(!detail.primary.is_enabled());
        assert_eq!(detail.note, Some("Offline"));
        let revoked = Detail::of(
            &publication(),
            ProgressSummary::UNREAD,
            Some(("Comics".into(), Access::Withdrawn)),
        );
        assert_eq!(revoked.note, Some("Needs access"));
    }
}
