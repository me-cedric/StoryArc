import AppKit
import DesignSystem
import StoryArcCore
import SwiftUI
import WebKit

/// One reflowable publication, read in the Mac's web view with the chrome of the comic reader.
///
/// `ebook-reader` on a desktop: the renderer paginates and themes the text; the window owns
/// the keys (arrows, space, Page Up and Down turn, Escape leaves the text for the chrome),
/// the theme menu with the six presets of `reading-themes`, search in the book with its
/// results listed in context, the way back after a jump, and the position in the foot. The
/// chrome is glass and only here; it hides after the pointer rests, as the comic reader's
/// does. Task 4.5.
struct EpubReaderWindow: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: ReaderTarget
    let library: MacLibrary

    /// View state, registered with `EpubReaders` from `.task` and not from `init`: SwiftUI
    /// was seen to build this view twice for one window, and only the instance that appears
    /// runs its task and its disappearance, so only that one registers and tears down.
    @State private var model: EpubReaderModel
    @State private var isChromeVisible = true
    @State private var chromeTimer: Task<Void, Never>?
    @State private var isSearchOpen = false
    @State private var query = ""
    @State private var window: NSWindow?

    init(target: ReaderTarget, library: MacLibrary) {
        self.target = target
        self.library = library
        let publication = library.model.publications.first { $0.id == target.publicationID }
            ?? ReaderWindow.placeholder(for: target)
        let model = EpubReaderModel(target: target, publication: publication, progress: library.progress)
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            theme.palette.surfaceReader.ignoresSafeArea()
            if let failure = model.failure {
                ContentUnavailableView {
                    Label("desktop.reader.unavailable.title", systemImage: "book.closed")
                } description: {
                    Text(failure)
                }
            } else if let webView = model.webView {
                EpubWebView(webView: webView)
                    .onContinuousHover { phase in if case .active = phase { revealChrome() } }
                    .accessibilityLabel(Text(target.title))
            }
            if isChromeVisible, model.failure == nil {
                chrome.transition(.opacity)
            }
        }
        .navigationTitle(target.title)
        .focusedSceneValue(\.readerActions, actions)
        .background(WindowAccessor { attach($0) })
        .acceptsDroppedFiles()
        .onChange(of: isSearchOpen) { _, now in if now { revealChrome() } else { scheduleChromeHide() } }
        .task { await openReader() }
        .onDisappear { close() }
    }

    // MARK: - The chrome

    private var chrome: some View {
        VStack {
            HStack {
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: 4) {
                        themeMenu
                        searchButton
                        if model.offersReadAloud { readAloudButton }
                    }
                    .labelStyle(.iconOnly)
                }
                .storyArcGlass()
                .padding(16)
            }
            Spacer()
            footer
                .storyArcGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 48)
                .padding(.bottom, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { model.previous() } label: {
                Label("desktop.menu.previousPage", systemImage: "chevron.left").hitTarget()
            }
            .buttonStyle(.borderless)
            .help(Text("desktop.menu.previousPage"))
            Text(positionText).monospacedDigit().storyArcGlassText(.primary)
                .accessibilityLabel(Text("desktop.epub.position \(model.position ?? 0) \(model.positionCount)"))
            Button { model.next() } label: {
                Label("desktop.menu.nextPage", systemImage: "chevron.right").hitTarget()
            }
            .buttonStyle(.borderless)
            .help(Text("desktop.menu.nextPage"))
            if let sentence = model.spokenSentence, model.isBeingReadAloud {
                Text(sentence).scaledFont(.callout).lineLimit(1).storyArcGlassText(.secondary)
                    .accessibilityLabel(Text(sentence))
            }
            if model.returnLocator != nil {
                Button { model.goBack() } label: {
                    Label("desktop.epub.back", systemImage: "arrow.uturn.backward").hitTarget()
                }
                .buttonStyle(.borderless)
                .help(Text("desktop.epub.back"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Read Aloud, where a voice exists and the book has text; absent otherwise. Task 4.8.
    private var readAloudButton: some View {
        Button { model.toggleReadAloud() } label: {
            Label(
                model.isBeingReadAloud ? "desktop.epub.readAloud.stop" : "desktop.epub.readAloud",
                systemImage: model.isBeingReadAloud ? "stop.fill" : "speaker.wave.2"
            )
            .hitTarget(HitTarget.icon)
        }
        .buttonStyle(.borderless)
        .padding(4)
        .help(Text(model.isBeingReadAloud ? "desktop.epub.readAloud.stop" : "desktop.epub.readAloud"))
    }

    private var positionText: String {
        guard model.positionCount > 0 else { return "–" }
        return "\(model.position ?? 1) / \(model.positionCount)"
    }

    private var themeMenu: some View {
        Menu {
            Picker(selection: Binding(get: { model.theme }, set: { model.apply($0) })) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    Text(preset.titleKey).tag(preset)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            Label("desktop.epub.theme", systemImage: "textformat")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .hitTarget(HitTarget.icon)
        .padding(4)
        .help(Text("desktop.epub.theme"))
    }

    private var searchButton: some View {
        Button { isSearchOpen.toggle() } label: {
            Label("desktop.epub.search", systemImage: "magnifyingglass").hitTarget(HitTarget.icon)
        }
        .buttonStyle(.borderless)
        .padding(4)
        .help(Text("desktop.epub.search"))
        .popover(isPresented: $isSearchOpen, arrowEdge: .bottom) {
            EpubSearchPanel(model: model, query: $query) { hit in
                model.go(to: hit.locator)
                isSearchOpen = false
            }
        }
    }

    // MARK: - Opening and closing

    private func openReader() async {
        if let progress = library.progress {
            let writer = ProgressWriter(store: progress)
            model.writer = writer
            ProgressFlushers.shared.register(writer, for: target.publicationID)
        }
        ReaderWindows.shared.didOpen(target)
        EpubReaders.shared.register(model)
        model.onEscape = { if isSearchOpen { isSearchOpen = false } else { toggleChrome() } }
        await model.open()
        scheduleChromeHide()
    }

    /// The window closed: the position is written, the session and the keys let go.
    private func close() {
        chromeTimer?.cancel()
        model.close()
        ProgressFlushers.shared.finish(target.publicationID)
        ReaderWindows.shared.didClose(target)
        ReaderWindowRegistry.detach(target)
        EpubReaders.shared.unregister(target)
        Task { await library.refreshProgress() }
    }

    private func attach(_ window: NSWindow) {
        self.window = window
        ReaderWindowRegistry.attach(window, for: target)
    }

    /// The Reader menu over this window: the page items turn, the rest are not a book's.
    private var actions: ReaderActions {
        ReaderActions(
            openFile: { Task { for target in await library.chooseFile() { WindowOpener.shared.openReader?(target) } } },
            addFolder: { library.chooseFolder() },
            page: { action in
                switch action {
                case .next, .last: model.next()
                case .previous, .first: model.previous()
                case .toggleChrome: toggleChrome()
                }
            },
            goToPage: {}, singlePage: {}, twoPages: {}, zoomIn: {}, zoomOut: {}, fit: { _ in },
            showControls: { toggleChrome() }, chapter: { $0 > 0 ? model.next() : model.previous() },
            showPages: {}, adjust: {}
        )
    }

    // MARK: - Chrome timing

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

    private func scheduleChromeHide() {
        chromeTimer?.cancel()
        chromeTimer = Task {
            try? await Task.sleep(for: PointerIdle.hideAfter)
            guard !Task.isCancelled, !isSearchOpen else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isChromeVisible = false }
        }
    }
}

/// The web view, placed by SwiftUI and owned by the model.
private struct EpubWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// The search field and its results, in context, one row a hit.
struct EpubSearchPanel: View {
    let model: EpubReaderModel
    @Binding var query: String
    let onChoose: (EpubSearchHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("desktop.epub.search.prompt", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.search(query) }
                .accessibilityLabel(Text("desktop.epub.search"))
            if model.isSearching {
                Text("desktop.epub.search.searching").scaledFont(.callout).foregroundStyle(.secondary)
            } else if model.hits.isEmpty, !query.isEmpty {
                Text("desktop.epub.search.none").scaledFont(.callout).foregroundStyle(.secondary)
            }
            if !model.hits.isEmpty {
                List(model.hits) { hit in
                    Button { onChoose(hit) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let chapter = hit.chapter {
                                Text(chapter).scaledFont(.caption).foregroundStyle(.secondary)
                            }
                            (Text(hit.before) + Text(hit.match).bold() + Text(hit.after))
                                .scaledFont(.callout)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(hit.before) \(hit.match) \(hit.after)"))
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

/// The open EPUB readers' models, so a walk can read what a window holds.
@MainActor
final class EpubReaders {
    static let shared = EpubReaders()
    private var models: [String: EpubReaderModel] = [:]

    func register(_ model: EpubReaderModel) { models[model.target.publicationID] = model }

    func unregister(_ target: ReaderTarget) { models[target.publicationID] = nil }

    func model(for target: ReaderTarget) -> EpubReaderModel? { models[target.publicationID] }
}

/// The keys of a reflowable reader: arrows, space, Page Up and Page Down turn, Escape leaves
/// the text for the chrome. A local monitor, as `WheelMonitor` is for the wheel: the web view
/// is the first responder and takes the key as text input before a SwiftUI `onKeyPress`
/// sees it. The *Reader* menu's items turn the page too (`ReaderActions`).
@MainActor
final class EpubKeyMonitor {
    enum Key { case next, previous, escape }

    private var token: Any?

    /// Keys in whichever window holds the web view now: SwiftUI was seen to move the view
    /// between windows of one title while it settled, so the window is read at the press.
    init(over webView: WKWebView, handle: @escaping @MainActor (Key) -> Void) {
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak webView] event in
            guard let window = webView?.window, event.window === window,
                  event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
                  let key = Self.key(of: event.keyCode)
            else { return event }
            MainActor.assumeIsolated { handle(key) }
            return nil
        }
    }

    static func key(of keyCode: UInt16) -> Key? {
        switch keyCode {
        case 124, 121, 49, 125: .next     // right, page down, space, down
        case 123, 116, 126: .previous     // left, page up, up
        case 53: .escape
        default: nil
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

extension ThemePreset {
    /// The preset's name in the menu.
    var titleKey: LocalizedStringKey {
        switch self {
        case .original: "desktop.epub.theme.original"
        case .quiet: "desktop.epub.theme.quiet"
        case .paper: "desktop.epub.theme.paper"
        case .bold: "desktop.epub.theme.bold"
        case .calm: "desktop.epub.theme.calm"
        case .focus: "desktop.epub.theme.focus"
        }
    }
}
