internal import SwiftUI

internal import DesignSystem

/// The scan's own count and a way to stop it, drawn in the bottom strip once the shelf
/// already has rows on it.
///
/// ``ScanningView`` draws the same count, centred, but only while the shelf is still empty
/// — `LibraryContent`'s `shelfBody` never reached that branch once there was anything to
/// show. So a rescan, or a second folder added to a library that already had books, reported
/// no count of items found and offered no action to stop it. 10.6, 10.7.
struct ScanProgressNotice: View {
    let found: Int
    let cancel: () -> Void

    /// The count the strip draws, or `nil` when it has nothing to say about a scan. Only
    /// while the shelf has rows: an empty shelf draws ``ScanningView`` in its middle, and a
    /// second count with a second Cancel beneath it would say the same thing twice.
    nonisolated static func found(in state: LibraryScanState, shelfHasRows: Bool) -> Int? {
        guard shelfHasRows, case .scanning(let found) = state else { return nil }
        return found
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    sentence
                    action
                }
            } else {
                HStack(spacing: StoryArcSpace.sm) {
                    sentence
                    Spacer(minLength: 0)
                    action
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StoryArcSpace.md)
        .padding(.vertical, StoryArcSpace.sm)
        .storyArcGlass()
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    private var sentence: some View {
        Text("library.scanning \(found)", bundle: .module)
            .textRole(.footnote)
            .storyArcGlassText()
            .monospacedDigit()
    }

    private var action: some View {
        Button(action: cancel) {
            Text("library.scan.cancel", bundle: .module)
                .textRole(.footnote)
        }
    }
}
