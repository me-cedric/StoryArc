internal import Foundation

#if os(iOS)
internal import AVFoundation
#endif

/// What the platform's audio session said happened, read out of a notification.
///
/// Lifted out of ``PlaybackAudioSession`` so a host test can raise each event. That type read
/// `userInfo` under `#if os(iOS)`, and a macOS build compiled none of it: the decision
/// was asserted and the system event that reaches it was not. Tasks 3.9 and 4.1.
///
/// **Raw values, not `AVAudioSession`'s enums.** `AVAudioSession.InterruptionType` and
/// `RouteChangeReason` do not exist on the host, so the numbers are written here. They are
/// Apple's documented values. `AudioSessionEventPlatformTests` runs on a simulator and fails
/// if any of them, or either name or key below, differs from the real constant.
enum AudioSessionEvent: Equatable {
    /// Another app, a call or Siri took the audio.
    case interruptionBegan
    /// It was given back. `mayResume` is the platform's `.shouldResume` option.
    case interruptionEnded(mayResume: Bool)
    /// The device the audio was on went away: headphones pulled out, a Bluetooth speaker off.
    case routeLost

    /// An interruption's `userInfo`, or `nil` when it names no type the app acts on.
    init?(interruption userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?[Keys.interruptionType] as? UInt else { return nil }
        switch raw {
        case Raw.interruptionBegan:
            self = .interruptionBegan
        case Raw.interruptionEnded:
            let options = userInfo?[Keys.interruptionOptions] as? UInt ?? 0
            self = .interruptionEnded(mayResume: options & Raw.shouldResume != 0)
        default:
            return nil
        }
    }

    /// A route change's `userInfo`, or `nil` for every reason but a device going away.
    ///
    /// Only `oldDeviceUnavailable`. The notification fires for every route change there is, a
    /// new device arriving included, and pausing on all of them would stop the book when the
    /// listener *plugged headphones in*, which is the opposite of what this exists for.
    init?(routeChange userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?[Keys.routeChangeReason] as? UInt, raw == Raw.oldDeviceUnavailable else {
            return nil
        }
        self = .routeLost
    }

    // Apple's values, from `AVAudioSession.InterruptionType`, `.InterruptionOptions` and
    // `.RouteChangeReason`.
    enum Raw {
        static let interruptionBegan: UInt = 1
        static let interruptionEnded: UInt = 0
        static let shouldResume: UInt = 1
        static let newDeviceAvailable: UInt = 1
        static let oldDeviceUnavailable: UInt = 2
    }

    // The spelling the platform uses, written out so a host build can post it. On iOS the real
    // constants are used instead, so a wrong string here cannot reach a device;
    // `AudioSessionEventPlatformTests` compares each string with its constant on a simulator.
    enum Spelling {
        static let interruption = "AVAudioSessionInterruptionNotification"
        static let routeChange = "AVAudioSessionRouteChangeNotification"
        static let interruptionType = "AVAudioSessionInterruptionTypeKey"
        static let interruptionOptions = "AVAudioSessionInterruptionOptionKey"
        static let routeChangeReason = "AVAudioSessionRouteChangeReasonKey"
    }

    #if os(iOS)
    static let interruptionName = AVAudioSession.interruptionNotification
    static let routeChangeName = AVAudioSession.routeChangeNotification
    fileprivate enum Keys {
        static let interruptionType = AVAudioSessionInterruptionTypeKey
        static let interruptionOptions = AVAudioSessionInterruptionOptionKey
        static let routeChangeReason = AVAudioSessionRouteChangeReasonKey
    }
    #else
    static let interruptionName = Notification.Name(Spelling.interruption)
    static let routeChangeName = Notification.Name(Spelling.routeChange)
    fileprivate enum Keys {
        static let interruptionType = Spelling.interruptionType
        static let interruptionOptions = Spelling.interruptionOptions
        static let routeChangeReason = Spelling.routeChangeReason
    }
    #endif
}
