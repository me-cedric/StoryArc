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
                    displayIndex = displayIndex(forModel: index)
                    withAnimation(.easeInOut(duration: 0.2)) { isBrowsingThumbnails = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: StoryArcSpace.sm) {
                transitionPicker

                // A segmented control rather than a menu. Four options fit across a
                // phone, and a control with no open state cannot be swallowed by
                // the chrome auto-hiding under it.
                Picker("", selection: fitBinding) {
                    ForEach(PageFit.allCases, id: \.self) { candidate in
                        Text(candidate.shortTitleKey, bundle: .module).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.pages.count > 1 {
                    pageSliderRow
                } else if !model.pages.isEmpty {
                    pageCount
                }
            }
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.bottom, StoryArcSpace.lg)
        }
        .transition(.opacity)
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
            } label: {
                Label {
                    Text(choices.effective.titleKey, bundle: .module)
                } icon: {
                    Image(systemName: "book.pages")
                }
            }
            .buttonStyle(.glass)
            .tint(.white)

            if let reason = choices.unavailable[choices.chosen] {
                Text(reason.titleKey, bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else if choices.curlIsAbsent {
                // Once, and in the reader's language rather than the platform's.
                Text("reader.transition.noCurl", bundle: .module)
                    .textRole(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var pageCount: some View {
        pageCountLabel
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .storyArcGlass()
    }

    var pageCountLabel: some View {
        Text("reader.page \(model.currentIndex + 1) \(model.pages.count)", bundle: .module)
            .textRole(.footnote)
            .monospacedDigit()
            .foregroundStyle(.white)
    }

    var pageSliderRow: some View {
        VStack(spacing: StoryArcSpace.xs) {
            pageCountLabel

            // Bound to the *publication's* page number, not the pager's position.
            // In right-to-left the two run opposite ways, and a slider whose left
            // end is the last page would be a puzzle. Thumbnails on the slider are
            // the rest of what `comic-reader` asks for and are not here yet.
            Slider(value: pageSlider, in: 0...Double(max(1, model.pages.count - 1)), step: 1)
                .tint(.white)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.lg))
    }
}
