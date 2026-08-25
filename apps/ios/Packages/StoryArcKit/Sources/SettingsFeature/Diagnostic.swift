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

    static func text(
        settings: AppSettings,
        readerStore: ReaderPreferences,
        historyBytes: Int64,
        cacheBytes: Int64
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
            "pageFit = \(readerStore.pageFit())",
            "",
            "[Reading defaults]",
        ]

        for scope in ThemeScope.allCases {
            let shelf = memory.default(for: scope)
            lines.append("\(scope).preset = \(shelf.theme.preset)")
            lines.append("\(scope).modified = \(shelf.theme.isModified)")
            lines.append("\(scope).transition = \(shelf.transition)")
        }

        lines += [
            "",
            "[Storage]",
            "cacheBytes = \(cacheBytes)",
            "historyBytes = \(historyBytes)",
            "",
            "[Sources]",
            // Reported as a count rather than a list. A source's display name is text the
            // reader typed, which is exactly where a hostname would be — so the report
            // does not carry it at all, rather than carrying it redacted.
            "configured = 0",
        ]

        return DiagnosticRedaction.redact(lines.joined(separator: "\n"))
    }
}
