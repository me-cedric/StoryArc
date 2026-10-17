//! Kavita (task 3.5 of `desktop-clients`).
//!
//! The exchange cases are StoryArcKit's `KavitaExchangeTests`, case for case, because the
//! progress mapping is the rule every platform must answer alike. The client cases run against
//! `pnpm kavita` (`scripts/kavita-server.mjs`) at `STORYARC_KAVITA_URL`, default
//! `http://127.0.0.1:5000`, and skip with a line on stderr when no Kavita mock answers there.
//! On a Mac, port 5000 is the AirPlay receiver's, which answers 403 and is skipped by shape.

use std::collections::HashMap;

use storyarc_core::domain::{
    ProgressPull, PublicationIdentity, ReadingPosition, ReadingProgress, Timestamp,
};
use storyarc_core::net::{HttpClient, TrustStore};
use storyarc_core::runtime::Runtime;
use storyarc_core::sources::kavita::{
    KavitaAddress, KavitaChapter, KavitaClient, KavitaError, KavitaExchange,
};

const EPOCH: Timestamp = Timestamp(1_700_000_000);

fn progress(id: &str, page: i64, of: i64, finished: bool, synced: Option<i64>) -> ReadingProgress {
    ReadingProgress {
        identity: PublicationIdentity::digest(id),
        position: ReadingPosition::page(page, of),
        is_finished: finished,
        finished_at: None,
        updated_at: EPOCH,
        synced_position: synced.map(|s| ReadingPosition::page(s, of)),
    }
}

fn at(id: &str, page: i64) -> ReadingProgress {
    progress(id, page, 10, false, None)
}

fn chapter(id: i64, pages: i64) -> KavitaChapter {
    KavitaChapter {
        id,
        number: "1".into(),
        title: Some(format!("Chapter {id}")),
        pages,
        pages_read: 0,
        files: Vec::new(),
    }
}

fn key(id: &str) -> String {
    PublicationIdentity::digest(id).stable_id()
}

fn pull(remote: &[ReadingProgress], held: &[ReadingProgress]) -> ProgressPull {
    ProgressPull::merging(remote, |wanted| {
        held.iter()
            .find(|record| record.identity.stable_id() == wanted.stable_id())
            .cloned()
    })
}

fn chapters(pairs: &[(&str, KavitaChapter)]) -> HashMap<String, KavitaChapter> {
    pairs
        .iter()
        .map(|(id, chapter)| (key(id), chapter.clone()))
        .collect()
}

// ---- the arithmetic ------------------------------------------------------------------------

#[test]
fn pages_read_is_the_page_before_and_is_clamped() {
    assert_eq!(KavitaExchange::position(3, 8), ReadingPosition::page(2, 8));
    assert_eq!(KavitaExchange::position(0, 8), ReadingPosition::page(0, 8));
    assert_eq!(KavitaExchange::position(99, 8), ReadingPosition::page(7, 8));
}

#[test]
fn against_a_reflowable_position_the_count_becomes_a_fraction_with_no_locator() {
    assert_eq!(
        KavitaExchange::position_like(3, 8, &ReadingPosition::page(0, 8)),
        ReadingPosition::page(2, 8)
    );
    let reflowed = KavitaExchange::position_like(3, 8, &ReadingPosition::reflowable(0.0, "x"));
    assert_eq!(
        reflowed,
        ReadingPosition::reflowable(ReadingPosition::page(2, 8).fraction(), "")
    );
}

#[test]
fn a_position_is_told_to_the_server_as_a_page_number() {
    assert_eq!(
        KavitaExchange::page_number(&ReadingPosition::page(4, 10), 10),
        4
    );
    assert_eq!(
        KavitaExchange::page_number(&ReadingPosition::reflowable(0.5, "{}"), 9),
        4
    );
    assert_eq!(
        KavitaExchange::page_number(&ReadingPosition::page(7, 1), 1),
        0
    );
    assert_eq!(
        KavitaExchange::page_number(&ReadingPosition::page(40, 10), 10),
        9
    );
}

#[test]
fn a_record_the_server_took_is_stamped() {
    let stamped = KavitaExchange::settled(&at("one", 4));
    assert_eq!(stamped.synced_position, Some(ReadingPosition::page(4, 10)));
}

// ---- the sorting ---------------------------------------------------------------------------

#[test]
fn a_server_behind_is_owed_the_position_and_it_is_not_stamped_until_it_lands() {
    let held = progress("one", 8, 10, false, Some(8));
    let exchange = KavitaExchange::of(
        &pull(&[at("one", 2)], &[held]),
        &chapters(&[("one", chapter(41, 10))]),
    );
    assert_eq!(exchange.owed.len(), 1);
    assert_eq!(exchange.owed[0].chapter_id, 41);
    assert_eq!(exchange.owed[0].page_num, 8);
    assert!(!exchange.owed[0].is_mark_read);
    assert!(exchange.to_save.is_empty());
    assert_eq!(
        exchange.owed[0].settled.synced_position,
        Some(ReadingPosition::page(8, 10))
    );
}

#[test]
fn a_finished_local_record_is_owed_a_mark() {
    let held = progress("one", 8, 10, true, Some(2));
    let exchange = KavitaExchange::of(
        &pull(&[at("one", 2)], &[held]),
        &chapters(&[("one", chapter(41, 10))]),
    );
    assert!(exchange.owed[0].is_mark_read);
}

#[test]
fn a_position_adopted_from_the_server_is_written_stamped() {
    let held = progress("one", 2, 10, false, Some(2));
    let exchange = KavitaExchange::of(
        &pull(&[at("one", 6)], &[held]),
        &chapters(&[("one", chapter(41, 10))]),
    );
    assert!(exchange.owed.is_empty());
    assert_eq!(
        exchange.to_save[0].synced_position,
        Some(ReadingPosition::page(6, 10))
    );
}

#[test]
fn one_sweep_sorts_ahead_and_behind_apart() {
    let held = [
        progress("adopt", 1, 10, false, Some(1)),
        progress("push", 9, 10, false, Some(9)),
    ];
    let exchange = KavitaExchange::of(
        &pull(&[at("adopt", 5), at("push", 3)], &held),
        &chapters(&[("adopt", chapter(41, 10)), ("push", chapter(42, 10))]),
    );
    assert_eq!(exchange.to_save.len(), 1);
    assert_eq!(exchange.to_save[0].position, ReadingPosition::page(5, 10));
    let owed: Vec<_> = exchange.owed.iter().map(|o| o.chapter_id).collect();
    assert_eq!(owed, [42]);
    assert_eq!(exchange.owed[0].page_num, 9);
}

#[test]
fn a_conflict_local_wins_is_written_now_and_owed_too() {
    let held = progress("one", 7, 10, false, Some(1));
    let pulled = pull(&[at("one", 4)], &[held]);
    let exchange = KavitaExchange::of(&pulled, &chapters(&[("one", chapter(41, 10))]));
    assert_eq!(pulled.conflicts.len(), 1);
    assert_eq!(
        exchange.to_save[0].synced_position,
        Some(ReadingPosition::page(1, 10))
    );
    assert_eq!(exchange.owed[0].page_num, 7);
}

#[test]
fn a_conflict_the_server_wins_is_adopted_and_owed_nothing() {
    let held = progress("one", 3, 10, false, Some(1));
    let pulled = pull(&[at("one", 8)], &[held]);
    let exchange = KavitaExchange::of(&pulled, &chapters(&[("one", chapter(41, 10))]));
    assert_eq!(pulled.conflicts.len(), 1);
    assert!(exchange.owed.is_empty());
    assert_eq!(
        exchange.to_save[0].synced_position,
        Some(ReadingPosition::page(8, 10))
    );
}

#[test]
fn no_chapter_or_a_pageless_one_is_owed_nothing() {
    let held = progress("one", 8, 10, false, Some(8));
    let pulled = pull(&[at("one", 2)], &[held]);
    assert!(KavitaExchange::of(&pulled, &HashMap::new()).owed.is_empty());
    assert!(
        KavitaExchange::of(&pulled, &chapters(&[("one", chapter(41, 0))]))
            .owed
            .is_empty()
    );
    let empty = KavitaExchange::of(&ProgressPull::default(), &HashMap::new());
    assert!(empty.to_save.is_empty() && empty.owed.is_empty());
}

#[test]
fn a_first_open_is_seeded_from_the_server_and_only_a_first_one() {
    assert_eq!(
        KavitaExchange::open_seed(4, 10, None, false),
        Some(ReadingPosition::page(3, 10))
    );
    assert_eq!(KavitaExchange::open_seed(0, 10, None, false), None);
    assert_eq!(
        KavitaExchange::open_seed(4, 10, Some(&at("one", 7)), false),
        None
    );
    assert_eq!(
        KavitaExchange::open_seed(6, 11, None, true),
        Some(ReadingPosition::reflowable(
            ReadingPosition::page(5, 11).fraction(),
            ""
        ))
    );
    assert_eq!(KavitaExchange::open_seed(4, 0, None, false), None);
}

// ---- against `pnpm kavita` -----------------------------------------------------------------

const KEY: &str = "storyarc-test-key";

fn client(key: &str) -> Option<KavitaClient> {
    let base =
        std::env::var("STORYARC_KAVITA_URL").unwrap_or_else(|_| "http://127.0.0.1:5000".into());
    let http = HttpClient::new(&Runtime::new().unwrap(), TrustStore::new()).unwrap();
    let address = KavitaAddress::parse(&base, key)?;
    let probe = KavitaClient::new(&http, KavitaAddress::parse(&base, KEY)?).ok()?;
    if probe.connect().is_err() {
        eprintln!("skipped: no Kavita mock at {base} (pnpm kavita)");
        return None;
    }
    KavitaClient::new(&http, address).ok()
}

#[test]
fn a_rejected_key_is_named() {
    let Some(client) = client("not-the-key") else {
        return;
    };
    assert_eq!(client.connect().unwrap_err(), KavitaError::KeyRejected);
}

#[test]
fn the_key_signs_in_and_libraries_series_and_chapters_list() {
    let Some(client) = client(KEY) else { return };
    assert_eq!(client.connect().unwrap().username, "ada");
    let libraries = client.libraries().unwrap();
    assert!(libraries.len() >= 2);
    let comics = client.series(Some(libraries[0].id)).unwrap();
    assert!(!comics.is_empty());
    assert!(comics.iter().all(|s| s.library_id == libraries[0].id));
    let everything = client.series(None).unwrap();
    assert!(everything.len() > comics.len());
    let volumes = client.volumes(comics[0].id).unwrap();
    assert!(!volumes[0].chapters.is_empty());
    assert!(volumes[0].chapters[0].file_bytes() > 0);
    assert!(client.series_cover(comics[0].id).is_some());
}

#[test]
fn a_page_pushed_is_the_page_the_server_continues_from() {
    let Some(client) = client(KEY) else { return };
    let library = client.libraries().unwrap()[0].id;
    let series = client
        .series(Some(library))
        .unwrap()
        .into_iter()
        .find(|s| s.name == "Tidal Reach")
        .expect("the corpus holds Tidal Reach 01 to 03");
    let volume = &client.volumes(series.id).unwrap()[0];
    let first = &volume.chapters[0];

    // The reader is on page 5 of 8: Kavita stores pageNum 4 and reports five pages read.
    let local = ReadingProgress::new(
        PublicationIdentity::server("source", first.remote_id()),
        ReadingPosition::page(4, first.pages),
        EPOCH,
    );
    let owed = KavitaExchange::of(
        &ProgressPull {
            to_push: vec![local.clone()],
            ..Default::default()
        },
        &HashMap::from([(local.identity.stable_id(), first.clone())]),
    )
    .owed;
    client
        .push(&owed[0], library, series.id, volume.id)
        .unwrap();
    let after = client.volumes(series.id).unwrap()[0].chapters[0].clone();
    assert_eq!(after.pages_read, 5);
    assert_eq!(
        KavitaExchange::position(after.pages_read, after.pages),
        local.position,
        "the round trip lands on the page it left"
    );
    let next = client.continue_point(series.id).unwrap();
    assert_eq!(next.id, first.id);

    // Finished is pushed as a mark; the server then continues from the next chapter.
    let finished = local.finished(true, EPOCH);
    let mark = KavitaExchange::of(
        &ProgressPull {
            to_push: vec![finished.clone()],
            ..Default::default()
        },
        &HashMap::from([(finished.identity.stable_id(), first.clone())]),
    )
    .owed;
    assert!(mark[0].is_mark_read);
    client
        .push(&mark[0], library, series.id, volume.id)
        .unwrap();
    assert!(client.volumes(series.id).unwrap()[0].chapters[0].is_finished());
    assert_ne!(client.continue_point(series.id).unwrap().id, first.id);
    client.mark(series.id, first.id, false).unwrap();
}

#[test]
fn a_chapter_downloads_through_a_request_signed_for_the_server() {
    let Some(client) = client(KEY) else { return };
    let series = &client.series(None).unwrap()[0];
    let chapter = &client.volumes(series.id).unwrap()[0].chapters[0];
    let http = HttpClient::new(&Runtime::new().unwrap(), TrustStore::new()).unwrap();
    let response = http
        .send(client.chapter_request(chapter.id).unwrap())
        .unwrap();
    assert_eq!(response.status, 200);
    assert_eq!(response.body.len() as i64, chapter.file_bytes());
}
