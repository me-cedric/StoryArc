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
        prefetch = window
        if pressure == .critical { thumbnails.removeAll() }
        await warm(around: currentIndex)
    }

    /// Decodes the current page and its neighbours, and drops the rest.
    func warm(around index: Int) async {
        let wanted = prefetch.pages(around: index, of: pages.count)
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        for key in decoded.keys where !wanted.contains(key) {
            decoded.removeValue(forKey: key)
            attempted.remove(key)
        }
        // The current page first: a turn should not wait on its neighbours.
        for target in [index] + wanted.sorted(by: { abs($0 - index) < abs($1 - index) }) {
            guard decoded[target] == nil, !attempted.contains(target) else { continue }
            await decode(target)
        }
    }

    private func decode(_ index: Int) async {
        guard pages.indices.contains(index) else { return }
        attempted.insert(index)
        let size = maxPixelSize

        if let pdf {
            if let image = await pdf.image(at: index, maxPixelSize: size) {
                decoded[index] = image
                noteDecoded(image, at: index)
            } else {
                attempted.remove(index)
            }
            return
        }

        guard let archive else { return }
        let page = pages[index]
        let image = await Task.detached(priority: .userInitiated) {
            guard let data = try? await archive.data(for: page) else { return CGImage?.none }
            return try? PageDecoder.decode(data, maxPixelSize: size)
        }.value
        if let image {
            decoded[index] = image
            noteDecoded(image, at: index)
        } else {
            // Forgotten rather than remembered as tried. A page that failed because the
            // share was away must be readable once it comes back — `network-share` asks the
            // app to "resume streaming at the current page" after reconnecting, and a page
            // marked attempted for ever never gets a second chance.
            attempted.remove(index)
        }
    }
}
