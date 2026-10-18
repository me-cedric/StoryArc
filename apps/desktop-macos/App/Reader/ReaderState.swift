import Formats
import Foundation
import Persistence
import ReaderFeature
import StoryArcCore

/// What one reader window holds beyond `ReaderFeature`'s model: the spread, the zoom and its
/// fit, the turn in flight, the adjustments, the page browser, a jump's way back, the chapter
/// markers and the end of the publication.
///
/// Out of `ReaderWindow` so the window stays plumbing and the rules sit in one place the
/// walks can reach. Every turn goes through ``go(to:step:)``, which notes the position at once
/// so a close or a quit straight after a press still writes it (task 2.17).
@MainActor
@Observable
final class ReaderState {
    let target: ReaderTarget
    let model: ReaderModel
    let preferences: ReaderPreferences
    var writer: ProgressWriter?

    var zoom = ZoomModel()
    var spreadMode: SpreadMode = .automatic
    /// The window's content size, which decides the spread.
    var viewport = CGSize(width: 980, height: 820)
    var reduceMotion = false
    /// The page a turn asked for while the model is still getting there. Turns count from
    /// it, so two presses in quick succession move two pages and not one.
    private(set) var pendingIndex: Int?
    /// How the last change is drawn, read by the canvas as the page arrives.
    private(set) var change: PageChange = .cut
    /// The last turn the curl draws from start to end, read by the canvas. Task 5.1.
    private(set) var curlRequest: MacCurlRequest?
    /// The series' adjustments, and the pages the reader excused from the border trim.
    private(set) var adjustments: ImageAdjustments
    private(set) var uncropped: Set<Int> = []
    var isBrowsingPages = false
    /// Where a jump came from, so the reader can go back: *Page slider with thumbnails*.
    private(set) var returnIndex: Int?
    /// Set when a turn went past the last page: *Reaching the end*.
    var isAtEnd = false
    private(set) var markers: [ChapterMarker] = []
    /// The text layer of a PDF that has one, or `nil`: a scan and a comic have no text controls.
    private(set) var pdfText: MacPdfText?
    /// A press-and-drag on a PDF that has no text: told once that the file is images of pages.
    var saysThereIsNoText = false
    /// Words a selection asked to search for; the chrome's search takes them and clears this.
    var pdfSearchRequest: String?

    init(target: ReaderTarget, publication: Publication, progress: ProgressStore?,
         preferences: ReaderPreferences = ReaderPreferences()) {
        self.target = target
        self.preferences = preferences
        model = ReaderModel(
            publication: publication, url: target.url, progress: progress,
            preferences: preferences, canCurl: MacCurlShader.isPresent
        )
        adjustments = preferences.themes().theme(for: .fixedLayout, shelf: Self.shelf(of: publication)).adjustments
    }

    // MARK: - What runs

    var choices: TransitionChoices { model.transitions(reduceMotion: reduceMotion) }

    var isScrolling: Bool { choices.effective.isScroll }

    var isRightToLeft: Bool { model.readingDirection == .rightToLeft }

    /// The spread for the window's shape, or one page a slot in a continuous scroll.
    var layout: SpreadLayout {
        let pairs: Bool = switch spreadMode {
        case .automatic: SpreadDecision.pairs(viewport: viewport)
        case .single: false
        case .double: true
        }
        return SpreadDecision.layout(
            pageCount: model.pages.count, wide: model.wideIndices,
            pairs: pairs && choices.effective.pairsPages, coverAlone: MacSettings.shared.coverAlone
        )
    }

    /// The page the reader is on, or the one a turn is taking them to.
    var shownIndex: Int { pendingIndex ?? model.currentIndex }

    // MARK: - Turning

    /// Moves by whole slots, so a pair turns as one. Past the last slot it shows the end.
    ///
    /// In Curl a turn of one page is drawn by the curl, from the page in view to the next one;
    /// `curled` says the pointer already drew it, so the page changes with nothing more.
    func turn(by step: Int, curled: Bool = false) {
        let layout = layout
        let slot = layout.slot(containing: shownIndex)
        if isAtEnd {
            if step < 0 { isAtEnd = false }
            return
        }
        if ReaderEnd.isPastEnd(slot: slot, step: step, slotCount: layout.count) {
            note(model.pages.count - 1, finished: true)
            isAtEnd = true
            return
        }
        guard let spread = layout[slot + step] else { return }
        let request = curled ? nil : curl(from: layout[slot], to: spread, step: step)
        go(to: spread.leading, step: step)
        if curled || request != nil { change = .cut }
        if let request { curlRequest = request }
    }

    /// The curl for a turn, or `nil` where it is a slide: a pair, a page not decoded yet, or
    /// another mode. A pair turns as one sheet in the phone's book, which the shader does not draw.
    private func curl(from: Spread?, to: Spread, step: Int) -> MacCurlRequest? {
        guard choices.effective == .pageCurl, abs(step) == 1, let from, !from.isPair, !to.isPair,
              let leaving = model.displayImage(at: from.leading), let coming = model.displayImage(at: to.leading)
        else { return nil }
        return MacCurlRequest(from: leaving, to: coming, isForward: step > 0, serial: (curlRequest?.serial ?? 0) + 1)
    }

    /// A move the reader asked for by place rather than by turn: the slider, the page
    /// browser, Go to Page. Remembers where it came from.
    func jump(to index: Int) {
        guard index != shownIndex, model.pages.indices.contains(index) else { return }
        returnIndex = shownIndex
        go(to: index, step: index > shownIndex ? 1 : -1)
    }

    func goBack() {
        guard let back = returnIndex else { return }
        returnIndex = nil
        go(to: back, step: back > shownIndex ? 1 : -1)
    }

    func go(to index: Int, step: Int = 0) {
        guard model.pages.indices.contains(index) else { return }
        isAtEnd = false
        change = PageChanges.change(effective: choices.effective, step: step, isRightToLeft: isRightToLeft)
        pendingIndex = index
        note(index, finished: index == model.pages.count - 1)
        Task {
            await model.go(to: index)
            if pendingIndex == index { pendingIndex = nil }
        }
    }

    /// Owed from the moment of the turn, not from when the model has caught up with it.
    private func note(_ index: Int, finished: Bool) {
        writer?.note(ReadingProgress(
            identity: model.publication.identity,
            position: .page(index: index, of: model.pages.count),
            isFinished: finished,
            updatedAt: Date()
        ))
    }

    // MARK: - Choices, remembered for the series

    func choose(_ transition: PageTransition) { remembering { model.choose(transition) } }

    /// Bumped when the reader chooses a fit, so the canvas sizes the page in front by it.
    private(set) var fitSerial = 0

    /// *Fit modes*: chosen for the series, and applied to the page in front at once.
    func applyFit(_ fit: PageFit) {
        remembering { model.choose(fit) }
        fitSerial += 1
    }

    func choosePageSeparator(_ isShown: Bool) { remembering { model.choosePageSeparator(isShown) } }

    func choose(_ direction: ReadingDirection) { remembering { model.choose(direction) } }

    func setAdjustments(_ new: ImageAdjustments) {
        adjustments = new
        rememberAdjustments()
    }

    func setCropsPage(_ index: Int, _ crops: Bool) {
        if crops { uncropped.remove(index) } else { uncropped.insert(index) }
    }

    /// The series' adjustments, with the trim off on a page the reader excused.
    func adjustments(at index: Int) -> ImageAdjustments {
        adjustments.trimmingBorders(!uncropped.contains(index))
    }

    /// `ReaderModel.choose` writes the whole of the series' settings from what the model
    /// read when it opened, adjustments included, so they are written again after it.
    private func remembering(_ change: () -> Void) {
        change()
        rememberAdjustments()
    }

    private func rememberAdjustments() {
        let memory = preferences.themes()
        let shelf = Self.shelf(of: model.publication)
        let stored = memory.theme(for: .fixedLayout, shelf: shelf).settingAdjustments(adjustments)
        preferences.save(memory.remembering(stored, for: .fixedLayout, shelf: shelf))
    }

    static func shelf(of publication: Publication) -> String {
        ShelfMemory.shelf(series: publication.series, identity: publication.id)
    }

    // MARK: - Chapters

    /// Reads the archive's chapter markers once, off the main actor. A PDF's text layer is
    /// opened here too, and its outline is its markers (task 4.6).
    func loadMarkers() async {
        let url = target.url
        guard model.publication.format != .pdf else {
            pdfText = MacPdfText.open(url: url, publication: model.publication)
            await pdfText?.load()
            let outline = pdfText?.outline ?? []
            markers = outline.compactMap { item in item.pageIndex.map { ChapterMarker(index: $0, title: item.title) } }
            return
        }
        let found = await Task.detached(priority: .utility) { () -> ([Int], [Int: String]) in
            guard let archive = try? await ComicArchiveOpener.open(fileAt: url) else { return ([], [:]) }
            return (archive.chapterStartIndices, archive.chapterTitles)
        }.value
        markers = ReaderChapters.markers(starts: found.0, titles: found.1)
    }
}
