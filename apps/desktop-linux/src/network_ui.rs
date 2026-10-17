//! The sources screens over the core's SMB, OPDS and Kavita (task 3.17): the add sheets,
//! the list of added libraries with the state of each, and removal. A share is found
//! through `avahi-browse` where it is installed and its daemon answers, and is always
//! enterable by hand. Each failure is named and grey; a secret goes to the vault and the
//! record the sources file keeps holds only its id (`remote_sources.rs`).

use std::cell::RefCell;
use std::process::Command;
use std::sync::Arc;

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::net::Credential;
use storyarc_core::secrets::{Secret, SecretKey};
use storyarc_core::shelves::new_shelf_id;
use storyarc_core::sources::kavita::{KavitaAddress, KavitaClient};
use storyarc_core::sources::opds::{OpdsCatalogue, OpdsError};
use storyarc_core::sources::smb::{SmbLogin, SmbShare};

use crate::app::Shared;
use crate::remote_sources::{self as remote, Kind, RemoteRecord, Said, Suggestion};
use crate::secret_state::{self, Noun, Saved};
use crate::services::Services;
use crate::session;
use crate::strings::{tr, tr_args};

/// One added library and what is known of it now.
#[derive(Clone)]
pub struct RemoteEntry {
    pub record: RemoteRecord,
    /// The grey line: unreachable, or needing a sign-in.
    pub grey: Option<String>,
}

#[derive(Default)]
pub struct RemoteState {
    pub entries: RefCell<Vec<RemoteEntry>>,
}

impl RemoteState {
    pub fn records(&self) -> Vec<RemoteRecord> {
        self.entries
            .borrow()
            .iter()
            .map(|e| e.record.clone())
            .collect()
    }
}

/// Reads the file at start. Whether each secret survived is looked at once the services
/// are up: with no keyring daemon none did, and each source says it needs a sign-in.
pub fn start(shared: &Shared) {
    let records = remote::restore(&session::load_remote_sources());
    *shared.remote.entries.borrow_mut() = records
        .into_iter()
        .map(|record| RemoteEntry { record, grey: None })
        .collect();
}

pub fn check_sign_ins(shared: &Shared) {
    let Some(services) = shared.services.get() else {
        return;
    };
    for entry in shared.remote.entries.borrow_mut().iter_mut() {
        let key = SecretKey::for_source(&entry.record.id, entry.record.kind.secret_field());
        let wants_secret = entry.record.username.is_some() || entry.record.kind == Kind::Kavita;
        if wants_secret && secret_state::needs_sign_in(&services.vault, &key) {
            entry.grey = Some(tr("sources.needsSignIn", "Needs a sign-in"));
        }
    }
    shared.library_changed();
}

fn save(shared: &Shared) {
    session::save_remote_sources(&remote::save(&shared.remote.records()));
}

/// Removes a library: its record, its secret, and any pin of its certificate. Downloads
/// and reading positions are the reader's and stay unless asked for.
pub fn remove(shared: &Shared, id: &str) {
    let removed = {
        let mut entries = shared.remote.entries.borrow_mut();
        let at = entries.iter().position(|e| e.record.id == id);
        at.map(|at| entries.remove(at))
    };
    let Some(removed) = removed else { return };
    if let Some(services) = shared.services.get() {
        let key = SecretKey::for_source(id, removed.record.kind.secret_field());
        let vault_services = services.clone();
        glib::spawn_future_local(async move {
            let _ = gio::spawn_blocking(move || vault_services.vault.delete(&key)).await;
        });
    }
    save(shared);
    shared.library_changed();
}

// ---- the sheets -------------------------------------------------------------------

/// What a worker reports to the sheet.
enum Attempt {
    Added(RemoteRecord, Option<String>),
    Failed(Said),
    Untrusted { host: String, fingerprint: String },
}

struct Sheet {
    dialog: adw::Dialog,
    status: gtk::Label,
    connect: gtk::Button,
}

fn sheet(title: &str, rows: &[&adw::PreferencesGroup]) -> Sheet {
    let status = gtk::Label::builder()
        .wrap(true)
        .xalign(0.0)
        .css_classes(["dimmed"])
        .visible(false)
        .build();
    let connect = gtk::Button::builder()
        .label(tr("smb.connect", "Connect"))
        .css_classes(["suggested-action"])
        .build();
    let header = adw::HeaderBar::new();
    header.pack_end(&connect);
    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(18)
        .margin_top(12)
        .margin_bottom(18)
        .margin_start(18)
        .margin_end(18)
        .build();
    for group in rows {
        column.append(*group);
    }
    column.append(&status);
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&gtk::ScrolledWindow::builder().child(&column).build()));
    let dialog = adw::Dialog::builder()
        .title(title)
        .content_width(440)
        .content_height(520)
        .child(&toolbar)
        .build();
    Sheet {
        dialog,
        status,
        connect,
    }
}

impl Sheet {
    fn say(&self, said: &Said) {
        let mut text = said.text.clone();
        if let Some(remedy) = &said.remedy {
            text = format!("{text} {remedy}.");
        }
        self.status.set_label(&text);
        self.status.set_visible(true);
        self.connect.set_sensitive(true);
    }

    fn working(&self) {
        self.status
            .set_label(&tr("catalogue.connecting", "Connecting…"));
        self.status.set_visible(true);
        self.connect.set_sensitive(false);
    }
}

fn entry(title: &str, text: &str) -> adw::EntryRow {
    adw::EntryRow::builder().title(title).text(text).build()
}

fn password(title: &str) -> adw::PasswordEntryRow {
    adw::PasswordEntryRow::builder().title(title).build()
}

fn group(rows: &[&gtk::Widget]) -> adw::PreferencesGroup {
    let group = adw::PreferencesGroup::new();
    for row in rows {
        group.add(*row);
    }
    group
}

fn name_from(address: &str) -> String {
    address
        .trim_start_matches("smb://")
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_end_matches('/')
        .to_owned()
}

/// Add a network share: host, share, folder, user and password, with the shares the
/// system announces listed first where it announces any.
pub fn present_share(shared: &Shared, parent: &gtk::Window) {
    let host = entry(&tr("smb.host.label", "Host"), "");
    let share = entry(&tr("smb.share.label", "Share"), "");
    let folder = entry(&tr("smb.folder.label", "Folder (optional)"), "");
    let user = entry(&tr("smb.user.label", "User name"), "");
    user.set_tooltip_text(Some(&tr(
        "smb.user.hint",
        "Leave empty to connect as a guest.",
    )));
    let pass = password(&tr("smb.password.label", "Password"));
    let form = group(&[
        host.upcast_ref(),
        share.upcast_ref(),
        folder.upcast_ref(),
        user.upcast_ref(),
        pass.upcast_ref(),
    ]);
    let found = adw::PreferencesGroup::builder()
        .title(tr("smb.found", "On this network"))
        .build();
    let sheet = Rc::new(sheet(
        &tr("smb.title", "Add a shared folder"),
        &[&found, &form],
    ));
    discover(&found, &host, &sheet);

    let on = shared.clone();
    let weak = Rc::downgrade(&sheet);
    sheet.connect.connect_clicked(move |_| {
        let Some(sheet) = weak.upgrade() else { return };
        let Some(address) = remote::share_address(&host.text(), &share.text(), &folder.text())
        else {
            sheet.say(&Said {
                text: tr("smb.error.notAnAddress", "Enter a host and a share name."),
                grey: true,
                remedy: None,
            });
            return;
        };
        let username = user.text().trim().to_owned();
        let secret = pass.text().to_string();
        let record = RemoteRecord {
            id: new_shelf_id(),
            kind: Kind::Share,
            name: address.display_name(),
            address: remote::share_locator(&address),
            username: (!username.is_empty()).then(|| username.clone()),
        };
        let login = if username.is_empty() {
            SmbLogin::Guest
        } else {
            SmbLogin::account(username, Secret::new(secret.clone()))
        };
        let Some(services) = on.services.get() else {
            sheet.say(&starting());
            return;
        };
        sheet.working();
        run(&on, &sheet, move || {
            let identity = SmbShare::check(&services.runtime, address, login);
            match identity {
                Err(error) => Attempt::Failed(remote::smb_failure(&error)),
                Ok(identity) => {
                    let line = if identity.is_encrypted {
                        tr_args("smb.encrypted %s", "%s · encrypted", &[&identity.dialect])
                    } else {
                        tr_args(
                            "smb.notEncrypted %s",
                            "%s · not encrypted",
                            &[&identity.dialect],
                        )
                    };
                    keep(&services, record, secret, Noun::Password, Some(line))
                }
            }
        });
    });
    sheet.dialog.present(Some(parent));
}

use std::rc::Rc;

fn starting() -> Said {
    Said {
        text: tr(
            "network.starting",
            "StoryArc is still starting. Try again in a moment.",
        ),
        grey: true,
        remedy: None,
    }
}

/// Saves the secret and says what became of it, for the success line.
fn keep(
    services: &Arc<Services>,
    record: RemoteRecord,
    secret: String,
    noun: Noun,
    detail: Option<String>,
) -> Attempt {
    if secret.is_empty() {
        return Attempt::Added(record, detail);
    }
    let key = SecretKey::for_source(&record.id, record.kind.secret_field());
    match secret_state::save(&services.vault, &key, Secret::new(secret), noun) {
        Saved::Kept => Attempt::Added(record, detail),
        Saved::ThisSession { grey_line } => {
            let line = [detail, grey_line]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>();
            Attempt::Added(record, (!line.is_empty()).then(|| line.join(" ")))
        }
        Saved::Refused { text } => Attempt::Failed(Said {
            text,
            grey: true,
            remedy: None,
        }),
    }
}

/// Runs an attempt on a worker and brings its result back to the sheet.
fn run(shared: &Shared, sheet: &Rc<Sheet>, work: impl FnOnce() -> Attempt + Send + 'static) {
    let on = shared.clone();
    let sheet = sheet.clone();
    glib::spawn_future_local(async move {
        let result = gio::spawn_blocking(work).await;
        match result {
            Ok(Attempt::Added(record, line)) => {
                on.remote.entries.borrow_mut().push(RemoteEntry {
                    record: record.clone(),
                    grey: None,
                });
                save(&on);
                sheet.dialog.close();
                let mut said = tr_args("sources.added %s", "Added %s", &[&record.name]);
                if let Some(line) = line {
                    said = format!("{said} · {line}");
                }
                on.toast(&said);
                on.library_changed();
            }
            Ok(Attempt::Failed(said)) => sheet.say(&said),
            Ok(Attempt::Untrusted { host, fingerprint }) => {
                sheet.connect.set_sensitive(true);
                sheet.status.set_visible(false);
                offer_trust(&on, &sheet, &host, &fingerprint);
            }
            Err(_) => sheet.say(&Said {
                text: tr("smb.error.unexpected", "The share could not be reached."),
                grey: true,
                remedy: None,
            }),
        }
    });
}

/// Shows the fingerprint of a certificate the system does not trust; trusting it pins it
/// and the reader presses Connect again.
fn offer_trust(shared: &Shared, sheet: &Rc<Sheet>, host: &str, fingerprint: &str) {
    let alert = adw::AlertDialog::new(
        Some(&tr("catalogue.untrusted.title", "Trust this server?")),
        Some(&format!(
            "{}\n\n{host}\n{fingerprint}",
            tr(
                "catalogue.untrusted.explanation",
                "This server's certificate is not one this system trusts. Trust it only if you set the server up yourself and the fingerprint below is the one you expect."
            )
        )),
    );
    alert.add_responses(&[
        ("cancel", &tr("sources.rename.cancel", "Cancel")),
        ("trust", &tr("catalogue.untrusted.trust", "Trust")),
    ]);
    alert.set_close_response("cancel");
    let (host, fingerprint) = (host.to_owned(), fingerprint.to_owned());
    let on = shared.clone();
    alert.connect_response(None, move |_, response| {
        if response == "trust"
            && let Some(services) = on.services.get()
        {
            services.trust.pin(&host, &fingerprint);
        }
    });
    alert.present(Some(&sheet.dialog));
}

/// Add an online catalogue (OPDS): its address, and a user and password where it asks.
pub fn present_catalogue(shared: &Shared, parent: &gtk::Window) {
    let address = entry(&tr("catalogue.address.label", "Address"), "");
    let user = entry(&tr("catalogue.signIn.user", "User name"), "");
    let pass = password(&tr("catalogue.signIn.password", "Password"));
    let sheet = Rc::new(sheet(
        &tr("catalogue.title", "Add an online library"),
        &[
            &group(&[address.upcast_ref()]),
            &group(&[user.upcast_ref(), pass.upcast_ref()]),
        ],
    ));
    let on = shared.clone();
    let weak = Rc::downgrade(&sheet);
    sheet.connect.connect_clicked(move |_| {
        let Some(sheet) = weak.upgrade() else { return };
        let Some(typed) = remote::catalogue_address(&address.text()) else {
            sheet.say(&Said {
                text: tr(
                    "catalogue.error.notAURL",
                    "That is not an address StoryArc can reach.",
                ),
                grey: true,
                remedy: None,
            });
            return;
        };
        let Some(services) = on.services.get() else {
            sheet.say(&starting());
            return;
        };
        let username = user.text().trim().to_owned();
        let secret = pass.text().to_string();
        sheet.working();
        run(&on, &sheet, move || {
            add_catalogue(&services, &typed, username, secret)
        });
    });
    sheet.dialog.present(Some(parent));
}

fn add_catalogue(
    services: &Arc<Services>,
    typed: &str,
    username: String,
    secret: String,
) -> Attempt {
    let Ok(url) = typed.parse() else {
        return Attempt::Failed(remote::opds_failure(&OpdsError::RefusedAddress));
    };
    let credential = (!username.is_empty()).then(|| Credential::Basic {
        username: username.clone(),
        password: Secret::new(secret.clone()),
    });
    let catalogue = match OpdsCatalogue::new(&services.http, url, credential) {
        Ok(catalogue) => catalogue,
        Err(error) => return Attempt::Failed(remote::opds_failure(&error)),
    };
    match catalogue.validate() {
        Ok(feed) => {
            let name = if feed.title.trim().is_empty() {
                name_from(typed)
            } else {
                feed.title.clone()
            };
            let record = RemoteRecord {
                id: new_shelf_id(),
                kind: Kind::Catalogue,
                name,
                address: typed.to_owned(),
                username: (!username.is_empty()).then_some(username),
            };
            keep(services, record, secret, Noun::SignIn, None)
        }
        Err(OpdsError::Untrusted(certificate)) => Attempt::Untrusted {
            host: certificate.host,
            fingerprint: certificate.fingerprint,
        },
        Err(error) => Attempt::Failed(remote::opds_failure(&error)),
    }
}

/// Add a Kavita server: its address and the API key from the reader's account.
pub fn present_kavita(shared: &Shared, parent: &gtk::Window) {
    let address = entry(&tr("kavita.address.label", "Address"), "");
    let key = password(&tr("kavita.key.label", "API key"));
    let sheet = Rc::new(sheet(
        &tr("kavita.add", "Add a Kavita library"),
        &[&group(&[address.upcast_ref(), key.upcast_ref()])],
    ));
    let on = shared.clone();
    let weak = Rc::downgrade(&sheet);
    sheet.connect.connect_clicked(move |_| {
        let Some(sheet) = weak.upgrade() else { return };
        let typed = address.text().to_string();
        let secret = key.text().to_string();
        let Some(base) = remote::kavita_address(&typed) else {
            sheet.say(&Said {
                text: tr(
                    "kavita.error.notAnAddress",
                    "That is not an address StoryArc can reach.",
                ),
                grey: true,
                remedy: None,
            });
            return;
        };
        let Some(services) = on.services.get() else {
            sheet.say(&starting());
            return;
        };
        sheet.working();
        run(&on, &sheet, move || {
            add_kavita(&services, &typed, &base, secret)
        });
    });
    sheet.dialog.present(Some(parent));
}

fn add_kavita(services: &Arc<Services>, typed: &str, base: &str, secret: String) -> Attempt {
    let Some(address) = KavitaAddress::parse(typed, secret.clone()) else {
        return Attempt::Failed(remote::kavita_failure(
            &storyarc_core::sources::kavita::KavitaError::BadAddress,
        ));
    };
    let client = match KavitaClient::new(&services.http, address) {
        Ok(client) => client,
        Err(error) => return Attempt::Failed(remote::kavita_failure(&error)),
    };
    match client.connect() {
        Ok(identity) => {
            let record = RemoteRecord {
                id: new_shelf_id(),
                kind: Kind::Kavita,
                name: name_from(base),
                address: base.to_owned(),
                username: Some(identity.username),
            };
            keep(services, record, secret, Noun::ApiKey, None)
        }
        Err(error) => Attempt::Failed(remote::kavita_failure(&error)),
    }
}

// ---- discovery --------------------------------------------------------------------

/// What `avahi-browse` found. `None`: it is not installed or its daemon does not answer,
/// so the sheet says so once, in grey, and the fields are the way in.
fn browse() -> Option<Vec<Suggestion>> {
    let output = Command::new("avahi-browse")
        .args(["-tpr", "_smb._tcp"])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| remote::parse_avahi(&String::from_utf8_lossy(&output.stdout)))
}

/// The note a sheet says when discovery is not there.
pub fn no_discovery_note() -> String {
    tr(
        "smb.discovery.absent",
        "This system does not announce shares (Avahi is not running), so enter the address by hand.",
    )
}

fn discover(found: &adw::PreferencesGroup, host: &adw::EntryRow, sheet: &Rc<Sheet>) {
    let found = found.clone();
    let host = host.clone();
    let _ = sheet;
    glib::spawn_future_local(async move {
        match gio::spawn_blocking(browse).await {
            Ok(Some(suggestions)) if !suggestions.is_empty() => {
                for suggestion in suggestions {
                    let row = adw::ActionRow::builder()
                        .title(&suggestion.name)
                        .subtitle(format!("{}:{}", suggestion.host, suggestion.port))
                        .activatable(true)
                        .build();
                    let host = host.clone();
                    row.connect_activated(move |_| {
                        host.set_text(&if suggestion.port == 445 {
                            suggestion.host.clone()
                        } else {
                            format!("{}:{}", suggestion.host, suggestion.port)
                        });
                    });
                    found.add(&row);
                }
            }
            Ok(Some(_)) => found.set_description(Some(&tr(
                "smb.discovery.none",
                "No shares were announced on this network.",
            ))),
            _ => found.set_description(Some(&no_discovery_note())),
        }
    });
}
