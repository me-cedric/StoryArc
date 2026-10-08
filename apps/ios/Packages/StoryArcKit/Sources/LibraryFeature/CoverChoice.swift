public import Foundation

internal import CoreGraphics
internal import Formats
public import StoryArcCore

/// What the reader can do about a publication's cover.
///
/// Tasks 2.2 and 2.4 of `cover-for-every-publication`, as model work rather than as view
/// work, so the rules can be asserted without a window. The view beside this —
/// ``DetailCoverChoice`` — is the picker and two labels; everything that decides what the
/// shelf draws next is here.
extension LibraryModel {

    /// Whether the reader has chosen this publication's cover themselves.
    public func hasChosenCover(for publication: Publication) -> Bool {
        CoverOverrideStore().file(for: publication) != nil
    }

    /// Whether moving this publication would lose the cover the reader chose.
    ///
    /// `cover-art`'s *A publication with no digest*: a folder of images and a server row
    /// carry no content digest, so their override is filed under the stable identifier —
    /// which is the path — and a move breaks it. The page says so plainly rather than
    /// letting the choice disappear without explanation.
    public func chosenCoverIsTiedToPath(for publication: Publication) -> Bool {
        CoverOverrideStore().keyKind(for: publication) == .stableIdentifier
    }

    /// Records a picture the reader picked as this publication's cover.
    ///
    /// The picture is cropped to the cover shape first, because the ladder's other rungs all
    /// answer with artwork that already is that shape and a photograph is not.
    ///
    /// - Returns: whether the picture was stored. False is a picture this device cannot
    ///   decode, or a write that failed; the caller tells the reader rather than leaving a
    ///   button that appears to do nothing.
    @discardableResult
    public func setCover(_ picture: Data, for publication: Publication) async -> Bool {
        await setCover(picture, for: publication, in: CoverOverrideStore())
    }

    /// ``setCover(_:for:)`` into a store of the caller's choosing, which is how a test keeps
    /// a chosen cover out of the real Application Support directory.
    @discardableResult
    func setCover(
        _ picture: Data, for publication: Publication, in overrides: CoverOverrideStore
    ) async -> Bool {
        // Decoded, cropped, encoded and written off the main actor: a phone photograph takes
        // long enough at each step to drop frames on the page the reader is looking at.
        let stored = await Task.detached(priority: .userInitiated) {
            guard let shaped = CoverArtwork.coverShaped(picture) else { return false }
            return overrides.store(shaped, for: publication) != nil
        }.value
        guard stored else { return false }
        forgetDrawnCover(of: publication)
        return true
    }

    /// Removes the cover the reader chose, and deletes the image.
    ///
    /// The ladder resolves the publication's cover again from the rung below on the next
    /// draw, which is what `cover-art`'s *Undoing the choice* asks for.
    public func removeChosenCover(for publication: Publication) async {
        // Off the main actor: the store deletes a file and the cover cache lists a directory.
        await Task.detached(priority: .userInitiated) {
            CoverOverrideStore().remove(for: publication)
        }.value
        forgetDrawnCover(of: publication)
    }

    /// Drops every copy of this publication's artwork that something has already drawn.
    ///
    /// Both caches, not one. ``covers`` is what the shelf is holding this launch, and
    /// ``CoverCache`` is what it will read on the next one — leaving either behind shows the
    /// reader the cover they just replaced, which reads as the choice not having worked.
    private func forgetDrawnCover(of publication: Publication) {
        // Every copy of one file shares one chosen cover, because the store keys it by
        // digest, so every copy is redrawn — not only the one the reader acted on.
        let digest = publication.identity.contentDigest
        let copies = publications
            .filter { digest != nil && $0.identity.contentDigest == digest }
            .map(\.id)
        for id in Set(copies + [publication.id]) {
            covers[id] = nil
            CoverCache().removeEverySize(for: id)
            coverRevisions[id, default: 0] += 1
        }
    }

    /// The key a view that draws this publication's cover loads it under.
    ///
    /// It carries how many times the cover changed this launch, so a cover the reader chooses
    /// or removes is redrawn wherever it is on screen rather than on the next launch.
    func coverLoadKey(for publication: Publication) -> String {
        "\(publication.id)#\(coverRevisions[publication.id, default: 0])"
    }
}
