public import CoreGraphics
public import Foundation

public import Formats
public import StoryArcCore

/// Keeping the pages around the reader decoded, and dropping the rest.
///
/// `comic-reader` requires a turn to be immediate, which means the next page has to be
/// decoded before it is asked for. This is the window that does that, and the pressure
/// rule that narrows it.
///
/// Split from `ReaderModel.swift` when that file passed the length the linter allows.
/// Opening, position and settings stayed there; the decode window came here.
/// The decode window reaches the model's page store directly, so those few properties are
/// internal rather than private. Internal, not public: nothing outside this module can
/// see them, and the reader's own API is still the four methods above.
extension ReaderModel {

    /// What to draw for a page: the copy re-decoded for a held zoom when there is one,
    /// and the display-resolution copy otherwise.
    ///
    /// The one call a page view should make. `publication-formats` requires a page to be
    /// "downsampled to the display's needs for viewing and re-decoded at higher
    /// resolution when the user zooms", and which of the two is in hand is not a
    /// distinction a view should have to carry.
    public func displayImage(at index: Int) -> CGImage? {
        if let zoomed, zoomed.index == index { return zoomed.image }
        return decoded[index]
    }

    /// What a page that would not decode turned out to be, when its bytes said.
    ///
    /// `publication-formats`: an undecodable page "displays a placeholder naming the
    /// codec". `nil` when nothing could be read at all, in which case there is no codec
    /// to name and the placeholder says only that the page could not be read.
    public func codecName(at index: Int) -> String? { refusedCodecs[index] }

    /// Narrows or restores the prefetch window, and drops what no longer fits.
    ///
    /// `comic-reader`: "prefetch depth shrinks under memory pressure rather than the app
    /// being terminated". Shrinking has to take effect at once rather than at the next
    /// turn — the pages already held are the ones the system is asking for back, and a
    /// window that only narrowed on the way to the next page would give up nothing while
    /// the reader sat still.
    ///
    /// Thumbnails go entirely under critical pressure: up to sixty-four small pages held
    /// for a strip the reader may not have open, each re-decoded on demand.
    public func noteMemoryPressure(_ pressure: MemoryPressure) async {
        let window = PrefetchWindow.under(pressure)
        guard window != prefetch else { return }
        // A page held at three times the display's resolution is the largest single
        // thing this reader owns, so it goes first when the window narrows — before
        // the neighbours, which are the pages a turn is waiting on. The next frame of
        // the pinch asks again, against the narrower ceiling.
        if window.zoomCeiling < prefetch.zoomCeiling { zoomed = nil }
        prefetch = window
        if pressure == .critical { thumbnails.removeAll() }
        await warm(around: currentIndex)
    }

    /// Re-decodes the page under a held zoom at the resolution the zoom asks for.
    ///
    /// `publication-formats`: a page too large for the device is "downsampled to the
    /// display's needs for viewing and re-decoded at higher resolution when the user
    /// zooms". Decoding to the *display* is what makes a comic readable on a phone at
    /// all; it is also what makes a magnified page soft, because the pixels that would
    /// have carried the lettering were thrown away before the reader asked for them.
    ///
    /// Held, not permanent: ``releaseZoom()`` drops the larger copy and the page falls
    /// back to the display-resolution one, which is still decoded and still in the
    /// window. So the cost is one extra page for as long as a finger is on the screen.
    ///
    /// Nothing happens when ``PrefetchWindow/zoomedPixelSize(display:scale:)`` declines
    /// — a pinch too small to see, or a window narrowed by memory pressure.
    public func holdZoom(_ scale: Double, at index: Int) async {
        guard let target = prefetch.zoomedPixelSize(display: maxPixelSize, scale: scale) else {
            releaseZoom()
            return
        }
        guard pages.indices.contains(index) else { return }
        // Already at this size, or larger: a pinch that wanders inside one step of the
        // ceiling should not decode the page again on every frame.
        if let zoomed, zoomed.index == index, zoomed.pixelSize >= target { return }
        guard let image = await decodedImage(at: index, maxPixelSize: target) else { return }
        // The reader may have turned several pages while that was decoding. The window
        // rather than the current index, because a landscape spread puts two pages on
        // screen and only one of them is the current one.
        guard prefetch.pages(around: currentIndex, of: pages.count).contains(index) else { return }
        zoomed = ZoomedPage(index: index, pixelSize: target, image: image)
    }

    /// Drops the page held for a zoom. The display-resolution copy takes over again.
    public func releaseZoom() {
        zoomed = nil
    }

    /// Decodes the current page and its neighbours, and drops the rest.
    func warm(around index: Int) async {
        let wanted = prefetch.pages(around: index, of: pages.count)
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        for key in decoded.keys where !wanted.contains(key) {
            decoded.removeValue(forKey: key)
            attempted.remove(key)
            refusedCodecs.removeValue(forKey: key)
        }
        // A zoom held on a page the reader has moved away from is the same waste as a
        // decoded page outside the window, only three times the size.
        if let zoomed, !wanted.contains(zoomed.index) { self.zoomed = nil }
        // The current page first: a turn should not wait on its neighbours.
        for target in [index] + wanted.sorted(by: { abs($0 - index) < abs($1 - index) }) {
            guard decoded[target] == nil, !attempted.contains(target) else { continue }
            await decode(target)
        }
    }

    private func decode(_ index: Int) async {
        guard pages.indices.contains(index) else { return }
        attempted.insert(index)
        // Only the page on screen, and only for a share: `network-share`'s notice is
        // about *that* page's own trouble, not a prefetched neighbour's, and a plain
        // local file offers no download-for-offline and no "share" to name.
        let isShare = url.scheme == "smb"
        if isShare, index == currentIndex { pageWaitStarted = Date() }
        reading.insert(index)
        let result = await outcome(at: index, maxPixelSize: maxPixelSize)
        reading.remove(index)
        // Asked again now that the read has ended: a prefetch the reader turned to while it
        // was reading is the page on screen, and its wait is the one the notice counts.
        let isOnScreen = isShare && index == currentIndex
        let waitedSince = isOnScreen ? pageWaitStarted : nil
        if isOnScreen { pageWaitStarted = nil }

        switch result {
        case .decoded(let image):
            decoded[index] = image
            refusedCodecs.removeValue(forKey: index)
            noteDecoded(image, at: index)
            if isOnScreen { pageFailingSince = nil }

        case .refused(let codec):
            // Remembered as tried, which is what makes the placeholder appear: the bytes
            // are here and the decoder will say the same thing about them next time.
            if let codec { refusedCodecs[index] = codec }
            if isOnScreen { pageFailingSince = nil }

        case .unread:
            // Forgotten rather than remembered as tried. A page that failed because the
            // share was away must be readable once it comes back — `network-share` asks the
            // app to "resume streaming at the current page" after reconnecting, and a page
            // marked attempted for ever never gets a second chance.
            attempted.remove(index)
            // The *first* failure only, and timed from when the page began to wait rather
            // than from when the read gave up: the notice then keeps counting through the
            // failure and through the gaps between ``watchForPageRecovery()``'s retries.
            if isOnScreen, pageFailingSince == nil { pageFailingSince = waitedSince ?? Date() }
        }
    }

    /// Re-reads the page on screen at a short interval while it has not arrived, so
    /// streaming resumes at the current page without the reader turning away and back.
    ///
    /// `network-share`'s *Connection drops while reading*: `warm(around:)`'s only other
    /// callers are `open`, `go(to:)` and `noteMemoryPressure`, none of which fire on
    /// their own while the reader sits still on one page waiting — a page that failed
    /// stayed a spinner until a turn away and back asked for it again.
    public func watchForPageRecovery() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.recoveryInterval)
            await recoverCurrentPage()
        }
    }

    /// One round of ``watchForPageRecovery()``: reads the page on screen again when it
    /// still needs a read.
    func recoverCurrentPage() async {
        guard Self.needsRecovery(
            currentIndex: currentIndex,
            pageCount: pages.count,
            decoded: Set(decoded.keys),
            attempted: attempted,
            refused: Set(refusedCodecs.keys)
        ) else { return }
        await decode(currentIndex)
    }

    private static let recoveryInterval: Duration = .seconds(3)

    /// Whether the page on screen still needs a read, lifted beside ``watchForPageRecovery()``
    /// so a test can hold the rule without owning a publication to wait on.
    ///
    /// Not already in flight: ``decode(_:)`` inserts into `attempted` before it awaits, and
    /// only a failure removes the entry again — so a page mid-read reads as attempted here,
    /// and this declines to ask again under it.
    static func needsRecovery(
        currentIndex: Int,
        pageCount: Int,
        decoded: Set<Int>,
        attempted: Set<Int>,
        refused: Set<Int>
    ) -> Bool {
        (0..<pageCount).contains(currentIndex)
            && !decoded.contains(currentIndex)
            && !refused.contains(currentIndex)
            && !attempted.contains(currentIndex)
    }

    public func go(to index: Int) async {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        // The trouble belongs to the page being left. A page turned to while its prefetch
        // is still reading has been waiting since this turn; `decode(_:)` sets the wait
        // itself for a read it starts.
        pageFailingSince = nil
        pageWaitStarted = url.scheme == "smb" && reading.contains(index) ? Date() : nil
        // Written down before the pages ahead are read: the read takes seconds on a large
        // archive, and a reader closed or killed inside it lost the turn (2026-10-09).
        await record(index)
        await warm(around: index)
    }

    /// Writes the position down.
    ///
    /// Every turn, not on leaving: ADR-0006 makes the local store authoritative,
    /// and a reader that only saves on a clean exit loses the evening when the app
    /// is killed in the background — which is the normal way a phone closes an app.
    ///
    /// The last page marks the publication finished. Finished is sticky, so
    /// turning back afterwards does not unmark it.
    private func record(_ index: Int) async {
        guard let progress, !pages.isEmpty else { return }
        try? await progress.save(
            ReadingProgress(
                identity: publication.identity,
                position: .page(index: index, of: pages.count),
                isFinished: index == pages.count - 1,
                updatedAt: Date()
            )
        )
    }

    /// The next page in *reading* order, which is not always the next index.
    public func advance() async {
        await go(to: currentIndex + 1)
    }

    public func retreat() async {
        await go(to: currentIndex - 1)
    }

    /// One decode of one page, and what it settled.
    ///
    /// The distinction between the last two cases is the reason this exists. Both used
    /// to be "no image", and treating a refusal as a missing read left the reader
    /// spinning for ever on a page nothing was ever going to produce.
    enum PageOutcome {
        case decoded(CGImage)
        /// The bytes arrived and the decoder would not have them. Permanent for this
        /// file, and the codec is what `publication-formats` wants named in the
        /// placeholder — `nil` when the bytes say nothing recognisable at all.
        case refused(codec: String?)
        /// The bytes could not be read. Usually the source is away, so it is worth
        /// asking again.
        case unread
    }

    private func outcome(at index: Int, maxPixelSize size: Int) async -> PageOutcome {
        if let pdf {
            guard let image = await pdf.image(at: index, maxPixelSize: size) else {
                // A PDF page is drawn rather than stored, so there are no codec bytes to
                // sniff. The format is still what was refused, and naming it is the
                // point: `publication-formats` asks for "the codec or format".
                return .refused(codec: PublicationFormat.pdf.displayName)
            }
            return .decoded(image)
        }

        guard let archive else { return .unread }
        let page = pages[index]
        let sourceID = publication.sourceID
        return await Task.detached(priority: .userInitiated) {
            guard let data = await Self.pageData(of: page, in: archive, sourceID: sourceID) else {
                return .unread
            }
            guard let image = try? PageDecoder.decode(data, maxPixelSize: size) else {
                return .refused(codec: PageCodec.name(of: data, path: page.path))
            }
            return .decoded(image)
        }.value
    }

    /// The same decode, without the bookkeeping, for a zoom that wants one page larger.
    func decodedImage(at index: Int, maxPixelSize size: Int) async -> CGImage? {
        guard case .decoded(let image) = await outcome(at: index, maxPixelSize: size) else {
            return nil
        }
        return image
    }
}
