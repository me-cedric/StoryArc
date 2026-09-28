internal import SwiftUI

/// What the reader starts when it appears, and stops when it goes.
///
/// Three tasks that are one subject: opening the publication, following the memory pressure
/// that narrows the prefetch window, and watching for the local copy of a publication that is
/// still arriving. Each is bounded by the reader being on screen — leaving cancels the task,
/// which cancels what it is driving.
///
/// **A modifier rather than three `.task` calls in the view.** `ReaderView.swift` is at the
/// 400-line cap, and a file that may not grow is a file where the next thing is added
/// somewhere else. This is a real seam rather than a place to put the overflow: what these
/// three share is a lifetime, and nothing above them needs to know how many there are.
struct ReaderLifecycle: ViewModifier {
    let model: ReaderModel

    /// The longest side of the reader in pixels, which bounds how large a page is decoded.
    let maxPixelSize: Int

    func body(content: Content) -> some View {
        content
            .task {
                // Bounded by the screen, not by the page. A 2000×3000 scan decoded in full
                // costs 24 MB for something shown at a fraction of it — `publication-formats`
                // requires the bound.
                await model.open(maxPixelSize: maxPixelSize)
            }
            // `comic-reader`: the prefetch window narrows "under memory pressure rather than
            // the app being terminated", and widens again when the pressure lifts.
            .task {
                for await pressure in MemoryPressureSource.pressures() {
                    await model.noteMemoryPressure(pressure)
                }
            }
            // `offline-downloads`: a publication opened by streaming "switches to the local
            // copy when the download completes, without interrupting reading". This is the
            // watch. It starts in parallel with the `.task` above, before `open` has set
            // `archive` — see ``ReaderModel/adoptTheCopyWhenItArrives()`` for how it waits.
            .task { await model.adoptTheCopyWhenItArrives() }
    }
}

extension View {
    /// Starts what the reader owns for as long as it is on screen. See ``ReaderLifecycle``.
    func readerLifecycle(_ model: ReaderModel, maxPixelSize: Int) -> some View {
        modifier(ReaderLifecycle(model: model, maxPixelSize: maxPixelSize))
    }
}
