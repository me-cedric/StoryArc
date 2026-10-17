//! The rules the Downloads page and the app's quit follow (task 3.19; `desktop-experience`,
//! *Metered connections* and *No presence when the app is closed*; `offline-downloads`).
//! Pure over the core's `DownloadQueue`, `DownloadPolicy` and `NetworkState`, so each rule
//! is a test on any host. `downloads_ui.rs` is the GTK and transfer side.

use storyarc_core::downloads::policy::{DownloadPolicy, NetworkState};
use storyarc_core::downloads::queue::{Download, DownloadQueue, DownloadState, Pause};

use crate::strings::{tr, tr_plural};

/// The queue after the network or the policy changed: what the policy holds back is
/// paused (running rows included, so a change mid-download pauses them), and what it no
/// longer holds goes back in the queue. The ids paused out of `Running` are returned so
/// the caller stops their transfers; the partial files keep what arrived.
pub fn network_changed(
    queue: &DownloadQueue,
    network: NetworkState,
    policy: &DownloadPolicy,
    used: u64,
) -> (DownloadQueue, Vec<String>) {
    let next = queue.holding(network, policy, used);
    let stopped = queue
        .downloads()
        .iter()
        .filter(|before| before.state == DownloadState::Running)
        .filter(|before| {
            next.get(&before.id)
                .is_some_and(|after| matches!(after.state, DownloadState::Paused(_)))
        })
        .map(|before| before.id.clone())
        .collect();
    (next, stopped)
}

/// A download the reader asked for by hand: it runs on a metered connection too.
pub fn started_by_hand(
    queue: &DownloadQueue,
    download: Download,
    network: NetworkState,
    policy: &DownloadPolicy,
    used: u64,
) -> DownloadQueue {
    queue
        .queueing(download.by_hand())
        .holding(network, policy, used)
}

/// The grey line a row says while it waits, and nothing for a row that is not waiting.
pub fn waiting_line(state: &DownloadState) -> Option<String> {
    let DownloadState::Paused(pause) = state else {
        return None;
    };
    Some(match pause {
        Pause::ByReader => tr("downloads.paused.byReader", "Paused"),
        // On a desktop the condition is a metered connection, where the phones say Wi-Fi.
        Pause::WaitingForUnmetered => tr(
            "downloads.paused.waitingForMetered",
            "Waiting for an unmetered connection",
        ),
        Pause::WaitingForNetwork => tr(
            "downloads.paused.waitingForNetwork",
            "Waiting for a connection",
        ),
        Pause::OutOfSpace => tr(
            "downloads.paused.outOfSpace",
            "Not enough space on the device",
        ),
    })
}

/// What the quit prompt says, when one is owed: a download is in progress, so it will
/// pause and resume at the next launch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuitPrompt {
    pub running: usize,
    pub title: String,
    pub body: String,
}

pub fn quit_prompt(queue: &DownloadQueue) -> Option<QuitPrompt> {
    let running = queue
        .downloads()
        .iter()
        .filter(|d| d.state == DownloadState::Running)
        .count();
    if running == 0 {
        return None;
    }
    Some(QuitPrompt {
        running,
        title: tr_plural(
            "downloads.quit.title %d",
            "A download is in progress",
            "Downloads are in progress",
            running as u64,
        ),
        body: tr(
            "downloads.quit.body",
            "It pauses when StoryArc quits and resumes from where it stopped the next time you open StoryArc. The part already downloaded is kept.",
        ),
    })
}

/// The queue as a launch finds it: nothing carried a running row over, so each goes back
/// to the queue and resumes from its partial file.
pub fn at_launch(saved: &DownloadQueue) -> DownloadQueue {
    saved.reclaiming()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn running(id: &str) -> DownloadQueue {
        DownloadQueue::default()
            .queueing(Download::new(id, id, "http://x/a.cbz"))
            .marking(id, DownloadState::Running)
    }

    #[test]
    fn a_metered_connection_holds_back_what_the_policy_queued_and_says_why_in_grey() {
        let queue = DownloadQueue::default().queueing(Download::new("a", "A", "u"));
        let (held, stopped) =
            network_changed(&queue, NetworkState::Metered, &DownloadPolicy::default(), 0);
        let state = &held.get("a").unwrap().state;
        assert_eq!(*state, DownloadState::Paused(Pause::WaitingForUnmetered));
        assert!(stopped.is_empty());
        assert!(waiting_line(state).is_some());
        assert_eq!(waiting_line(&DownloadState::Queued), None);
    }

    #[test]
    fn a_download_started_by_hand_runs_on_a_metered_connection() {
        let queue = started_by_hand(
            &DownloadQueue::default(),
            Download::new("a", "A", "u"),
            NetworkState::Metered,
            &DownloadPolicy::default(),
            0,
        );
        assert_eq!(queue.get("a").unwrap().state, DownloadState::Queued);
        assert_eq!(
            queue.startable(NetworkState::Metered, &DownloadPolicy::default()),
            vec!["a".to_owned()]
        );
    }

    #[test]
    fn an_unmetered_or_undescribed_connection_runs_the_queue_as_the_policy_says() {
        let queue = DownloadQueue::default().queueing(Download::new("a", "A", "u"));
        let (next, _) = network_changed(
            &queue,
            NetworkState::Unmetered,
            &DownloadPolicy::default(),
            0,
        );
        assert_eq!(next.get("a").unwrap().state, DownloadState::Queued);
    }

    #[test]
    fn a_change_to_metered_mid_download_pauses_the_running_row_and_a_return_resumes_it() {
        let policy = DownloadPolicy::default();
        let (paused, stopped) = network_changed(&running("a"), NetworkState::Metered, &policy, 0);
        assert_eq!(stopped, vec!["a".to_owned()]);
        assert!(matches!(
            paused.get("a").unwrap().state,
            DownloadState::Paused(Pause::WaitingForUnmetered)
        ));
        let (back, _) = network_changed(&paused, NetworkState::Unmetered, &policy, 0);
        assert_eq!(back.get("a").unwrap().state, DownloadState::Queued);
    }

    #[test]
    fn with_no_connection_the_queue_waits_in_grey_and_the_readers_pause_is_not_lifted() {
        let policy = DownloadPolicy::default();
        let queue = DownloadQueue::default()
            .queueing(Download::new("a", "A", "u"))
            .queueing(Download::new("b", "B", "u"))
            .pausing("b");
        let (offline, _) = network_changed(&queue, NetworkState::Offline, &policy, 0);
        assert_eq!(
            offline.get("a").unwrap().state,
            DownloadState::Paused(Pause::WaitingForNetwork)
        );
        let (back, _) = network_changed(&offline, NetworkState::Unmetered, &policy, 0);
        assert_eq!(back.get("a").unwrap().state, DownloadState::Queued);
        assert_eq!(
            back.get("b").unwrap().state,
            DownloadState::Paused(Pause::ByReader)
        );
    }

    #[test]
    fn quitting_with_a_download_running_asks_and_says_it_pauses_and_resumes() {
        let prompt = quit_prompt(&running("a")).expect("a prompt is owed");
        assert_eq!(prompt.running, 1);
        assert!(prompt.body.contains("pauses") && prompt.body.contains("resumes"));
        assert_eq!(quit_prompt(&DownloadQueue::default()), None);
        let waiting = DownloadQueue::default().queueing(Download::new("a", "A", "u"));
        assert_eq!(quit_prompt(&waiting), None);
    }

    #[test]
    fn a_launch_puts_a_row_that_was_running_back_in_the_queue_and_keeps_its_bytes() {
        let queue = running("a").advancing("a", 512, Some(1024));
        let dir = crate::scratch::Scratch::new("queue");
        let file = dir.join("queue.json");
        queue.save(&file).unwrap();
        let loaded = at_launch(&DownloadQueue::load(&file).unwrap());
        let row = loaded.get("a").unwrap();
        assert_eq!(row.state, DownloadState::Queued);
        assert_eq!(row.downloaded_bytes, 512);
    }
}
