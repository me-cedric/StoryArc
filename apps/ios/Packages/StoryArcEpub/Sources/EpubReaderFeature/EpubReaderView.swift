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
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var model: EpubReaderModel
    @State private var isChromeVisible = true
    @State private var isShowingTheme = false
    @State private var isShowingContents = false
    /// What the device's brightness was before the reader touched it.
    @State private var deviceBrightness: CGFloat?

    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        /// See ``EpubReaderModel/init(publication:url:progress:preferences:linkedPreset:)``.
        linkedPreset: ThemePreset? = nil
    ) {
        _model = State(
            initialValue: EpubReaderModel(
                publication: publication,
                url: url,
                progress: progress,
                preferences: preferences,
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
                NavigatorHost(navigator: navigator) {
                    withAnimation(.easeInOut(duration: 0.2)) { isChromeVisible.toggle() }
                }
                .ignoresSafeArea()
            } else {
                ProgressView()
            }

            // Grouped, because `native-experience` asks for overlapping glass
            // shapes to "morph as one". Only the container produces that — a
            // surface cannot know about its neighbours from the inside.
            if isChromeVisible {
                GlassEffectContainer(spacing: StoryArcSpace.md) { chrome }
            }
        }
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
        // Presented like the theme sheet, for the same reason: on a tablet the
        // navigation sits beside the page it is about, and on a phone the platform
        // turns the same declaration into a detented sheet.
        .popover(
            isPresented: $isShowingContents,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            TableOfContentsSheet(model: model)
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

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Label {
                        Text("epub.close", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }
                // The platform's own glass button, rather than glass painted
                // behind a plain one: it carries the interactive highlight and the
                // Reduce-Transparency fallback that a hand-rolled pill would not.
                .buttonStyle(.glass)
                .tint(theme.palette.textPrimary)

                Spacer()

                Button { isShowingContents = true } label: {
                    Label {
                        Text("contents.title", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(theme.palette.textPrimary)

                Button { isShowingTheme = true } label: {
                    Label {
                        Text("theme.title", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(theme.palette.textPrimary)

                if let chapter = model.chapterTitle {
                    Text(chapter)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, StoryArcSpace.md)
                        .padding(.vertical, StoryArcSpace.xs)
                        .storyArcGlass()
                }
            }
            .padding(StoryArcSpace.md)

            Spacer()

            // A percentage, never a page number. `ebook-reader` is explicit that a
            // reflowable page count is a function of the type size and must not be
            // presented as an identity.
            Text("epub.progress \(Int((model.progression * 100).rounded()))", bundle: .module)
                .textRole(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.palette.textSecondary)
                .padding(.horizontal, StoryArcSpace.md)
                .padding(.vertical, StoryArcSpace.xs)
                .storyArcGlass()
                .padding(.bottom, StoryArcSpace.lg)
        }
        .transition(.opacity)
    }
}

/// The navigator, in a SwiftUI hierarchy.
///
/// The tap is registered through Readium's own input observer rather than a
/// SwiftUI gesture: a gesture layered over the web view swallows the taps the
/// reader needs to turn pages and follow links.
private struct NavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        navigator.addObserver(.tap { _ in
            onTap()
            return true
        })
        return navigator
    }

    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}
}

private struct Failure: View {
    @Environment(\.theme) private var theme

    let message: String

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
            Text(message)
                .textRole(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.palette.textSecondary)
        .padding(StoryArcSpace.gutter)
    }
}
