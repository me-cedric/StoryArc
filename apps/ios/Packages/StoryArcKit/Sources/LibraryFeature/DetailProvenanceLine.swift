internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The one line, quietly typeset at the foot of the information.
///
/// This is the only place on the browse path where origin is named. Home, the library, the
/// on-device destination, search and shelves say nothing about it at all — that is what
/// makes five kinds of source read as one library, and it is only affordable because this
/// sentence exists.
///
/// It answers both questions at once, because `publication-detail` requires both and a line
/// that answers one is worse than no line: *where does this live* and *can I open it now*.
/// A reader who owns the same volume on the device and on a server can tell, before they
/// tap, which of the two they are about to read.
///
/// Composed from clauses rather than written as whole sentences per case. Four places
/// crossed with four availabilities is sixteen strings to translate into four languages and
/// sixteen chances for one of them to disagree with the others; two clauses and a separator
/// is eight, and the halves cannot drift because neither half knows about the other.
struct DetailProvenanceLine: View {
    @Environment(\.theme) private var theme

    let provenance: PublicationProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(sentence)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let alsoIn = provenance.alsoIn {
                Text("detail.provenance.alsoIn \(alsoIn)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read, not inferred. Availability is in the words, so a screen-reader user is told
        // the same thing a sighted one is shown — dimming a cover elsewhere is never the
        // only way that fact is conveyed.
        .accessibilityElement(children: .combine)
    }

    /// "On this device, readable with no network." / "From Attic, not answering."
    private var sentence: String {
        "\(place), \(availability)"
    }

    private var place: String {
        switch provenance.home {
        case .thisDevice:
            String(localized: "source.onThisDevice", bundle: .module, locale: .storyArc)
        case let .library(name):
            // "From %@" — the reader's own name for it, and nothing else about it. No
            // protocol, no address, no product, no path: that is the requirement, and the
            // registry's display name is the only field this line is allowed to read.
            String(localized: "library.cell.source \(name)", bundle: .module, locale: .storyArc)
        case .unattributed:
            DetailStrings.text("detail.provenance.unattributed")
        }
    }

    private var availability: String {
        switch provenance.availability {
        case .offline: DetailStrings.text("detail.availability.offline")
        case .now: DetailStrings.text("detail.availability.now")
        case .notHere: DetailStrings.text("detail.availability.notHere")
        case .notAnswering: DetailStrings.text("detail.availability.notAnswering")
        }
    }
}

/// One of this screen's strings, resolved as a `String` rather than as a `Text`.
///
/// The provenance sentence is assembled from two clauses before it is rendered, so both
/// halves have to be strings first — two `Text`s cannot be joined with a comma.
///
/// `Locale.storyArc` rather than the device's: `localization` lets a reader run StoryArc in
/// a language the phone is not set to, and a string resolved against the device would put
/// one English clause in the middle of a French sentence.
///
/// The clauses are new; the *places* reuse what the catalogue and the grid already say in
/// four languages, because two spellings of "On this device" in one app is how a vocabulary
/// drifts.
enum DetailStrings {
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module, locale: .storyArc)
    }
}
