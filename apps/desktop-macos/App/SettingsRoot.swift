import SwiftUI

/// The preferences window: one window, toolbar tabs, grouped forms.
///
/// The six tabs are the design's (section 5) and match the spec groups. Each one is a
/// grouped form with one grey sentence until its wave fills it, so `⌘,` already opens the
/// window a reader will keep. Sources is first because it is the one action the empty
/// library offers. The search field the spec asks for is proposed in the design and not
/// built here.
struct SettingsRoot: View {
    /// Fixed by the design: "Width 560 pt fixed."
    static let width: CGFloat = 560

    var body: some View {
        TabView {
            Tab("desktop.settings.sources", systemImage: "externaldrive.connected.to.line.below") {
                SettingsPlaceholder()
            }
            Tab("desktop.settings.appearance", systemImage: "paintpalette") {
                SettingsPlaceholder()
            }
            Tab("desktop.settings.reading", systemImage: "book") {
                SettingsPlaceholder()
            }
            Tab("desktop.settings.downloads", systemImage: "arrow.down.circle") {
                SettingsPlaceholder()
            }
            Tab("desktop.settings.language", systemImage: "globe") {
                SettingsPlaceholder()
            }
            Tab("desktop.settings.privacy", systemImage: "hand.raised") {
                SettingsPlaceholder()
            }
        }
        .frame(width: Self.width)
        .frame(minHeight: 220)
    }
}

/// A tab with nothing to set yet: one sentence in grey, in the form it will become.
private struct SettingsPlaceholder: View {
    var body: some View {
        Form {
            Text("desktop.settings.empty")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
