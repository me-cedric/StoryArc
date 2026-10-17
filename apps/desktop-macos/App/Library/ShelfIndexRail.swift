import DesignSystem
import SwiftUI

/// The index down the trailing edge of a long shelf: one button per letter.
///
/// `library-browsing`, *An index down the side of a long shelf* and *The index without
/// sight*. On a Mac a pointer can hit a letter, so each letter is its own button rather than
/// the phone's scrubber; VoiceOver reads the rail as one named group, each entry as the
/// letter it moves to, and says where the shelf went once one is chosen. When the window is
/// too short for every letter, letters are dropped evenly, as `LibraryRail.collapsed` does on
/// iOS, and the first and last always stay.
struct ShelfIndexRail: View {
    static let width: CGFloat = 28
    static let entryHeight: CGFloat = 20

    @Environment(\.theme) private var theme

    let entries: [ShelfIndexEntry]
    let onChoose: (ShelfIndexEntry) -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(Self.collapsed(entries, toFit: geometry.size.height - 16)) { entry in
                    Button {
                        onChoose(entry)
                        AccessibilityNotification.Announcement(
                            String(localized: "desktop.library.index.moved \(entry.label)")
                        ).post()
                    } label: {
                        Text(verbatim: entry.label)
                            .scaledFont(.caption, weight: .semibold)
                            .frame(width: Self.width, height: Self.entryHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .help(Text("desktop.library.index.jump \(entry.label)"))
                    .accessibilityLabel(Text(verbatim: entry.label))
                }
            }
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("desktop.library.index"))
    }

    /// Every entry when they fit, else an even spread that keeps the first and the last.
    static func collapsed(_ entries: [ShelfIndexEntry], toFit height: CGFloat) -> [ShelfIndexEntry] {
        guard height > 0 else { return entries }
        let capacity = max(2, Int((height / entryHeight).rounded(.down)))
        guard entries.count > capacity else { return entries }
        var kept: [ShelfIndexEntry] = []
        var last = -1
        for slot in 0..<capacity {
            let index = slot * (entries.count - 1) / (capacity - 1)
            guard index != last else { continue }
            kept.append(entries[index])
            last = index
        }
        return kept
    }
}
