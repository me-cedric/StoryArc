//! The publication page's widgets (task 2.35d, `publication-detail`): the cover on a
//! wash taken from it, the title, one primary action, a menu, the other issues of its
//! series, and the line that names where the file lives. The same view is pushed in a
//! narrow window and stands beside the library in a wide one. What it says is
//! `library/detail.rs`; the wash is `cover_colour.rs`.

use std::cell::RefCell;
use std::collections::BTreeSet;
use std::path::PathBuf;
use std::rc::Rc;

use adw::prelude::*;
use gtk::{gdk, gio};
use storyarc_core::domain::Publication;

use crate::cover_colour;
use crate::covers::Covers;
use crate::home_view::CardState;
use crate::library::detail::Detail;
use crate::library_views::{cover_picture, cover_picture_fitted, set_class};
use crate::settings::Rgb;
use crate::strings::{tr, tr_args, tr_plural};

/// What the page needs from the window.
/// Starts an audiobook at a part and an offset.
pub type ListenFrom = Rc<dyn Fn(&Publication, usize, std::time::Duration)>;

pub struct DetailHooks {
    /// Opens the publication in a reader.
    pub read: Rc<dyn Fn(&Publication)>,
    /// Shows another publication's page.
    pub show: Rc<dyn Fn(&Publication)>,
    /// The other issues of the series, each with the marks its cover carries.
    pub others: Vec<(Publication, CardState)>,
    /// The app's accent, the wash for a cover that yields no colour.
    pub accent: Rgb,
    /// For an audiobook: where the listener stopped, and a way to start at a chapter.
    pub stopped: Option<(usize, std::time::Duration)>,
    pub listen_from: ListenFrom,
}

/// The detail page pushed over the library in a narrow window.
pub fn detail_page(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    hooks: &DetailHooks,
) -> adw::NavigationPage {
    adw::NavigationPage::builder()
        .title(&detail.title)
        .tag("detail")
        .child(&detail_view(detail, publication, covers, hooks))
        .build()
}

/// The second pane of a wide window before a cover is chosen: one sentence.
pub fn pane_placeholder() -> gtk::Widget {
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&adw::HeaderBar::builder().show_title(false).build());
    toolbar.set_content(Some(
        &adw::StatusPage::builder()
            .description(tr(
                "detail.empty",
                "Choose a cover to see what it is and where it came from.",
            ))
            .build(),
    ));
    toolbar.upcast()
}

/// The page with its own header bar. The header bar is chrome: it never takes the wash.
pub fn detail_view(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    hooks: &DetailHooks,
) -> adw::ToolbarView {
    let path = publication.identity.normalized_path.clone();
    let column = detail_column(detail, publication, covers, hooks);
    let toolbar = adw::ToolbarView::new();
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(&adw::WindowTitle::new(&detail.title, "")));
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(
        &gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .child(&column)
            .build(),
    ));
    toolbar.insert_action_group("detail", Some(&show_in_files(path)));
    toolbar
}

fn show_in_files(path: Option<String>) -> gio::SimpleActionGroup {
    let group = gio::SimpleActionGroup::new();
    let show = gio::SimpleAction::new("show-in-files", None);
    show.connect_activate(move |_, _| {
        if let Some(path) = &path {
            gtk::FileLauncher::new(Some(&gio::File::for_path(path))).open_containing_folder(
                gtk::Window::NONE,
                None::<&gio::Cancellable>,
                |_| {},
            );
        }
    });
    group.add_action(&show);
    group
}

fn detail_column(
    detail: &Detail,
    publication: &Publication,
    covers: &Rc<Covers>,
    hooks: &DetailHooks,
) -> gtk::Box {
    let picture = cover_picture(220);
    picture.set_halign(gtk::Align::Center);
    let path = publication.identity.normalized_path.clone();
    covers.show(&picture, &publication.id(), path.clone().map(PathBuf::from));
    picture.set_hexpand(true);

    let column = gtk::Box::builder()
        .orientation(gtk::Orientation::Vertical)
        .spacing(12)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(24)
        .margin_end(24)
        .build();
    column.append(&picture);
    column.append(
        &gtk::Label::builder()
            .label(&detail.title)
            .wrap(true)
            .css_classes(["title-1"])
            .build(),
    );
    if let Some(subtitle) = &detail.subtitle {
        column.append(
            &gtk::Label::builder()
                .label(subtitle)
                .wrap(true)
                .css_classes(["dimmed"])
                .build(),
        );
    }
    let actions = actions(detail, publication, hooks);
    column.append(&actions);
    if let Some(note) = detail.note {
        column.append(
            &gtk::Label::builder()
                .label(note)
                .css_classes(["dimmed"])
                .build(),
        );
    }
    if let Some(count) = detail.page_count {
        column.append(
            &gtk::Label::builder()
                .label(tr_plural(
                    "library.cell.pages %d",
                    "%d page",
                    "%d pages",
                    count as u64,
                ))
                .css_classes(["dimmed", "caption"])
                .build(),
        );
    }
    column.append(
        &gtk::Label::builder()
            .label(&detail.location)
            .wrap(true)
            .wrap_mode(gtk::pango::WrapMode::WordChar)
            .selectable(true)
            .css_classes(["dimmed", "caption"])
            .build(),
    );
    if publication.format.is_audio() {
        column.append(&audiobook_section(publication, &actions, hooks));
    }
    if publication.format == storyarc_core::domain::PublicationFormat::Epub
        && let Some(voice) = crate::player::voice_name()
    {
        column.append(
            &gtk::Label::builder()
                .label(tr_args("detail.readAloud.voice %s", "Read aloud by %s", &[&voice]))
                .css_classes(["dimmed", "caption"])
                .build(),
        );
    }
    if !hooks.others.is_empty() {
        column.append(&other_issues(&hooks.others, covers, &hooks.show));
    }
    let clamp = adw::Clamp::builder()
        .maximum_size(640)
        .child(&column)
        .build();
    let page = gtk::Box::new(gtk::Orientation::Vertical, 0);
    page.append(&clamp);
    page.set_vexpand(true);
    follow_cover(&picture, &page, hooks.accent);
    page
}

fn actions(detail: &Detail, publication: &Publication, hooks: &DetailHooks) -> gtk::Box {
    let primary = gtk::Button::builder()
        .label(detail.primary.label())
        .sensitive(detail.primary.is_enabled())
        .css_classes(["pill", "suggested-action"])
        .build();
    let target = publication.clone();
    let read = hooks.read.clone();
    primary.connect_clicked(move |_| read(&target));
    let menu = gio::Menu::new();
    menu.append(
        Some(&tr("detail.showInFolder", "Show in folder")),
        Some("detail.show-in-files"),
    );
    let more = gtk::MenuButton::builder()
        .icon_name("view-more-symbolic")
        .tooltip_text(tr("detail.more", "More actions"))
        .menu_model(&menu)
        .css_classes(["circular"])
        .build();
    let actions = gtk::Box::builder()
        .spacing(12)
        .halign(gtk::Align::Center)
        .build();
    actions.append(&primary);
    actions.append(&more);
    actions
}

/// An audiobook's chapters before the first minute (`audio-playback`, *Chapters before the
/// first minute*): read from the files on a worker, each a way to start there, or the book's
/// length when it is one part with no marks. The primary action names where it resumes.
fn audiobook_section(publication: &Publication, actions: &gtk::Box, hooks: &DetailHooks) -> gtk::Box {
    let section = gtk::Box::new(gtk::Orientation::Vertical, 12);
    section.set_margin_top(12);
    let Some(path) = publication.identity.normalized_path.clone().map(PathBuf::from) else {
        return section;
    };
    let primary = actions
        .first_child()
        .and_then(|child| child.downcast::<gtk::Button>().ok());
    let (target, stopped, listen_from) = (publication.clone(), hooks.stopped, hooks.listen_from.clone());
    let on_section = section.clone();
    gtk::glib::spawn_future_local(async move {
        let parts = crate::player::audiobook_parts(&path);
        let Ok((chapters, _)) = gio::spawn_blocking(move || crate::player::book_chapters(&parts)).await else {
            return;
        };
        if let Some(primary) = primary.filter(|p| p.is_sensitive()) {
            primary.set_label(&crate::playback::resume_label(&chapters, stopped));
        }
        match crate::playback::listing(&chapters, stopped) {
            crate::playback::Listing::Length(length) => {
                if let Some(length) = length {
                    on_section.append(
                        &gtk::Label::builder()
                            .label(tr_args("detail.duration %s", "Duration %s", &[&crate::player::clock(length)]))
                            .css_classes(["dimmed"])
                            .build(),
                    );
                }
            }
            crate::playback::Listing::Chapters(rows) => {
                on_section.append(
                    &gtk::Label::builder()
                        .label(tr("detail.chapters", "Chapters"))
                        .xalign(0.0)
                        .css_classes(["title-4"])
                        .accessible_role(gtk::AccessibleRole::Heading)
                        .build(),
                );
                let list = gtk::ListBox::builder()
                    .selection_mode(gtk::SelectionMode::None)
                    .css_classes(["boxed-list"])
                    .build();
                for (row, chapter) in rows.into_iter().zip(chapters) {
                    let item = adw::ActionRow::builder()
                        .title(gtk::glib::markup_escape_text(&row))
                        .activatable(true)
                        .build();
                    let (target, listen_from) = (target.clone(), listen_from.clone());
                    item.connect_activated(move |_| listen_from(&target, chapter.part, chapter.start));
                    list.append(&item);
                }
                on_section.append(&list);
            }
        }
    });
    section
}

/// The rest of the series, in order, each cover marked with how far it is read and
/// dimmed when its folder cannot be read now; each leads to its own page.
fn other_issues(
    others: &[(Publication, CardState)],
    covers: &Rc<Covers>,
    show: &Rc<dyn Fn(&Publication)>,
) -> gtk::Box {
    let section = gtk::Box::new(gtk::Orientation::Vertical, 12);
    section.set_margin_top(12);
    section.append(
        &gtk::Label::builder()
            .label(tr("detail.series.title", "Other issues in this series"))
            .xalign(0.0)
            .css_classes(["title-4"])
            .accessible_role(gtk::AccessibleRole::Heading)
            .build(),
    );
    let flow = gtk::FlowBox::builder()
        .selection_mode(gtk::SelectionMode::None)
        .max_children_per_line(8)
        .column_spacing(12)
        .row_spacing(12)
        .homogeneous(true)
        .build();
    for (publication, state) in others {
        let tile = gtk::Box::new(gtk::Orientation::Vertical, 6);
        let picture = cover_picture_fitted(72, gtk::ContentFit::Contain);
        let path = publication
            .identity
            .normalized_path
            .clone()
            .map(PathBuf::from);
        covers.show(&picture, &publication.id(), path);
        tile.append(&picture);
        let mut said = vec![publication.display_title.clone()];
        if let Some(percent) = state.percent {
            tile.append(
                &gtk::ProgressBar::builder()
                    .fraction(f64::from(percent.min(100)) / 100.0)
                    .css_classes(["osd"])
                    .build(),
            );
            said.push(tr_args(
                "library.cell.progress %d",
                "%d%% read",
                &[&percent],
            ));
        }
        tile.append(
            &gtk::Label::builder()
                .label(&publication.display_title)
                .ellipsize(gtk::pango::EllipsizeMode::End)
                .max_width_chars(10)
                .css_classes(["caption"])
                .build(),
        );
        set_class(&tile, "dimmed", state.unavailable);
        let button = gtk::Button::builder()
            .child(&tile)
            .css_classes(["flat"])
            .tooltip_text(&publication.display_title)
            .build();
        button.update_property(&[gtk::accessible::Property::Label(&said.join(", "))]);
        let show = show.clone();
        let publication = publication.clone();
        button.connect_clicked(move |_| show(&publication));
        flow.append(&button);
    }
    section.append(&flow);
    section
}

/// Gives `page` the wash of the cover `picture` shows, once it has decoded, or the
/// accent's when the cover yields nothing. With high contrast on, the page stays the
/// plain surface: nothing on it depends on the wash.
fn follow_cover(picture: &gtk::Picture, page: &gtk::Box, accent: Rgb) {
    let apply = {
        let page = page.downgrade();
        move |picture: &gtk::Picture| {
            let Some(page) = page.upgrade() else {
                return;
            };
            if adw::StyleManager::default().is_high_contrast() {
                return;
            }
            let texture = picture.paintable().and_downcast::<gdk::Texture>();
            let wash = match texture.as_ref().and_then(rgba) {
                Some((bytes, width, height)) => {
                    cover_colour::page_wash(Some((&bytes, width, height)), accent)
                }
                None => cover_colour::page_wash(None, accent),
            };
            for class in page.css_classes() {
                if class.starts_with("storyarc-wash-") {
                    page.remove_css_class(&class);
                }
            }
            page.add_css_class(&wash_class(wash));
        }
    };
    apply(picture);
    picture.connect_paintable_notify(apply);
}

/// The texture's pixels as straight RGBA rows.
fn rgba(texture: &gdk::Texture) -> Option<(Vec<u8>, usize, usize)> {
    let mut downloader = gdk::TextureDownloader::new(texture);
    downloader.set_format(gdk::MemoryFormat::R8g8b8a8);
    let (bytes, stride) = downloader.download_bytes();
    let (width, height) = (
        usize::try_from(texture.width()).ok()?,
        usize::try_from(texture.height()).ok()?,
    );
    let rows: Vec<u8> = bytes
        .chunks(stride)
        .take(height)
        .flat_map(|row| row[..width * 4].to_vec())
        .collect();
    Some((rows, width, height))
}

thread_local! {
    /// The wash classes defined so far, in one stylesheet on the display.
    static WASHES: RefCell<(Option<gtk::CssProvider>, BTreeSet<String>)> =
        const { RefCell::new((None, BTreeSet::new())) };
}

/// The class that paints a wash: its colour behind white text. Defined once per colour.
fn wash_class(wash: Rgb) -> String {
    let hex = wash.hex();
    let class = format!("storyarc-wash-{}", hex.trim_start_matches('#'));
    WASHES.with(|washes| {
        let mut washes = washes.borrow_mut();
        if !washes.1.insert(hex) {
            return;
        }
        let css: String = washes
            .1
            .iter()
            .map(|hex| {
                format!(
                    ".storyarc-wash-{} {{ background-color: {hex}; color: #FFFFFF; }}\n",
                    hex.trim_start_matches('#')
                )
            })
            .collect();
        let provider = washes.0.get_or_insert_with(|| {
            let provider = gtk::CssProvider::new();
            if let Some(display) = gdk::Display::default() {
                gtk::style_context_add_provider_for_display(
                    &display,
                    &provider,
                    gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
                );
            }
            provider
        });
        provider.load_from_string(&css);
    });
    class
}
