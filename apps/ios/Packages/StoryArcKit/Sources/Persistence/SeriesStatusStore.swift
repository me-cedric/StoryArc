public import Foundation

public import StoryArcCore

/// A status the reader set by hand, for a series whose source reports none.
///
/// `library-browsing` (D36): "a reader may set a status for that series by hand" when "a
/// series' source reports no publication status at all". The reported half of a status lives
/// on ``Publication`` itself, carried there at index time by `KavitaCard.applied(to:)`; this
/// is the other half, since nothing a scan or a Kavita answer produces can be re-indexed to
/// recover a choice the reader made in the app.
///
/// Keyed by series name rather than by ``PublicationIdentity``: a status is a fact about a
/// series, every member of which the library already groups by that name
/// (`seriesShelfMembers(named:in:)`), and a per-publication key would have to be written to
/// every issue a series holds and kept in step as issues are added. The same collision a
/// shared series name across two sources could cause already exists for grouping itself;
/// this does not make it worse.
///
/// `@unchecked Sendable` for the reason ``KavitaProgressStore`` gives. Android's
/// `SeriesStatusStore` mirrors it.
public struct SeriesStatusStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.library.seriesStatus"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every status a reader has set by hand, keyed by series name.
    public func all() -> [String: PublicationStatus] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: PublicationStatus].self, from: data)
        else { return [:] }
        return stored
    }

    /// Sets, or replaces, the status a reader chose for one series.
    public func set(_ status: PublicationStatus, for series: String) {
        var value = all()
        value[series] = status
        write(value)
    }

    /// Clears the status a reader had set for one series, leaving it unset again.
    public func clear(_ series: String) {
        var value = all()
        value[series] = nil
        write(value)
    }

    private func write(_ value: [String: PublicationStatus]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
