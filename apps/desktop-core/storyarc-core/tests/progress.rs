//! The progress store and the merge, asserted against the mobile fixtures (task 2.1 of
//! `desktop-clients`).
//!
//! The merge table is ADR-0006's, row by row, the same rows iOS's `ProgressMergeTests` and
//! Android's `ProgressMergeTest` assert. The store reads the three progress records the
//! two library documents in `packages/test-fixtures/library` carry — one written by each
//! platform's encoder — so a position written on a phone is one this core reads back
//! unchanged, whichever phone wrote it.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use storyarc_core::domain::{
    ProgressMerge, ProgressMergeOutcome, PublicationIdentity, ReadingPosition, ReadingProgress,
    Timestamp,
};
use storyarc_core::store::Store;

const EPOCH: Timestamp = Timestamp(1_700_000_000);

fn identity() -> PublicationIdentity {
    PublicationIdentity::digest("abc123")
}

fn progress(page: i64, finished: bool, synced: Option<i64>) -> ReadingProgress {
    ReadingProgress {
        identity: identity(),
        position: ReadingPosition::page(page, 100),
        is_finished: finished,
        finished_at: None,
        updated_at: EPOCH,
        synced_position: synced.map(|page| ReadingPosition::page(page, 100)),
    }
}

mod merge {
    use super::*;

    #[test]
    fn remote_ahead_and_local_untouched_adopts_remote_silently() {
        let local = progress(10, false, Some(10));
        let remote = progress(40, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::AdoptRemote(remote.clone())
        );
    }

    #[test]
    fn remote_behind_local_keeps_local_and_pushes_it() {
        let local = progress(40, false, Some(10));
        let remote = progress(10, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::KeepLocalAndPush(local.clone())
        );
    }

    #[test]
    fn both_moved_resolves_to_the_further_position_and_reports_the_conflict() {
        let local = progress(30, false, Some(10));
        let remote = progress(55, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::Conflict {
                resolved: remote.clone(),
                discarded: ReadingPosition::page(30, 100),
            }
        );
        let local = progress(70, false, Some(10));
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::Conflict {
                resolved: local.clone(),
                discarded: ReadingPosition::page(55, 100),
            }
        );
    }

    #[test]
    fn finished_wins_over_a_further_partial_position() {
        // Remote is finished but sits at page 0; local is untouched at page 90.
        let local = progress(90, false, Some(10));
        let remote = progress(0, true, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::AdoptRemote(remote.clone())
        );
    }

    #[test]
    fn a_locally_finished_publication_is_never_unmarked_by_a_partial_remote() {
        let local = progress(99, true, Some(10));
        let remote = progress(5, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::KeepLocalAndPush(local.clone())
        );
    }

    #[test]
    fn identical_positions_are_not_a_conflict() {
        let local = progress(30, false, Some(10));
        let remote = progress(30, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::KeepLocalAndPush(local.clone())
        );
    }

    #[test]
    fn a_device_with_no_watermark_takes_the_further_position_quietly() {
        // `library-portability`, *A device that never synced*: an import onto a new device
        // must not raise a conflict it invented.
        let local = progress(20, false, None);
        let remote = progress(60, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::AdoptRemote(remote.clone())
        );
        let local = progress(60, false, None);
        let remote = progress(20, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::KeepLocalAndPush(local.clone())
        );
    }

    #[test]
    fn a_synced_position_kept_as_a_bare_fraction_still_counts() {
        // What Android's Room row hands back: the fraction survived, the page did not.
        let mut local = progress(10, false, None);
        local.synced_position = Some(ReadingPosition::reflowable(
            ReadingPosition::page(10, 100).fraction(),
            "",
        ));
        let remote = progress(40, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::AdoptRemote(remote.clone())
        );

        let mut local = progress(40, false, None);
        local.synced_position = Some(ReadingPosition::reflowable(
            ReadingPosition::page(10, 100).fraction(),
            "",
        ));
        let remote = progress(10, false, None);
        assert_eq!(
            ProgressMerge::merge(&local, &remote),
            ProgressMergeOutcome::KeepLocalAndPush(local.clone())
        );
    }
}

mod store {
    use super::*;

    /// The three progress records a library document carries.
    fn fixture_progress(file: &str) -> Vec<ReadingProgress> {
        let text = std::fs::read_to_string(corpus::manifest::path(&format!("library/{file}")))
            .expect("read the library document");
        let document: serde_json::Value = serde_json::from_str(&text).expect("parse");
        serde_json::from_value(document["library"]["progress"].clone())
            .expect("the document's progress records decode")
    }

    #[test]
    fn the_records_both_phones_wrote_decode_to_the_same_three() {
        let ios = fixture_progress("written-by-ios.json");
        let android = fixture_progress("written-by-android.json");
        assert_eq!(ios.len(), 3);
        assert_eq!(ios, android, "the two encoders disagree about the data");
    }

    #[test]
    fn a_phones_records_are_stored_and_read_back_unchanged() {
        for file in ["written-by-ios.json", "written-by-android.json"] {
            let store = Store::in_memory().unwrap();
            let records = fixture_progress(file);
            for record in &records {
                store.save_progress(record).unwrap();
            }
            for record in &records {
                let found = store.progress(&record.identity).unwrap();
                assert_eq!(
                    found.as_ref(),
                    Some(record),
                    "{file}: {:?}",
                    record.identity
                );
            }
            // Most recently read first: the listening record, then the finished book.
            let recent: Vec<_> = store
                .recent_progress(10)
                .unwrap()
                .into_iter()
                .map(|r| r.updated_at.to_rfc3339())
                .collect();
            assert_eq!(
                recent,
                [
                    "2025-12-30T18:40:00Z",
                    "2025-12-30T15:53:20Z",
                    "2025-12-30T13:06:40Z"
                ]
            );
        }
    }

    #[test]
    fn a_record_is_found_by_any_identity_component_in_preference_order() {
        let store = Store::in_memory().unwrap();
        let folder =
            PublicationIdentity::path("/books/Bone 01.cbz").recording_digest(Some("bone-01"));
        store
            .save_progress(&ReadingProgress::new(
                folder,
                ReadingPosition::page(11, 30),
                Timestamp(1_000),
            ))
            .unwrap();

        // The server hands back the bytes it was given, so the digest joins the two — the
        // server identifier arrives alongside and must not fork the record.
        let served = PublicationIdentity::server("55555555", "42")
            .recording_digest(Some("bone-01"))
            .filling(&PublicationIdentity::path("/caches/Kavita/42/Bone 1.cbz"));
        assert_eq!(
            store.progress(&served).unwrap().map(|r| r.position),
            Some(ReadingPosition::page(11, 30))
        );
        store
            .save_progress(&ReadingProgress::new(
                served.clone(),
                ReadingPosition::page(19, 30),
                Timestamp(2_000),
            ))
            .unwrap();
        assert_eq!(
            store.recent_progress(10).unwrap().len(),
            1,
            "one book, one record"
        );

        // Components fill in as they become known: the record is now reachable by the
        // server id alone, and by the original path.
        let by_server = store
            .progress(&PublicationIdentity::server("55555555", "42"))
            .unwrap()
            .expect("found by the server identifier");
        assert_eq!(by_server.position, ReadingPosition::page(19, 30));
        assert_eq!(
            by_server.identity.content_digest.as_deref(),
            Some("bone-01")
        );
        assert_eq!(
            by_server.identity.normalized_path.as_deref(),
            Some("/books/Bone 01.cbz"),
            "the first path stays the filing key"
        );
        assert!(
            store
                .progress(&PublicationIdentity::path("/books/Bone 01.cbz"))
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn lookalike_publications_never_merge() {
        let store = Store::in_memory().unwrap();
        let one = PublicationIdentity::server("s", "42").recording_digest(Some("print-one"));
        let two = PublicationIdentity::server("s", "43").recording_digest(Some("print-two"));
        store
            .save_progress(&ReadingProgress::new(
                one,
                ReadingPosition::page(3, 30),
                Timestamp(1_000),
            ))
            .unwrap();
        store
            .save_progress(&ReadingProgress::new(
                two,
                ReadingPosition::page(8, 30),
                Timestamp(1_000),
            ))
            .unwrap();
        assert_eq!(store.recent_progress(10).unwrap().len(), 2);
    }

    #[test]
    fn finished_is_sticky_on_a_routine_save_and_the_stamp_moves_once() {
        let store = Store::in_memory().unwrap();
        let done = ReadingProgress::new(identity(), ReadingPosition::page(99, 100), Timestamp(10))
            .finished(true, Timestamp(10));
        store.save_progress(&done).unwrap();
        // Reopening writes a new position and must not unmark or restamp.
        store
            .save_progress(&ReadingProgress::new(
                identity(),
                ReadingPosition::page(3, 100),
                Timestamp(20),
            ))
            .unwrap();
        let stored = store.progress(&identity()).unwrap().unwrap();
        assert!(stored.is_finished);
        assert_eq!(stored.finished_at, Some(Timestamp(10)));
        assert_eq!(stored.position, ReadingPosition::page(3, 100));
        assert_eq!(stored.updated_at, Timestamp(20));

        // Unmarking is the deliberate act, and it drops the stamp.
        store
            .mark_finished(&identity(), false, Timestamp(30))
            .unwrap();
        let stored = store.progress(&identity()).unwrap().unwrap();
        assert!(!stored.is_finished);
        assert_eq!(stored.finished_at, None);
        assert_eq!(stored.updated_at, Timestamp(30));
    }

    #[test]
    fn marking_an_unknown_publication_finished_records_a_whole_position() {
        let store = Store::in_memory().unwrap();
        store
            .mark_finished(&identity(), true, Timestamp(5))
            .unwrap();
        let stored = store.progress(&identity()).unwrap().unwrap();
        assert!(stored.is_finished);
        assert_eq!(stored.position, ReadingPosition::page(0, 1));
        assert_eq!(stored.finished_at, Some(Timestamp(5)));
    }

    #[test]
    fn a_synced_position_survives_a_save_that_carries_none() {
        // Every reader save sends none; only an exchange with a server knows one, and
        // overwriting it unconditionally made the next pull see a conflict where there
        // was none.
        let store = Store::in_memory().unwrap();
        store.save_progress(&progress(10, false, Some(10))).unwrap();
        store.save_progress(&progress(12, false, None)).unwrap();
        let stored = store.progress(&identity()).unwrap().unwrap();
        assert_eq!(stored.synced_position, Some(ReadingPosition::page(10, 100)));
        assert_eq!(stored.position, ReadingPosition::page(12, 100));
    }

    #[test]
    fn linking_attaches_what_is_newly_known_and_changes_nothing_about_the_reading() {
        let store = Store::in_memory().unwrap();
        store
            .save_progress(&ReadingProgress::new(
                PublicationIdentity::path("/a.cbz"),
                ReadingPosition::page(4, 10),
                Timestamp(100),
            ))
            .unwrap();
        let learned = PublicationIdentity::path("/a.cbz").recording_digest(Some("sha-a"));
        assert!(store.link_identity(&learned).unwrap());
        assert!(
            !store.link_identity(&learned).unwrap(),
            "nothing new the second time"
        );
        assert!(
            !store
                .link_identity(&PublicationIdentity::path("/unknown.cbz"))
                .unwrap()
        );
        let stored = store
            .progress(&PublicationIdentity::digest("sha-a"))
            .unwrap()
            .expect("found by the digest it was linked to");
        assert_eq!(
            stored.updated_at,
            Timestamp(100),
            "learning a digest is not reading"
        );
    }

    #[test]
    fn forgetting_and_clearing_are_deliberate_and_complete() {
        let store = Store::in_memory().unwrap();
        store.save_progress(&progress(1, false, None)).unwrap();
        store
            .save_progress(&ReadingProgress::new(
                PublicationIdentity::path("/b.cbz"),
                ReadingPosition::page(1, 2),
                EPOCH,
            ))
            .unwrap();
        store.forget_progress(&identity()).unwrap();
        assert!(store.progress(&identity()).unwrap().is_none());
        assert_eq!(store.recent_progress(10).unwrap().len(), 1);
        store.clear_progress().unwrap();
        assert!(store.recent_progress(10).unwrap().is_empty());
    }

    #[test]
    fn the_store_persists_to_a_file_and_reopens() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("library.sqlite");
        {
            let store = Store::open(&path).unwrap();
            store.save_progress(&progress(7, false, None)).unwrap();
        }
        let store = Store::open(&path).unwrap();
        assert_eq!(
            store.progress(&identity()).unwrap().map(|r| r.position),
            Some(ReadingPosition::page(7, 100))
        );
        assert!(store.size_on_disk() > 0);
    }
}
