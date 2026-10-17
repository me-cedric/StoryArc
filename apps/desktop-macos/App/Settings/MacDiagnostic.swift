import AppKit
import Persistence
import StoryArcCore

/// The diagnostic, as the phone writes it, for a Mac.
///
/// A Mac copy of `SettingsFeature`'s `Diagnostic.text` (internal to that module): the same
/// sections, the same keys, and the same redaction, `DiagnosticRedaction`, which is public in
/// `StoryArcCore` and is what the mobile redaction test holds. `extra` carries the Mac's own
/// lines (the last write that failed, the connection), redacted with the rest. Making the
/// package's builder public is a parent edit under `apps/ios`.
enum MacDiagnostic {
    static func text(
        settings: AppSettings, sources: SourceRegistry, cacheBytes: Int64, historyBytes: Int64,
        readerStore: ReaderPreferences = ReaderPreferences(), extra: [String] = []
    ) -> String {
        let info = Bundle.main.infoDictionary
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var lines: [String] = [
            "StoryArc diagnostic", "",
            "[App]",
            "version = \(info?["CFBundleShortVersionString"] as? String ?? "0")",
            "build = \(info?["CFBundleVersion"] as? String ?? "0")",
            "",
            "[Device]",
            "platform = macOS \(version.majorVersion).\(version.minorVersion)",
            "deviceClass = Mac",
            "locale = \(Locale.current.identifier)",
            "",
            "[Settings]",
            "appearance = \(settings.appearance)",
            "language = \(settings.language ?? "system")",
            "volumeButtonsTurnPages = unavailable on macOS",
            "readingThemeFollowsAppearance = \(settings.linkReadingThemeToAppearance)",
            "downloadOnlyWhenNotMetered = \(settings.downloadOverWifiOnly)",
            "",
            "[Reading defaults]",
        ]
        let memory = readerStore.themes()
        for scope in ThemeScope.allCases {
            let shelf = memory.default(for: scope)
            lines.append("\(scope).preset = \(shelf.theme.preset)")
            lines.append("\(scope).modified = \(shelf.theme.isModified)")
            lines.append("\(scope).transition = \(shelf.transition)")
            lines.append("\(scope).fit = \(shelf.fit)")
        }
        lines += ["", "[Storage]", "cacheBytes = \(cacheBytes)", "historyBytes = \(historyBytes)", ""]
        lines += ["[Sources]", "configured = \(sources.sources.count)"]
        if !extra.isEmpty { lines += ["", "[Mac]"] + extra }
        return DiagnosticRedaction.redact(lines.joined(separator: "\n"))
    }
}

/// Where a saved diagnostic went, or why it did not.
enum DiagnosticSave: Equatable {
    case saved(URL)
    /// The folder the reader picked, by name, which could not be written.
    case failed(place: String)
    case cancelled
}

/// The save, with the panel and the write as parts a test can replace.
///
/// A cancel returns before anything is written, and the export itself is never kept: the
/// text lives in the sheet that shows it and goes with it. A failed write names the folder,
/// and the sheet offers the panel again; nothing is written anywhere the reader did not pick.
@MainActor
struct DiagnosticExporter {
    let choose: () async -> URL?
    let write: (Data, URL) throws -> Void

    init(
        choose: @escaping () async -> URL? = DiagnosticExporter.savePanel,
        write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.choose = choose
        self.write = write
    }

    func export(_ text: String) async -> DiagnosticSave {
        guard let url = await choose() else { return .cancelled }
        do {
            try write(Data(text.utf8), url)
            return .saved(url)
        } catch {
            return .failed(place: url.deletingLastPathComponent().lastPathComponent)
        }
    }

    /// The system's save panel, named for the day so two exports do not overwrite each other.
    static func savePanel() async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let day = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = String(localized: "desktop.diagnostic.fileName \(day)")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
