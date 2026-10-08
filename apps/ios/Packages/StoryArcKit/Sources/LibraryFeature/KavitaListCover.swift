internal import PhotosUI
internal import SwiftUI

internal import DesignSystem
internal import Formats
internal import Kavita
internal import StoryArcCore

/// What a Kavita reading list's own cover needs decided before it is drawn.
///
/// Tasks 6.4 and 5.1 of `cover-for-every-publication`. Free of the view so a test can state
/// both rules without a window. Android's `KavitaListCover` is its twin.
enum KavitaListCover {

    /// A server list as the cover-override store names it, under the same kind of identity
    /// `EntryPoster` gives a chapter, so the two cannot be filed under one key.
    ///
    /// Nil when the source is not named by a UUID, which no registered source fails to be: a
    /// list there has nowhere to keep a chosen cover, so none is offered.
    static func publication(serverID: String, listID: Int) -> Publication? {
        guard let source = UUID(uuidString: serverID) else { return nil }
        return Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "list:\(listID)")
            ),
            format: .cbz,
            displayTitle: "",
            origin: .authoritative
        )
    }

    /// What the write-back button is asked about, or nil where it is not placed at all.
    ///
    /// Two things must hold before the button exists. A cover has been chosen, because the
    /// button's Send has nothing to send otherwise. And the server has said this list is in
    /// its answer, because `ReadingList/lists` is the only place the `promoted` flag comes
    /// from: a list the server did not list, or an answer that never arrived, proves no
    /// ownership. Whether a promoted list is then refused is
    /// ``CoverWriteBack/offer(for:)``'s decision and nobody else's.
    static func writeSubject(
        listID: Int, hasChosen: Bool, lists: [KavitaReadingList]?
    ) -> CoverWriteSubject? {
        guard hasChosen, let held = lists?.first(where: { $0.id == listID }) else { return nil }
        return .kavitaReadingList(id: listID, promoted: held.promoted)
    }

    /// Crops the picture to a cover's shape and files it. False is a picture that cannot be used.
    static func choose(
        _ picture: Data, as list: Publication, in overrides: CoverOverrideStore
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let shaped = CoverArtwork.coverShaped(picture) else { return false }
            return overrides.store(shaped, for: list) != nil
        }.value
    }
}

/// The list's own cover, and the things a reader can do about it.
///
/// A picture of the reader's own choosing, kept on this device. Once one is chosen, and only
/// then, the reader may also send it to the server, where ``CoverWriteBackButton`` confirms
/// that this changes the cover for everyone who can see the list.
struct KavitaListCoverControls: View {
    let serverID: String
    let listID: Int
    let address: KavitaAddress
    var overrides = CoverOverrideStore()

    @Environment(\.theme) private var theme

    @State private var chosen: CGImage?
    @State private var picked: PhotosPickerItem?
    @State private var isUnreadable = false
    @State private var lists: [KavitaReadingList]?

    private var list: Publication? {
        KavitaListCover.publication(serverID: serverID, listID: listID)
    }

    var body: some View {
        if let list {
            HStack(spacing: StoryArcSpace.md) {
                well
                VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                    controls(for: list)
                }
            }
            .task(id: listID) {
                chosen = Self.cover(overrides.data(for: list))
                lists = try? await KavitaClient(address: address).readingLists()
            }
            .onChange(of: picked) { _, item in Task { await adopt(item, as: list) } }
        }
    }

    private var well: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm).fill(theme.palette.surfaceRaised)
            if let chosen {
                Image(decorative: chosen, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: StoryArcRadius.sm))
            }
        }
        .frame(height: 88)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func controls(for list: Publication) -> some View {
        PhotosPicker(selection: $picked, matching: .images) {
            Text(chosen == nil ? "cover.choose" : "cover.change", bundle: .module)
        }
        .buttonStyle(.borderless)
        if chosen != nil {
            Button(role: .destructive) {
                overrides.remove(for: list)
                chosen = nil
            } label: {
                Text("cover.remove", bundle: .module)
            }
            .buttonStyle(.borderless)
        }
        if let subject = KavitaListCover.writeSubject(
            listID: listID, hasChosen: chosen != nil, lists: lists
        ) {
            CoverWriteBackButton(
                subject: subject,
                image: { overrides.data(for: list) },
                send: { id, data in
                    try await KavitaClient(address: address).uploadReadingListCover(id, image: data)
                }
            )
            .buttonStyle(.borderless)
        }
        if isUnreadable {
            Text("cover.unreadable", bundle: .module)
                .textRole(.caption)
                .foregroundStyle(StoryArcColor.Status.offline)
        }
    }

    private func adopt(_ item: PhotosPickerItem?, as list: Publication) async {
        guard let item else { return }
        picked = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              await KavitaListCover.choose(data, as: list, in: overrides)
        else {
            isUnreadable = true
            return
        }
        isUnreadable = false
        chosen = Self.cover(overrides.data(for: list))
    }

    private static func cover(_ data: Data?) -> CGImage? {
        data.flatMap { try? PageDecoder.decode($0, maxPixelSize: 264) }
    }
}
