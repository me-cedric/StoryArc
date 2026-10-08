internal import PhotosUI
internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The hero, and what the reader can do about the picture in it.
///
/// Tasks 2.2, 2.3 and 2.4 of `cover-for-every-publication`. ``DetailHero`` draws the artwork
/// and knows nothing about where it came from; this owns the choosing, so the hero stays a
/// view that takes a `CGImage` and the chooser can be read in one place.
///
/// **`PhotosPicker` and nothing else.** It is `PHPickerViewController`, which runs out of
/// process and hands this app the one picture the reader selected — so there is no
/// photo-library permission to ask for, and `design.md`'s rule about not asking for what you
/// do not need is kept by the platform rather than by us. A document picker or a library
/// authorisation would both put a prompt in front of a reader who only wants to set a
/// picture, and `design.md` records that decision at length.
struct DetailCoverChoice: View {
    @Environment(\.theme) private var theme

    let publication: Publication
    let model: LibraryModel
    let cover: CGImage?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    @State private var isFinding = false
    /// The address the system browser is showing, while it is.
    @State private var browsing: URL?
    @State private var isChoosing = false
    @State private var picked: PhotosPickerItem?
    @State private var hasChosenCover = false
    @State private var isUnreadable = false

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            DetailHero(
                publication: publication,
                cover: cover,
                onChooseCover: { isChoosing = true }
            )
            controls
        }
        .photosPicker(isPresented: $isChoosing, selection: $picked, matching: .images)
        .sheet(isPresented: $isFinding) {
            CoverFinderSheet(publication: publication, model: model) { stored in
                isUnreadable = !stored
                hasChosenCover = hasChosenCover || stored
            }
        }
        #if os(iOS)
        .sheet(isPresented: Binding(get: { browsing != nil }, set: { if !$0 { browsing = nil } })) {
            if let browsing { SystemBrowser(url: browsing).ignoresSafeArea() }
        }
        #endif
        .task(id: publication.id) { hasChosenCover = model.hasChosenCover(for: publication) }
        .onChange(of: picked) { _, item in Task { await adopt(item) } }
    }

    /// The two controls the hero itself cannot carry.
    ///
    /// The empty well is already the way in — it *is* the button, per task 2.3 — but a well
    /// that is silently tappable is a well nobody taps, so the same offer is made in words
    /// underneath, and a publication that already has a cover has nowhere else to put it. The
    /// warning is drawn only where it is true.
    @ViewBuilder
    private var controls: some View {
        VStack(spacing: StoryArcSpace.hair) {
            // Side by side until the text stops fitting, then stacked. `design.md` §3 rule 3
            // asks every screen to survive the largest accessibility size, and two labels in
            // a row at that size wrap into each other — `ios-detail-chosen-cover-ax5-dark.png`
            // photographed *Cha nge cov er* across *Remove cover* before this split existed.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: StoryArcSpace.xs) { buttons }
                } else {
                    HStack(spacing: StoryArcSpace.md) { buttons }
                }
            }
            .textRole(.subheadline)
            .buttonStyle(.borderless)

            finder

            // `cover-art`'s *A publication with no digest*: an image folder and a server row
            // have no content digest, so the choice is filed under the path and a move loses
            // it. Said here rather than nowhere, because a silent loss is worse than a
            // stated limit — and said only once the reader has something to lose.
            if hasChosenCover, model.chosenCoverIsTiedToPath(for: publication) {
                Text("cover.tiedToPath", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if isUnreadable {
                Text("cover.unreadable", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(StoryArcColor.Status.offline)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The two ways of finding a cover, as far as the lookup switch allows.
    ///
    /// Task 6.2. The title search is here only while the switch is on; the web hand-off is
    /// always here, because the browser makes that request and the app does not.
    @ViewBuilder
    private var finder: some View {
        let offer = model.coverFinderOffer()
        if offer.findACover {
            Button { isFinding = true } label: {
                Label {
                    Text("covers.find", bundle: .module)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
            }
            .textRole(.subheadline)
            .buttonStyle(.borderless)
        }
        if offer.webSearch {
            CoverSearchHandoff(
                title: publication.displayTitle, author: publication.authors.first, open: openInBrowser
            )
        }
    }

    /// Hands the address to the system browser and keeps nothing it shows.
    private func openInBrowser(_ url: URL) {
        #if os(iOS)
        browsing = url
        #else
        openURL(url)
        #endif
    }

    /// The two controls themselves, so one copy serves both the row and the stack.
    @ViewBuilder
    private var buttons: some View {
        // Said in words as well as offered on the well itself. A well that is silently
        // tappable is a well that nobody taps: `design.md` rule 2 asks for a label beside
        // anything a reader has to notice, and the glyph alone says only "no artwork".
        Button { isChoosing = true } label: {
            Label {
                Text(cover == nil ? "cover.choose" : "cover.change", bundle: .module)
            } icon: {
                Image(systemName: "photo")
            }
        }
        if hasChosenCover {
            Button(role: .destructive) {
                Task {
                    await model.removeChosenCover(for: publication)
                    hasChosenCover = false
                }
            } label: {
                Text("cover.remove", bundle: .module)
            }
        }
    }

    /// Takes the picture the reader chose and makes it this publication's cover.
    ///
    /// The picker hands over bytes rather than a file, which is the whole of what this app
    /// ever learns about the reader's photo library: no album, no asset identifier, no second
    /// picture. Nothing is fetched and nothing is sent.
    private func adopt(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        picked = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              await model.setCover(data, for: publication)
        else {
            isUnreadable = true
            return
        }
        isUnreadable = false
        hasChosenCover = true
    }
}
