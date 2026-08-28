public import Foundation

/// The certificates a reader has explicitly accepted, on disk.
///
/// `opds-catalog` lets a reader pin a self-signed certificate "after showing its
/// fingerprint and an explicit warning". A pin that did not survive a launch would ask
/// that question again every morning, and a question asked daily is a question answered
/// without reading it — which is the failure mode the warning exists to prevent.
///
/// `UserDefaults`, not the keychain. A fingerprint is a public value: it is printed by
/// `openssl`, sent by the server to anyone who connects, and useless to an attacker who
/// does not already control the connection. What it must be is *hard to change quietly*,
/// and an app's own defaults are as private as its keychain is to anything but this app.
public struct CertificatePinStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.certificatePins"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every accepted fingerprint, per host.
    public func pins() -> [String: Set<String>] {
        guard let stored = defaults.dictionary(forKey: key) as? [String: [String]] else { return [:] }
        return stored.mapValues(Set.init)
    }

    public func save(_ pins: [String: Set<String>]) {
        defaults.set(pins.mapValues { $0.sorted() }, forKey: key)
    }

    /// Forgets one host's pins. Called when its source is removed, so re-adding the same
    /// server asks the question again rather than trusting a decision the reader
    /// deliberately undid.
    public func forget(_ host: String) {
        var current = pins()
        current[host] = nil
        save(current)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
