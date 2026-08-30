internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The reader chrome's two button clusters.
//
// Split out of `ReaderChrome.swift` because that file is an extension, and the clusters
// need a view of their own: a `ButtonStyle` and the layout that goes with it. It also
// keeps that file under the project's 400-line ceiling, which it was 45 lines away from.
//
// **Why not `ToolbarSpacer` or `glassEffectUnion`, which the design direction names.**
// `ToolbarSpacer` groups items inside a real `.toolbar`; this chrome is a hand-built
// overlay that fades in over the artwork and auto-hides, not a navigation bar, so there
// is no toolbar for it to space. `glassEffectUnion` was tried first and does nothing
// here: glass drawn by `.buttonStyle(.glass)` is the button style's own, it does not join
// the enclosing `GlassEffectContainer`, and a row of glass buttons stays a row of
// separate pills however close together it sits. That was verified on a booted iPhone 17
// Pro rather than reasoned about — a burst of captures showed the merged shape only in
// the frames while the chrome was still fading in, and the settled state unchanged.
//
// So a cluster paints one `storyArcGlass` capsule and holds plain buttons. That helper is
// the house glass, and it carries the opaque Reduce-Transparency and Increase-Contrast
// fallback `native-experience` requires — which is the thing `.buttonStyle(.glass)` was
// originally chosen for, and the reason a hand-paint would otherwise be wrong here.
// The press feedback the glass style would have given is restored below rather than lost.

/// A control inside a shared glass capsule.
///
/// The 44pt minimum is stated rather than inherited: the glass button style used to
/// supply it, and a plain button does not.
private struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.4 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The top row: the way out, and the tools that act on the page.
///
/// Two shapes rather than five pills. Close keeps its own capsule and the platform's
/// glass button style — it leaves the reader, the others change what the reader is
/// looking at, and a control that ends the session should not read as one more item in a
/// strip of adjustments.
///
/// The tools share one capsule, so a tool that arrives with the publication's shape — a
/// PDF that turns out to carry text, a comic that turns out to pair its pages — widens
/// the capsule it belongs to instead of popping in beside it as another pill.
struct ReaderTopControls: View {
    let model: ReaderModel
    /// Whether nothing is applied to the page, which decides the adjust icon's fill.
    let adjustmentsAreNeutral: Bool
    /// Whether there is a pairing to shift. Absent in portrait and in a scroll.
    let hasPairs: Bool
    /// Whether this PDF carries text. A find button over a scan promises what
    /// `ebook-reader` forbids, so the control is absent rather than disabled.
    let hasPdfText: Bool
    @Binding var isAdjusting: Bool
    @Binding var isFindingText: Bool
    @Binding var isBrowsingThumbnails: Bool
    let onClose: () -> Void

    private var hasThumbnails: Bool { model.pages.count > 1 }

    var body: some View {
        HStack {
            Button(action: onClose) {
                Label {
                    Text("reader.close", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            // The platform's own glass button rather than glass painted behind
            // a plain one: it carries the interactive highlight, and its own
            // Reduce-Transparency fallback, which a hand-rolled pill does not.
            // It stands alone, so nothing has to merge with it.
            .buttonStyle(.glass)
            .tint(.white)

            Spacer()

            HStack(spacing: 0) {
                Button { isAdjusting = true } label: {
                    Label {
                        Text("reader.adjust", bundle: .module)
                    } icon: {
                        // Filled while something is applied, so a reader who wonders why
                        // the page looks like that can see that they asked for it.
                        Image(systemName: adjustmentsAreNeutral
                            ? "slider.horizontal.below.rectangle"
                            : "slider.horizontal.below.square.filled.and.square")
                    }
                    .labelStyle(.iconOnly)
                }

                // Only where there is a pairing to shift. `comic-reader` offers the
                // offset "for publications whose cover throws the pairing off", which
                // is a question that does not arise in portrait or in a scroll.
                if hasPairs {
                    Button {
                        model.chooseSpreadOffset(!model.settings.offsetsSpreads)
                    } label: {
                        Label {
                            Text("reader.spreads.offset", bundle: .module)
                        } icon: {
                            Image(systemName: model.settings.offsetsSpreads
                                ? "rectangle.split.2x1.fill"
                                : "rectangle.split.2x1")
                        }
                        .labelStyle(.iconOnly)
                    }
                }

                if hasPdfText {
                    Button { isFindingText = true } label: {
                        Label {
                            Text("reader.pdf.find", bundle: .module)
                        } icon: {
                            Image(systemName: "text.magnifyingglass")
                        }
                        .labelStyle(.iconOnly)
                    }
                }

                if hasThumbnails {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBrowsingThumbnails.toggle()
                        }
                    } label: {
                        Label {
                            Text("reader.thumbnails", bundle: .module)
                        } icon: {
                            Image(systemName: isBrowsingThumbnails
                                ? "square.grid.2x2.fill"
                                : "square.grid.2x2")
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .buttonStyle(ChromeButtonStyle())
            .storyArcGlass()
            // The capsule resizes when a tool arrives or leaves rather than jumping to
            // the new width.
            .animation(.smooth(duration: 0.25), value: hasPairs)
            .animation(.smooth(duration: 0.25), value: hasPdfText)
            .animation(.smooth(duration: 0.25), value: hasThumbnails)
        }
        .padding(StoryArcSpace.md)
    }
}

/// How the publication is laid out: which way it runs, and whether the device may turn.
///
/// One capsule, for the same reason as the tools above — two adjacent pills that both
/// answer "how is this page presented" read as two unrelated controls.
struct ReaderLayoutControls: View {
    let model: ReaderModel
    @Binding var isOrientationLocked: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                directionPicker
                #if os(iOS)
                orientationButton
                #endif
            }
            .buttonStyle(ChromeButtonStyle())
            .storyArcGlass()

            Spacer()
        }
    }

    /// The reading-direction picker.
    ///
    /// `comic-reader` opens a publication in the direction its metadata declares and lets
    /// the reader overrule that. Two rows and a checkmark, the same shape as the
    /// transition menu rather than a bare toggle: metadata gets this wrong often
    /// enough that a reader who suspects it needs to see which way the comic is running,
    /// not only be able to change it.
    private var directionPicker: some View {
        Menu {
            ForEach(ReadingDirection.allCases, id: \.self) { candidate in
                Button { model.choose(candidate) } label: {
                    if model.readingDirection == candidate {
                        Label {
                            Text(candidate.titleKey, bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(candidate.titleKey, bundle: .module)
                    }
                }
            }
        } label: {
            Label {
                Text("reader.direction", bundle: .module)
            } icon: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
    }

    #if os(iOS)
    /// Holds the reader at the way up it is now.
    ///
    /// `comic-reader` scopes the lock to the reader, so this is a button here rather than
    /// a row in Settings. Its title says what pressing it would do rather than what the
    /// state is: with no label on screen beside the icon, that sentence is all VoiceOver
    /// has to go on.
    private var orientationButton: some View {
        Button { isOrientationLocked.toggle() } label: {
            Label {
                Text(orientationTitleKey, bundle: .module)
            } icon: {
                Image(systemName: isOrientationLocked ? "lock.rotation" : "lock.rotation.open")
            }
            .labelStyle(.iconOnly)
        }
    }

    private var orientationTitleKey: LocalizedStringKey {
        isOrientationLocked ? "reader.orientation.unlock" : "reader.orientation.lock"
    }
    #endif
}
