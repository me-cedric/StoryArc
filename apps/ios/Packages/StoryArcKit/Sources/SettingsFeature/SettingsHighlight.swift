internal import SwiftUI

internal import DesignSystem

/// How long a highlight stays lit before it fades.
///
/// Long enough to be seen by someone whose eyes are still on the search field they came
/// from, short enough that it is gone before it becomes part of the screen. A highlight
/// that never fades stops meaning "here" and starts meaning "selected", which is a
/// different claim and a wrong one.
private let highlightDwell = Duration.seconds(2)

/// A settings list that can be arrived at with one of its rows named.
///
/// `settings-and-about` asks a search result to navigate "and highlight" what it matched.
/// Two things make that true and neither is enough alone: the row has to be *on screen*,
/// which is the scroll, and it has to be *pointed at*, which is the tint. A tint below the
/// fold highlights nothing, and a scroll with no tint leaves a reader looking at a list.
struct HighlightingList<Content: View>: View {
    let highlight: SettingsAnchor?

    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            List { content }
                .task(id: highlight) {
                    guard let highlight else { return }
                    // The list has to have laid the row out before it can be scrolled to,
                    // and on a first appearance `task` runs before it has. One frame of
                    // grace rather than a guess at a longer number.
                    try? await Task.sleep(for: .milliseconds(120))
                    withAnimation(.easeOut(duration: StoryArcDuration.normal)) {
                        proxy.scrollTo(highlight, anchor: .center)
                    }
                }
        }
    }
}

extension View {
    /// Marks this row as the one a search result points at.
    ///
    /// Applied to whatever the setting *is*: one row for a toggle, a whole group of
    /// sections for the reading defaults. Both are one setting to a reader, and the tint
    /// should cover what they came to find rather than the first line of it.
    func settingsHighlight(_ anchor: SettingsAnchor, when highlight: SettingsAnchor?) -> some View {
        modifier(SettingsHighlight(anchor: anchor, highlighted: highlight))
    }
}

private struct SettingsHighlight: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let anchor: SettingsAnchor
    let highlighted: SettingsAnchor?

    @State private var isLit = false

    private var isMine: Bool { highlighted == anchor }

    func body(content: Content) -> some View {
        content
            .id(anchor)
            // `nil` restores the list's own row background rather than clearing it, which
            // is why this is an optional colour and not a `Color.clear`: a grouped list
            // row with a clear background loses the surface it sits on.
            .listRowBackground(isLit ? theme.palette.accentMuted.opacity(0.30) : nil)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: StoryArcDuration.chromeFade),
                value: isLit
            )
            .task(id: isMine) {
                guard isMine else {
                    isLit = false
                    return
                }
                isLit = true
                try? await Task.sleep(for: highlightDwell)
                // Cancelled means the reader left, or searched again, before the dwell was
                // up. Either way the row below is no longer the one being pointed at.
                guard !Task.isCancelled else { return }
                isLit = false
            }
    }
}
