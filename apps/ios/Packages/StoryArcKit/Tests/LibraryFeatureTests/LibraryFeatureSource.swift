import Foundation

/// The package's own source and string catalogue, read from disk by the guards that grep them.
///
/// Extracted from `BulkSelectionChromeTests` when that file crossed SwiftLint's 400-line cap.
/// The seam is a real one rather than a place to cut: two suites now read these — the chrome's
/// shape and state, and the action names in four languages — and a third copy of a `#filePath`
/// walk is a third chance for one of them to point somewhere else.
///
/// **Why these guards read source at all.** Several of the things this change had to fix are
/// declarations rather than values: whether the tab bar is hidden *inside the same statement*
/// that tests the selection, whether the foot of an Android screen holds a selection branch,
/// whether a named row is offered before the glyph fallback. A composition reports what the
/// inputs it was handed drew; the absence of a code path is not something any single
/// composition settles. Where a rendered pixel is the claim, the captures under
/// `docs/designs/screenshots/` are the proof and these guards only stop the declaration going
/// away between them.
enum LibraryFeatureSource {

    /// The package root, reached from `#filePath` rather than found.
    ///
    /// So it is inside the checkout being compiled, by construction. Walking up looking for a
    /// marker leaves it: this repository nests agent worktrees at `.claude/worktrees/`, and a
    /// walk climbs out of the one under test.
    private static var package: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// A source file in the package under test.
    static func source(_ relativePath: String) -> String {
        let file = package.appending(path: relativePath)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("\(relativePath) is not at \(file.path) — has it moved?")
        }
        return text
    }

    /// A file's code, with `//` prose removed.
    ///
    /// Every one of these files explains the defect it fixes, and those comments name the tab
    /// bar, the rectangle and the icon-only labels in order to say they are gone. A guard that
    /// searched the prose would pass on the documentation of the change.
    static func code(of relativePath: String) -> String {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The library's string catalogue, for one key.
    static func localizations(of key: String) -> [String: Any] {
        let catalogue = package.appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any],
            let record = strings[key] as? [String: Any]
        else {
            fatalError("the library's string catalogue is not readable at \(catalogue.path)")
        }
        return record["localizations"] as? [String: Any] ?? [:]
    }
}
