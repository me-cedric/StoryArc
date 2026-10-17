import DesignSystem
import StoryArcCore
import SwiftUI

/// What a turn past the last page shows.
///
/// `comic-reader`, *Reaching the end*: the publication is marked finished, and the next one
/// in the series is offered without being opened (`desktop-experience`, *A key at the end*).
/// Nothing here reads as an error. A turn back, Escape or Back to the Page returns to the
/// last page; downloads, and so the offer to delete one, are wave 3. Reading lists are wave 3
/// too, so the next publication is the series'.
struct EndOfPublicationView: View {
    @Environment(\.theme) private var theme

    let state: ReaderState
    let next: Publication?
    let onOpen: (Publication) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text("desktop.end.title \(state.model.publication.displayTitle)")
                .scaledFont(.title2, weight: .semibold)
                .foregroundStyle(theme.palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("desktop.end.finished").scaledFont(.callout).foregroundStyle(theme.palette.textSecondary)
            if let next {
                Button { onOpen(next) } label: {
                    Text("desktop.end.next \(next.displayTitle)").onAccentLabel()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 12) {
                Button { state.isAtEnd = false } label: { Text("desktop.end.back") }
                Button { onClose() } label: { Text("desktop.end.close") }
            }
            .buttonStyle(.borderless)
        }
        .padding(32)
        .frame(maxWidth: 420)
        // Opaque rather than glass: this is a screen of its own over the page, not chrome, and
        // glass over a pale page left its words under the contrast floor.
        .background(theme.palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
