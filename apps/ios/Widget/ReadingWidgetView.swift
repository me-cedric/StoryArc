import SwiftUI
import WidgetKit

import StoryArcCore

/// The widget's face: the cover above the title when small, beside it when medium.
///
/// A tap opens ``ReadingSnapshot/link(to:)``: the book, or the library when there is none.
struct ReadingWidgetView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemSmall {
                    small(snapshot)
                } else {
                    medium(snapshot)
                }
            } else {
                empty
            }
        }
        .widgetURL(ReadingSnapshot.link(to: entry.snapshot))
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("widget.empty")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func small(_ snapshot: ReadingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cover(snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(snapshot.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            progress(snapshot)
        }
    }

    private func medium(_ snapshot: ReadingSnapshot) -> some View {
        HStack(spacing: 12) {
            cover(snapshot)
                .aspectRatio(2 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                if let series = snapshot.series {
                    Text(series)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let percent = snapshot.percentRead {
                    Text("widget.percentRead \(percent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                progress(snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cover(_ snapshot: ReadingSnapshot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let url = entry.cover, let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(shape)
                .accessibilityLabel(Text(verbatim: snapshot.title))
        } else {
            // No cover yet, or none at all: a quiet well in the cover's place.
            shape
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "book.closed")
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func progress(_ snapshot: ReadingSnapshot) -> some View {
        if let fraction = snapshot.fractionRead {
            ProgressView(value: fraction)
        }
    }
}
