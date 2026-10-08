internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The index itself, down the trailing edge of the shelf: **one scrubber**.
///
/// `close-the-audited-gaps` 24.6, decision O23. The rail used to be twenty-seven buttons of
/// 22 points, each too small to hit. It is one hit region now, ``LibraryRail/hitWidth`` wide
/// and as tall as the letters: a tap or a drag along it chooses the letter under the finger, ticks once
/// for each new letter, and names the letter in a bubble beside the finger. Every letter
/// stays drawn while the space allows (``LibraryRail/collapsed(_:toFit:entryHeight:)``), and
/// ``RailScrub`` reads the finger against all of them regardless.
///
/// `library-browsing`'s *The index without sight* is why the accessibility lines are what
/// they are:
///
/// - the rail is one element named *Alphabetical index*, announced once,
/// - it is **adjustable**: VoiceOver's swipe up and down steps to the next and the previous
///   letter and says which one it is on, which is the step-by-step control the scrub has
///   instead of twenty-seven buttons,
/// - and every letter is also a named *Jump to X* action, for a reader who knows the one
///   they want.
///
/// Nothing here is the only statement of anything: the shelf's own section headings say the
/// same thing in the content. Android's `IndexRail` is the twin.
struct IndexRail: View {

    /// How much of the shelf's width the rail takes, which is the hit region.
    ///
    /// Stated rather than measured, because the shelf has to reserve it *before* the rail is
    /// laid out: the rail is an `.overlay(alignment: .trailing)`, so a shelf that did not
    /// inset itself drew its last column underneath it. Android's `RAIL_WIDTH` is the twin.
    static let width: CGFloat = LibraryRail.hitWidth

    private static let bubbleSize: CGFloat = 56

    @Environment(\.theme) private var theme

    let entries: [RailEntry]
    /// Where a chosen letter sends the shelf.
    let onChoose: (RailEntry) -> Void

    @State private var scrub = RailScrub()
    @State private var height: CGFloat = 0
    @State private var touchY: CGFloat = 0
    /// The letter last chosen, kept after the finger lifts: it is VoiceOver's value.
    @State private var chosen: Int?

    /// **A `GeometryReader`, because ``LibraryRail/collapsed(_:toFit:entryHeight:)`` needs the
    /// height before it can draw.** Photographed in landscape on 2026-09-28: 27 entries of
    /// 22 pt wanting about 600 pt of a shelf shorter than that.
    var body: some View {
        GeometryReader { geometry in
            strip(for: LibraryRail.collapsed(entries, toFit: geometry.size.height - 2 * LibraryRail.inset))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func strip(for shown: [RailEntry]) -> some View {
        RailLetters(shown: shown)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .contentShape(.rect)
            .gesture(drag)
            .overlay(alignment: .topLeading) { bubble }
            .storyArcFeedback(.selection, trigger: scrub.current, when: { $0 != nil })
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("library.rail")
            .accessibilityLabel(Text("library.index", bundle: .module))
            .accessibilityValue(spokenValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: 1)
                case .decrement: step(by: -1)
                @unknown default: break
                }
            }
            .accessibilityActions {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { choose(index) } label: {
                        Text("library.index.jump \(entry.label)", bundle: .module)
                    }
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                touchY = drag.location.y
                guard let index = scrub.move(
                    to: drag.location.y, height: height, inset: LibraryRail.inset, count: entries.count
                ) else { return }
                choose(index)
            }
            .onEnded { _ in scrub.end() }
    }

    @ViewBuilder
    private var bubble: some View {
        if let index = scrub.current, entries.indices.contains(index) {
            Text(entries[index].label)
                .textRole(.title1)
                .foregroundStyle(theme.palette.textPrimary)
                .frame(width: Self.bubbleSize, height: Self.bubbleSize)
                .background(theme.palette.surfaceOverlay, in: .circle)
                .offset(
                    x: -(Self.bubbleSize + StoryArcSpace.sm),
                    y: min(max(0, touchY - Self.bubbleSize / 2), max(0, height - Self.bubbleSize))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var spokenValue: Text {
        guard let chosen, entries.indices.contains(chosen) else { return Text(verbatim: "") }
        return Text(verbatim: entries[chosen].label)
    }

    private func step(by delta: Int) {
        guard let next = RailScrub.step(from: chosen, by: delta, count: entries.count) else { return }
        choose(next)
    }

    private func choose(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        chosen = index
        onChoose(entries[index])
    }
}

/// The letters and the capsule behind them, ``LibraryRail/hitWidth`` wide.
///
/// Drawn and nothing else: the gesture and the accessibility are the rail's, so this is what
/// `HitRegionTests` measures to hold the 44 points.
struct RailLetters: View {

    @Environment(\.theme) private var theme

    let shown: [RailEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(shown) { entry in
                Text(entry.label)
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(width: 22, height: LibraryRail.entryHeight)
            }
        }
        // **The type is capped, because the box is.** Each entry declares a 22-point frame so
        // a shelf holding every letter fits one column. At the largest accessibility size the
        // letters grew and the frames did not, so they overlapped into one illegible vertical
        // smear -- photographed at `UICTContentSizeCategoryAccessibilityXXXL` on 2026-09-11.
        // Capping is what Apple's own section index does, and nothing is lost: the shelf's
        // section headings say the same thing at full size, and the rail is adjustable.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.vertical, LibraryRail.inset)
        .frame(width: LibraryRail.capsuleWidth)
        .background(theme.palette.surfaceOverlay, in: .capsule)
        .frame(width: LibraryRail.hitWidth)
    }
}
