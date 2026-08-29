import SwiftUI

import DesignSystem
import StoryArcCore

/// The reading preset the app's appearance dictates, when the reader opted into that.
///
/// `nil` when they have not, which leaves each shelf's own theme in force.
/// `settings-and-about` keeps the two separate by default and says why: "a dark app chrome
/// with a paper-white page is a legitimate preference".
///
/// A free function rather than a computed property on `StoryArcApp`, and its own file
/// rather than a tail on that one: it derives one value from two inputs and touches no
/// state, so nothing about it needs to live inside the app struct — which was over the
/// length the linter allows. `ReadingSelection` moved out for the same reason.
///
/// `colorScheme` is a parameter because "System" is a question about the device and only
/// the environment can answer it: it follows the device whatever the setting says.
func linkedPreset(for settings: AppSettings, in colorScheme: ColorScheme) -> ThemePreset? {
    guard settings.linkReadingThemeToAppearance else { return nil }
    let resolved: AppearanceMode = settings.appearance == .system
        ? (colorScheme == .dark ? .dark : .light)
        : settings.appearance
    return .matching(resolved)
}
