import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// Home: Keep reading and Up next, each absent when empty.
///
/// `home-screen` on a desktop, task 2.23c. The plan is `HomePlan`, pure; this draws it as
/// the design's wide cards with a progress rail.
struct HomeView: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        let plan = plan
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !plan.keepReading.isEmpty {
                    shelf("desktop.home.keepReading", plan.keepReading)
                }
                if !plan.upNext.isEmpty {
                    shelf("desktop.home.upNext", plan.upNext)
                }
                if plan.isEmpty {
                    ContentUnavailableView {
                        Label("desktop.home.nothing.title", systemImage: "book")
                    } description: {
                        Text("desktop.home.nothing.body")
                    }
                }
            }
            .padding(24)
        }
    }

    private var plan: HomePlan {
        let model = library.model
        let finished = model.publications
            .compactMap { publication -> (Publication, Date)? in
                guard let record = library.record(of: publication), record.isFinished else { return nil }
                return (publication, record.finishedAt ?? record.updatedAt)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return HomePlan.make(
            continueReading: model.continueReading,
            finished: finished,
            next: { model.next(after: $0) },
            isUnread: { library.record(of: $0) == nil }
        )
    }

    private func shelf(_ title: LocalizedStringKey, _ publications: [Publication]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(publications) { publication in
                        HomeCard(library: library, publication: publication, onOpen: onOpen, onShow: onShow)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// A wide card: cover, title, series, and how far the reader got.
private struct HomeCard: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        let fraction = library.model.readFraction(of: publication)
        Button { onOpen(publication) } label: {
            HStack(alignment: .top, spacing: 12) {
                CoverImage(library: library, publication: publication, maxPixelSize: 300)
                    .frame(width: 72, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(publication.displayTitle).font(.headline).lineLimit(2)
                    if let line = CoverCell.secondLine(of: publication) {
                        Text(line).font(.subheadline).foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let fraction {
                        ProgressRail(fraction: fraction).clipShape(Capsule())
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.caption).foregroundStyle(theme.palette.textSecondary)
                    } else {
                        Text("desktop.home.unread").font(.caption).foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .frame(width: 180, alignment: .leading)
            }
            .padding(12)
            .background(theme.palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: onShow) }
        .accessibilityLabel(Text(CoverCell.label(for: publication, fraction: fraction)))
    }
}
