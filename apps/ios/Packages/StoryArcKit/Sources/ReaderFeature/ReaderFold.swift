internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The comic reader on a foldable display: `native-experience`, *Foldable devices*, and
// `foldables-and-iphone-duo` D2 to D5. The fold itself comes from `sensingFold(into:)` in
// `DesignSystem`, or from a test through the `deviceFold` environment value.
//
// What the reader does with it:
//
// - A lone page moves to the wider side of a vertical fold, and a spread puts its gutter on it
//   (`ReaderContainers.swift`, with ``HingeSpreadSplit``).
// - Half open on a table, the page takes the upper half and the two controls the lower half.
//   The controls stay up while the posture lasts, and VoiceOver hears "Controls below" once.
// - Held like a book, the spread is forced on and Curl is withheld (D4).
// - The controls keep clear of the camera and of the fold (``DeviceFold/controlArea(in:)``).
//
// Nothing here moves a sheet. Every sheet and alert the reader presents (the menu, the
// adjustments, the PDF find and note sheets) is the system's own `.sheet` or `.alert`, and Apple
// states that iOS 27.1 lays those out clear of the fold and the camera itself ("Prepare your app
// for iPhone Duo"). A sheet of the reader's own drawing would need ``DeviceFold/controlArea(in:)``
// too. The three notices over the page (`NetworkNotice`, the voice-stopped banner, the return
// offer) are overlays, not sheets, and are centred: a vertical fold can still run through them.
//
// Plain layout rather than `ArrangementView`: the page and the controls are already two layers
// of one `ZStack`, and two frames move them without a second container that only iOS 27.1 has.
//
// The members are internal rather than private because `ReaderView.body` is in another file.

extension ReaderView {
    /// The fold in force: the device's own, or the one handed in.
    var fold: DeviceFold? { sensedFold ?? injectedFold }

    /// How the device is held. `.flat` whenever nothing is reported.
    var posture: FoldPosture { FoldPosture.of(fold) }

    /// Which transitions to offer and which runs, in this posture.
    ///
    /// The one place the reader asks the model, so that the picker, the pager and the pairing
    /// agree that a book posture has no Curl.
    var transitions: TransitionChoices {
        model.transitions(reduceMotion: reduceMotion, isBookPosture: posture == .book)
    }

    /// How a spread splits across a vertical fold on the pages' surface, or `nil` with no such fold.
    var foldSplit: HingeSpreadSplit? {
        guard surface.width > 0, let span = fold?.verticalSpan(in: surface) else { return nil }
        return hingeSpreadSplit(containerWidth: surface.width, hingeStart: span.lowerBound, hingeEnd: span.upperBound)
    }
}

/// Follows the posture: announces the tabletop layout, and keeps the device's own fold.
struct ReaderFoldTracking: ViewModifier {
    @Binding var sensed: DeviceFold?
    let posture: FoldPosture

    func body(content: Content) -> some View {
        content
            // D3: a reader who cannot see the fold is told the controls moved, once, when they do.
            .onChange(of: posture == .tabletop) { _, isTabletop in
                guard isTabletop else { return }
                let sentence = String(
                    localized: "reader.tabletop.controlsBelow", bundle: .module.inChosenLanguage, locale: .storyArc
                )
                AccessibilityNotification.Announcement(sentence).post()
            }
            .sensingFold(into: $sensed)
    }
}
