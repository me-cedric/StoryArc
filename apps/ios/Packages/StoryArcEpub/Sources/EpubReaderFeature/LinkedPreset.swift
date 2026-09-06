public import SwiftUI

public import StoryArcCore

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
///
/// **It lives in this package rather than in the app target, and that is the half that made
/// the link testable.** The app target has no test bundle, so nothing named this rule and
/// deleting its opt-in guard broke no build. Android's `ReaderAppearanceTest` had covered the
/// same guard since the day it was written. `AppearanceFollowedTests` covers it here now.
public func linkedPreset(for settings: AppSettings, in colorScheme: ColorScheme) -> ThemePreset? {
    guard settings.linkReadingThemeToAppearance else { return nil }
    let resolved: AppearanceMode = settings.appearance == .system
        ? (colorScheme == .dark ? .dark : .light)
        : settings.appearance
    return .matching(resolved)
}

public extension EpubReaderModel {
    /// Takes the appearance's reading theme, while the book stays open.
    ///
    /// `ebook-reader` / *Theme follows appearance*: the reading theme switches "then and
    /// there rather than at the next open". The value used to reach the reader through the
    /// initialiser alone, which is read once, so a device that turned dark mid-chapter took
    /// the chrome with it and left the page as it was until the book was closed and reopened.
    ///
    /// `nil` means the reader never linked the two, and it does nothing — the shelf's own
    /// theme stays in force. That is the scenario's second clause.
    ///
    /// It goes through ``EpubReaderModel/adopt(_:)`` rather than writing the theme itself,
    /// because that is the one path that captures the reading position, submits the
    /// preferences and goes back to the position afterwards. `reading-themes` requires the
    /// position to survive a repagination "exactly as a type-size change is".
    ///
    /// A change that names the theme already in force does nothing either. Dark and OLED Dark
    /// both mean Quiet, so a reader moving between them would otherwise lose every axis they
    /// had moved, for an appearance change the reading theme cannot see.
    ///
    /// An extension rather than a member, for two reasons: this rule belongs beside the
    /// appearance it reads, and `EpubReaderModel.swift` is at the line cap. Android puts its
    /// own `follow` in `ReaderAppearance.kt` for the same two.
    func follow(_ linked: ThemePreset?) {
        guard let linked, linked != theme.preset else { return }
        adopt(linked)
    }
}
