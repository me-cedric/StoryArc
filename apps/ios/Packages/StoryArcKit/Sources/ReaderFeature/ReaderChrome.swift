internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The reader's controls: one gesture away, and gone while reading.
//
// Split out of `ReaderView` so that file stays the screen's structure rather than the
// structure plus every control in it. The members are internal rather than private
// because `ReaderView.body` is in the other file, and a `private` member of an
// extension cannot be reached from it.
extension ReaderView {
    /// The controls. One gesture away, and gone while reading.
    var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
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

                Button { isAdjusting = true } label: {
                    Label {
                        Text("reader.adjust", bundle: .module)
                    } icon: {
                        // Filled while something is applied, so a reader who wonders why
                        // the page looks like that can see that they asked for it.
                        Image(systemName: adjustments.isNeutral
                            ? "slider.horizontal.below.rectangle"
                            : "slider.horizontal.below.square.filled.and.square")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(.white)

                // Only where there is a pairing to shift. `comic-reader` offers the
                // offset "for publications whose cover throws the pairing off", which
                // is a question that does not arise in portrait or in a scroll.
                if layout.hasPairs {
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
                }

                // Only for a PDF that carries text. `ebook-reader` requires a
                // text-dependent control to be hidden rather than disabled when there is no
                // text, and a button that opened a search box over a scan would be exactly the
                // promise the spec forbids.
                if pdfText != nil {
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
                }
            }
            .padding(StoryArcSpace.md)

            Spacer()

            if isBrowsingThumbnails {
                ThumbnailStrip(model: model, currentIndex: model.currentIndex) { index in
                    // A jump, like the slider's: it leaves the same mark, so the way
                    // back from a mis-tap in a three-hundred-page strip is one control.
                    jump(to: index)
                    withAnimation(.easeInOut(duration: 0.2)) { isBrowsingThumbnails = false }
                }
                // The cross-fade alone says the strip arrived. `native-experience`
                // forbids the translation of a full-width panel under Reduce Motion.
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: StoryArcSpace.sm) {
                transitionPicker

                // Down here with the other choices about how this publication is laid
                // out, not up in the top row, which is already the way out of the reader
                // and two content tools wide on a phone.
                HStack(spacing: StoryArcSpace.sm) {
                    directionPicker
                    #if os(iOS)
                    orientationButton
                    #endif
                    Spacer()
                }

                // A segmented control rather than a menu. Four options fit across a
                // phone, and a control with no open state cannot be swallowed by
                // the chrome auto-hiding under it. That holds at the default text
                // size only: at an accessibility size iOS truncates four segments to
                // a character each, so there the same picker becomes a menu, which
                // also shows its label rather than hiding it.
                if dynamicTypeSize.isAccessibilitySize {
                    fitPicker
                        .pickerStyle(.menu)
                } else {
                    fitPicker
                        .pickerStyle(.segmented)
                        .labelsHidden()
                }

                chapterRow

                if model.pages.count > 1 {
                    pageSliderRow
                } else if !model.pages.isEmpty {
                    pageCount
                }

                skippedNotice
            }
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.bottom, StoryArcSpace.lg)
        }
        .transition(.opacity)
    }

    /// How many entries the archive could not give us, when any.
    ///
    /// `publication-formats`: a damaged archive opens "whatever pages it can read and
    /// states how many were skipped, rather than refusing the whole publication". The
    /// opening half was already true and the *stating* half was not — the count reached
    /// the model and stopped there, so a reader met a comic that was quietly eight pages
    /// short and had nothing to tell them why.
    ///
    /// In the chrome rather than over the artwork: it is a fact about the file, not
    /// about the page in front of the reader, and the non-negotiable is that chrome
    /// recedes. So it arrives with the controls, sits under the page counter it
    /// qualifies, and leaves with them four seconds later.
    @ViewBuilder
    var skippedNotice: some View {
        if model.skippedPageCount > 0 {
            Text("reader.skipped \(model.skippedPageCount)", bundle: .module)
                .textRole(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, StoryArcSpace.sm)
                .padding(.vertical, StoryArcSpace.xs)
                .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.sm))
        }
    }

    /// The page-transition picker.
    ///
    /// `page-transitions` is specific about what a mode that cannot run looks like:
    /// "shown unavailable with a one-line reason, never silently absent". A row
    /// disabled by Reduce Motion therefore stays, disabled, and the reason is stated
    /// under the row rather than left to be guessed.
    ///
    /// Curl is the one exception, and the spec draws that line itself: where the
    /// *device* cannot honour it, Curl is "absent from the picker on that device… with
    /// the reason stated once in plain language — naming the requirement, not an API
    /// level". A permanently dead row is furniture; a sentence is an explanation.
    ///
    /// A menu rather than a segmented control, unlike the fit above: five rows do not
    /// fit across a phone, and a disabled segment cannot carry a reason.
    var transitionPicker: some View {
        let choices = model.transitions(reduceMotion: reduceMotion)
        return VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
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

                // Only where there are stitched pages to separate. In a paged mode there
                // is a whole screen between one page and the next already.
                if choices.effective.scrollAxis != nil {
                    Divider()
                    Toggle(isOn: separatorBinding) {
                        Text("reader.separator", bundle: .module)
                    }
                }
            } label: {
                Label {
                    Text(choices.effective.titleKey, bundle: .module)
                } icon: {
                    Image(systemName: "book.pages")
                }
            }
            .buttonStyle(.glass)
            .tint(.white)

            // Full white on glass, not 70% white on the page: the chrome paints no
            // scrim, so a translucent caption over white manga stock is invisible.
            if let reason = choices.unavailable[choices.chosen] {
                Text(reason.titleKey, bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, StoryArcSpace.sm)
                    .padding(.vertical, StoryArcSpace.xs)
                    .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.sm))
            } else if choices.curlIsAbsent {
                // Once, and in the reader's language rather than the platform's.
                Text("reader.transition.noCurl", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, StoryArcSpace.sm)
                    .padding(.vertical, StoryArcSpace.xs)
                    .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.sm))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The reading-direction picker.
    ///
    /// `comic-reader` opens a publication in the direction its metadata declares and lets
    /// the reader overrule that. Two rows and a checkmark, the same shape as the
    /// transition menu above rather than a bare toggle: metadata gets this wrong often
    /// enough that a reader who suspects it needs to see which way the comic is running,
    /// not only be able to change it.
    var directionPicker: some View {
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
    }

    #if os(iOS)
    /// Holds the reader at the way up it is now.
    ///
    /// `comic-reader` scopes the lock to the reader, so this is a button here rather than
    /// a row in Settings. Its title says what pressing it would do rather than what the
    /// state is: with no label on screen beside the icon, that sentence is all VoiceOver
    /// has to go on.
    var orientationButton: some View {
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
    }

    private var orientationTitleKey: LocalizedStringKey {
        isOrientationLocked ? "reader.orientation.unlock" : "reader.orientation.lock"
    }
    #endif

    /// Whether a continuous scroll draws a line where one page ends and the next begins.
    var separatorBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showsPageSeparator },
            set: { model.choosePageSeparator($0) }
        )
    }
    /// The page-fit picker, without a style.
    ///
    /// The label is a real one rather than `""`: each segment reads its own title to
    /// VoiceOver, but nothing else states what the four titles control.
    var fitPicker: some View {
        Picker(selection: fitBinding) {
            ForEach(PageFit.allCases, id: \.self) { candidate in
                Text(candidate.shortTitleKey, bundle: .module).tag(candidate)
            }
        } label: {
            Text("reader.fit", bundle: .module)
        }
    }

    var fitBinding: Binding<PageFit> {
        Binding(
            get: { fit },
            set: { new in
                fit = new
                preferences?.save(new)
            }
        )
    }

}
