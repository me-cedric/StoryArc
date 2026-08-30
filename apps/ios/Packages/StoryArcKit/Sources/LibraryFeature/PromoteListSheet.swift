internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Choosing a server for a local reading list, and being told what the copy will do.
///
/// `collections-and-reading-lists` asks the app to "offer to copy it" and to state "which
/// entries cannot be included because they do not exist on that server". Both happen here,
/// before anything is sent: the plan is on the screen the reader confirms from, so nothing
/// about the copy is discovered afterwards.
///
/// Only servers that answered the reading-list question are offered — see
/// ``ServerShelves/listCapable``. A server that is not there is not on this screen, which is
/// how the offer stays honest while the network is not.
struct PromoteListSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: LibraryModel
    let list: ReadingList
    /// Handed the undo when something reached the server, so the ten seconds are counted by
    /// the same bar every other bulk action uses.
    let onCopied: (BulkUndo) -> Void

    @State private var chosen: KavitaPage?
    @State private var isCopying = false
    @State private var hasFailed = false

    /// What each server would take, worked out once and keyed by the server.
    ///
    /// Once rather than per redraw: every answer reads the origin note off disk for every
    /// entry, and a computed property would do that on each pass over the sheet. The copy
    /// works the plan out again for itself, so what is sent can never be the stale copy of
    /// what was shown.
    @State private var plans: [String: ListPromotion] = [:]

    var body: some View {
        NavigationStack {
            List {
                servers

                if let chosen, let promotion = plans[chosen.id] {
                    plan(on: chosen, promotion: promotion)
                }
            }
            .task {
                plans = Dictionary(
                    uniqueKeysWithValues: model.listCapableServers.map {
                        ($0.id, model.promotion(of: list, to: $0))
                    }
                )
            }
            .navigationTitle(Text("shelves.promote.title", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("shelves.cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await copy() } } label: {
                        Text("shelves.promote.copy", bundle: .module)
                    }
                    .disabled(isCopying || !canCopy)
                }
            }
            .alert(
                Text("shelves.promote.failed", bundle: .module),
                isPresented: $hasFailed
            ) {
                Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            }
        }
    }

    /// Whether the chosen server could take anything at all.
    private var canCopy: Bool {
        guard let chosen else { return false }
        return plans[chosen.id]?.isPossible == true
    }

    @ViewBuilder
    private var servers: some View {
        Section {
            ForEach(model.listCapableServers) { server in
                Button {
                    chosen = server
                } label: {
                    HStack(spacing: StoryArcSpace.md) {
                        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                            Text(server.title)
                                .foregroundStyle(theme.palette.textPrimary)
                            // The count is on the row itself, so the choice between two
                            // servers is made on what each of them can actually take. Absent
                            // until it is known rather than shown as nought: a count that
                            // corrects itself a frame later is a count nobody can trust.
                            if let promotion = plans[server.id] {
                                Text(
                                    "shelves.promote.entries \(promotion.copying.count) \(promotion.total)",
                                    bundle: .module
                                )
                                .textRole(.footnote)
                                .foregroundStyle(theme.palette.textSecondary)
                            }
                        }

                        Spacer(minLength: 0)

                        if chosen?.id == server.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.palette.accent)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("shelves.promote.choose", bundle: .module)
        }
    }

    @ViewBuilder
    private func plan(on server: KavitaPage, promotion: ListPromotion) -> some View {
        Section {
            if promotion.isPossible {
                Text("shelves.promote.copying \(promotion.copying.count)", bundle: .module)
                    .foregroundStyle(theme.palette.textPrimary)
            } else {
                Text("shelves.promote.none \(server.title)", bundle: .module)
                    .foregroundStyle(theme.palette.textPrimary)
            }

            if !promotion.leftBehind.isEmpty {
                Text("shelves.promote.leftBehind \(promotion.leftBehind.count)", bundle: .module)
                    .foregroundStyle(theme.palette.textPrimary)

                // Why, in the reader's terms rather than the protocol's: the app does not
                // upload, so a publication the server has never seen cannot join its list.
                Text("shelves.promote.why \(server.title)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)

                // Named, not counted. A reader can only act on a title.
                ForEach(promotion.leftBehind, id: \.self) { entry in
                    Text(title(of: entry))
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }
        } header: {
            Text("shelves.promote.plan", bundle: .module)
        }
    }

    private func title(of entry: String) -> String {
        model.publications.first { $0.id == entry }?.displayTitle ?? entry
    }

    private func copy() async {
        guard let chosen, !isCopying else { return }
        isCopying = true
        defer { isCopying = false }
        guard let undo = await model.promote(list, to: chosen) else {
            hasFailed = true
            return
        }
        onCopied(undo)
        dismiss()
    }
}
