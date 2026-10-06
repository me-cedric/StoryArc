internal import SwiftUI

internal import Catalogue
internal import DesignSystem

/// The candidates a title search found, for the reader to choose from.
///
/// `cover-art`: the app "SHALL show the candidates and let the reader choose", and "never
/// silently adopts a match it is not certain of, because a wrong cover is worse than none".
/// So this sheet has no "best match" and no automatic dismissal: it waits.
///
/// An exact lookup by identifier never reaches this screen. A title is the uncertain case,
/// and this is what uncertainty looks like when it is shown rather than guessed at.
struct CoverCandidateSheet: View {
    let candidates: [CoverCandidate]

    /// What the reader picked. Called once, with the candidate, and never with a default.
    let onChoose: (CoverCandidate) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        List {
            if candidates.isEmpty {
                Text("covers.candidates.none", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                Section {
                    ForEach(candidates) { candidate in
                        Button { onChoose(candidate) } label: { row(candidate) }
                    }
                } footer: {
                    Text("covers.candidates.note", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("covers.candidates", bundle: .module))
    }

    @ViewBuilder
    private func row(_ candidate: CoverCandidate) -> some View {
        HStack(spacing: StoryArcSpace.sm) {
            // Decorative: the label beside it says what this is, and a description here
            // would read the same title twice.
            AsyncImage(url: candidate.imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: 44, height: 66)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(candidate.title)
                if let subtitle = candidate.subtitle {
                    Text(subtitle)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                // Which catalogue answered, because a reader choosing between two nearly
                // identical pictures has nothing else to choose on.
                Text("covers.candidates.from \(candidate.provider.displayName)", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
    }
}
