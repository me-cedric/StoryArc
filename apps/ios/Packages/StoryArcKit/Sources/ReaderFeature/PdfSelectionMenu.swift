internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The menu a PDF selection gets.
//
// `ebook-reader`: on a selection, "highlight in several colours, add a note, copy, and
// search-in-publication are offered". The same four the reflowable reader offers, in the same
// order, because it is the same act — what differs is only what is under the finger.
//
// Drawn on glass over the page rather than as a system edit menu, for the reason the EPUB
// reader refuses that menu too: five colours is not a list of verbs. It sits at the foot of
// the screen rather than beside the words, because the words are on a page the reader may have
// zoomed and panned, and a popover anchored to a moving rectangle chases it.
//
// Android's `PdfSelectionBar` offers the same four things.
struct PdfSelectionMenu: View {
    let text: String
    let onHighlight: (HighlightColour) -> Void
    let onNote: () -> Void
    let onCopy: () -> Void
    let onSearch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            // The words themselves, so a reader who dragged past what they meant can see it
            // before they mark it.
            Text(text)
                .textRole(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: StoryArcSpace.sm) {
                ForEach(HighlightColour.allCases, id: \.self) { colour in
                    Button { onHighlight(colour) } label: {
                        Circle()
                            .fill(colour.swatch)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(colour.titleKey, bundle: .module))
                }

                Spacer()

                action("reader.pdf.note", "square.and.pencil", onNote)
                action("reader.pdf.copy", "doc.on.doc", onCopy)
                action("reader.pdf.searchSelection", "magnifyingglass", onSearch)
                action("reader.pdf.deselect", "xmark", onDismiss)
            }
        }
        .padding(StoryArcSpace.md)
        .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.md))
        .padding(.horizontal, StoryArcSpace.md)
    }

    private func action(
        _ key: LocalizedStringKey,
        _ symbol: String,
        _ perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label {
                Text(key, bundle: .module)
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(Text(key, bundle: .module))
    }
}

extension HighlightColour {
    /// Named, not described. A screen reader saying "yellow" is what a reader picking a colour
    /// needs; "the first swatch" is not.
    ///
    /// Its own strings in this module rather than the EPUB reader's: a module carries its own
    /// catalogue, and `localization` requires every string in every language on both platforms
    /// rather than one module reaching into another's bundle.
    var titleKey: LocalizedStringKey {
        switch self {
        case .yellow: "reader.pdf.colour.yellow"
        case .green: "reader.pdf.colour.green"
        case .blue: "reader.pdf.colour.blue"
        case .pink: "reader.pdf.colour.pink"
        case .purple: "reader.pdf.colour.purple"
        }
    }
}
