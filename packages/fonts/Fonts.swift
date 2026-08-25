public import Foundation

/// Where the bundled typefaces are.
///
/// A resource-only target still needs one Swift file for `Bundle.module` to exist.
/// This is it, and it earns its place by being the only thing that knows the file
/// names — the reader asks for a family and gets URLs.
public enum StoryArcFonts {
    /// The bundle the `.ttf` files live in.
    public static var bundle: Bundle { .module }

    /// A font file by name, or `nil` if it is not bundled.
    public static func url(_ name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "ttf")
    }
}
