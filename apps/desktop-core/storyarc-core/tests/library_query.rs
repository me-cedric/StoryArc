//! Library queries (task 2.8a of `desktop-clients`), test first.
//!
//! The cases are iOS's and Android's: `LibraryIndexTests`, `LibraryFilterTests`,
//! `DownloadFilterTests`, `HomeShelvesTests` and `LibrarySortSpeaksTheReadersLanguageTests`,
//! one table held by three implementations (ADR-0001). The progress records come from the
//! library documents each phone wrote in `packages/test-fixtures/library`, so Keep reading
//! is ordered from a phone's own history.
//!
//! One deliberate difference: search here is folded for accents as well as case, through
//! `locale::fold`, the fold iOS's `SearchRank` already uses. The phones' `LibraryIndex.rank`
//! only lower-cases, so "Cafe" finds "Café" on a desktop and not yet on a phone.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use storyarc_core::domain::{
    MetadataOrigin, Publication, PublicationFormat, PublicationIdentity, PublicationStatus,
    ReadingPosition, ReadingProgress, ServerIdentifier, Timestamp,
};
use storyarc_core::library::{
    DownloadFilter, LibraryIndex, LibraryQuery, LibraryScope, LibrarySort, ProgressIndex,
    ReadState, YearRange,
};
use storyarc_core::locale::Collation;

fn publication(title: &str) -> Publication {
    Publication::new(
        PublicationIdentity::path(format!("/library/{title}")),
        PublicationFormat::Cbz,
        title,
        MetadataOrigin::Inferred,
    )
}

fn with(title: &str, change: impl FnOnce(&mut Publication)) -> Publication {
    let mut made = publication(title);
    change(&mut made);
    made
}

fn titles(publications: &[Publication]) -> Vec<&str> {
    publications
        .iter()
        .map(|publication| publication.display_title.as_str())
        .collect()
}

fn english() -> Collation {
    Collation::new("en")
}

fn arrange(library: &[Publication], query: &LibraryQuery) -> Vec<Publication> {
    LibraryIndex::arrange(
        library,
        query,
        &english(),
        &ProgressIndex::default(),
        |_| false,
    )
}

fn query(change: impl FnOnce(&mut LibraryQuery)) -> LibraryQuery {
    let mut made = LibraryQuery::default();
    change(&mut made);
    made
}

fn read(publication: &Publication, page: i64, of: i64, finished: bool, at: i64) -> ReadingProgress {
    ReadingProgress::new(
        publication.identity.clone(),
        ReadingPosition::page(page, of),
        Timestamp(at),
    )
    .finished(finished, Timestamp(at))
}

mod sorting {
    use super::*;

    #[test]
    fn titles_sort_by_their_key_not_their_first_letter() {
        let library = [
            publication("The Sandman"),
            publication("Akira"),
            publication("Bone"),
        ];
        assert_eq!(
            titles(&arrange(&library, &LibraryQuery::default())),
            ["Akira", "Bone", "The Sandman"]
        );
    }

    #[test]
    fn descending_reverses_the_order() {
        let library = [publication("Akira"), publication("Bone")];
        let descending = query(|q| q.ascending = false);
        assert_eq!(titles(&arrange(&library, &descending)), ["Bone", "Akira"]);
    }

    fn issue(series: &str, number: &str) -> Publication {
        with(&format!("{series} #{number}"), |p| {
            p.series = Some(series.to_owned());
            p.number = Some(number.to_owned());
        })
    }

    #[test]
    fn a_series_sorts_by_issue_number_numerically() {
        let library = [issue("Bone", "10"), issue("Bone", "9"), issue("Bone", "2")];
        let by_series = query(|q| q.sort = LibrarySort::Series);
        assert_eq!(
            titles(&arrange(&library, &by_series)),
            ["Bone #2", "Bone #9", "Bone #10"]
        );
    }

    #[test]
    fn a_publication_with_no_series_sorts_after_every_series() {
        let library = [
            issue("Blackwater", "1"),
            publication("Zephyr"),
            issue("Ashfall", "2"),
            issue("Ashfall", "1"),
            publication("Almanac"),
        ];
        let by_series = query(|q| q.sort = LibrarySort::Series);
        assert_eq!(
            titles(&arrange(&library, &by_series)),
            [
                "Ashfall #1",
                "Ashfall #2",
                "Blackwater #1",
                "Almanac",
                "Zephyr"
            ]
        );
    }

    #[test]
    fn an_empty_and_a_whitespace_series_are_both_no_series() {
        let library = [
            with("Blank", |p| p.series = Some(String::new())),
            issue("Ashfall", "1"),
            with("Spaces", |p| p.series = Some("   ".to_owned())),
            publication("Absent"),
        ];
        let by_series = query(|q| q.sort = LibrarySort::Series);
        assert_eq!(
            titles(&arrange(&library, &by_series)),
            ["Ashfall #1", "Absent", "Blank", "Spaces"]
        );
    }

    #[test]
    fn descending_keeps_the_standalones_together_at_the_other_end() {
        let library = [
            issue("Ashfall", "1"),
            publication("Zephyr"),
            issue("Blackwater", "1"),
            publication("Almanac"),
        ];
        let descending = query(|q| {
            q.sort = LibrarySort::Series;
            q.ascending = false;
        });
        assert_eq!(
            titles(&arrange(&library, &descending)),
            ["Zephyr", "Almanac", "Blackwater #1", "Ashfall #1"]
        );
    }

    #[test]
    fn date_added_puts_the_newest_first_and_never_dated_last() {
        let library = [
            publication("Maus"),
            with("Bone", |p| p.added_at = Some(Timestamp(100))),
            with("Akira", |p| p.added_at = Some(Timestamp(300))),
        ];
        let by_date = query(|q| q.sort = LibrarySort::DateAdded);
        assert_eq!(
            titles(&arrange(&library, &by_date)),
            ["Akira", "Bone", "Maus"]
        );
    }

    #[test]
    fn file_size_puts_the_largest_first_and_unweighed_last() {
        let library = [
            publication("Maus"),
            with("Bone", |p| p.file_size = Some(100)),
            with("Akira", |p| p.file_size = Some(300)),
        ];
        let by_size = query(|q| q.sort = LibrarySort::FileSize);
        assert_eq!(
            titles(&arrange(&library, &by_size)),
            ["Akira", "Bone", "Maus"]
        );
    }

    #[test]
    fn last_read_puts_the_most_recent_first_and_never_read_last() {
        let akira = publication("Akira");
        let bone = publication("Bone");
        let maus = publication("Maus");
        let progress = ProgressIndex::new(vec![
            read(&bone, 3, 10, false, 100),
            read(&akira, 3, 10, false, 900),
        ]);
        let shelf = LibraryIndex::arrange(
            &[maus, bone, akira],
            &query(|q| q.sort = LibrarySort::LastRead),
            &english(),
            &progress,
            |_| false,
        );
        assert_eq!(titles(&shelf), ["Akira", "Bone", "Maus"]);
    }

    /// The iOS sorting table, the five titles in four languages and Swedish.
    #[test]
    fn the_shelf_files_titles_in_the_readers_language() {
        let library: Vec<Publication> = ["Zorro", "Ähre", "Nuez", "Ñandú", "Ångström"]
            .into_iter()
            .map(publication)
            .collect();
        let german = ["Ähre", "Ångström", "Ñandú", "Nuez", "Zorro"];
        for (language, expected) in [
            ("es", ["Ähre", "Ångström", "Nuez", "Ñandú", "Zorro"]),
            ("de", german),
            ("en", german),
            ("fr", german),
            ("sv", ["Ñandú", "Nuez", "Zorro", "Ångström", "Ähre"]),
        ] {
            let shelf = LibraryIndex::arrange(
                &library,
                &LibraryQuery::default(),
                &Collation::new(language),
                &ProgressIndex::default(),
                |_| false,
            );
            assert_eq!(titles(&shelf), expected, "{language}");
        }
    }

    #[test]
    fn the_series_shelf_files_a_series_in_the_readers_language() {
        let library: Vec<Publication> = ["Nube", "Ñandú", "Nuez"]
            .into_iter()
            .map(|name| issue(name, "1"))
            .collect();
        let shelf = LibraryIndex::arrange(
            &library,
            &query(|q| q.sort = LibrarySort::Series),
            &Collation::new("es"),
            &ProgressIndex::default(),
            |_| false,
        );
        assert_eq!(titles(&shelf), ["Nube #1", "Nuez #1", "Ñandú #1"]);
    }
}

mod search {
    use super::*;

    #[test]
    fn a_title_that_starts_with_the_query_outranks_an_author_who_contains_it() {
        let library = [
            with("Watchmen", |p| p.authors = vec!["Alan Moore".to_owned()]),
            with("Alan's Diary", |p| {
                p.authors = vec!["Someone Else".to_owned()]
            }),
        ];
        assert_eq!(
            titles(&arrange(&library, &query(|q| q.search = "alan".to_owned()))),
            ["Alan's Diary", "Watchmen"]
        );
    }

    #[test]
    fn a_query_that_matches_nothing_returns_nothing() {
        let library = [publication("Akira"), publication("Bone")];
        assert!(arrange(&library, &query(|q| q.search = "zzz".to_owned())).is_empty());
    }

    #[test]
    fn a_genre_or_a_tag_surfaces_what_title_series_and_author_do_not() {
        let library = [
            with("Watchmen", |p| p.genres = vec!["Noir".to_owned()]),
            with("Akira", |p| p.tags = vec!["Cyberpunk".to_owned()]),
            publication("Bone"),
        ];
        assert_eq!(
            titles(&arrange(&library, &query(|q| q.search = "noir".to_owned()))),
            ["Watchmen"]
        );
        assert_eq!(
            titles(&arrange(
                &library,
                &query(|q| q.search = "cyberpunk".to_owned())
            )),
            ["Akira"]
        );
    }

    #[test]
    fn title_series_and_author_are_searched_folded_for_case_and_accents() {
        let library = [
            publication("Café Noir"),
            with("Bone #1", |p| p.series = Some("Bône".to_owned())),
            with("Persepolis", |p| {
                p.authors = vec!["Marjane Satrapi".to_owned()]
            }),
            with("Asterix", |p| p.authors = vec!["René Goscinny".to_owned()]),
        ];
        let found = |term: &str| {
            titles(&arrange(&library, &query(|q| q.search = term.to_owned())))
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        };
        assert_eq!(found("CAFE"), ["Café Noir"]);
        assert_eq!(found("bone"), ["Bone #1"]);
        assert_eq!(found("rene"), ["Asterix"]);
        assert_eq!(found("Réne"), ["Asterix"]);
        assert_eq!(found("satrapi"), ["Persepolis"]);
        assert_eq!(found("  café  "), ["Café Noir"]);
    }

    #[test]
    fn a_search_reaches_past_the_library_filter() {
        let library = [
            with("Akira", |p| p.source_id = Some("one".to_owned())),
            with("Akira Club", |p| p.source_id = Some("two".to_owned())),
        ];
        let scoped = query(|q| q.scope = LibraryScope::Source("one".to_owned()));
        assert_eq!(titles(&arrange(&library, &scoped)), ["Akira"]);
        let searched = query(|q| {
            q.scope = LibraryScope::Source("one".to_owned());
            q.search = "akira".to_owned();
        });
        assert_eq!(
            titles(&arrange(&library, &searched)),
            ["Akira", "Akira Club"]
        );
    }
}

mod filters {
    use super::*;

    #[test]
    fn filters_combine_with_and_and_values_in_one_group_with_or() {
        let matching = with("Watchmen", |p| {
            p.publisher = Some("DC".to_owned());
            p.year = Some(1986);
            p.language = Some("en".to_owned());
            p.genres = vec!["Superhero".to_owned()];
            p.tags = vec!["Reprint".to_owned()];
        });
        let miss = with("Watchmen Companion", |p| {
            p.publisher = Some("Marvel".to_owned());
            p.year = Some(1986);
            p.language = Some("en".to_owned());
            p.genres = vec!["Superhero".to_owned()];
            p.tags = vec!["Reprint".to_owned()];
        });
        let every_group = query(|q| {
            q.formats = vec![PublicationFormat::Cbz];
            q.languages = vec!["en".to_owned()];
            q.publishers = vec!["DC".to_owned()];
            q.genres = vec!["Superhero".to_owned()];
            q.tags = vec!["Reprint".to_owned()];
            q.years = YearRange {
                from: Some(1980),
                to: Some(1989),
            };
        });
        let library = [matching, miss];
        assert_eq!(titles(&arrange(&library, &every_group)), ["Watchmen"]);
        let either = query(|q| q.publishers = vec!["DC".to_owned(), "Marvel".to_owned()]);
        assert_eq!(arrange(&library, &either).len(), 2);
    }

    #[test]
    fn a_format_filter_keeps_only_that_format() {
        let library = [
            publication("Akira"),
            with("Dune", |p| p.format = PublicationFormat::Epub),
        ];
        let epubs = query(|q| q.formats = vec![PublicationFormat::Epub]);
        assert_eq!(titles(&arrange(&library, &epubs)), ["Dune"]);
    }

    #[test]
    fn a_status_filter_never_keeps_a_publication_with_no_status() {
        let library = [
            with("Saga", |p| p.status = Some(PublicationStatus::Ongoing)),
            publication("Bone"),
        ];
        let ongoing = query(|q| q.statuses = vec![PublicationStatus::Ongoing]);
        assert_eq!(titles(&arrange(&library, &ongoing)), ["Saga"]);
    }

    #[test]
    fn a_publication_with_no_year_is_outside_an_active_range() {
        let library = [
            with("Maus", |p| p.year = Some(1991)),
            publication("Undated"),
        ];
        let since = query(|q| {
            q.years = YearRange {
                from: Some(1990),
                to: None,
            }
        });
        assert_eq!(titles(&arrange(&library, &since)), ["Maus"]);
        assert!(YearRange::default().contains(None));
    }

    #[test]
    fn a_source_filter_keeps_that_source_alone() {
        let library = [
            with("Akira", |p| p.source_id = Some("nas".to_owned())),
            with("Bone", |p| p.source_id = Some("folder".to_owned())),
        ];
        let nas = query(|q| q.scope = LibraryScope::Source("nas".to_owned()));
        assert_eq!(titles(&arrange(&library, &nas)), ["Akira"]);
    }

    #[test]
    fn read_state_filters_on_what_the_progress_store_says() {
        let akira = publication("Akira");
        let bone = publication("Bone");
        let maus = publication("Maus");
        let progress = ProgressIndex::new(vec![
            read(&akira, 9, 10, true, 10),
            read(&bone, 5, 10, false, 20),
            // Opened and never moved: still unread.
            read(&maus, 0, 10, false, 30),
        ]);
        let library = [akira, bone, maus];
        let state = |states: Vec<ReadState>| {
            let shelf = LibraryIndex::arrange(
                &library,
                &query(|q| q.read_states = states),
                &english(),
                &progress,
                |_| false,
            );
            titles(&shelf)
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        };
        assert_eq!(state(vec![ReadState::InProgress]), ["Bone"]);
        assert_eq!(state(vec![ReadState::Finished]), ["Akira"]);
        assert_eq!(state(vec![ReadState::Unread]), ["Maus"]);
    }

    #[test]
    fn the_download_filter_keeps_what_was_asked_and_the_sorted_order() {
        let library = [
            publication("Akira"),
            publication("Bone"),
            publication("Maus"),
        ];
        let downloaded = |p: &Publication| p.display_title != "Bone";
        let run = |filter: DownloadFilter| {
            let shelf = LibraryIndex::arrange(
                &library,
                &query(|q| q.downloads = filter),
                &english(),
                &ProgressIndex::default(),
                downloaded,
            );
            titles(&shelf)
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        };
        assert_eq!(run(DownloadFilter::Either), ["Akira", "Bone", "Maus"]);
        assert_eq!(run(DownloadFilter::Downloaded), ["Akira", "Maus"]);
        assert_eq!(run(DownloadFilter::NotDownloaded), ["Bone"]);
        assert!(!DownloadFilter::Either.is_active());
        assert!(DownloadFilter::Downloaded.is_active());
    }

    #[test]
    fn a_group_counts_once_and_clearing_keeps_the_search_and_the_sort() {
        let busy = query(|q| {
            q.search = "bone".to_owned();
            q.sort = LibrarySort::Year;
            q.formats = vec![PublicationFormat::Cbz, PublicationFormat::Cbr];
            q.years = YearRange {
                from: Some(1990),
                to: Some(2000),
            };
            q.downloads = DownloadFilter::Downloaded;
        });
        assert_eq!(busy.active_filter_count(), 3);
        assert!(busy.is_narrowed());
        let cleared = busy.without_filters();
        assert_eq!(cleared.active_filter_count(), 0);
        assert_eq!(cleared.search, "bone");
        assert_eq!(cleared.sort, LibrarySort::Year);
    }

    #[test]
    fn a_query_written_by_an_older_build_still_reads() {
        let stored: LibraryQuery =
            serde_json::from_str(r#"{"search":"x","formats":["cbz","audiobook"],"sort":"series"}"#)
                .unwrap();
        assert_eq!(stored.search, "x");
        assert_eq!(stored.formats, [PublicationFormat::Cbz]);
        assert_eq!(stored.sort, LibrarySort::Series);
        assert!(stored.ascending);
        assert_eq!(stored.scope, LibraryScope::AllSources);
        let round = serde_json::to_string(&stored).unwrap();
        assert_eq!(
            serde_json::from_str::<LibraryQuery>(&round).unwrap(),
            stored
        );
    }
}

mod home {
    use super::*;

    fn issue(series: &str, number: &str) -> Publication {
        Publication {
            series: Some(series.to_owned()),
            number: Some(number.to_owned()),
            ..Publication::new(
                PublicationIdentity::path(format!("/{series}/{number}.cbz")),
                PublicationFormat::Cbz,
                format!("{series} #{number}"),
                MetadataOrigin::Inferred,
            )
        }
    }

    fn up_next(library: &[Publication], progress: Vec<ReadingProgress>) -> Vec<String> {
        LibraryIndex::up_next(library, 12, &ProgressIndex::new(progress))
            .iter()
            .map(Publication::id)
            .collect()
    }

    #[test]
    fn the_issue_after_the_one_finished_is_offered() {
        let (first, second) = (issue("Saga", "1"), issue("Saga", "2"));
        let progress = vec![read(&first, 9, 10, true, 1000)];
        assert_eq!(up_next(&[first, second.clone()], progress), [second.id()]);
    }

    #[test]
    fn a_series_with_something_part_read_offers_nothing() {
        let (first, second, third) = (issue("Saga", "1"), issue("Saga", "2"), issue("Saga", "3"));
        let progress = vec![
            read(&first, 9, 10, true, 1000),
            read(&second, 4, 10, false, 1000),
        ];
        assert!(up_next(&[first, second, third], progress).is_empty());
    }

    #[test]
    fn a_series_nothing_has_been_read_of_offers_nothing() {
        assert!(up_next(&[issue("Saga", "1"), issue("Saga", "2")], vec![]).is_empty());
    }

    #[test]
    fn a_series_read_to_the_end_offers_nothing() {
        let (first, second) = (issue("Saga", "1"), issue("Saga", "2"));
        let progress = vec![
            read(&first, 9, 10, true, 1000),
            read(&second, 9, 10, true, 1000),
        ];
        assert!(up_next(&[first, second], progress).is_empty());
    }

    #[test]
    fn a_gap_in_a_collection_does_not_re_offer_what_was_skipped() {
        let [one, two, three, four] = ["1", "2", "3", "4"].map(|n| issue("Saga", n));
        let progress = vec![
            read(&one, 9, 10, true, 1000),
            read(&three, 9, 10, true, 1000),
        ];
        assert_eq!(
            up_next(&[one, two, three, four.clone()], progress),
            [four.id()]
        );
    }

    #[test]
    fn series_are_offered_most_recently_read_first() {
        let (older, older_next) = (issue("Bone", "1"), issue("Bone", "2"));
        let (newer, newer_next) = (issue("Saga", "1"), issue("Saga", "2"));
        let progress = vec![
            read(&older, 9, 10, true, 10),
            read(&newer, 9, 10, true, 900),
        ];
        assert_eq!(
            up_next(
                &[older, older_next.clone(), newer, newer_next.clone()],
                progress
            ),
            [newer_next.id(), older_next.id()]
        );
    }

    #[test]
    fn a_publication_with_no_series_contributes_nothing() {
        let alone = publication("Alone");
        let progress = vec![read(&alone, 9, 10, true, 1000)];
        assert!(up_next(&[alone], progress).is_empty());
    }

    /// The three records each phone wrote, read back as the phones wrote them, and Keep
    /// reading ordered from them: the audiobook listened to last, then the comic; the
    /// finished EPUB is in neither shelf.
    #[test]
    fn keep_reading_orders_a_phones_own_history_most_recent_first() {
        for file in ["written-by-ios.json", "written-by-android.json"] {
            let text = std::fs::read_to_string(corpus::manifest::path(&format!("library/{file}")))
                .unwrap();
            let document: serde_json::Value = serde_json::from_str(&text).unwrap();
            let records: Vec<ReadingProgress> =
                serde_json::from_value(document["library"]["progress"].clone()).unwrap();
            let comic = Publication::new(
                PublicationIdentity::path("/a.cbz"),
                PublicationFormat::Cbz,
                "A",
                MetadataOrigin::Inferred,
            );
            let book = Publication::new(
                PublicationIdentity::digest("d2"),
                PublicationFormat::Epub,
                "B",
                MetadataOrigin::Inferred,
            );
            let audiobook = Publication::new(
                PublicationIdentity {
                    server_identifier: Some(ServerIdentifier {
                        source_id: "55555555-5555-5555-5555-555555555555".to_owned(),
                        remote_id: "901".to_owned(),
                    }),
                    ..PublicationIdentity::default()
                },
                PublicationFormat::M4b,
                "C",
                MetadataOrigin::Inferred,
            );
            let never = publication("Never opened");
            let library = [comic, book, audiobook, never];
            let progress = ProgressIndex::new(records);
            let shelf = LibraryIndex::continue_reading(&library, 12, &progress);
            assert_eq!(titles(&shelf), ["C", "A"], "{file}");
            let summary = progress.summary(&library[0]);
            assert_eq!(summary.state, ReadState::InProgress, "{file}");
            assert!((summary.fraction - 12.0 / 40.0).abs() < 0.05, "{file}");
            assert_eq!(progress.summary(&library[1]).state, ReadState::Finished);
            assert_eq!(progress.summary(&library[3]).state, ReadState::Unread);
        }
    }

    #[test]
    fn keep_reading_respects_its_limit() {
        let library: Vec<Publication> = (0..5).map(|n| publication(&format!("P{n}"))).collect();
        let progress = ProgressIndex::new(
            library
                .iter()
                .enumerate()
                .map(|(n, p)| read(p, 3, 10, false, n as i64))
                .collect(),
        );
        assert_eq!(
            titles(&LibraryIndex::continue_reading(&library, 2, &progress)),
            ["P4", "P3"]
        );
    }

    #[test]
    fn next_and_previous_follow_the_issue_number() {
        let library = [
            issue("Bone", "10"),
            issue("Bone", "2"),
            issue("Bone", "9"),
            issue("Saga", "3"),
        ];
        let next = LibraryIndex::next(&library[2], &library).unwrap();
        assert_eq!(next.display_title, "Bone #10");
        let previous = LibraryIndex::previous(&library[2], &library).unwrap();
        assert_eq!(previous.display_title, "Bone #2");
        assert!(LibraryIndex::next(&library[0], &library).is_none());
        assert!(LibraryIndex::next(&publication("Alone"), &library).is_none());
    }
}
