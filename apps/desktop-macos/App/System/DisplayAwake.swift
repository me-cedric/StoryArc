import Foundation
import IOKit.pwr_mgt

/// The system calls behind a power assertion, behind a seam so a test can count them.
protocol PowerAssertions: Sendable {
    /// Creates an assertion that keeps the display awake. `nil` when the system refuses.
    func createDisplayAssertion(reason: String) -> UInt32?
    func release(_ id: UInt32)
}

/// IOKit's own calls.
struct IOKitPowerAssertions: PowerAssertions {
    func createDisplayAssertion(reason: String) -> UInt32? {
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return status == kIOReturnSuccess ? id : nil
    }

    func release(_ id: UInt32) {
        IOPMAssertionRelease(id)
    }
}

/// Keeps the display awake while a reader window is in front, and no longer.
///
/// `desktop-experience`, *Keeping the display awake while reading*: held while a reader
/// window is in front, released as soon as that ends, and a refusal is silent — reading
/// continues and nothing alarming is said. One assertion per app however many readers are
/// in front, because the system counts assertions and a Mac has one display to keep awake.
/// Task 2.22.
@MainActor
final class DisplayAwake {
    static let shared = DisplayAwake()
    static let reason = "StoryArc is showing a page"

    private let system: any PowerAssertions
    private var holders: Set<String> = []
    private(set) var assertion: UInt32?
    private(set) var refusals = 0

    init(system: any PowerAssertions = IOKitPowerAssertions()) {
        self.system = system
    }

    var isHeld: Bool { assertion != nil }

    /// A reader window came to the front.
    func hold(for window: String) {
        holders.insert(window)
        guard assertion == nil else { return }
        if let id = system.createDisplayAssertion(reason: Self.reason) {
            assertion = id
        } else {
            refusals += 1
        }
    }

    /// A reader window left the front, was hidden or closed.
    func release(for window: String) {
        holders.remove(window)
        guard holders.isEmpty, let id = assertion else { return }
        system.release(id)
        assertion = nil
    }
}
