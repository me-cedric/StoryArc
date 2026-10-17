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
                    shelf("desktop.home.keepReading", plan.keepReading, unreadable: plan.unreadable)
                }
                if !plan.upNext.isEmpty {
                    shelf("desktop.home.upNext", plan.upNext)
                }
                if !plan.recentlyAdded.isEmpty {
                    coverShelf("desktop.home.recentlyAdded", plan.recentlyAdded, showAll: plan.recentlyAddedHasMore ? {
                        library.navigationRequest = .filter(.recentlyAdded)
                    } : nil)
                }
                if !plan.finished.isEmpty {
                    finishedSection(plan)
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
            isUnread: { library.record(of: $0) == nil },
            isReadable: { library.model.location(of: $0).map(MacLibrary.isReachable) ?? false },
            library: model.publications,
            finishedAt: { library.record(of: $0).map { $0.finishedAt ?? $0.updatedAt } }
        )
    }

    /// A shelf of covers, with a Show All in its heading when it holds more than it shows.
    private func coverShelf(
        _ title: LocalizedStringKey, _ publications: [Publication], showAll: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(title, showAll: showAll)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(publications) { publication in
                        HomeCover(library: library, publication: publication, onOpen: onOpen, onShow: onShow)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    /// *Finished*, last on the surface, grouped by the month each was finished.
    private func finishedSection(_ plan: HomePlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("desktop.home.finished", showAll: plan.finishedHasMore ? {
                library.navigationRequest = .finished
            } : nil)
            ForEach(plan.finished) { month in
                VStack(alignment: .leading, spacing: 8) {
                    Text(month.month, format: .dateTime.month(.wide).year().locale(Locale.storyArc))
                        .scaledFont(.headline).foregroundStyle(theme.palette.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(month.publications) { publication in
                                HomeCover(library: library, publication: publication, onOpen: onOpen, onShow: onShow)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private func heading(_ title: LocalizedStringKey, showAll: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).scaledFont(.title2, weight: .semibold).accessibilityAddTraits(.isHeader)
            Spacer()
            if let showAll {
                Button(action: showAll) { Text("desktop.home.showAll") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("desktop.home.showAll.label \(Text(title))"))
            }
        }
    }

    private func shelf(
        _ title: LocalizedStringKey, _ publications: [Publication], unreadable: Set<String> = []
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(title, showAll: nil)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(publications) { publication in
                        HomeCard(
                            library: library, publication: publication,
                            isReadable: !unreadable.contains(publication.id), onOpen: onOpen, onShow: onShow
                        )
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
    let isReadable: Bool
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
                    Text(publication.displayTitle).scaledFont(.headline).lineLimit(2)
                    if let line = CoverCell.secondLine(of: publication) {
                        Text(line).scaledFont(.subheadline).foregroundStyle(theme.palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !isReadable {
                        Text("desktop.home.unavailable")
                            .scaledFont(.caption).foregroundStyle(theme.palette.textSecondary)
                    }
                    if let fraction {
                        ProgressRail(fraction: fraction).clipShape(Capsule())
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .scaledFont(.caption).foregroundStyle(theme.palette.textSecondary)
                    } else {
                        Text("desktop.home.unread").scaledFont(.caption).foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .frame(width: 180, alignment: .leading)
            }
            .padding(12)
            .background(theme.palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isReadable)
        .opacity(isReadable ? 1 : 0.55)
        .contextMenu { PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: onShow) }
        .accessibilityLabel(Text(CoverCell.label(for: publication, fraction: fraction)))
    }
}

/// A cover with its title under it, for the shelves below the two lead ones.
private struct HomeCover: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        let fraction = library.model.readFraction(of: publication)
        Button { onShow(publication) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    CoverImage(library: library, publication: publication, maxPixelSize: 300)
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    if let fraction { ProgressRail(fraction: fraction) }
                }
                .frame(width: 110, height: 165)
                Text(publication.displayTitle).scaledFont(.callout, weight: .medium).lineLimit(2)
                    .foregroundStyle(theme.palette.textPrimary)
            }
            .frame(width: 110, alignment: .leading)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(publication) })
        .contextMenu { PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: onShow) }
        .accessibilityLabel(Text(CoverCell.label(for: publication, fraction: fraction)))
    }
}
