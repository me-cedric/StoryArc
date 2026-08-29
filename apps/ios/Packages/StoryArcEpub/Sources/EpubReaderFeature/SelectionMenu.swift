internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The menu a selection gets.
//
// `ebook-reader`: on a selection, "highlight in several colours, add a note, copy, and
// search-in-publication are offered". The system's own edit menu can hold none of that —
// five colours is not a list of verbs — so Readium is told not to show it and this is shown
// instead, anchored where the words are.
//
// Android's `SelectionMenu` offers the same four things.

/// Colours first, then the verbs.
struct SelectionMenu: View {
    @Environment(\.theme) private var theme

    let onHighlight: (HighlightColour) -> Void
    let onNote: () -> Void
    let onCopy: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            HStack(spacing: StoryArcSpace.sm) {
                ForEach(HighlightColour.allCases, id: \.self) { colour in
                    Button { onHighlight(colour) } label: {
                        Circle()
                            .fill(colour.swatch)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(theme.palette.textTertiary, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(colour.titleKey, bundle: .module))
                }
            }

            Divider()

            HStack(spacing: StoryArcSpace.lg) {
                action("annotations.note", "square.and.pencil", onNote)
                action("annotations.copy", "doc.on.doc", onCopy)
                action("search.title", "magnifyingglass", onSearch)
            }
        }
        .padding(StoryArcSpace.md)
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
        .tint(theme.palette.textPrimary)
        .accessibilityLabel(Text(key, bundle: .module))
    }
}

extension HighlightColour {
    /// Named, not described. A screen reader saying "yellow" is what a reader picking a
    /// colour needs; "the first swatch" is not.
    var titleKey: LocalizedStringKey {
        switch self {
        case .yellow: "annotations.colour.yellow"
        case .green: "annotations.colour.green"
        case .blue: "annotations.colour.blue"
        case .pink: "annotations.colour.pink"
        case .purple: "annotations.colour.purple"
        }
    }
}
