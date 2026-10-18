import AppKit
import DesignSystem
import Playback
import PlayerFeature
import StoryArcCore
import SwiftUI

/// The player window for an audiobook: the cover, the title and the chapter, the position
/// with its slider, skip back fifteen and forward thirty, play and pause, the chapters and the
/// speed. The session is `PlayerCentre.shared`, so closing or hiding the window changes
/// nothing about the audio: *The windows are hidden*, playback continues and the media keys
/// and the Now Playing panel still control it. Space toggles, the arrows skip. Task 4.7.
struct PlayerWindow: View {
    @Environment(\.theme) private var theme

    let target: ReaderTarget
    let library: MacLibrary
    private let centre = PlayerCentre.shared

    @State private var scrubbing: Double?
    @State private var cover: CGImage?
    @FocusState private var isFocused: Bool

    private var publication: Publication {
        library.model.publications.first { $0.id == target.publicationID }
            ?? ReaderWindow.placeholder(for: target)
    }

    /// Whether this window's book is the one on the player.
    private var isMine: Bool { centre.book?.id == publication.id }

    var body: some View {
        VStack(spacing: 20) {
            artwork
            VStack(spacing: 4) {
                Text(publication.displayTitle).scaledFont(.title2, weight: .semibold).lineLimit(2)
                    .multilineTextAlignment(.center)
                if let chapter = isMine ? centre.book?.label.detail : nil {
                    Text(chapter).scaledFont(.body).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            if isMine { position }
            transport
            if isMine { settings }
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 520)
        .background(theme.palette.surfaceReader.ignoresSafeArea())
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press) }
        .navigationTitle(target.title)
        .background(WindowAccessor { ReaderWindowRegistry.attach($0, for: target) })
        .task { await open() }
        .onDisappear { close() }
    }

    // MARK: - Parts of the window

    private var artwork: some View {
        // `audio-playback`, *A publication with no cover*: the phones' artwork, so a coverless book draws the
        // kind over the format's name, as every other surface does.
        PlayerArtwork(format: publication.format, cover: cover)
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private var position: some View {
        VStack(spacing: 4) {
            if let total = centre.time.total {
                Slider(
                    value: Binding(get: { scrubbing ?? centre.time.elapsed }, set: { scrubbing = $0 }),
                    in: 0...max(1, total)
                ) {
                    Text("desktop.player.position")
                } onEditingChanged: { editing in
                    if !editing, let scrubbing { centre.scrub(to: scrubbing) }
                    scrubbing = nil
                }
                .labelsHidden()
                .controlSize(.large)
                .accessibilityLabel(Text("desktop.player.position"))
                .accessibilityValue(Text(PlaybackClock.spokenTime(scrubbing ?? centre.time.elapsed)))
            }
            HStack {
                Text(PlaybackClock.time(scrubbing ?? centre.time.elapsed)).monospacedDigit()
                Spacer()
                if let total = centre.time.total { Text(PlaybackClock.time(total)).monospacedDigit() }
            }
            .scaledFont(.caption).foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 28) {
            skipButton(.back, "gobackward.15", "desktop.player.skipBack")
            Button { centre.toggle() } label: {
                Image(systemName: isMine && centre.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .hitTarget(56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isMine && centre.isPlaying ? "desktop.player.pause" : "desktop.player.play"))
            .help(Text(isMine && centre.isPlaying ? "desktop.player.pause" : "desktop.player.play"))
            .disabled(!isMine)
            skipButton(.forward, "goforward.30", "desktop.player.skipForward")
        }
    }

    private func skipButton(_ direction: SkipDirection, _ symbol: String, _ key: LocalizedStringKey) -> some View {
        Button { centre.skip(direction) } label: {
            Image(systemName: symbol).font(.system(size: 24)).hitTarget(44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key))
        .help(Text(key))
        .disabled(!isMine)
    }

    private var settings: some View {
        HStack(spacing: 16) {
            ChaptersMenu(centre: centre).hitTarget(HitTarget.icon)
            SleepMenu(centre: centre).hitTarget(HitTarget.icon)
            Menu {
                ForEach(PlaybackSpeed.stops, id: \.rate) { speed in
                    Button { centre.setSpeed(speed) } label: { Text(Self.speedText(speed)) }
                }
            } label: {
                // The name carries the value: "Speed: 1×" is what the menu says and what
                // VoiceOver reads, as `audio-playback` asks for a control with a value.
                Label("desktop.player.speed.value \(Self.speedText(centre.speed))", systemImage: "gauge.with.needle")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .hitTarget(HitTarget.icon)
            .help(Text("desktop.player.speed"))
        }
    }

    static func partName(_ index: Int) -> String {
        String(localized: "desktop.player.part \(index + 1)", locale: .storyArc)
    }

    /// "1×", "1.5×": the value stated as a number, as `audio-playback` asks.
    static func speedText(_ speed: PlaybackSpeed) -> String {
        let number = speed.rate.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number)×"
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard isMine, press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        switch press.key {
        case .space: centre.toggle()
        case .leftArrow: centre.skip(.back)
        case .rightArrow: centre.skip(.forward)
        default: return .ignored
        }
        return .handled
    }

    // MARK: - Opening and closing

    private func open() async {
        isFocused = true
        ReaderWindows.shared.didOpen(target)
        MacPlayer.wire(progress: library.progress, library: library)
        cover = await library.model.cover(for: publication, maxPixelSize: 512)
        await MacPlayer.listen(to: publication, at: target.url, progress: library.progress)
    }

    /// The window goes; the session stays. The record is the centre's, written as it moves.
    private func close() {
        ReaderWindows.shared.didClose(target)
        ReaderWindowRegistry.detach(target)
    }
}
