internal import Foundation
public import StoryArcCore

/// A date, abbreviated, with no time -- in the reader's chosen language.
///
/// `Date.formatted(date:time:)` is a convenience over the process locale, which the
/// interface-language override does not move. ``SettingsFeature/SourceDetail`` already
/// asks the full style for ``StoryArcCore/Locale/storyArc``; this is that same answer,
/// shared with the catalogue screens that show a certificate's expiry and a feed entry's
/// last update.
var abbreviatedDateStyle: Date.FormatStyle {
    Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.storyArc)
}
