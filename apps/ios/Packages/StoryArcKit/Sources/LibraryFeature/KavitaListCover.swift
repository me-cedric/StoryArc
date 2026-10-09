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

    /// The cover menu's rows for this list.
    ///
    /// Choosing, and sending where ``CoverWriteBack/offer(for:)`` offers it, then removal alone
    /// in its own group once a picture is chosen. There is no title search here: a list has no
    /// publication to look a title up for.
    static func menuRows(
        listID: Int, hasChosen: Bool, lists: [KavitaReadingList]?
    ) -> [[CoverMenuRow]] {
        let send = writeSubject(listID: listID, hasChosen: hasChosen, lists: lists)
            .map { CoverWriteBack.offer(for: $0) != .none } ?? false
        return CoverMenu.rows(find: false, web: false, send: send, remove: hasChosen)
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
/// A picture of the reader's own choosing, kept on this device, behind one edit button on the
/// cover. Once one is chosen, and only then, the reader may also send it to the server, where
/// ``coverWriteBack(asking:subject:image:send:)`` confirms that this changes the cover for
/// everyone who can see the list.
struct KavitaListCoverControls: View {
    let serverID: String
    let listID: Int
    let address: KavitaAddress
    var overrides = CoverOverrideStore()

    @Environment(\.theme) private var theme

    @State private var chosen: CGImage?
    @State private var picked: PhotosPickerItem?
    @State private var isChoosing = false
    @State private var isUnreadable = false
    @State private var lists: [KavitaReadingList]?
    /// The menu row that waits for a yes, while one does.
    @State private var asking: CoverMenuRow?

    private var list: Publication? {
        KavitaListCover.publication(serverID: serverID, listID: listID)
    }

    var body: some View {
        if let list {
            VStack(spacing: StoryArcSpace.xs) {
                well.coverEditing(menu)
                if chosen == nil { CoverAddMenu(menu: menu) }
                if isUnreadable {
                    Text("cover.unreadable", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(StoryArcColor.Status.offline)
                }
            }
            .frame(maxWidth: .infinity)
            .photosPicker(isPresented: $isChoosing, selection: $picked, matching: .images)
            .coverRemoval(asking: $asking) {
                overrides.remove(for: list)
                chosen = nil
            }
            .coverWriteBack(
                asking: $asking,
                subject: KavitaListCover.writeSubject(listID: listID, hasChosen: chosen != nil, lists: lists),
                image: { overrides.data(for: list) },
                send: { id, data in
                    try await KavitaClient(address: address).uploadReadingListCover(id, image: data)
                }
            )
            .task(id: listID) {
                chosen = Self.cover(overrides.data(for: list))
                lists = try? await KavitaClient(address: address).readingLists()
            }
            .onChange(of: picked) { _, item in Task { await adopt(item, as: list) } }
        }
    }

    private var menu: CoverMenu {
        CoverMenu(
            hasCover: chosen != nil,
            rows: KavitaListCover.menuRows(listID: listID, hasChosen: chosen != nil, lists: lists),
            act: select
        )
    }

    private func select(_ row: CoverMenuRow) {
        if row.asksFirst {
            asking = row
        } else if row == .choose {
            isChoosing = true
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
            } else {
                Image(systemName: "photo").foregroundStyle(theme.palette.textTertiary)
            }
        }
        .frame(height: 150)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        // A second element in the row, and not only a label for the picture: a list row that
        // holds one accessibility element lends it the whole row as its frame, so the edit
        // button answered as an element as large as the cover and held the real button inside.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cover.picture", bundle: .module))
        .accessibilityAddTraits(.isImage)
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
