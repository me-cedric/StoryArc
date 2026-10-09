internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

struct DetailProvenanceLine: View {
    @Environment(\.theme) private var theme

    let provenance: PublicationProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(provenance.sentence)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let alsoIn = provenance.alsoInSentence {
                Text(alsoIn)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension PublicationProvenance {
    /// One whole sentence per state, never a place clause joined to an availability clause
    /// (one-vocabulary 4.6, O19). French, German and Spanish order the words of *from X, not
    /// on this device* differently from English, so a comma between two strings is a sentence
    /// only English can write. Each sentence takes at most the library's name.
    ///
    /// Android carries the same five sentences as `detail_provenance_*`.
    var sentence: String {
        switch (home, availability) {
        case (.thisDevice, _):
            DetailStrings.text("detail.provenance.device")
        case (.unattributed, _):
            DetailStrings.text("detail.provenance.unattributed")
        case let (.library(name), .notAnswering):
            DetailStrings.text("detail.provenance.away \(name)")
        case let (.library(name), .notHere):
            DetailStrings.text("detail.provenance.notHere \(name)")
        case let (.library(name), .now), let (.library(name), .offline):
            DetailStrings.text("detail.provenance.library \(name)")
        }
    }

    /// The second place, as a sentence of its own that names it, or `nil` when there is none.
    var alsoInSentence: String? {
        alsoIn.map { DetailStrings.text("detail.provenance.alsoIn \($0)") }
    }
}

enum DetailStrings {
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: Bundle.module.inChosenLanguage, locale: .storyArc)
    }
}
