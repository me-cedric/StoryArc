//! The cover ladder (task 2.35a): a placeholder until the cover's thumbnail decodes on a
//! worker, then the cover. A decode never blocks a scroll: a cell asks, keeps scrolling,
//! and takes the texture when it lands if it still shows the same publication.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
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
            picture.set_paintable(Some(&texture));
            return;
        }
        picture.set_paintable(gdk::Paintable::NONE);
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
            let decoded = gio::spawn_blocking(move || {
                OpenPublication::open(&path)
                    .and_then(|open| open.decode_page(0, Some(THUMBNAIL_EDGE)))
                    .ok()
            })
            .await;
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
                    picture.set_paintable(Some(&texture));
                }
            }
        });
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
