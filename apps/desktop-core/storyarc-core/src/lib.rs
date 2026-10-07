//! Shared desktop core for StoryArc on Windows and Linux. It has no UI code and never will.

/// The crate version, for example `0.1.0`.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    #[test]
    fn version_is_semver_shaped() {
        assert_eq!(super::version().split('.').count(), 3);
    }

    #[test]
    fn corpus_manifest_parses_and_lists_fixtures() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../packages/test-fixtures/manifest.json");
        let text = std::fs::read_to_string(&path).expect("read the shared corpus manifest");
        let manifest: serde_json::Value = serde_json::from_str(&text).expect("parse the manifest");
        let listed: usize = ["comics", "ebooks", "audiobooks", "pdfs"]
            .iter()
            .map(|kind| manifest[kind].as_array().map_or(0, Vec::len))
            .sum();
        assert!(listed >= 1, "the manifest lists no fixture");
        let first = manifest["comics"][0]["file"]
            .as_str()
            .expect("first comic has a file");
        assert!(
            path.parent().unwrap().join(first).is_file(),
            "{first} is missing on disk"
        );
    }
}
