internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The whole preview: one section per line of the plan, in the order the plan gives them.
struct ImportPreviewList: View {
    let lines: [ImportPreviewLine]

    var body: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            ImportPreviewLineView(line: line)
        }
    }
}

/// One line of the import preview, drawn as a section: a sentence, and the names it counts.
///
/// The words are four languages' business, and the values come from
/// ``LibraryImportPlan/previewLines``, so what is drawn is what the plan holds. Android's
/// `ImportPreviewLineRows` draws the same lines in the same order.
struct ImportPreviewLineView: View {
    let line: ImportPreviewLine

    @Environment(\.theme) private var theme

    var body: some View {
        switch line {
        case let .certificatePins(pins): pinsSection(pins)
        case let .sourcesToAdd(names):
            section(names) { Text("transfer.line.sources \(names.count)", bundle: .module) }
        case let .sourcesNeedingSignIn(names):
            section(names) { Text("transfer.line.signIn \(names.count)", bundle: .module) }
        case let .shelvesToAdd(names):
            section(names) { Text("transfer.line.shelves \(names.count)", bundle: .module) }
        case let .shelvesMerged(shelves): mergedSection(shelves)
        case let .progress(add, merge): progressSection(add: add, merge: merge)
        case let .themes(count):
            Section { Text("transfer.line.themes \(count)", bundle: .module) }
        case let .covers(count):
            Section { Text("transfer.line.covers \(count)", bundle: .module) }
        case .settingsChange:
            Section { Text("transfer.line.settings", bundle: .module) }
        case .nothingNew:
            Section { Text("transfer.line.nothing", bundle: .module) }
        }
    }

    private func section<Header: View>(
        _ names: [String],
        @ViewBuilder header: () -> Header
    ) -> some View {
        Section {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in Text(name) }
        } header: {
            header()
        }
    }

    /// A change to what the app trusts, so it is flagged apart from the changes to what the
    /// reader owns and explained under the list.
    private func pinsSection(_ pins: [CertificatePinNotice]) -> some View {
        Section {
            ForEach(pins, id: \.host) { PinRow(pin: $0) }
        } header: {
            Label {
                Text("transfer.line.pins", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } footer: {
            Text("transfer.line.pins.note", bundle: .module)
        }
    }

    private func mergedSection(_ shelves: [ImportedShelf]) -> some View {
        Section {
            ForEach(Array(shelves.enumerated()), id: \.offset) { MergedShelfRow(shelf: $1) }
        } header: {
            Text("transfer.line.merged \(shelves.count)", bundle: .module)
        }
    }

    private func progressSection(add: Int, merge: Int) -> some View {
        Section {
            if add > 0 { Text("transfer.line.progress.add \(add)", bundle: .module) }
            if merge > 0 { Text("transfer.line.progress.merge \(merge)", bundle: .module) }
        }
    }
}

/// A host that gains a pinned certificate, and the source it arrived with.
struct PinRow: View {
    let pin: CertificatePinNotice

    var body: some View {
        if let source = pin.sourceName {
            Text("transfer.line.pin \(pin.host) \(source)", bundle: .module)
        } else {
            Text("transfer.line.pin.alone \(pin.host)", bundle: .module)
        }
    }
}

/// A shelf on both sides, and how many members the import adds to it.
struct MergedShelfRow: View {
    let shelf: ImportedShelf

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Text(shelf.name)
            Text("transfer.line.merged.added \(shelf.membersAdded)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
