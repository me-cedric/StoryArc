internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The one switch that lets a cover request leave the device.
///
/// On the Privacy screen rather than beside the other reading settings, because what it
/// changes is where data goes. `cover-art` requires the app to "name the provider it would
/// ask" before a reader turns it on, so the row states all three and the sentence under it
/// states what travels: one identifier, and nothing else.
struct CoverLookupSettings: View {
    @Binding var settings: AppSettings

    var highlight: SettingsAnchor?

    @Environment(\.theme) private var theme

    /// The three catalogues, written out for the reader.
    ///
    /// Joined with a comma rather than a localised list format: these are the catalogues'
    /// own names, and the row's job is to let a reader recognise them. Static, so a test
    /// can assert the row names every provider the lookup can reach — a fourth provider
    /// added without a word on this screen would be a request a reader never agreed to.
    nonisolated static var providerNames: String {
        CoverLookupProvider.allCases.map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        Section {
            Toggle(isOn: $settings.lookUpMissingCovers) {
                VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                    Text("covers.lookup", bundle: .module)
                    Text("covers.lookup.providers \(Self.providerNames)", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
            .settingsHighlight(.coverLookup, when: highlight)
        } footer: {
            Text("covers.lookup.note", bundle: .module)
        }
    }
}
