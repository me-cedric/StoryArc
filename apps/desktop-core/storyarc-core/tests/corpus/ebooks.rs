//! What an EPUB fixture must parse to. Grows with the EPUB reader of task 1.6.

use super::manifest::Ebook;

pub fn check(fixture: &Ebook) -> Result<(), String> {
    Err(format!(
        "no reader opens {} yet ({})",
        fixture.file, fixture.pins
    ))
}
