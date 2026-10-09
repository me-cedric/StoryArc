internal import Foundation

/// When the last sync ran, as the words that sit inside one whole sentence.
///
/// Two sentences, not one with a clause that changes: *Synced 2 hours ago* and *Synced on Jan 1,
/// 2026 at 1:00 PM* take different small words in French, German and Spanish (*il y a*, *vor*,
/// *hace*; *le*, *am*, *el*), so each case has its own string per language and this type only
/// says which one and what goes in it. The platform's formatters write the moment, so the
/// language, the region and the hour cycle (1:00 PM or 13:00) are the reader's. The old line put
/// a date that already held its own *at* after another *at*, and left the hour cycle to chance.
enum SyncMoment: Equatable {
    /// Within a day: how long ago, already phrased by the locale.
    case recent(String)
    /// Older: the date and the time, in the locale's order and hour cycle.
    case older(String)

    static let recentWindow: TimeInterval = 24 * 3600

    static func of(_ moment: Date, now: Date, locale: Locale, timeZone: TimeZone = .current) -> SyncMoment {
        if abs(now.timeIntervalSince(moment)) < recentWindow {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            formatter.formattingContext = .middleOfSentence
            return .recent(formatter.localizedString(for: moment, relativeTo: now))
        }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
        return .older(moment.formatted(style))
    }
}
