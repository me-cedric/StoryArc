//! The cover ladder (task 2.35a): a placeholder until the cover's thumbnail decodes on a
//! worker, then the cover. A decode never blocks a scroll: a cell asks, keeps scrolling,
//! and takes the texture when it lands if it still shows the same publication.
//!
//! The rungs, cheapest first (`cover-art`, The cover ladder): the publication's own first
//! page, then a `cover`, `folder` or `poster` image beside the file (the phones'
//! `LooseCover`), then the placeholder. Nothing is fetched.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::rc::Rc;

use gtk::prelude::*;
use gtk::{gdk, gio, glib};
use storyarc_core::library::OpenPublication;

/// The longest edge a thumbnail decodes to: sharp at the largest cover tier on a
/// two-times display.
const THUMBNAIL_EDGE: u32 = 360;

#[derive(Default)]
pub struct Covers {
    textures: RefCell<HashMap<String, gdk::Texture>>,
    pending: RefCell<HashSet<String>>,
    /// Ids whose cover could not be decoded: they keep the placeholder.
    failed: RefCell<HashSet<String>>,
    waiting: RefCell<HashMap<String, Vec<glib::WeakRef<gtk::Picture>>>>,
}

impl Covers {
    pub fn get(&self, id: &str) -> Option<gdk::Texture> {
        self.textures.borrow().get(id).cloned()
    }

    /// Shows the cover of `id` in `picture`, now or once it decodes. The picture's name
    /// carries the id it is bound to, so a recycled cell never takes another's cover.
    pub fn show(self: &Rc<Self>, picture: &gtk::Picture, id: &str, path: Option<PathBuf>) {
        picture.set_widget_name(id);
        if let Some(texture) = self.get(id) {
            set_cover(picture, Some(&texture));
            return;
        }
        set_cover(picture, None);
        let Some(path) = path else {
            return;
        };
        if self.failed.borrow().contains(id) {
            return;
        }
        self.waiting
            .borrow_mut()
            .entry(id.to_owned())
            .or_default()
            .push(picture.downgrade());
        if !self.pending.borrow_mut().insert(id.to_owned()) {
            return;
        }
        let covers = Rc::downgrade(self);
        let id = id.to_owned();
        glib::spawn_future_local(async move {
            let decoded = gio::spawn_blocking(move || thumbnail(&path)).await;
            let Some(covers) = covers.upgrade() else {
                return;
            };
            covers.pending.borrow_mut().remove(&id);
            let pictures = covers.waiting.borrow_mut().remove(&id).unwrap_or_default();
            let Ok(Some(page)) = decoded else {
                covers.failed.borrow_mut().insert(id);
                return;
            };
            let texture = texture(page);
            covers
                .textures
                .borrow_mut()
                .insert(id.clone(), texture.clone());
            for picture in pictures.iter().filter_map(glib::WeakRef::upgrade) {
                if picture.widget_name() == id.as_str() {
                    set_cover(&picture, Some(&texture));
                }
            }
        });
    }
}

/// The stems a loose cover is looked for under, in order, and the extensions each is
/// tried with: the phones' `LooseCover`, so one folder answers the same on every app.
const LOOSE_STEMS: [&str; 3] = ["cover", "folder", "poster"];
const LOOSE_EXTENSIONS: [&str; 5] = ["jpg", "jpeg", "png", "webp", "heic"];

/// A cover image beside the publication at `path`: inside it when it is a folder, in its
/// own folder when it is a file. Stem outermost, so `cover.png` wins over `folder.jpg`.
pub fn loose_cover(path: &Path) -> Option<PathBuf> {
    let folder = if path.is_dir() { path } else { path.parent()? };
    LOOSE_STEMS
        .iter()
        .flat_map(|stem| {
            LOOSE_EXTENSIONS
                .iter()
                .map(move |extension| folder.join(format!("{stem}.{extension}")))
        })
        .find(|candidate| candidate.is_file())
}

/// The cover of the publication at `path`, decoded for a thumbnail: its own first page,
/// else a loose cover beside it, else nothing. Blocks: call it from a worker.
pub fn thumbnail(path: &Path) -> Option<storyarc_core::image::DecodedPage> {
    let own =
        OpenPublication::open(path).and_then(|open| open.decode_page(0, Some(THUMBNAIL_EDGE)));
    if let Ok(page) = own {
        return Some(page);
    }
    let bytes = std::fs::read(loose_cover(path)?).ok()?;
    storyarc_core::image::decode(&bytes, Some(THUMBNAIL_EDGE)).ok()
}

/// The placeholder is a card; a cover shown whole stands on its own, so no card edge
/// shows beside a cover narrower than its box.
fn set_cover(picture: &gtk::Picture, texture: Option<&gdk::Texture>) {
    picture.set_paintable(texture);
    if texture.is_none() || picture.content_fit() == gtk::ContentFit::Cover {
        picture.add_css_class("card");
    } else {
        picture.remove_css_class("card");
    }
}

/// A decoded page as a texture: straight RGBA, rows without padding.
pub fn texture(page: storyarc_core::image::DecodedPage) -> gdk::Texture {
    let stride = page.width as usize * 4;
    let bytes = glib::Bytes::from_owned(page.rgba);
    gdk::MemoryTexture::new(
        i32::try_from(page.width).unwrap_or(i32::MAX),
        i32::try_from(page.height).unwrap_or(i32::MAX),
        gdk::MemoryFormat::R8g8b8a8,
        &bytes,
        stride,
    )
    .upcast()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::publication::tests::fixture;
    use crate::scratch::Scratch;

    /// The bytes of a real page, to stand in for a cover image.
    fn page_bytes() -> Vec<u8> {
        OpenPublication::open(fixture("natural-sort.cbz"))
            .and_then(|open| open.page_bytes(0))
            .expect("a fixture page")
    }

    #[test]
    fn a_cover_image_beside_a_file_with_no_pages_becomes_its_cover() {
        let scratch = Scratch::new("loose-cover");
        let book = scratch.join("book.cbz");
        std::fs::copy(fixture("no-pages.cbz"), &book).expect("copied");
        assert_eq!(loose_cover(&book), None);
        assert!(
            thumbnail(&book).is_none(),
            "nothing answers: the placeholder"
        );
        std::fs::write(scratch.join("folder.jpg"), page_bytes()).expect("written");
        std::fs::write(scratch.join("cover.png"), page_bytes()).expect("written");
        assert_eq!(loose_cover(&book), Some(scratch.join("cover.png")));
        let cover = thumbnail(&book).expect("the loose cover answers");
        assert!(cover.width.max(cover.height) <= THUMBNAIL_EDGE);
    }

    #[test]
    fn the_publication_s_own_page_answers_before_a_loose_cover() {
        let scratch = Scratch::new("own-cover");
        let book = scratch.join("book.cbz");
        std::fs::copy(fixture("single-page.cbz"), &book).expect("copied");
        std::fs::write(scratch.join("poster.jpg"), b"not an image").expect("written");
        assert!(
            thumbnail(&book).is_some(),
            "the file's own page is the cover"
        );
    }

    #[test]
    fn a_folder_publication_is_searched_inside() {
        let scratch = Scratch::new("folder-cover");
        std::fs::write(scratch.join("poster.webp"), b"x").expect("written");
        assert_eq!(
            loose_cover(scratch.path()),
            Some(scratch.join("poster.webp"))
        );
    }
}
