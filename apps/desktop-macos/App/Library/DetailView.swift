import AppKit
import DesignSystem
import LibraryFeature
import StoryArcCore
import Playback
import SwiftUI

/// A publication's page, pushed into the content column.
///
/// `docs/designs/desktop/macos.md` section 3: the cover wash under the hero, one primary
/// action, the other actions in a menu, and one line that names where the file lives.
/// `DetailPresentation` decides the words; this draws them. Task 2.23d.
struct DetailView: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication
    /// An audiobook's parts, for the primary action that names the chapter it resumes in.
    @State private var audioParts: [AudiobookPart] = []
    let onOpen: (Publication) -> Void
    /// Pushes another publication's page: an entry on the series shelf leads to its own page.
    let onShow: (Publication) -> Void

    var body: some View {
        let detail = presentation
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 24) {
                    CoverImage(library: library, publication: publication, maxPixelSize: 900)
                        .frame(width: 220, height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(publication.displayTitle).scaledFont(.largeTitle, weight: .bold).fontDesign(.serif)
                        if let line = CoverCell.secondLine(of: publication) {
                            Text(line).scaledFont(.title3).foregroundStyle(theme.palette.textSecondary)
                        }
                        if !publication.authors.isEmpty {
                            Text(publication.authors.joined(separator: ", "))
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        facts
                        HStack(spacing: 12) {
                            primary(detail)
                            more
                        }
                        .padding(.top, 8)
                        whereItLives(detail)
                    }
                    Spacer(minLength: 0)
                }
                if publication.format.isAudio, let url = library.model.location(of: publication) {
                    let record = library.record(of: publication)
                    let progress = library.progress
                    DetailAudioChapters(publication: publication, url: url, record: record) { part in
                        Task { await MacPlayer.listen(to: publication, at: url, startingAt: part, progress: progress) }
                    }
                }
                if let summary = publication.summary, !summary.isEmpty {
                    Text(summary).foregroundStyle(theme.palette.textPrimary).frame(maxWidth: 640, alignment: .leading)
                }
                OtherIssuesShelf(library: library, publication: publication, onShow: onShow)
            }
            .padding(28)
            .opacity(detail.isGrey ? 0.7 : 1)
        }
        .background(DetailWashBackground(library: library, publication: publication))
        .navigationTitle(publication.displayTitle)
        .task(id: publication.id) {
            guard publication.format.isAudio, let url = library.model.location(of: publication) else { return }
            audioParts = await DetailAudioChapters.parts(of: url)
        }
    }

    private var presentation: DetailPresentation {
        let location = library.model.location(of: publication)
        return DetailPresentation.make(
            publication: publication,
            location: location,
            isReachable: location.map(MacLibrary.isReachable) ?? false,
            progress: library.record(of: publication),
            hasCover: library.model.cachedCover(for: publication) != nil
        )
    }

    private var facts: some View {
        HStack(spacing: 14) {
            Text(publication.format.displayName)
            if let pages = publication.pageCount { Text("desktop.detail.pages \(pages)") }
            if let year = publication.year { Text(String(year)) }
        }
        .scaledFont(.callout)
        .foregroundStyle(theme.palette.textTertiary)
    }

    @ViewBuilder
    private func primary(_ detail: DetailPresentation) -> some View {
        switch detail.primary {
        case .read:
            Button { onOpen(publication) } label: {
                Text(publication.format.isAudio ? "desktop.detail.listen" : "desktop.detail.read").onAccentLabel()
            }
                .buttonStyle(.borderedProminent).tint(theme.accent)
        case .continue where publication.format.isAudio:
            Button { onOpen(publication) } label: {
                let words = DetailAudioChapters.primary(library.record(of: publication), parts: audioParts)
                Text(words.key).onAccentLabel()
            }
            .buttonStyle(.borderedProminent).tint(theme.accent)
        case let .continue(page, total):
            Button { onOpen(publication) } label: { Text("desktop.detail.continue \(page) \(total)").onAccentLabel() }
                .buttonStyle(.borderedProminent).tint(theme.accent)
        case .readAgain:
            Button { onOpen(publication) } label: { Text("desktop.detail.readAgain").onAccentLabel() }
                .buttonStyle(.borderedProminent).tint(theme.accent)
        case .unavailable:
            EmptyView()
        }
    }

    private var more: some View {
        Menu {
            PublicationMenu(library: library, publication: publication, onOpen: onOpen, onShow: { _ in })
        } label: {
            Text("desktop.detail.more")
        }
        // A secondary action beside the prominent one is borderless (AGENTS.md section 6).
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hitTarget()
    }

    private func whereItLives(_ detail: DetailPresentation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: detail.isGrey ? "externaldrive.badge.xmark" : "folder")
            if detail.isGrey {
                Text("desktop.detail.unavailable \(detail.whereItLives)")
            } else {
                Text(detail.whereItLives)
            }
        }
        .scaledFont(.callout)
        .foregroundStyle(theme.palette.textTertiary)
        .accessibilityElement(children: .combine)
    }
}

/// The cover wash under the hero, from the cover's own colour when one is cached.
private struct DetailWashBackground: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let publication: Publication

    var body: some View {
        LinearGradient(
            colors: [wash.opacity(0.35), theme.palette.surfaceCanvas],
            startPoint: .top, endPoint: .center
        )
        .ignoresSafeArea()
        .background(theme.palette.surfaceCanvas)
    }

    private var wash: Color {
        guard let image = library.model.cachedCover(for: publication),
              let pixels = CoverAccent.pixels(of: image),
              let hex = CoverAccent.derived(from: pixels)?.wash,
              let colour = Color(storyArcHex: hex)
        else { return theme.palette.surfaceSunken }
        return colour
    }
}

extension Color {
    /// A colour from the `#RRGGBB` strings `StoryArcCore` answers in, or `nil`.
    init?(storyArcHex hex: String) {
        let body = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard body.count == 6, let value = UInt32(body, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
