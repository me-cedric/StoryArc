public import SwiftUI

internal import ReadiumNavigator
internal import UIKit

internal import DesignSystem
public import Persistence
public import StoryArcCore

/// A reflowable book, open.
///
/// The chrome is the same idea as the comic reader's: nothing on screen while
/// reading, one tap to bring it back. What differs is what it can honestly say.
/// `ebook-reader` forbids presenting a reflowable page number as a stable
/// identity — the count changes with the type size — so this shows a percentage
/// and the chapter, which do not.
///
/// Typography controls are absent rather than disabled. They belong to the
/// `reader-theming-and-page-transitions` change, and a sheet of sliders that does
/// nothing would be worse than no sheet at all.
public struct EpubReaderView: View {
    // Internal rather than private throughout: the chrome, the menu and the progress line
    // are extensions in their own files, and a `private` member cannot be reached from one.
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss

    @State var model: EpubReaderModel
    @State private var isChromeVisible = true
    @State var isShowingTheme = false
    @State var isShowingContents = false

    /// Which of the contents sheet's four panels it opens on.
    ///
    /// The menu has a row per panel, and `comic-reader` requires each control to be
    /// "reachable from here in one action".
    @State var contentsTab: ContentsTab = .contents

    /// Whether the reader's menu is open.
    ///
    /// The other half of the two-control chrome: one button leaves the publication and this
    /// one is everything else. See `EpubReaderMenu.swift`.
    @State var isShowingMenu = false

    /// What restarts the four-second countdown.
    ///
    /// Every value the guard above reads. Without the sheets in it, opening the menu and
    /// closing it again would leave a countdown that had already been cancelled and never
    /// restarted, so the chrome would stay up for ever — which is the bug this whole task
    /// is fixing, arriving by a different door.
    private var chromeTimerKey: String {
        "\(isChromeVisible)-\(isShowingMenu)-\(isShowingTheme)-\(isShowingContents)-\(model.failure != nil)"
    }

    @State private var editingNote: Annotation?
    @State private var noteText = ""
    /// What the device's brightness was before the reader touched it.
    @State private var deviceBrightness: CGFloat?

    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        /// Where the marks a reader makes live between sessions.
        bookmarks: BookmarkStore? = nil,
        /// Where the highlights and notes a reader makes live between sessions.
        annotations: AnnotationStore? = nil,
        /// See ``EpubReaderModel/init(publication:url:progress:preferences:linkedPreset:)``.
        linkedPreset: ThemePreset? = nil
    ) {
        _model = State(
            initialValue: EpubReaderModel(
                publication: publication,
                url: url,
                progress: progress,
                preferences: preferences,
                bookmarkStore: bookmarks,
                annotationStore: annotations,
                linkedPreset: linkedPreset
            )
        )
    }

    public var body: some View {
        ZStack {
            theme.palette.surfaceCanvas.ignoresSafeArea()

            if let failure = model.failure {
                Failure(message: failure)
            } else if let navigator = model.navigator {
                NavigatorHost(
                    navigator: navigator,
                    // Nil while Readium owns the turn, which leaves its paginated scroll
                    // exactly as it was. Only Fast fade takes it over.
                    turn: model.ownsTheTurn ? { forward in
                        Task { await model.turnWithFade(forward: forward) }
                    } : nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible.toggle() }
                }
                .ignoresSafeArea()
            } else {
                ProgressView()
            }

            // Between the page and the chrome, which is where "reading surfaces only"
            // puts it: over the words, under the toolbar. Draws nothing unless Natural
            // is on and neither accessibility setting refuses it.
            PaperGrainOverlay()

            // Grouped, because `native-experience` asks for overlapping glass
            // shapes to "morph as one". Only the container produces that — a
            // surface cannot know about its neighbours from the inside.
            if isChromeVisible {
                GlassEffectContainer(spacing: StoryArcSpace.md) { chrome }
            }

            // Not the chrome, and on screen on their own terms — see ``transientOverlays``.
            transientOverlays
        }
        // The controls take themselves away, which until now only the comic reader did.
        //
        // `comic-reader`, *Revealing controls*: "they fade out again after 4 seconds of no
        // interaction". This reader only ever **toggled** — it showed its chrome on arrival
        // and kept it there until a centre tap, so the page was never alone unless the
        // reader asked for it, which is the opposite of the requirement. A screenshot pair
        // is what found it; no source-level test had ever looked at the arrival frame.
        //
        // The guards mirror `ReaderView`'s, and each is the same rule for the same reason:
        // a sheet that sits over the page means the reader has not stopped interacting, and
        // chrome hidden four seconds after a failure leaves a page that can only be escaped
        // by force-quitting the app.
        .task(id: chromeTimerKey) {
            guard isChromeVisible,
                  !isShowingMenu, !isShowingTheme, !isShowingContents,
                  model.failure == nil
            else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible = false }
        }
        // Everything the five pills used to do. `comic-reader` allows two controls over the
        // page, and this is what the second one opens.
        .sheet(isPresented: $isShowingMenu) { readerMenu }
        // A popover, not a sheet — and on a phone the platform turns it back into
        // one. `native-experience` asks for "popover anchored to its control, reader
        // visible beside it" on a tablet and a detented sheet on a phone, which is
        // exactly what a popover with a declared compact adaptation is. Writing the
        // two presentations ourselves would mean maintaining the phone one twice.
        .popover(
            isPresented: $isShowingTheme,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            ThemeSheet(model: model)
                // A sheet that covers the page would hide the live preview
                // `ebook-reader` asks for: "the change is visible immediately in
                // the reader behind the sheet".
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                // A popover has no detent to size it, so it needs a width a sheet
                // does not: wide enough for the preset grid, narrow enough that the
                // page stays readable beside it.
                .frame(idealWidth: 380, idealHeight: 620)
        }
        // Writing on the mark the selection menu just made. Presented from here rather than
        // from the list, because that is where the reader asked for it.
        .sheet(item: $editingNote) { annotation in
            NoteEditor(text: $noteText) {
                Task { await model.annotate(annotation, with: noteText) }
                editingNote = nil
            } cancel: {
                editingNote = nil
            }
        }
        // Anchored to the words, which is what makes it a selection menu rather than a
        // sheet about the selection. `ebook-reader` asks for the colours, a note, copy and
        // search-in-publication; the system's own edit menu is refused in the delegate
        // because it has nowhere to put five colours.
        .popover(
            isPresented: Binding(
                get: { model.selection != nil },
                set: { if !$0 { model.selection = nil } }
            ),
            attachmentAnchor: .rect(.rect(model.selection?.frame ?? .zero)),
            arrowEdge: .top
        ) {
            SelectionMenu(
                onHighlight: { colour in Task { await model.highlight(colour) } },
                onNote: {
                    Task {
                        await model.highlight(.yellow)
                        // Straight into writing on the mark just made: a reader who chose
                        // "Note" wants to write, not to be handed a highlight and left to
                        // find the list.
                        if let latest = model.annotations.max(by: { $0.createdAt < $1.createdAt }) {
                            noteText = latest.note
                            editingNote = latest
                        }
                    }
                },
                onCopy: {
                    UIPasteboard.general.string = model.selection?.locator.text.highlight
                    model.selection = nil
                },
                onSearch: {
                    let words = model.selection?.locator.text.highlight
                    model.selection = nil
                    contentsTab = .search
                    isShowingContents = true
                    Task { if let words { await model.search(words) } }
                }
            )
            .presentationCompactAdaptation(.popover)
        }
        // A link out of the book names where it goes before it goes there.
        //
        // The destination is the publication's choice and the link text is too, so the one
        // thing the reader cannot get from the page is the host. A confirmation is the only
        // place it fits, and the default button is the one that stays.
        .confirmationDialog(
            Text("epub.leave.ask \(model.leaving?.host ?? "")", bundle: .module),
            isPresented: Binding(
                get: { model.leaving != nil },
                set: { if !$0 { model.stayInTheBook() } }
            ),
            titleVisibility: .visible
        ) {
            Button { model.leaveTheBook() } label: {
                Text("epub.leave.open", bundle: .module)
            }
            Button(role: .cancel) { model.stayInTheBook() } label: {
                Text("epub.leave.cancel", bundle: .module)
            }
        }
        // `ebook-reader` asks for a footnote to open "in place as a popover", which is
        // the word this file already uses for the other two: a popover on a tablet, and
        // the same declaration adapted to a detented sheet on a phone. The page stays
        // visible either way, which is what makes it in place rather than a departure.
        .popover(
            isPresented: Binding(
                get: { model.note != nil },
                set: { if !$0 { model.dismissNote() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            ScrollView {
                Text(model.note ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(StoryArcSpace.gutter)
            }
            .presentationCompactAdaptation(.sheet)
            // Smaller than the other two: a note is a sentence or two, and a half-screen
            // sheet for one sentence reads as a departure from the page rather than an
            // aside beside it.
            .presentationDetents([.fraction(0.3), .medium])
            .frame(idealWidth: 380, idealHeight: 260)
        }
        // Presented like the theme sheet, for the same reason: on a tablet the
        // navigation sits beside the page it is about, and on a phone the platform
        // turns the same declaration into a detented sheet.
        .popover(
            isPresented: $isShowingContents,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            TableOfContentsSheet(model: model, opensOn: contentsTab)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .frame(idealWidth: 380, idealHeight: 620)
        }
        .task { await model.open() }
        .statusBarHidden(!isChromeVisible)
        .toolbar(.hidden, for: .navigationBar)
        // `comic-reader`'s rule, and it reads the same for a book: a long look at
        // one page is reading, not idling.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            deviceBrightness = UIScreen.main.brightness
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // The voice outlives this screen. `ebook-reader`: closing the publication while
            // it is being read leaves speech running and returns the listener "to whatever
            // they were doing in the app rather than being kept in the book" — so this lets
            // go of the session rather than ending it. Ending it here is what made leaving
            // the book the same act as leaving the audio.
            model.detachReadAloud()
            // `reading-themes`: the system brightness "is not permanently
            // modified". iOS's brightness is global, so leaving has to put it back
            // — Android's is a window attribute and reverts by itself.
            if let deviceBrightness { UIScreen.main.brightness = deviceBrightness }
        }
        // Applied while reading rather than when the slider is released, so the
        // reader sees what they are choosing.
        .onChange(of: model.brightness) { _, new in
            if let new { UIScreen.main.brightness = CGFloat(new) }
        }
    }

    /// What is over the page and is not the chrome.
    ///
    /// **Why these two are not a third revealed control.** `comic-reader`'s count is about
    /// what a centre tap reveals. The return offer is armed by a long jump the reader just
    /// made and disarmed by taking it; the transport exists only while a voice is speaking,
    /// and `read-aloud` requires it to be reachable while the reader is looking at the page.
    /// Neither arrives with the chrome and neither survives the thing that armed it.
    private var transientOverlays: some View {
        VStack {
            Spacer()

            // Offered after any long jump, taken once, and never re-armed by its own use —
            // see ``EpubReaderModel/returnToWhereTheyWere()``. Above the transport because it
            // is about where the reader just was, and the transport is about what the voice
            // is doing now.
            if model.returnPoint != nil {
                ReturnControl { Task { await model.returnToWhereTheyWere() } }
                    .padding(.bottom, StoryArcSpace.sm)
            }

            if model.readAloud.isActive {
                ReadAloudBar(
                    isSpeaking: model.readAloud.isSpeaking,
                    onPrevious: { model.skipSentence(forward: false) },
                    onToggle: { model.toggleReadAloud() },
                    onNext: { model.skipSentence(forward: true) },
                    onStop: { model.stopReadAloud() }
                )
                .padding(.bottom, StoryArcSpace.lg)
            }
        }
        .transition(.opacity)
    }
}
