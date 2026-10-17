//! Downloads (task 3.19; `offline-downloads`, `desktop-experience`, *Metered connections*
//! and *No presence when the app is closed*): the queue the core keeps, the transfers it
//! starts, the page that shows it and the prompt a quit owes. The rules are
//! `download_rules.rs`. Transfers run on workers; this module only moves their results
//! onto the interface thread once a second. A download that finishes lands in the downloads
//! folder, which the library reads as a folder of its own; no notification is posted.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::downloads::policy::{DownloadPolicy, NetworkState};
use storyarc_core::downloads::queue::{Download, DownloadQueue, DownloadState, FailureReason};
use storyarc_core::downloads::transfer::TransferError;
use storyarc_core::downloads::{DownloadFolder, Landed, LandingError};
use storyarc_core::io::CancelToken;
use storyarc_core::metered::NetworkWatch;
use storyarc_core::net::{Credential, HttpError, Request};
use storyarc_core::secrets::SecretKey;
use storyarc_core::sources::kavita::{KavitaAddress, KavitaClient};
use storyarc_core::sources::opds::OpdsCatalogue;

use crate::app::Shared;
use crate::download_rules;
use crate::remote_sources::{Kind, RemoteRecord};
use crate::services::Services;
use crate::session::{self, LOG_DOMAIN};
use crate::storage_rules;
use crate::strings::{tr, tr_args};

/// What a transfer reported since the last look, by download id.
type Progress = Arc<Mutex<HashMap<String, (u64, Option<u64>)>>>;
/// A transfer's end, brought back to the interface thread.
type Finished = Arc<Mutex<Vec<(String, Result<Landed, LandingError>)>>>;

#[derive(Default)]
pub struct Downloads {
    queue: RefCell<DownloadQueue>,
    network: Cell<Option<NetworkState>>,
    watch: RefCell<Option<NetworkWatch>>,
    tokens: RefCell<HashMap<String, CancelToken>>,
    progress: Progress,
    finished: Finished,
    page: RefCell<Option<adw::Bin>>,
    /// Said once per start when the disk fills: the grey line on the page.
    full_disk: Cell<bool>,
    retry_at: RefCell<HashMap<String, std::time::Instant>>,
}

impl Downloads {
    pub fn full_disk(&self) -> bool {
        self.full_disk.get()
    }

    pub fn quit_prompt(&self) -> Option<download_rules::QuitPrompt> {
        download_rules::quit_prompt(&self.queue.borrow())
    }

    pub fn is_known(&self, id: &str) -> bool {
        self.queue.borrow().get(id).is_some()
    }

    pub fn used_bytes(&self) -> u64 {
        self.queue.borrow().bytes_on_disk()
    }
}

/// Loads the saved queue (a row that was running comes back queued), reads the network
/// and starts what the policy allows. Called once the services are up.
pub fn start(shared: &Shared) {
    let Some(services) = shared.services.get() else {
        return;
    };
    let loaded = DownloadQueue::load(&session::queue_path()).unwrap_or_else(|error| {
        glib::g_warning!(LOG_DOMAIN, "Could not read the download queue: {error:?}");
        DownloadQueue::default()
    });
    *shared.downloads.queue.borrow_mut() = download_rules::at_launch(&loaded);
    *shared.downloads.watch.borrow_mut() = Some(NetworkWatch::new(services.provider.as_ref()));
    shared.downloads.network.set(Some(services.network()));
    apply_network(shared, services.network());
    let weak = Rc::downgrade(shared);
    glib::timeout_add_local(Duration::from_secs(1), move || {
        let Some(shared) = weak.upgrade() else {
            return glib::ControlFlow::Break;
        };
        tick(&shared);
        glib::ControlFlow::Continue
    });
}

/// The reader's policy: unmetered only, as the preferences say, and the core's defaults
/// for how many run at once.
fn policy(shared: &Shared) -> DownloadPolicy {
    DownloadPolicy {
        unmetered_only: shared.preferences().unmetered_only,
        ..DownloadPolicy::default()
    }
}

/// The metered rule was changed in the preferences: held rows are held or released now.
pub fn policy_changed(shared: &Shared) {
    if let Some(network) = shared.downloads.network.get() {
        apply_network(shared, network);
    }
}

/// Removes every download, running ones included: transfers stop, the files go and the
/// queue empties. Reading positions are not touched.
pub fn clear_all(shared: &Shared, root: &std::path::Path) -> std::io::Result<()> {
    let ids: Vec<String> = shared
        .downloads
        .queue
        .borrow()
        .downloads()
        .iter()
        .map(|d| d.id.clone())
        .collect();
    stop_transfers(shared, &ids);
    *shared.downloads.queue.borrow_mut() = DownloadQueue::default();
    save(shared);
    let cleared = crate::storage_rules::clear(root);
    crate::sources::refresh(shared);
    render(shared);
    cleared
}

fn save(shared: &Shared) {
    if let Err(error) = shared.downloads.queue.borrow().save(&session::queue_path()) {
        glib::g_warning!(LOG_DOMAIN, "Could not save the download queue: {error:?}");
    }
}

/// One look: the network, what the transfers reported, what ended, what is due to retry.
fn tick(shared: &Shared) {
    let Some(services) = shared.services.get() else {
        return;
    };
    let changed = shared
        .downloads
        .watch
        .borrow_mut()
        .as_mut()
        .and_then(|watch| watch.poll(services.provider.as_ref()));
    if let Some(network) = changed {
        shared.downloads.network.set(Some(network));
        apply_network(shared, network);
    }
    let reported: Vec<_> = shared
        .downloads
        .progress
        .lock()
        .map(|mut map| map.drain().collect())
        .unwrap_or_default();
    let ended: Vec<_> = shared
        .downloads
        .finished
        .lock()
        .map(|mut list| std::mem::take(&mut *list))
        .unwrap_or_default();
    let busy = !reported.is_empty() || !ended.is_empty();
    for (id, (done, total)) in reported {
        let next = shared.downloads.queue.borrow().advancing(&id, done, total);
        *shared.downloads.queue.borrow_mut() = next;
    }
    for (id, result) in ended {
        finished(shared, &id, result);
    }
    let due: Vec<String> = shared
        .downloads
        .retry_at
        .borrow()
        .iter()
        .filter(|(_, at)| **at <= std::time::Instant::now())
        .map(|(id, _)| id.clone())
        .collect();
    for id in due {
        shared.downloads.retry_at.borrow_mut().remove(&id);
        let next = shared.downloads.queue.borrow().resuming(&id);
        *shared.downloads.queue.borrow_mut() = next;
        pump(shared);
    }
    if busy {
        render(shared);
    }
}

/// The network or the policy changed: pause what the policy holds back, stop those
/// transfers (their partial files stay), and start what may run.
fn apply_network(shared: &Shared, network: NetworkState) {
    let policy = policy(shared);
    let used = shared.downloads.used_bytes();
    let (next, stopped) =
        download_rules::network_changed(&shared.downloads.queue.borrow(), network, &policy, used);
    *shared.downloads.queue.borrow_mut() = next;
    stop_transfers(shared, &stopped);
    pump(shared);
}

fn stop_transfers(shared: &Shared, ids: &[String]) {
    for id in ids {
        if let Some(token) = shared.downloads.tokens.borrow_mut().remove(id) {
            token.cancel();
        }
    }
}

/// Starts what the queue says may start now.
fn pump(shared: &Shared) {
    let Some(services) = shared.services.get() else {
        return;
    };
    let network = shared
        .downloads
        .network
        .get()
        .unwrap_or(NetworkState::Unmetered);
    let policy = policy(shared);
    let startable = shared.downloads.queue.borrow().startable(network, &policy);
    for id in startable {
        start_transfer(shared, &services, &id);
    }
    save(shared);
    render(shared);
}

fn start_transfer(shared: &Shared, services: &Arc<Services>, id: &str) {
    let Some(download) = shared.downloads.queue.borrow().get(id).cloned() else {
        return;
    };
    let record = download.source_id.as_deref().and_then(|source| {
        shared
            .remote
            .entries
            .borrow()
            .iter()
            .find(|e| e.record.id == source)
            .map(|e| e.record.clone())
    });
    let next = shared
        .downloads
        .queue
        .borrow()
        .marking(id, DownloadState::Running);
    *shared.downloads.queue.borrow_mut() = next;
    let token = CancelToken::new();
    shared
        .downloads
        .tokens
        .borrow_mut()
        .insert(id.to_owned(), token.clone());
    let progress = shared.downloads.progress.clone();
    let finished_list = shared.downloads.finished.clone();
    let services = services.clone();
    let root = services.locations.downloads.clone();
    glib::spawn_future_local(async move {
        let _ = gio::spawn_blocking(move || {
            let result = transfer(
                &services,
                &root,
                &download,
                record.as_ref(),
                &token,
                &progress,
            );
            if let Ok(mut list) = finished_list.lock() {
                list.push((download.id.clone(), result));
            }
        })
        .await;
    });
}

fn transfer(
    services: &Services,
    root: &std::path::Path,
    download: &Download,
    record: Option<&RemoteRecord>,
    cancel: &CancelToken,
    progress: &Progress,
) -> Result<Landed, LandingError> {
    let request = request_for(services, download, record).map_err(|detail| {
        LandingError::Transfer(TransferError::Network(HttpError::Unreachable(detail)))
    })?;
    let id = download.id.clone();
    let sink = progress.clone();
    std::fs::create_dir_all(root).map_err(|e| LandingError::Disk(e.to_string()))?;
    DownloadFolder::new(root).fetch(
        &services.http,
        &download.id,
        &download.title,
        request,
        None,
        cancel,
        move |done, total| {
            if let Ok(mut map) = sink.lock() {
                map.insert(id.clone(), (done, total));
            }
        },
    )
}

/// The request a download sends, signed for its source's own origin and nowhere else.
fn request_for(
    services: &Services,
    download: &Download,
    record: Option<&RemoteRecord>,
) -> Result<Request, String> {
    let Some(record) = record else {
        let url = download
            .remote
            .parse()
            .map_err(|_| "not an address".to_owned())?;
        return Ok(Request::get(url));
    };
    let key = SecretKey::for_source(&record.id, record.kind.secret_field());
    let secret = services.vault.load(&key).ok().flatten();
    match record.kind {
        Kind::Catalogue => {
            let root = record
                .address
                .parse()
                .map_err(|_| "not an address".to_owned())?;
            let credential = match (&record.username, secret) {
                (Some(username), Some(password)) => Some(Credential::Basic {
                    username: username.clone(),
                    password,
                }),
                _ => None,
            };
            let catalogue = OpdsCatalogue::new(&services.http, root, credential)
                .map_err(|error| error.to_string())?;
            let url = download
                .remote
                .parse()
                .map_err(|_| "not an address".to_owned())?;
            Ok(catalogue.request(&url))
        }
        Kind::Kavita => {
            let id: i64 = download
                .remote
                .strip_prefix("chapter:")
                .and_then(|n| n.parse().ok())
                .ok_or_else(|| "not a chapter".to_owned())?;
            let key = secret.ok_or_else(|| "the API key is not held".to_owned())?;
            let address = KavitaAddress::parse(&record.address, key)
                .ok_or_else(|| "not an address".to_owned())?;
            let client = KavitaClient::new(&services.http, address).map_err(|e| e.to_string())?;
            client.connect().map_err(|e| e.to_string())?;
            client.chapter_request(id).map_err(|e| e.to_string())
        }
        Kind::Share => Err("a share is read in place".to_owned()),
    }
}

/// A transfer ended: the row lands, fails, retries or stays as the reader left it.
fn finished(shared: &Shared, id: &str, result: Result<Landed, LandingError>) {
    shared.downloads.tokens.borrow_mut().remove(id);
    let queue = shared.downloads.queue.borrow().clone();
    let held = queue
        .get(id)
        .is_none_or(|d| matches!(d.state, DownloadState::Paused(_)));
    let next = match result {
        Ok(landed) => {
            let now = glib::real_time() / 1000;
            let next = queue.finishing(id, landed.length, now);
            // The library reads the downloads folder, so it shows the new file at once.
            crate::sources::refresh(shared);
            next
        }
        // Stopped by a pause, a removal or a network change: the row already says so.
        Err(_) if held => queue,
        Err(LandingError::Unreadable) => queue.failing_verification(id, FailureReason::Unreadable),
        Err(error) => {
            let reason = FailureReason::from(&error);
            if reason == FailureReason::Disk {
                shared.downloads.full_disk.set(true);
            }
            let next = queue.failing(id, reason, error.is_transient());
            if let Some(row) = next.get(id)
                && DownloadQueue::should_retry(row)
                && let DownloadState::Failed { attempts, .. } = row.state
            {
                shared.downloads.retry_at.borrow_mut().insert(
                    id.to_owned(),
                    std::time::Instant::now() + DownloadQueue::backoff(attempts),
                );
            }
            next
        }
    };
    *shared.downloads.queue.borrow_mut() = next;
    pump(shared);
}

// ---- the reader's controls ---------------------------------------------------------

/// Download this: queued from a catalogue or a Kavita chapter. Started by hand, so it
/// runs on a metered connection too.
pub fn enqueue(shared: &Shared, id: &str, title: &str, remote: &str, source_id: &str) {
    let network = shared
        .downloads
        .network
        .get()
        .unwrap_or(NetworkState::Unmetered);
    let mut download = Download::new(id, title, remote);
    download.source_id = Some(source_id.to_owned());
    let next = download_rules::started_by_hand(
        &shared.downloads.queue.borrow(),
        download,
        network,
        &policy(shared),
        shared.downloads.used_bytes(),
    );
    *shared.downloads.queue.borrow_mut() = next;
    pump(shared);
}

#[derive(Clone, Copy)]
enum Control {
    Pause,
    Resume,
    Remove,
}

fn control(shared: &Shared, id: &str, what: Control) {
    let queue = shared.downloads.queue.borrow().clone();
    let next = match what {
        Control::Pause => {
            stop_transfers(shared, &[id.to_owned()]);
            queue.pausing(id)
        }
        Control::Resume => queue.resuming(id),
        Control::Remove => {
            stop_transfers(shared, &[id.to_owned()]);
            if let Some(services) = shared.services.get() {
                DownloadFolder::new(&services.locations.downloads).remove(id);
            }
            crate::sources::refresh(shared);
            queue.removing(id)
        }
    };
    *shared.downloads.queue.borrow_mut() = next;
    pump(shared);
}

fn control_all(shared: &Shared, pause: bool) {
    let ids: Vec<String> = shared
        .downloads
        .queue
        .borrow()
        .pending()
        .map(|d| d.id.clone())
        .collect();
    let queue = shared.downloads.queue.borrow().clone();
    if pause {
        stop_transfers(shared, &ids);
        *shared.downloads.queue.borrow_mut() = queue.pausing_all();
    } else {
        *shared.downloads.queue.borrow_mut() = queue.resuming_all();
    }
    pump(shared);
}

/// What quitting does to the transfers: each stops, its partial file stays, and the saved
/// queue brings it back at the next launch.
pub fn pause_for_quit(shared: &Shared) {
    let ids: Vec<String> = shared.downloads.tokens.borrow().keys().cloned().collect();
    stop_transfers(shared, &ids);
    save(shared);
}

// ---- the page ----------------------------------------------------------------------

/// The container the library window puts on its Downloads destination.
pub fn page(shared: &Shared) -> adw::Bin {
    let bin = adw::Bin::new();
    *shared.downloads.page.borrow_mut() = Some(bin.clone());
    render(shared);
    bin
}

fn size(bytes: u64) -> String {
    glib::format_size(bytes).to_string()
}

fn subtitle(download: &Download, full_disk: bool) -> (String, bool) {
    if let Some(line) = download_rules::waiting_line(&download.state) {
        return (line, true);
    }
    match &download.state {
        DownloadState::Running | DownloadState::Queued => {
            let done = size(download.downloaded_bytes);
            match (download.expected_bytes, download.fraction()) {
                (Some(total), Some(fraction)) => (
                    tr_args(
                        "downloads.progress %d %s %s",
                        "%1$d%% · %2$s of %3$s",
                        &[&((fraction * 100.0) as u32), &done, &size(total)],
                    ),
                    false,
                ),
                _ => (
                    tr_args("downloads.progress.unsized %s", "%s so far", &[&done]),
                    false,
                ),
            }
        }
        DownloadState::Failed { reason, attempts } => {
            let text = match reason {
                FailureReason::Disk if full_disk => storage_rules::full_disk_line(),
                FailureReason::Unsupported(format) => tr_args(
                    "library.skipped.reason.unsupported %s",
                    "%s is not a format StoryArc reads",
                    &[format],
                ),
                _ => tr("downloads.failure.unknown", "The download failed."),
            };
            (
                tr_args(
                    "downloads.failed %s %d@SettingsFeature",
                    "Failed after %2$d attempts: %1$s",
                    &[&text, attempts],
                ),
                true,
            )
        }
        DownloadState::Finished => (size(download.downloaded_bytes), false),
        DownloadState::Paused(_) => (String::new(), true),
    }
}

fn row(shared: &Shared, download: &Download) -> adw::ActionRow {
    let (line, grey) = subtitle(download, shared.downloads.full_disk.get());
    let row = adw::ActionRow::builder()
        .title(glib::markup_escape_text(&download.title))
        .subtitle(glib::markup_escape_text(&line))
        .build();
    if grey {
        row.add_css_class("dimmed");
    }
    if let (DownloadState::Running, Some(fraction)) = (&download.state, download.fraction()) {
        row.add_suffix(
            &gtk::ProgressBar::builder()
                .fraction(fraction)
                .valign(gtk::Align::Center)
                .width_request(96)
                .build(),
        );
    }
    let menu = gio::Menu::new();
    let group = gio::SimpleActionGroup::new();
    let add = |name: &str, label: String, what: Control| {
        menu.append(Some(&label), Some(&format!("row.{name}")));
        let action = gio::SimpleAction::new(name, None);
        let on = shared.clone();
        let id = download.id.clone();
        action.connect_activate(move |_, _| control(&on, &id, what));
        group.add_action(&action);
    };
    match &download.state {
        DownloadState::Finished => {}
        DownloadState::Paused(_) | DownloadState::Failed { .. } => {
            let label = if matches!(download.state, DownloadState::Failed { .. }) {
                tr("downloads.retry", "Retry")
            } else {
                tr("downloads.resume", "Resume")
            };
            add("resume", label, Control::Resume);
        }
        _ => add("pause", tr("downloads.pause", "Pause"), Control::Pause),
    }
    add(
        "remove",
        tr("downloads.remove", "Remove download"),
        Control::Remove,
    );
    let button = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .menu_model(&menu)
        .valign(gtk::Align::Center)
        .css_classes(["flat"])
        .tooltip_text(tr_args(
            "downloads.actions %s",
            "Actions for “%s”",
            &[&download.title],
        ))
        .build();
    button.update_property(&[gtk::accessible::Property::Label(&tr_args(
        "downloads.actions %s",
        "Actions for “%s”",
        &[&download.title],
    ))]);
    button.insert_action_group("row", Some(&group));
    row.add_suffix(&button);
    row
}

/// Redraws the page from the queue.
pub fn render(shared: &Shared) {
    let Some(bin) = shared.downloads.page.borrow().clone() else {
        return;
    };
    let queue = shared.downloads.queue.borrow().clone();
    if queue.downloads().is_empty() {
        bin.set_child(Some(
            &adw::StatusPage::builder()
                .icon_name("folder-download-symbolic")
                .title(tr("sidebar.downloads", "Downloads"))
                .description(tr(
                    "downloads.none",
                    "Nothing is downloaded. A book you open from an online library is kept on this device.",
                ))
                .build(),
        ));
        return;
    }
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .margin_top(18)
        .margin_bottom(18)
        .margin_start(18)
        .margin_end(18)
        .build();
    let pending: Vec<&Download> = queue.pending().collect();
    if !pending.is_empty() {
        let group = adw::PreferencesGroup::builder()
            .title(tr("downloads.pending", "In progress"))
            .build();
        let menu = gio::Menu::new();
        menu.append(
            Some(&tr("downloads.pauseAll", "Pause all")),
            Some("all.pause"),
        );
        menu.append(
            Some(&tr("downloads.resumeAll", "Resume all")),
            Some("all.resume"),
        );
        let actions = gio::SimpleActionGroup::new();
        for (name, pause) in [("pause", true), ("resume", false)] {
            let action = gio::SimpleAction::new(name, None);
            let on = shared.clone();
            action.connect_activate(move |_, _| control_all(&on, pause));
            actions.add_action(&action);
        }
        let all = gtk::MenuButton::builder()
            .icon_name("view-more-symbolic")
            .menu_model(&menu)
            .css_classes(["flat"])
            .tooltip_text(tr("downloads.all", "All downloads"))
            .build();
        all.update_property(&[gtk::accessible::Property::Label(&tr(
            "downloads.all",
            "All downloads",
        ))]);
        all.insert_action_group("all", Some(&actions));
        group.set_header_suffix(Some(&all));
        for download in pending {
            group.add(&row(shared, download));
        }
        column.append(&group);
    }
    let done: Vec<&Download> = queue.finished().collect();
    if !done.is_empty() {
        let group = adw::PreferencesGroup::builder()
            .title(tr("downloads.onDevice", "On this device"))
            .build();
        for download in done {
            group.add(&row(shared, download));
        }
        column.append(&group);
    }
    bin.set_child(Some(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .child(
                &adw::Clamp::builder()
                    .maximum_size(720)
                    .child(&column)
                    .build(),
            )
            .build(),
    ));
}
