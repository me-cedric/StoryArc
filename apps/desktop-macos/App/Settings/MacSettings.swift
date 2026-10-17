import AppKit
import Persistence
import StoryArcCore
import SwiftUI

/// Which colour the library chrome takes.
///
/// `design.md` Open Question 1, answered by the owner: the StoryArc brand colour by
/// default, and a settings choice to follow the system accent instead. A colour taken from
/// a cover stays inside the readers and is the same under both choices. Task 2.23e.
enum ChromeAccent: String, CaseIterable, Sendable, Codable {
    case brand
    case system

    static let defaultsKey = "app.storyarc.mac.chromeAccent"
}

/// The reader's own text size, since macOS has no system text scaling for apps.
///
/// `desktop-experience`, *Text size, contrast and motion follow the system*: on macOS the
/// app's own size control meets the largest-text scenarios. Applied as a Dynamic Type size
/// to every window, so the library, the settings and the reader chrome all scale.
enum ChromeTextSize: String, CaseIterable, Sendable, Codable {
    case `default`
    case large
    case largest

    static let defaultsKey = "app.storyarc.mac.textSize"

    /// How much larger than the system's own sizes the windows draw their text.
    ///
    /// macOS has no system text size, and SwiftUI on macOS ignores `dynamicTypeSize`: wave 2
    /// set it and the largest-size frames came out identical to the default ones. So every
    /// window draws its text through `scaledFont`, which multiplies the macOS point size of
    /// each text style by this.
    var scale: CGFloat {
        switch self {
        case .default: 1
        case .large: 1.25
        case .largest: 1.6
        }
    }
}

/// Everything the Mac's preferences hold, observed by every window.
///
/// `AppSettings` and its `SettingsStore` are StoryArcKit's, so what iOS stores here is what
/// the Mac stores; the two Mac-only choices sit beside them under their own keys.
@MainActor
@Observable
final class MacSettings {
    static let shared = MacSettings()

    var settings: AppSettings {
        didSet { if settings != oldValue { store.save(settings) } }
    }

    var accent: ChromeAccent {
        didSet { if accent != oldValue { defaults.set(accent.rawValue, forKey: ChromeAccent.defaultsKey) } }
    }

    var textSize: ChromeTextSize {
        didSet { if textSize != oldValue { defaults.set(textSize.rawValue, forKey: ChromeTextSize.defaultsKey) } }
    }

    /// Whether the cover stands alone on the first screen of a spread. The spec's desktop
    /// default is on.
    var coverAlone: Bool {
        didSet { if coverAlone != oldValue { defaults.set(coverAlone, forKey: Self.coverAloneKey) } }
    }

    static let coverAloneKey = "app.storyarc.mac.coverAlone"

    /// The preferences tab on show. Not stored: the window opens on Sources each launch.
    var settingsTab: SettingsTab = .sources

    private let store: SettingsStore
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = SettingsStore(defaults: defaults)
        settings = store.settings()
        accent = ChromeAccent(rawValue: defaults.string(forKey: ChromeAccent.defaultsKey) ?? "") ?? .brand
        textSize = ChromeTextSize(rawValue: defaults.string(forKey: ChromeTextSize.defaultsKey) ?? "") ?? .default
        coverAlone = defaults.object(forKey: Self.coverAloneKey) as? Bool ?? true
    }

    /// Every preference back to its default: `settings-and-about`, *Resetting*. The folders,
    /// the downloads and the reading progress live elsewhere and are not touched, which is
    /// what the confirmation says. The app's language follows the system again.
    func reset() {
        store.reset()
        settings = store.settings()
        accent = .brand
        textSize = .default
        coverAlone = true
        InterfaceLanguage.choose(settings.language)
    }
}

/// The colour the chrome uses now, following the system accent live when asked to.
///
/// Observes the system's tint change, so *Following the system accent* holds: a later
/// change of the system accent recolours the chrome while the app is open, with no window
/// reopened. The brand colour is the design system's palette accent, which is what every
/// other surface already uses.
@MainActor
@Observable
final class AccentModel {
    static let shared = AccentModel()

    private(set) var systemAccent: Color
    private var observer: (any NSObjectProtocol)?

    init(systemAccent: Color = Color(nsColor: .controlAccentColor)) {
        self.systemAccent = systemAccent
        observer = NotificationCenter.default.addObserver(
            forName: NSColor.currentControlTintDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemAccentChanged(to: Color(nsColor: .controlAccentColor)) }
        }
    }

    /// What the chrome draws with, for this choice and this palette.
    func chromeColour(for choice: ChromeAccent, brand: Color) -> Color {
        switch choice {
        case .brand: brand
        case .system: systemAccent
        }
    }

    /// A cover's colour is the same under both choices: it never goes through here.
    static func coverAccent(_ cover: Color?, choice: ChromeAccent) -> Color? {
        _ = choice
        return cover
    }

    func systemAccentChanged(to colour: Color) {
        systemAccent = colour
    }
}
