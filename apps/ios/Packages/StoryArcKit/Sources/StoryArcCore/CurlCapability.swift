public import Foundation

/// Whether a device has proved it cannot draw the curl, from the turns it has already drawn.
///
/// `page-transitions` says Curl is absent where the device "cannot render it at the display's
/// refresh rate", and that "the app never ships a curl that stutters in preference to a slide
/// that does not". Nothing had ever measured that, so no device had ever withheld Curl for the
/// refresh rate — only Android's API floor did, which is a different sentence about a different
/// capability.
///
/// **D11 is the measurement.** The first ``turns`` curls on a device are counted, and the
/// median of what they cost decides. A median rather than a mean, because the first curl of a
/// session pays for a cold shader cache and a scheduler that has not seen this work before: a
/// mean lets that one turn condemn a phone that draws every later turn perfectly.
///
/// Android's `CurlVerdict` holds the same two numbers.
public enum CurlVerdict {

    /// How many curls a device draws before it is judged.
    public static let turns = 3

    /// How much longer than the display's own interval a frame may take.
    ///
    /// One frame in three missed, which on a 60 Hz panel is a mean frame time near 25 ms.
    /// Below it a reader sees a curl that keeps up with the finger; above it they see the
    /// stutter `page-transitions` refuses to ship.
    public static let tolerance = 1.5

    /// Whether the device has proved it cannot curl, or `nil` while it is still being asked.
    ///
    /// `nil` and `false` are deliberately different answers. A device is given the curl until
    /// it fails, never withheld while the question is open.
    public static func cannotCurl(strains: [Double]) -> Bool? {
        guard strains.count >= turns else { return nil }
        return strains.prefix(turns).sorted()[turns / 2] > tolerance
    }
}

/// What a device has shown about its own curl, kept across launches.
///
/// Per device, because that is the scope `page-transitions` states: "a user who set Curl on a
/// capable device and later opens the library on this one reads with Slide without their stored
/// preference being overwritten". So this is what ``TransitionChoices`` is told, and the
/// reader's own choice is never written — a faster phone, or a build that draws the same curl
/// more cheaply, honours a stored Curl again without asking.
///
/// Only the measurements are stored, never the verdict derived from them. A stored verdict is a
/// second state that can disagree with the first, and a device that was judged by an older
/// ``CurlVerdict/tolerance`` would keep that judgement for ever.
///
/// Android's `CurlCapability` is the same store over `SharedPreferences`.
public struct CurlCapability: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.curl-capability"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether this device has yet to be judged, which is what keeps the instrument running.
    ///
    /// False for the rest of the device's life once ``CurlVerdict/turns`` turns are in, so a
    /// shipping build pays for the frame clock over three page turns and never again.
    public var isUnjudged: Bool { strains.count < CurlVerdict.turns }

    /// Whether this device has proved it cannot curl.
    public var cannotCurl: Bool { CurlVerdict.cannotCurl(strains: strains) ?? false }

    /// Takes one measured turn. A turn past the ones that decide is dropped.
    public func record(strain: Double) {
        var all = strains
        guard all.count < CurlVerdict.turns else { return }
        all.append(strain)
        defaults.set(all, forKey: key)
    }

    /// Forgets what this device showed, so it is asked again. Used by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private var strains: [Double] { defaults.array(forKey: key) as? [Double] ?? [] }
}
