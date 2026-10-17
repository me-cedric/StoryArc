import Catalogue
import Foundation
import LibraryFeature
import Persistence
import StoryArcCore

/// The download queue on a Mac: StoryArcKit's shared `DownloadQueue`, the metered rule of
/// task 3.11 over it, and what a quit and the next launch owe it.
///
/// `desktop-experience`, *No presence when the app is closed*: a quit during a download says
/// first that the download pauses, pauses it with its partial file kept, and the next launch
/// resumes it; no notification is posted for a finished one. *Metered connections*: the
/// downloads the rule holds back wait, and say why in grey. Only what this type paused is
/// ever resumed by it: a pause the reader asked for stays a pause.
@MainActor
@Observable
final class MacDownloads {
    static let heldKey = "app.storyarc.mac.downloads.meteredHeld"
    static let pausedForQuitKey = "app.storyarc.mac.downloads.pausedForQuit"

    let queue: DownloadQueue
    let monitor: MeteredMonitor
    /// Paused by the metered rule, and released by it.
    private(set) var held: Set<Download.ID>
    /// Started by the reader's own hand on a metered link: the rule leaves these alone.
    private(set) var byHand: Set<Download.ID> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let wifiOnly: () -> Bool

    init(
        queue: DownloadQueue = .shared(),
        monitor: MeteredMonitor = MeteredMonitor(),
        defaults: UserDefaults = .standard,
        wifiOnly: @escaping () -> Bool = { MacSettings.shared.settings.downloadOverWifiOnly }
    ) {
        self.queue = queue
        self.monitor = monitor
        self.defaults = defaults
        self.wifiOnly = wifiOnly
        held = Set(defaults.stringArray(forKey: Self.heldKey) ?? [])
        monitor.onChange = { [weak self] in self?.reconsider() }
    }

    var downloads: [Download] { queue.library.downloads }
    var pending: [Download] { queue.library.pending }
    var finished: [Download] { queue.library.finished }

    /// Why a download waits, if the network is the reason.
    func reason(for download: Download) -> MeteredPolicy.Reason? {
        guard !download.state.isFinished else { return nil }
        return MeteredPolicy.reason(for: download.id, held: held, condition: monitor.condition)
    }

    /// Applies the metered rule to the queue as it stands. Called on every change of the
    /// connection or of the Wi-Fi-only setting, and after anything joins the queue.
    func reconsider() {
        let decision = MeteredPolicy.decide(
            downloads, held: held, byHand: byHand, wifiOnly: wifiOnly(), condition: monitor.condition
        )
        for id in decision.hold { queue.pause(id) }
        for id in decision.release { queue.resume(id) }
        held = held.union(decision.hold).subtracting(decision.release).subtracting(decision.forget)
        defaults.set(Array(held), forKey: Self.heldKey)
    }

    /// The reader's *Download Now* on a held row: theirs, so the rule lets it run.
    func startByHand(_ id: Download.ID) {
        byHand.insert(id)
        if held.remove(id) != nil { defaults.set(Array(held), forKey: Self.heldKey) }
        queue.resume(id)
    }

    /// Queues a catalogue entry the reader asked for, which counts as by hand.
    func enqueue(_ entry: OpdsEntry, using acquisition: OpdsAcquisition, sourceID: UUID?) {
        let id = queue.downloadID(for: entry.id, sourceID: sourceID)
        byHand.insert(id)
        queue.enqueue(entry, using: acquisition, sourceID: sourceID, overridingMeteredConnection: true)
        reconsider()
    }

    func pause(_ id: Download.ID) {
        queue.pause(id)
        forgetHold(id)
    }

    func resume(_ id: Download.ID) {
        forgetHold(id)
        queue.resume(id)
        reconsider()
    }

    func cancel(_ id: Download.ID) {
        forgetHold(id)
        queue.cancel(id)
    }

    func remove(_ id: Download.ID) {
        forgetHold(id)
        queue.remove(id)
    }

    private func forgetHold(_ id: Download.ID) {
        guard held.remove(id) != nil else { return }
        defaults.set(Array(held), forKey: Self.heldKey)
    }

    // MARK: - Quit and the next launch

    /// Whether a quit now would interrupt a transfer: something running, or queued and free
    /// to start. A download the rule holds is not running and is not asked about.
    var isTransferring: Bool {
        downloads.contains { $0.state == .running || ($0.state == .queued && !held.contains($0.id)) }
    }

    /// Pauses every transfer for the quit, keeping what arrived, and remembers which, so the
    /// next launch resumes them and not a download the reader paused.
    func pauseForQuit() {
        let interrupted = downloads.filter { $0.state.isActive && !held.contains($0.id) }.map(\.id)
        for id in interrupted { queue.pause(id) }
        let earlier = defaults.stringArray(forKey: Self.pausedForQuitKey) ?? []
        defaults.set(Array(Set(earlier + interrupted)), forKey: Self.pausedForQuitKey)
    }

    /// What the last quit paused, put back in the queue. Called once a launch.
    func resumeAfterLaunch() {
        let paused = defaults.stringArray(forKey: Self.pausedForQuitKey) ?? []
        defaults.removeObject(forKey: Self.pausedForQuitKey)
        for id in paused where queue.library[id] != nil { queue.resume(id) }
        reconsider()
    }
}
