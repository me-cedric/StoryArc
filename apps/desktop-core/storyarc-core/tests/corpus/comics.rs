//! What a comic fixture must parse to. Grows with each reader of wave 1, lane C.

use super::manifest::Comic;

/// Every assertion the manifest records for one comic archive.
///
/// Returns the first failure as text rather than panicking, so the per-fixture test names
/// the fixture and the pin together.
pub fn check(fixture: &Comic) -> Result<(), String> {
    Err(format!(
        "no reader opens {} yet ({})",
        fixture.file, fixture.pins
    ))
}
