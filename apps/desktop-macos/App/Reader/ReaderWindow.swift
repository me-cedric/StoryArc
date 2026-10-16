import AppKit
import DesignSystem
import Persistence
import ReaderFeature
import StoryArcCore
import SwiftUI

/// Which spread mode the reader asked for, over the window-shape rule.
enum SpreadMode: Equatable, Sendable {
    case automatic
    case single
    case double
}

/// One reader window: a comic or fixed-layout publication, read with keys, pointer and drag.
///
/// The model is `ReaderFeature`'s `ReaderModel` — it opens the archive through `Formats`,
/// decodes pages around the current one and records progress on every turn — and the page
/// view is the Mac's own (`ReaderCanvas`), because `ZoomablePage` is UIKit. The curl is
/// wave 5; the drag slides. Tasks 2.9, 2.11 to 2.17 and 2.22.
struct ReaderWindow: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    let target: ReaderTarget
    let library: MacLibrary

    @State private var model: ReaderModel
    @State private var writer: ProgressWriter?
    @State private var zoom = ZoomModel()
    @State private var spreadMode: SpreadMode = .automatic
    @State private var isChromeVisible = true
    @State private var chromeTimer: Task<Void, Never>?
    @State private var isAskingForPage = false
    @State private var pageField = ""
    @State private var observer: ReaderWindowObserver?
    @State private var window: NSWindow?
    @FocusState private var isFocused: Bool

    init(target: ReaderTarget, library: MacLibrary) {
        self.target = target
        self.library = library
        let publication = library.model.publications.first { $0.id == target.publicationID }
            ?? Self.placeholder(for: target)
        _model = State(initialValue: ReaderModel(
            publication: publication, url: target.url, progress: library.progress,
            preferences: ReaderPreferences(), canCurl: false
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.palette.surfaceReader.ignoresSafeArea()
                if let failure = model.failure {
                    unavailable(failure)
                } else {
                    ReaderCanvas(
                        model: model, zoom: $zoom, layout: layout(for: geometry.size),
                        viewport: geometry.size, reduceMotion: reduceMotion,
                        zonesOn: MacSettings.shared.settings.turnPagesByTappingTheEdges,
                        onTurn: { turn(by: $0) }, onToggleChrome: { toggleChrome() },
                        onPointerMoved: { revealChrome() }
                    )
                }
                if isChromeVisible, model.failure == nil {
                    ReaderChromeBar(
                        model: model, layout: layout(for: geometry.size),
                        spreadMode: $spreadMode, zoom: $zoom, onJump: { jump(to: $0) }
                    )
                    .transition(.opacity)
                }
            }
            .onChange(of: geometry.size) { _, size in zoom = zoom.settled(fittedSize: size, viewport: size) }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press) }
        .focusedSceneValue(\.readerActions, actions)
        .navigationTitle(target.title)
        .background(WindowAccessor { attach($0) })
        .sheet(isPresented: $isAskingForPage) { goToPageSheet }
        .task { await open() }
        .onDisappear { close() }
    }

    // MARK: - Opening and closing

    private static func placeholder(for target: ReaderTarget) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: target.path),
            format: PublicationFormat.detected(from: target.url) ?? .cbz,
            displayTitle: target.title,
            origin: .inferred
        )
    }

    private func open() async {
        isFocused = true
        if let progress = library.progress {
            let writer = ProgressWriter(store: progress)
            self.writer = writer
            ProgressFlushers.shared.register(writer, for: target.publicationID)
        }
        ReaderWindows.shared.didOpen(target)
        await model.open(maxPixelSize: 2048)
        scheduleChromeHide()
    }

    private func close() {
        chromeTimer?.cancel()
        if let writer {
            Task { await writer.flush() }
        }
        ProgressFlushers.shared.unregister(target.publicationID)
        ReaderWindows.shared.didClose(target)
        DisplayAwake.shared.release(for: target.publicationID)
        observer?.detach()
        Task { await library.refreshProgress() }
    }

    private func attach(_ window: NSWindow) {
        self.window = window
        if observer == nil {
            let observer = ReaderWindowObserver(
                onKey: { isKey in
                    if isKey {
                        DisplayAwake.shared.hold(for: target.publicationID)
                    } else {
                        DisplayAwake.shared.release(for: target.publicationID)
                    }
                },
                onFrame: { ReaderWindows.shared.didPlace(target, at: $0) }
            )
            self.observer = observer
            let screens = NSScreen.screens.map(\.frame)
            if let saved = RestorationPlan.visibleFrame(ReaderWindows.shared.frame(of: target), screens: screens) {
                window.setFrame(saved, display: true)
            }
        }
        observer?.attach(window)
    }

    // MARK: - Turning

    private func layout(for size: CGSize) -> SpreadLayout {
        let pairs: Bool = switch spreadMode {
        case .automatic: SpreadDecision.pairs(viewport: size)
        case .single: false
        case .double: true
        }
        return SpreadDecision.layout(
            pageCount: model.pages.count, wide: model.wideIndices, pairs: pairs,
            coverAlone: MacSettings.shared.coverAlone
        )
    }

    private var currentLayout: SpreadLayout {
        layout(for: window?.contentView?.bounds.size ?? CGSize(width: 980, height: 820))
    }

    /// Moves by whole slots, so a pair turns as one.
    private func turn(by step: Int) {
        let layout = currentLayout
        let slot = layout.slot(containing: model.currentIndex) + step
        guard let spread = layout[slot] else { return }
        go(to: spread.leading)
    }

    private func jump(to index: Int) { go(to: index) }

    private func go(to index: Int) {
        guard model.pages.indices.contains(index) else { return }
        zoom = zoom.fitted()
        Task {
            await model.go(to: index)
            writer?.note(ReadingProgress(
                identity: model.publication.identity,
                position: .page(index: index, of: model.pages.count),
                isFinished: index == model.pages.count - 1,
                updatedAt: Date()
            ))
        }
    }

    private func perform(_ action: PageAction) {
        switch action {
        case .toggleChrome: toggleChrome()
        case .next: turn(by: 1)
        case .previous: turn(by: -1)
        case .first: go(to: 0)
        case .last: go(to: model.pages.count - 1)
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let key = PageKey(press) else { return .ignored }
        guard let action = PageKeyMapper.action(for: key, direction: model.readingDirection) else { return .ignored }
        perform(action)
        return .handled
    }

    // MARK: - Chrome

    private func toggleChrome() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isChromeVisible.toggle() }
        if isChromeVisible { scheduleChromeHide() }
    }

    private func revealChrome() {
        if !isChromeVisible {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isChromeVisible = true }
        }
        scheduleChromeHide()
    }

    /// *Revealing chrome*: after the pointer rests for three seconds the chrome and the
    /// pointer hide, and the page does not move.
    private func scheduleChromeHide() {
        chromeTimer?.cancel()
        chromeTimer = Task {
            try? await Task.sleep(for: PointerIdle.hideAfter)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isChromeVisible = false }
            if window?.isKeyWindow == true { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    private var actions: ReaderActions {
        ReaderActions(
            openFile: { Task { for target in await library.chooseFile() { openWindow(value: target) } } },
            addFolder: { library.chooseFolder() },
            page: { perform($0) },
            goToPage: { pageField = String(model.currentIndex + 1); isAskingForPage = true },
            singlePage: { spreadMode = .single },
            twoPages: { spreadMode = .double },
            zoomIn: { zoom = zoom.zoomedIn() },
            zoomOut: { zoom = zoom.zoomedOut() },
            fitPage: { zoom = zoom.fitted() },
            showControls: { toggleChrome() }
        )
    }

    private var goToPageSheet: some View {
        VStack(spacing: 16) {
            Text("desktop.reader.goToPage.title \(model.pages.count)").font(.headline)
            TextField("desktop.reader.goToPage.prompt", text: $pageField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit { submitPage() }
            HStack {
                Button(role: .cancel) { isAskingForPage = false } label: { Text("desktop.drop.folder.cancel") }
                    .keyboardShortcut(.cancelAction)
                Button { submitPage() } label: { Text("desktop.reader.goToPage.go") }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func submitPage() {
        if let page = Int(pageField), model.pages.indices.contains(page - 1) { jump(to: page - 1) }
        isAskingForPage = false
    }

    private func unavailable(_ failure: String) -> some View {
        ContentUnavailableView {
            Label("desktop.reader.unavailable.title", systemImage: "book.closed")
        } description: {
            Text(failure)
        }
    }
}

extension PageKey {
    /// The key a press carries, or `nil` for one the reader does not turn pages with.
    init?(_ press: KeyPress) {
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
              let key = Self.byEquivalent[press.key]
        else { return nil }
        self = key
    }

    private static let byEquivalent: [KeyEquivalent: PageKey] = [
        .leftArrow: .leftArrow, .rightArrow: .rightArrow, .upArrow: .upArrow, .downArrow: .downArrow,
        .pageUp: .pageUp, .pageDown: .pageDown, .space: .space, .home: .home, .end: .end, .return: .return,
    ]
}

extension PublicationFormat {
    /// The format a file's extension names, for a window opened before the library knows it.
    static func detected(from url: URL) -> PublicationFormat? {
        switch url.pathExtension.lowercased() {
        case "cbz": .cbz
        case "cbr": .cbr
        case "cbt": .cbt
        case "pdf": .pdf
        case "epub": .epub
        default: nil
        }
    }
}
