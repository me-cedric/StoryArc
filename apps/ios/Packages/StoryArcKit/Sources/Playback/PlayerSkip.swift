public import Foundation

/// How far a skip moves, and who is told when it changes.
///
/// Its own file for the reason ``PlayerSleep`` has one: `PlayerCentre.swift` sits against
/// SwiftLint's 400-line cap, and the cap is pointing at a real seam — the centre owns *what is
/// playing*, and each control it offers owns its own rule.
public extension PlayerCentre {

    /// Sets how far a skip moves, and tells whoever wired ``onRememberSkip`` to keep it.
    ///
    /// **Global rather than per publication, which is where this differs from the speed.** A
    /// listener who wants ten seconds back wants it in every book: the reason to skip back is
    /// "I missed that sentence", and that reason does not change with the title. The speed does
    /// — a dense book is read slower than a familiar one — which is why that one is remembered
    /// per publication and offered as the series default and this one is not.
    func setSkipIntervals(_ intervals: SkipIntervals) {
        skipIntervals = intervals
        onRememberSkip?(intervals)
        // The lock screen states its own intervals, so it has to be told too — otherwise the
        // player says ten and the lock screen still says fifteen, which `audio-playback`'s
        // "stated on the control itself" makes a defect on two controls rather than one.
        platform?.skipIntervalsChanged(intervals)
    }
}
