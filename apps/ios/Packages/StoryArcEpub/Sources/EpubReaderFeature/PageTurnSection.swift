internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The page-turn rows in the theme sheet.
//
// Split out of `ThemeSheet` so that file stays the sheet's sections rather than the
// sections plus one of them in full. Internal rather than private because the sheet's
// `body` is in the other file, and a `private` member of an extension cannot cross one.
extension ThemeSheet {
    /// How a page becomes the next page.
    ///
    /// `page-transitions` asks for its four modes in *both* readers. Two of them animate
    /// a picture of a page, and a reflowable page is live web content — so those two are
    /// listed with the reason rather than dropped, which is the spec's own "a mode is
    /// unavailable for the content" scenario.
    ///
    /// Scroll here is Readium's own preference, not a container of ours: a web view that
    /// already paginates and a scroll view of ours would fight for the same gesture.
    var pageTurn: some View {
        let choices = model.transitions(reduceMotion: reduceMotion)
        return VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.pageTurn", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // `textRole` sets font and tracking only, so without this the sheet's
                // one long ScrollView offers VoiceOver no heading to jump to.
                .accessibilityAddTraits(.isHeader)

            ForEach(choices.offered, id: \.self) { mode in
                Button { model.choose(mode) } label: {
                    HStack(spacing: StoryArcSpace.sm) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mode.titleKey, bundle: .module)
                                .textRole(.body)
                                .foregroundStyle(
                                    choices.isAvailable(mode)
                                        ? theme.palette.textPrimary
                                        : theme.palette.textTertiary
                                )

                            if let reason = choices.unavailable[mode] {
                                Text(reason.titleKey, bundle: .module)
                                    .textRole(.caption)
                                    .foregroundStyle(theme.palette.textTertiary)
                            }
                        }

                        Spacer()

                        if model.transition == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!choices.isAvailable(mode))
                .accessibilityAddTraits(
                    model.transition == mode ? [.isButton, .isSelected] : .isButton
                )
            }
        }
    }
}
