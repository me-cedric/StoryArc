internal import Foundation
internal import StoryArcCore

/// A reader-facing list, joined in the reader's chosen language.
///
/// `ListFormatter.localizedString(byJoining:)` is a convenience over the process locale,
/// which the interface-language override does not move -- the same gap
/// ``StoryArcCore/Locale/storyArc``'s own doc comment describes for `String(localized:)`.
/// An instance asked for ``StoryArcCore/Locale/storyArc`` is the fix: `localization` asks
/// every list to join "and"/"et"/"und"/"y" in the chosen language, not the device's.
func localizedJoin(_ items: [String]) -> String {
    let formatter = ListFormatter()
    formatter.locale = .storyArc
    return formatter.string(from: items) ?? items.joined(separator: ", ")
}
