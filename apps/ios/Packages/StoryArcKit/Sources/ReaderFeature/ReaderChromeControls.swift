internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The reader chrome's two button clusters.
//
// Split out of `ReaderChrome.swift` for a reason the compiler imposes: grouping and
// morphing glass both need a `Namespace.ID`, `@Namespace` is stored storage, and stored
// storage cannot be declared in an extension — which is all `ReaderChrome.swift` is.
// A view of its own is the only place the namespace can live. It also keeps that file
// under the project's 400-line ceiling, which it was 45 lines away from.
//
// Both clusters sit inside the `GlassEffectContainer` that `ReaderView` wraps the chrome
// in. That container is what makes the union and the morph possible; neither does
// anything on its own.

/// The top row: the way out, and the tools that act on the page.
///
/// Two capsules rather than five pills. `glassEffectUnion` merges the tools into one
/// shape, and Close stays outside it — it leaves the reader, the others change what the
/// reader is looking at, and a control that ends the session should not read as one more
/// item in a strip of adjustments.
///
/// The three conditional tools carry a `glassEffectID`, so a tool that arrives with the
/// publication's shape — a PDF that turns out to carry text, a comic that turns out to
/// pair its pages — grows out of the capsule instead of popping in beside it.
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

    @Namespace private var glass

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
            .buttonStyle(.glass)
            .tint(.white)

            Spacer()

            HStack(spacing: StoryArcSpace.xs) {
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
                .buttonStyle(.glass)
                .tint(.white)
                .glassEffectUnion(id: Self.toolCluster, namespace: glass)

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
                    .buttonStyle(.glass)
                    .tint(.white)
                    .glassEffectID("spreads", in: glass)
                    .glassEffectUnion(id: Self.toolCluster, namespace: glass)
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
                    .buttonStyle(.glass)
                    .tint(.white)
                    .glassEffectID("find", in: glass)
                    .glassEffectUnion(id: Self.toolCluster, namespace: glass)
                }

                if model.pages.count > 1 {
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
                    .buttonStyle(.glass)
                    .tint(.white)
                    .glassEffectID("thumbnails", in: glass)
                    .glassEffectUnion(id: Self.toolCluster, namespace: glass)
                }
            }
        }
        .padding(StoryArcSpace.md)
    }

    /// One union id for the whole tool cluster: every member merges into the same shape.
    private static let toolCluster = "reader.tools"
}

/// How the publication is laid out: which way it runs, and whether the device may turn.
///
/// One capsule, for the same reason as the tools above — two adjacent pills that both
/// answer "how is this page presented" read as two unrelated controls.
struct ReaderLayoutControls: View {
    let model: ReaderModel
    @Binding var isOrientationLocked: Bool

    @Namespace private var glass

    var body: some View {
        HStack(spacing: StoryArcSpace.xs) {
            directionPicker
            #if os(iOS)
            orientationButton
            #endif
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
        }
        .buttonStyle(.glass)
        .tint(.white)
        .glassEffectUnion(id: Self.layoutCluster, namespace: glass)
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
        .buttonStyle(.glass)
        .tint(.white)
        .glassEffectUnion(id: Self.layoutCluster, namespace: glass)
    }

    private var orientationTitleKey: LocalizedStringKey {
        isOrientationLocked ? "reader.orientation.unlock" : "reader.orientation.lock"
    }
    #endif

    private static let layoutCluster = "reader.layout"
}
