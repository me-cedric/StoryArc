public import SwiftUI

/// What changed in a version, and whether this launch is the one that should say so.
///
/// `settings-and-about`: "The app SHALL tell a reader what changed, once, after it has been
/// updated, and SHALL never let that get in the way of reading."
///
/// **The log is a value compiled into the app, not a document fetched from anywhere.** The
/// spec's offline scenario — "the screen appears in full, because what changed ships with
/// the app and is never fetched" — is held structurally by that: there is no URL here, no
/// decoder and nothing to be unreachable. Only the *words* are a resource, in this module's
/// `Localizable.xcstrings`, which is how they exist in the four shipped languages.
/// Android's `WhatsNew.kt` is the same value over `R.string` ids.
///
/// `@MainActor` because a ``SwiftUI/LocalizedStringKey`` is not `Sendable`, and it is the
/// only string type that resolves against the environment's locale — which is how
/// `localization`'s in-app language override reaches a `Text` at all. A
/// `LocalizedStringResource` would be `Sendable` and would speak the *device's* language
/// instead. This is read while a view is being built and nowhere else, so the isolation
/// costs nothing.
@MainActor
public enum WhatsNew {

    /// Every release worth a word, newest first — which is the order About lists them in.
    ///
    /// **0.1.0 is a first entry that had a great deal to catch up on.** The app shipped
    /// page curl, five typefaces, six reading themes, OPDS, Kavita, SMB and a reading
    /// position that survives a file being renamed, and told nobody about any of it. What
    /// went in was not all of that: four lines, in the shape Apple's own What's New uses,
    /// because a reader who opens a reading app is there to read. The rest of the history
    /// is in the repository for anyone who wants it.
    public static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "0.1.0",
            notes: [
                WhatsNewNote(
                    symbolName: "books.vertical.fill",
                    title: LocalizedStringKey("whatsnew.0-1-0.sources.title"),
                    body: LocalizedStringKey("whatsnew.0-1-0.sources.body")
                ),
                WhatsNewNote(
                    symbolName: "textformat",
                    title: LocalizedStringKey("whatsnew.0-1-0.reading.title"),
                    body: LocalizedStringKey("whatsnew.0-1-0.reading.body")
                ),
                WhatsNewNote(
                    symbolName: "bookmark.fill",
                    title: LocalizedStringKey("whatsnew.0-1-0.place.title"),
                    body: LocalizedStringKey("whatsnew.0-1-0.place.body")
                ),
                WhatsNewNote(
                    symbolName: "hand.raised.fill",
                    title: LocalizedStringKey("whatsnew.0-1-0.private.title"),
                    body: LocalizedStringKey("whatsnew.0-1-0.private.body")
                ),
            ]
        )
    ]

    /// What to show on this launch, recording the version either way.
    ///
    /// **The recording is unconditional and it happens here**, before anything is drawn.
    /// Three of the spec's scenarios turn on that single line:
    ///
    /// - a first ever launch shows nothing "and the version is recorded as seen, so the
    ///   next update is the first thing they are told about";
    /// - a version with nothing worth saying shows nothing and "is still recorded as seen,
    ///   so the entry is not shown late alongside the next one";
    /// - and the sheet is *shown* rather than *dismissed* when the flag is written, because
    ///   "a reader who swipes it away has still seen it". Nothing here waits for an action,
    ///   so there is no way to be shown the screen and not be recorded as having been.
    ///
    /// Called once, from `AppShell`. About reads ``releases`` directly and never comes here.
    public static func onLaunch(store: WhatsNewStore = WhatsNewStore()) -> WhatsNewRelease? {
        onLaunch(installed: BuildInfo.version, store: store, in: releases)
    }

    /// The same decision with the version and the log handed in, so both can be fixed in a
    /// test. Not `public`: ``BuildInfo`` is this module's, and a default argument cannot
    /// reach it from outside.
    static func onLaunch(
        installed: String,
        store: WhatsNewStore,
        in releases: [WhatsNewRelease]
    ) -> WhatsNewRelease? {
        let seen = store.seenVersion
        store.record(installed)
        return release(installed: installed, seen: seen, in: releases)
    }

    /// The decision on its own, with nothing to write and nothing to read.
    ///
    /// `seen == nil` is a first ever launch: no version has been recorded, so the app has
    /// never been opened, so there is nothing to catch up on.
    static func release(
        installed: String,
        seen: String?,
        in releases: [WhatsNewRelease]
    ) -> WhatsNewRelease? {
        guard let seen, seen != installed else { return nil }
        return releases.first { $0.version == installed }
    }

    /// Whether one version string is newer than another.
    ///
    /// Dot-separated numbers compared as numbers, so `0.10.0` sorts above `0.9.0` where a
    /// string comparison would put it below. Anything non-numeric counts as zero: the log
    /// is written here rather than parsed from anywhere, so a version this cannot read is a
    /// typo rather than input, and the test that pins the order is what catches it.
    static func isNewer(_ left: String, _ right: String) -> Bool {
        let mine = left.split(separator: ".").map { Int($0) ?? 0 }
        let theirs = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(mine.count, theirs.count) {
            let one = index < mine.count ? mine[index] : 0
            let other = index < theirs.count ? theirs[index] : 0
            if one != other { return one > other }
        }
        return false
    }
}

/// One version's worth of notes.
public struct WhatsNewRelease: Identifiable {
    public var id: String { version }
    public let version: String
    public let notes: [WhatsNewNote]

    public init(version: String, notes: [WhatsNewNote]) {
        self.version = version
        self.notes = notes
    }
}

/// One line of a release note: a symbol, a heading, and a sentence.
///
/// Identified by its symbol rather than by a key of its own, because the two strings are
/// `LocalizedStringKey`s and a `LocalizedStringKey` will not give its key back. The symbol
/// is the one field that is already unique inside a release — a second row wearing the same
/// icon would read as a mistake to anyone looking at the screen — and the test suite pins
/// that rather than trusting it.
public struct WhatsNewNote: Identifiable {
    public var id: String { symbolName }
    public let symbolName: String
    public let title: LocalizedStringKey
    public let body: LocalizedStringKey

    public init(symbolName: String, title: LocalizedStringKey, body: LocalizedStringKey) {
        self.symbolName = symbolName
        self.title = title
        self.body = body
    }
}

/// The one version the reader has already been told about.
///
/// A single string in `UserDefaults`, beside the other small launch-time values, for the
/// reason `LibraryPreferences` gives: opening the progress database before the first screen
/// to learn whether to show a sheet would be a strange trade. Android's `WhatsNewStore`
/// keeps the same string in `SharedPreferences`.
public struct WhatsNewStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.whatsNewSeen"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The version last recorded, or `nil` on a device that has never opened the app.
    public var seenVersion: String? { defaults.string(forKey: key) }

    public func record(_ version: String) {
        defaults.set(version, forKey: key)
    }
}
