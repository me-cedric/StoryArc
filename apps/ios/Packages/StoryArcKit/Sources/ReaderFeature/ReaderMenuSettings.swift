internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// How this publication behaves, as rows rather than as a strip of icons.
//
// Every control here was a glass pill over the page: the transition menu, the fit segments,
// the direction menu, the orientation padlock and the spread-offset button. Six icons a
// reader had to recognise, three of which carried their state only in the picture — a
// filled `rectangle.split.2x1` against an outlined one is not a sentence.
//
// As menu rows they each state their own name and their own current value, which is the
// same argument `reading-themes` makes about a slider: "a reader cannot report, repeat or
// reason about a position". A row reading *Direction — Right to left* is a fact; an arrow
// glyph is a guess.
//
// The members are internal rather than private because `ReaderMenu` is in another file.
extension ReaderView {

    /// The settings section's rows, in the order a reader asks about them.
    @ViewBuilder
    var settingsRows: some View {
        transitionRow
        fitRow
        directionRow

        // Only where there is a pairing to shift. `comic-reader` offers the offset "for
        // publications whose cover throws the pairing off", which is a question that does
        // not arise in portrait or in a scroll.
        if layout.hasPairs {
            Toggle(isOn: spreadOffsetBinding) {
                Text("reader.spreads.offset", bundle: .module)
            }
        }

        #if os(iOS)
        orientationRow
        #endif
    }

    /// The page-transition row.
    ///
    /// `page-transitions` is specific about what a mode that cannot run looks like: "shown
    /// unavailable with a one-line reason, never silently absent". A row disabled by Reduce
    /// Motion therefore stays, disabled, and the reason is stated under it.
    ///
    /// Curl is the one exception, and the spec draws that line itself: where the *device*
    /// cannot honour it, Curl is "absent from the picker on that device… with the reason
    /// stated once in plain language".
    ///
    /// A `Menu` rather than a `Picker`: a picker's rows cannot be individually disabled, and
    /// a disabled segment cannot carry a reason.
    @ViewBuilder
    private var transitionRow: some View {
        let choices = model.transitions(reduceMotion: reduceMotion)
        Menu {
            ForEach(choices.offered, id: \.self) { mode in
                Button {
                    if let axis = mode.scrollAxis {
                        model.choose(axis)
                    } else {
                        model.choose(mode)
                    }
                } label: {
                    if choices.chosen == mode {
                        Label {
                            Text(mode.titleKey, bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(mode.titleKey, bundle: .module)
                    }
                }
                .disabled(!choices.isAvailable(mode))
            }

            // Only where there are stitched pages to separate. In a paged mode there is a
            // whole screen between one page and the next already.
            if choices.effective.scrollAxis != nil {
                Divider()
                Toggle(isOn: separatorBinding) {
                    Text("reader.separator", bundle: .module)
                }
            }
        } label: {
            // The name, then the value. The whole reason these left the page is that a
            // reader could not read them.
            LabeledContent {
                Text(choices.effective.titleKey, bundle: .module)
            } label: {
                Text("reader.transition", bundle: .module)
            }
        }

        // The reason under a mode this device refuses, in the quieter of the two roles
        // ``storyArcGlassText(_:)`` offers. Not a bare `.secondary`: this sheet is presented
        // over the page, so the ground under these words is whatever the reader is looking
        // at — see ``ReaderMenuOnGlassTests``.
        if let reason = choices.unavailable[choices.chosen] {
            Text(reason.titleKey, bundle: .module)
                .textRole(.caption)
                .storyArcGlassText(.secondary)
        } else if choices.curlIsAbsent {
            // Once, and in the reader's language rather than the platform's.
            Text("reader.transition.noCurl", bundle: .module)
                .textRole(.caption)
                .storyArcGlassText(.secondary)
        }
    }

    /// How the page is sized.
    ///
    /// A menu-styled `Picker`, which draws the label and the chosen value on one row. The
    /// segmented control this replaces truncated all four titles to a character each at an
    /// accessibility text size, and needed a second code path to survive it.
    private var fitRow: some View {
        Picker(selection: fitBinding) {
            ForEach(PageFit.allCases, id: \.self) { candidate in
                Text(candidate.shortTitleKey, bundle: .module).tag(candidate)
            }
        } label: {
            Text("reader.fit", bundle: .module)
        }
        .pickerStyle(.menu)
    }

    /// Which way the publication runs.
    ///
    /// `comic-reader` opens a publication in the direction its metadata declares and lets the
    /// reader overrule that. The row states the current direction, which matters more here
    /// than anywhere else on this screen: metadata gets it wrong often enough that a reader
    /// who suspects it needs to see which way the comic is running, not only be able to
    /// change it.
    private var directionRow: some View {
        Picker(selection: directionBinding) {
            ForEach(ReadingDirection.allCases, id: \.self) { candidate in
                Text(candidate.titleKey, bundle: .module).tag(candidate)
            }
        } label: {
            Text("reader.direction", bundle: .module)
        }
        .pickerStyle(.menu)
    }

    #if os(iOS)
    /// Holds the reader at the way up it is now.
    ///
    /// `comic-reader` scopes the lock to the reader, so this is here rather than in Settings.
    /// A toggle rather than the padlock button it replaces: the padlock's two glyphs were the
    /// only statement of which state it was in.
    private var orientationRow: some View {
        Toggle(isOn: $isOrientationLocked) {
            Text("reader.orientation", bundle: .module)
        }
    }
    #endif

    var directionBinding: Binding<ReadingDirection> {
        Binding(
            get: { model.readingDirection },
            set: { model.choose($0) }
        )
    }

    var spreadOffsetBinding: Binding<Bool> {
        Binding(
            get: { model.settings.offsetsSpreads },
            set: { model.chooseSpreadOffset($0) }
        )
    }

    /// Whether a continuous scroll draws a line where one page ends and the next begins.
    var separatorBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showsPageSeparator },
            set: { model.choosePageSeparator($0) }
        )
    }

    var fitBinding: Binding<PageFit> {
        Binding(
            get: { fit },
            set: { new in model.choose(new) }
        )
    }
}
