//! Shared desktop core for StoryArc on Windows and Linux. It has no UI code and never will.

pub mod domain;
pub mod formats;
pub mod image;
pub mod io;
pub mod library;
pub mod locale;
pub mod paths;
pub mod sources;
pub mod store;

/// The crate version, for example `0.1.0`.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    #[test]
    fn version_is_semver_shaped() {
        assert_eq!(super::version().split('.').count(), 3);
    }
}
