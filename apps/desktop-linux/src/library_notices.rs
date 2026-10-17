//! The two notices above the shelf (`library-browsing`, What could not be opened;
//! `navigation-shell`, A source stops being reachable): banners in the header's place,
//! never over a cover, and never on a timer. The rules are `library/notice.rs`.

use std::rc::Rc;

use adw::prelude::*;

use crate::app::Shared;
use crate::folders::Access;
use crate::library::notice::{self, Notice, Skipped};
use crate::library_menus;
use crate::library_window::LibraryUi;
use crate::sources;
use crate::strings::{tr, tr_args};

pub(crate) fn connect_banners(shared: &Shared, ui: &Rc<LibraryUi>) {
    let on = shared.clone();
    ui.skipped_banner.connect_button_clicked(move |banner| {
        let Some(ui) = on.library_ui.borrow().clone() else {
            return;
        };
        let skipped = on.sources.skipped();
        match Notice::of(&skipped, &ui.dismissed.borrow()) {
            Notice::Several(_) => show_skipped_list(&on, &ui, &skipped),
            _ => {
                *ui.dismissed.borrow_mut() = notice::dismissed(&skipped);
                banner.set_revealed(false);
            }
        }
    });
    let on = shared.clone();
    ui.access_banner.connect_button_clicked(move |_| {
        let Some(ui) = on.library_ui.borrow().clone() else {
            return;
        };
        if let Some(index) = ui.withdrawn.get() {
            sources::choose_again(&on, ui.window.upcast_ref(), index);
        }
    });
}

/// The list the notice leads to: every file, each with its own reason, and Dismiss.
pub(crate) fn show_skipped_list(shared: &Shared, ui: &Rc<LibraryUi>, skipped: &[Skipped]) {
    let body: Vec<String> = skipped
        .iter()
        .map(|(name, reason)| format!("{name}: {reason}"))
        .collect();
    let dialog = adw::AlertDialog::new(
        Some(&tr("library.skipped.list", "What couldn’t be opened")),
        Some(&body.join("\n")),
    );
    dialog.add_responses(&[
        ("close", &tr("reader.adjust.done", "Done")),
        ("dismiss", &tr("library.skipped.dismiss", "Dismiss")),
    ]);
    dialog.set_close_response("close");
    let on = shared.clone();
    let files = skipped.to_vec();
    dialog.connect_response(None, move |_, response| {
        if response == "dismiss"
            && let Some(ui) = on.library_ui.borrow().clone()
        {
            *ui.dismissed.borrow_mut() = notice::dismissed(&files);
            ui.skipped_banner.set_revealed(false);
        }
    });
    dialog.present(Some(&ui.window));
}
/// The two notices above the shelf. A folder that needs access again offers Choose
/// Again where its publications are; an offline one needs nothing, it returns by itself
/// and its covers are dimmed meanwhile. The files a scan could not open are named until
/// the reader dismisses them.
pub(crate) fn refresh_banners(shared: &Shared, ui: &LibraryUi) {
    let withdrawn = shared
        .sources
        .summary()
        .into_iter()
        .position(|(_, access, _)| access == Access::Withdrawn);
    ui.withdrawn.set(withdrawn);
    match withdrawn.and_then(|index| shared.sources.summary().into_iter().nth(index)) {
        Some((name, _, _)) => {
            ui.access_banner.set_title(&tr_args(
                "library.folderUnavailable %s",
                "“%s” can no longer be read",
                &[&name],
            ));
            ui.access_banner
                .set_button_label(Some(&tr("library.repick", "Choose Again")));
            ui.access_banner.set_revealed(true);
        }
        None => ui.access_banner.set_revealed(false),
    }
    let notice = Notice::of(&shared.sources.skipped(), &ui.dismissed.borrow());
    match (notice.title(), notice.button()) {
        (Some(title), button) => {
            ui.skipped_banner.set_title(&title);
            ui.skipped_banner.set_button_label(button.as_deref());
            ui.skipped_banner.set_revealed(true);
        }
        (None, _) => ui.skipped_banner.set_revealed(false),
    }
    let folders: Vec<String> = shared
        .sources
        .summary()
        .into_iter()
        .map(|(name, _, _)| name)
        .collect();
    ui.filter_button
        .set_menu_model(Some(&library_menus::filter_menu(&folders)));
}
