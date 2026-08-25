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
    /// What the device's brightness was before the reader touched it.
    @State private var deviceBrightness: CGFloat?

    public init(publication: Publication, url: URL, progress: ProgressStore? = nil) {
        _model = State(
            initialValue: EpubReaderModel(publication: publication, url: url, progress: progress)
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

            if isChromeVisible { chrome }
        }
        .sheet(isPresented: $isShowingTheme) {
            ThemeSheet(model: model)
                // A sheet that covers the page would hide the live preview
                // `ebook-reader` asks for: "the change is visible immediately in
                // the reader behind the sheet".
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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
                    .padding(StoryArcSpace.sm)
                }
                .background(.ultraThinMaterial, in: .circle)
                .tint(theme.palette.textPrimary)

                Spacer()

                Button { isShowingTheme = true } label: {
                    Label {
                        Text("theme.title", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat")
                    }
                    .labelStyle(.iconOnly)
                    .padding(StoryArcSpace.sm)
                }
                .background(.ultraThinMaterial, in: .circle)
                .tint(theme.palette.textPrimary)

                if let chapter = model.chapterTitle {
                    Text(chapter)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, StoryArcSpace.md)
                        .padding(.vertical, StoryArcSpace.xs)
                        .background(.ultraThinMaterial, in: .capsule)
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
                .background(.ultraThinMaterial, in: .capsule)
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
