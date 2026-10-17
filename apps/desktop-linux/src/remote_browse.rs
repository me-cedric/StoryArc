//! Looking into a network library (task 3.17): a share's folders and files, a catalogue's
//! feeds and publications, a Kavita server's libraries, series and chapters. Each level is
//! a page pushed over the library; a publication a catalogue or a server offers has a
//! Download button that queues it (`downloads_ui.rs`). A level that cannot load says why,
//! in grey, and the other libraries stay usable. A share's files are listed, not yet read
//! in place: the reader opens files by path.

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::net::Credential;
use storyarc_core::secrets::SecretKey;
use storyarc_core::sources::kavita::{KavitaAddress, KavitaClient};
use storyarc_core::sources::opds::OpdsCatalogue;
use storyarc_core::sources::smb::{SmbLogin, SmbShare};

use crate::app::Shared;
use crate::remote_sources::{self as remote, Kind, RemoteRecord, Said};
use crate::services::Services;
use crate::strings::{tr, tr_args};

/// One row of a level.
#[derive(Clone, Debug, PartialEq)]
pub enum Row {
    /// A level below: its title and the path the worker loads it from.
    Folder {
        title: String,
        subtitle: Option<String>,
        path: String,
    },
    /// A publication to download: the id it is kept under and where its bytes are.
    Download {
        title: String,
        subtitle: Option<String>,
        id: String,
        remote: String,
    },
    /// A file that is listed and not offered.
    File {
        title: String,
        subtitle: Option<String>,
    },
}

fn size(bytes: u64) -> String {
    glib::format_size(bytes).to_string()
}

fn load(services: &Services, record: &RemoteRecord, path: &str) -> Result<Vec<Row>, Said> {
    let key = SecretKey::for_source(&record.id, record.kind.secret_field());
    let secret = services.vault.load(&key).ok().flatten();
    match record.kind {
        Kind::Share => {
            let address = remote::share_of_locator(&record.address).ok_or_else(|| Said {
                text: tr("smb.error.notAnAddress", "Enter a host and a share name."),
                grey: true,
                remedy: None,
            })?;
            let login = match (&record.username, secret) {
                (Some(user), Some(password)) => SmbLogin::account(user.clone(), password),
                (Some(_), None) => return Err(signed_out()),
                _ => SmbLogin::Guest,
            };
            let share = SmbShare::connect(&services.runtime, address, login)
                .map_err(|e| remote::smb_failure(&e))?;
            let entries = share.list(path).map_err(|e| remote::smb_failure(&e))?;
            Ok(entries
                .into_iter()
                .map(|entry| {
                    if entry.is_directory {
                        Row::Folder {
                            title: entry.name,
                            subtitle: None,
                            path: entry.path,
                        }
                    } else {
                        Row::File {
                            title: entry.name,
                            subtitle: Some(size(entry.length)),
                        }
                    }
                })
                .collect())
        }
        Kind::Catalogue => {
            let root = record.address.parse().map_err(|_| Said {
                text: tr(
                    "catalogue.error.notAURL",
                    "That is not an address StoryArc can reach.",
                ),
                grey: true,
                remedy: None,
            })?;
            let credential = match (&record.username, secret) {
                (Some(username), Some(password)) => Some(Credential::Basic {
                    username: username.clone(),
                    password,
                }),
                (Some(_), None) => return Err(signed_out()),
                _ => None,
            };
            let catalogue = OpdsCatalogue::new(&services.http, root, credential)
                .map_err(|e| remote::opds_failure(&e))?;
            let url = if path.is_empty() {
                catalogue.root().clone()
            } else {
                path.parse().map_err(|_| Said {
                    text: tr(
                        "catalogue.error.notAURL",
                        "That is not an address StoryArc can reach.",
                    ),
                    grey: true,
                    remedy: None,
                })?
            };
            let feed = catalogue.feed(&url).map_err(|e| remote::opds_failure(&e))?;
            let mut rows: Vec<Row> = feed
                .navigation
                .iter()
                .map(|section| Row::Folder {
                    title: section.title.clone(),
                    subtitle: section.count.map(|n| n.to_string()),
                    path: section.href.to_string(),
                })
                .collect();
            for entry in &feed.publications {
                let subtitle = (!entry.authors.is_empty()).then(|| entry.authors.join(", "));
                match entry.best_acquisition() {
                    Some(acquisition) => rows.push(Row::Download {
                        title: entry.title.clone(),
                        subtitle,
                        id: format!("opds:{}:{}", record.id, entry.id),
                        remote: acquisition.href.to_string(),
                    }),
                    None => rows.push(Row::File {
                        title: entry.title.clone(),
                        subtitle: Some(tr(
                            "catalogue.acquire.unreadable",
                            "What the server sent could not be opened.",
                        )),
                    }),
                }
            }
            if let Some(next) = feed.next {
                rows.push(Row::Folder {
                    title: tr("browse.more", "More"),
                    subtitle: None,
                    path: next.to_string(),
                });
            }
            Ok(rows)
        }
        Kind::Kavita => {
            let key = secret.ok_or_else(signed_out)?;
            let address = KavitaAddress::parse(&record.address, key).ok_or_else(|| {
                remote::kavita_failure(&storyarc_core::sources::kavita::KavitaError::BadAddress)
            })?;
            let client = KavitaClient::new(&services.http, address)
                .map_err(|e| remote::kavita_failure(&e))?;
            client.connect().map_err(|e| remote::kavita_failure(&e))?;
            kavita_level(&client, record, path).map_err(|e| remote::kavita_failure(&e))
        }
    }
}

fn kavita_level(
    client: &KavitaClient,
    record: &RemoteRecord,
    path: &str,
) -> Result<Vec<Row>, storyarc_core::sources::kavita::KavitaError> {
    if path.is_empty() {
        return Ok(client
            .libraries()?
            .into_iter()
            .map(|library| Row::Folder {
                title: library.name,
                subtitle: None,
                path: format!("library:{}", library.id),
            })
            .collect());
    }
    if let Some(id) = path.strip_prefix("library:").and_then(|n| n.parse().ok()) {
        return Ok(client
            .series(Some(id))?
            .into_iter()
            .map(|series| Row::Folder {
                subtitle: Some(tr_args(
                    "browse.pagesRead %d %d",
                    "%d of %d pages read",
                    &[&series.pages_read, &series.pages],
                )),
                title: series.name,
                path: format!("series:{}", series.id),
            })
            .collect());
    }
    let id: i64 = path
        .strip_prefix("series:")
        .and_then(|n| n.parse().ok())
        .unwrap_or_default();
    let mut rows = Vec::new();
    for volume in client.volumes(id)? {
        for chapter in volume.chapters {
            let title = chapter
                .title
                .clone()
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| {
                    tr_args("kavita.chapter.number %s", "Chapter %s", &[&chapter.number])
                });
            rows.push(Row::Download {
                subtitle: (chapter.file_bytes() > 0).then(|| size(chapter.file_bytes() as u64)),
                title,
                id: format!("kavita:{}:{}", record.id, chapter.remote_id()),
                remote: chapter.remote_id(),
            });
        }
    }
    Ok(rows)
}

fn signed_out() -> Said {
    Said {
        text: tr("sources.needsSignIn", "Needs a sign-in"),
        grey: true,
        remedy: Some(tr(
            "sources.signIn.remedy",
            "Remove this library and add it again to sign in",
        )),
    }
}

/// Opens the `index`th network library at its first level.
pub fn open(shared: &Shared, index: usize) {
    let Some(record) = shared
        .remote
        .entries
        .borrow()
        .get(index)
        .map(|e| e.record.clone())
    else {
        return;
    };
    push(shared, record.clone(), String::new(), record.name);
}

fn push(shared: &Shared, record: RemoteRecord, path: String, title: String) {
    let Some(ui) = shared.library_ui.borrow().clone() else {
        return;
    };
    let body = adw::Bin::new();
    let spinner = gtk::Spinner::builder()
        .spinning(true)
        .halign(gtk::Align::Center)
        .valign(gtk::Align::Center)
        .build();
    body.set_child(Some(&spinner));
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::new());
    toolbar.set_content(Some(&body));
    let page = adw::NavigationPage::builder()
        .title(&title)
        .child(&toolbar)
        .build();
    ui.navigation.push(&page);
    ui.split.set_show_content(true);
    let Some(services) = shared.services.get() else {
        body.set_child(Some(&status(&Said {
            text: tr(
                "network.starting",
                "StoryArc is still starting. Try again in a moment.",
            ),
            grey: true,
            remedy: None,
        })));
        return;
    };
    let on = shared.clone();
    let worker_record = record.clone();
    glib::spawn_future_local(async move {
        let result = gio::spawn_blocking(move || load(&services, &worker_record, &path)).await;
        match result {
            Ok(Ok(rows)) => body.set_child(Some(&list(&on, &record, &rows))),
            Ok(Err(said)) => body.set_child(Some(&status(&said))),
            Err(_) => body.set_child(Some(&status(&Said {
                text: tr(
                    "catalogue.error.unreachable",
                    "This server could not be reached.",
                ),
                grey: true,
                remedy: None,
            }))),
        }
    });
}

/// The grey page a level that did not load shows: why, and what changes it.
fn status(said: &Said) -> adw::StatusPage {
    let mut text = said.text.clone();
    if let Some(remedy) = &said.remedy {
        text = format!("{}. {remedy}.", text.trim_end_matches('.'));
    }
    adw::StatusPage::builder()
        .icon_name("network-offline-symbolic")
        .title(tr("sources.unreachable", "Not available right now"))
        .description(text)
        .build()
}

fn list(shared: &Shared, record: &RemoteRecord, rows: &[Row]) -> gtk::Widget {
    if rows.is_empty() {
        return adw::StatusPage::builder()
            .icon_name("folder-symbolic")
            .title(tr("catalogue.empty", "This section is empty."))
            .build()
            .upcast();
    }
    let group = adw::PreferencesGroup::new();
    // Keyboard focus lands on the first thing that can be pressed, so a level opens ready
    // for Return.
    let mut first: Option<gtk::Widget> = None;
    for row in rows {
        match row {
            Row::Folder {
                title,
                subtitle,
                path,
            } => {
                let line = adw::ActionRow::builder()
                    .title(glib::markup_escape_text(title))
                    .activatable(true)
                    .build();
                if let Some(subtitle) = subtitle {
                    line.set_subtitle(&glib::markup_escape_text(subtitle));
                }
                line.add_suffix(&gtk::Image::from_icon_name("go-next-symbolic"));
                let (on, record, path, title) =
                    (shared.clone(), record.clone(), path.clone(), title.clone());
                line.connect_activated(move |_| {
                    push(&on, record.clone(), path.clone(), title.clone())
                });
                first.get_or_insert_with(|| line.clone().upcast());
                group.add(&line);
            }
            Row::File { title, subtitle } => {
                let line = adw::ActionRow::builder()
                    .title(glib::markup_escape_text(title))
                    .css_classes(["dimmed"])
                    .build();
                if let Some(subtitle) = subtitle {
                    line.set_subtitle(&glib::markup_escape_text(subtitle));
                }
                group.add(&line);
            }
            Row::Download {
                title,
                subtitle,
                id,
                remote,
            } => {
                let line = adw::ActionRow::builder()
                    .title(glib::markup_escape_text(title))
                    .build();
                if let Some(subtitle) = subtitle {
                    line.set_subtitle(&glib::markup_escape_text(subtitle));
                }
                let queued = shared.downloads.is_known(id);
                let button = gtk::Button::builder()
                    .label(if queued {
                        tr("downloads.queuedLabel", "In Downloads")
                    } else {
                        tr("catalogue.acquire.download", "Download")
                    })
                    .sensitive(!queued)
                    .valign(gtk::Align::Center)
                    .build();
                let (on, record_id, id, remote, title) = (
                    shared.clone(),
                    record.id.clone(),
                    id.clone(),
                    remote.clone(),
                    title.clone(),
                );
                button.connect_clicked(move |button| {
                    crate::downloads_ui::enqueue(&on, &id, &title, &remote, &record_id);
                    button.set_sensitive(false);
                    button.set_label(&tr("downloads.queuedLabel", "In Downloads"));
                });
                line.add_suffix(&button);
                if !queued {
                    first.get_or_insert_with(|| button.clone().upcast());
                }
                group.add(&line);
            }
        }
    }
    if let Some(first) = first {
        glib::idle_add_local_once(move || {
            first.grab_focus();
        });
    }
    gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .child(
            &adw::Clamp::builder()
                .maximum_size(720)
                .margin_top(18)
                .margin_bottom(18)
                .margin_start(18)
                .margin_end(18)
                .child(&group)
                .build(),
        )
        .build()
        .upcast()
}
