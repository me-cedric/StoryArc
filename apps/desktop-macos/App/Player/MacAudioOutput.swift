import CoreAudio
import Foundation

/// Watches the Mac's default output device and says when it changes while a session runs (`audio-playback`,
/// *Headphones removed*). A Mac has no `AVAudioSession` route-change notice; when headphones are unplugged
/// or a Bluetooth pair drops, Core Audio moves the default output to the next device, and the sound would
/// follow to the speakers. The player pauses instead, as the phones do on `.oldDeviceUnavailable`.
@MainActor
final class MacAudioOutput {
    private let onChange: @MainActor () -> Void
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.changed() }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr else { return }
        listener = block
    }

    func stop() {
        guard let listener else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    /// The device changed: the player is told, once a change.
    func changed() { onChange() }
}
