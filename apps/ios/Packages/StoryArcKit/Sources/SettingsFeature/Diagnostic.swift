internal import Foundation

internal import Persistence
internal import StoryArcCore

#if canImport(UIKit)
internal import UIKit
#endif

/// The diagnostic export, assembled and redacted.
///
/// `settings-and-about` asks for it to be "shown before sharing, with every credential,
/// token and server hostname redacted". Shown before sharing is the whole design: the
/// reader reads the text, then decides. Nothing is sent anywhere by the app.
///
/// Assembled here rather than in a shared type. Every value is one the platform alone can
/// read, so a shared report builder would be a shape with no logic in it. What *is* shared
/// is the rule — `DiagnosticRedaction` — and it is shared because it is the part that
/// would be dangerous to get differently right on each platform.
///
/// English, not localised. It goes into a bug report, and a report the maintainer cannot
/// read helps nobody. Every label is a fixed key rather than a sentence, for the same
/// reason.
enum Diagnostic {

    /// - Parameter sources: the registry, so the count below is the real one.
    ///
    ///   It used to be the literal `0`, which is a count in shape and a falsehood in fact —
    ///   a reader with four servers filed a report saying they had none.
    ///
    ///   **The registry rather than an `Int`, deliberately.** An `Int` would make a leak
    ///   unexpressible, which sounds stronger and is worse to depend on: it moves the
    ///   guarantee out of this file and into whichever caller does the counting, where
    ///   nothing asserts it. Passing the registry keeps the boundary *here*, two lines wide
    ///   and pointed at by a test that fails the moment a hostname joins the section.
    static func text(
        settings: AppSettings,
        readerStore: ReaderPreferences,
        historyBytes: Int64,
        cacheBytes: Int64,
        sources: SourceRegistry
    ) -> String {
        let memory = readerStore.themes()
        var lines: [String] = [
            "StoryArc diagnostic",
            "",
            "[App]",
            "version = \(BuildInfo.version)",
            "build = \(BuildInfo.build)",
            "",
            "[Device]",
        ]

        #if canImport(UIKit)
        let device = UIDevice.current
        lines.append("platform = \(device.systemName) \(device.systemVersion)")
        // A class, not a model identifier. `BuildInfo.issue` already settled this for the
        // issue link: the identifier narrows a person far more than "iPad" does, and
        // `settings-and-about` asked for the class. A diagnostic the reader shares
        // publicly is a stronger reason to hold that line, not a reason to relax it.
        lines.append("deviceClass = \(device.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
        // The counterpart of Android's `fontScale`, and the single most useful line in
        // the report for a "the text is cut off" complaint.
        // The raw value is Apple's internal identifier, `UICTContentSizeCategoryL`. The
        // prefix is noise in a report a person reads, and the suffix is the whole answer.
        let textSize = UITraitCollection.current.preferredContentSizeCategory.rawValue
            .replacingOccurrences(of: "UICTContentSizeCategory", with: "")
        lines.append("textSize = \(textSize)")
        #else
        lines.append("platform = macOS")
        lines.append("deviceClass = Mac")
        #endif
        lines.append("locale = \(Locale.current.identifier)")

        lines += [
            "",
            "[Settings]",
            "appearance = \(settings.appearance)",
            "language = \(settings.language ?? "system")",
            // Named as absent rather than omitted. A reader comparing this report with an
            // Android one should be able to see that the row is missing on purpose.
            "volumeButtonsTurnPages = unavailable on iOS",
            "readingThemeFollowsAppearance = \(settings.linkReadingThemeToAppearance)",
            "",
            "[Reading defaults]",
        ]

        for scope in ThemeScope.allCases {
            let shelf = memory.default(for: scope)
            lines.append("\(scope).preset = \(shelf.theme.preset)")
            lines.append("\(scope).modified = \(shelf.theme.isModified)")
            lines.append("\(scope).transition = \(shelf.transition)")
            // Per scope rather than on its own line above: the fit is a per-series
            // choice now, and what a report can state is the default a shelf inherits.
            lines.append("\(scope).fit = \(shelf.fit)")
        }

        lines += [
            "",
            "[Storage]",
            "cacheBytes = \(cacheBytes)",
            "historyBytes = \(historyBytes)",
            "",
        ]
        lines += sourceLines(in: sources)

        return DiagnosticRedaction.redact(lines.joined(separator: "\n"))
    }

    /// The report's `[Sources]` section: a heading and a count, and never a row per source.
    ///
    /// **Three values a source holds must not appear in a diagnostic, and this is the only
    /// place in the report where any of them could.** The display name is text the reader
    /// typed, and a reader names a server after the machine — so it *is* the hostname. The
    /// locator is a URL, which is where an embedded credential would survive. The credential
    /// reference is a handle into the platform secure store. `sources` forbids a secret
    /// reaching "preferences, logs, crash reports, backups, or exported diagnostics", and
    /// `AGENTS.md` §2.4 says it again without the escape hatch.
    ///
    /// So the section carries none of them, rather than carrying them redacted: redaction is
    /// a rule about strings that got out, and this is a string that never leaves.
    ///
    /// Its own function so that a test has something to point at, and so the mutation that
    /// would break it — appending anything derived from a source — is one line long and one
    /// line to catch. `DiagnosticSourcesTests` and Android's `DiagnosticSourcesTest` assert
    /// the same three refusals.
    static func sourceLines(in registry: SourceRegistry) -> [String] {
        ["[Sources]", "configured = \(registry.sources.count)"]
    }
}
