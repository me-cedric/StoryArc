import SwiftUI

internal import DesignSystem
import StoryArcCore

/// Everything on a publication's page that belongs inside the reading measure.
///
/// The hero, the title block, the actions, the description, and the two facts only a Kavita
/// server can state. ``PublicationDetailView`` puts the measure, the gutter and the series
/// shelf around it.
///
/// **A view rather than a `@ViewBuilder` on the page, so the composition can be asserted.**
/// Every one of these parts is tested on its own, and none of that catches the one defect
/// that matters here: a part the page stops calling. Android's `KavitaCardFactsTest` composes
/// `DetailMainPane` for exactly that reason, and this is the seam that lets iOS mirror it —
/// `KavitaCardFactsTests` measures this column with a card and without one.
struct DetailMainColumn: View {
    let publication: Publication
    let model: LibraryModel
    let cover: CGImage?
    @Binding var isKept: Bool

    /// What the server said when this chapter was kept, read by the page. Nil for everything
    /// that is not a kept Kavita chapter, which is most of the shelf.
    let kavitaCard: KavitaCard?

    let file: URL?

    /// Where the publication opens from, which may be an address a transfer is fetching.
    /// See ``DetailActions/address``.
    let address: URL?

    /// What the page says about an audiobook and about nothing else: its chapters, its
    /// length, and the chapter the primary action names. ``DetailAudiobook/absent`` for a
    /// comic, so a comic cannot grow a chapter list by being composed here.
    let audiobook: DetailAudiobook

    /// What to do with the chapter a listener chose, or `nil` where nothing here can start
    /// playback yet.
    let onChooseChapter: ((Int) -> Void)?

    let onRead: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        // A measure, not a margin. On a 13-inch iPad the description runs to nearly two
        // hundred characters a line and the primary action becomes a metre-wide bar — both
        // of which are the page *filling* the window rather than composing it.
        VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
            DetailHero(publication: publication, cover: cover)
            DetailTitleBlock(publication: publication)
            DetailActions(
                publication: publication,
                model: model,
                isKept: $isKept,
                file: file,
                address: address,
                resuming: audiobook.resuming,
                onRead: onRead
            )
            // Under the action rather than over it: `publication-detail` puts exactly one
            // thing first in the reading order after the title, and a list of chapters ahead
            // of it would put twelve.
            DetailChapterList(chapters: audiobook.chapters, onChoose: onChooseChapter)
            // The length only where there is no list to carry it, which is the one-part book.
            if audiobook.chapters.isEmpty {
                DetailBookLength(seconds: audiobook.length)
            }
            summary
            // The two of `kavita-server`'s seven metadata fields that ``Publication`` has no
            // slot for. Nothing at all — not an empty block — for everything that is not a
            // kept Kavita chapter. See ``KavitaCardFacts``.
            KavitaCardFacts(card: kavitaCard)
        }
    }

    /// The description, when the publication carries one.
    ///
    /// Absent rather than empty: the delta refuses a placeholder, and this change does not
    /// alter what the scan collects — if a description is missing today it is missing here.
    /// The rule is ``detailSummary(of:)``, free and pure so the absence is asserted rather
    /// than read off this `if let`, and blank-checked so a description of three spaces is an
    /// absence rather than an empty paragraph with the page's own spacing around it.
    @ViewBuilder
    private var summary: some View {
        if let summary = detailSummary(of: publication) {
            Text(summary)
                .textRole(.body)
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
