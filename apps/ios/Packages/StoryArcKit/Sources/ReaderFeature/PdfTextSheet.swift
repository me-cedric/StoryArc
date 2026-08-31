internal import SwiftUI

internal import DesignSystem
internal import Formats
internal import StoryArcCore

// Where a reader goes looking inside a PDF: the search, the marks they made, and the
// document's own navigation.
//
// One sheet with three tabs rather than three controls in the chrome, because all three answer
// the same question — where in this publication do I go — and a reader who opened the wrong
// one would have to close it to ask again. The EPUB reader's sheet is built the same way for
// the same reason.
//
// Android's `PdfTextSheet` holds the same three tabs.

/// Which of the three the sheet is showing.
enum PdfTextTab: Hashable, CaseIterable {
    case search
    case marks
    case contents

    var titleKey: LocalizedStringKey {
        switch self {
        case .search: "reader.pdf.tab.search"
        case .marks: "reader.pdf.tab.marks"
        case .contents: "reader.pdf.tab.contents"
        }
    }
}

struct PdfTextSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: PdfTextModel
    /// Where to turn to. The page, because that is what a PDF locator names.
    let onGo: (Int) -> Void

    @State private var tab: PdfTextTab

    /// Which list the sheet opens on.
    ///
    /// The reader's menu has a row for bookmarks, one for search and one for contents, and
    /// `comic-reader` requires each to be "reachable from here in one action". A sheet that
    /// always opened on search would make two of the three rows cost two.
    init(model: PdfTextModel, opensOn tab: PdfTextTab = .search, onGo: @escaping (Int) -> Void) {
        self.model = model
        self.onGo = onGo
        _tab = State(initialValue: tab)
    }

    /// Contents only where there is one. `ebook-reader` asks for the publication's own
    /// navigation "to its full depth"; a PDF that carries none has no depth to show, and an
    /// empty tab would be a promise of something the file does not contain.
    private var tabs: [PdfTextTab] {
        PdfTextTab.allCases.filter { $0 != .contents || !model.outline.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if tabs.count > 1 {
                    Picker(selection: $tab) {
                        ForEach(tabs, id: \.self) { candidate in
                            Text(candidate.titleKey, bundle: .module).tag(candidate)
                        }
                    } label: {
                        Text("reader.pdf.tab", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, StoryArcSpace.gutter)
                    .padding(.bottom, StoryArcSpace.sm)
                }

                switch tab {
                case .search: PdfSearchList(model: model, onGo: go)
                case .marks: PdfMarkList(model: model, onGo: go)
                case .contents: PdfOutlineList(items: model.outline, onGo: go)
                }
            }
            .navigationTitle(Text("reader.pdf.find", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("reader.pdf.done", bundle: .module) }
                }
            }
        }
    }

    private func go(to page: Int) {
        onGo(page)
        dismiss()
    }
}

/// Searching inside the publication.
///
/// `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it".
/// The match is emboldened inside its own line rather than shown as a separate field — a row
/// that read "context / match / context" in three styles would be three things to read, and one
/// sentence with the word standing out is one.
struct PdfSearchList: View {
    @Environment(\.theme) private var theme

    let model: PdfTextModel
    let onGo: (Int) -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query) {
                Text("reader.pdf.search", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.bottom, StoryArcSpace.sm)
            .onChange(of: query) { _, now in
                Task { await model.search(now) }
            }

            if model.isSearching && model.matches.isEmpty {
                // Said while it runs, because a long document takes a moment and a list that
                // is merely empty looks like an answer.
                VStack(spacing: StoryArcSpace.sm) {
                    ProgressView()
                    Text("reader.pdf.search.running", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, model.matches.isEmpty {
                Text("reader.pdf.search.none", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(StoryArcSpace.gutter)
            } else {
                List {
                    ForEach(model.matches) { match in
                        Button { jump(to: match) } label: { row(match) }
                            .buttonStyle(.plain)
                    }
                    if model.isCapped {
                        // Stated rather than applied quietly: a truncated list that says it is
                        // truncated is still a list a reader can trust.
                        Text("reader.pdf.search.capped", bundle: .module)
                            .textRole(.caption)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func jump(to match: SearchMatch) {
        guard let page = model.page(of: match) else { return }
        onGo(page)
    }

    private func row(_ match: SearchMatch) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            if !match.chapter.isEmpty {
                Text(match.chapter)
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Text(line(of: match.snippet))
                .textRole(.footnote)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // One announcement rather than three: the snippet is one sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(match.chapter). \(match.snippet.line)"))
    }

    /// The whole line with the match standing out inside it.
    ///
    /// One attributed string rather than three `Text` views added together: a row that read
    /// "context / match / context" in three styles would be three things to read, and one
    /// sentence with the word emboldened is one.
    private func line(of snippet: SearchSnippet) -> AttributedString {
        var line = AttributedString(snippet.before.isEmpty ? "" : snippet.before + " ")
        var match = AttributedString(snippet.match)
        match.inlinePresentationIntent = .stronglyEmphasized
        line.append(match)
        if !snippet.after.isEmpty { line.append(AttributedString(" " + snippet.after)) }
        return line
    }
}

/// One row of the document's own navigation, already flattened.
///
/// Flattened rather than nested, and the reason is the requirement: `ebook-reader` asks for the
/// navigation "to its full depth", and a reader looking for chapter nine should see it without
/// opening chapter one first. Flattening it also makes the depth a number rather than a shape,
/// which is what lets the whole of it be asserted without a screen.
struct PdfOutlineRow: Identifiable, Equatable {
    let id: Int
    let title: String
    /// `nil` for an entry whose destination the file does not resolve.
    let page: Int?
    let depth: Int

    /// Every entry, in reading order, carrying how deep it sits.
    static func rows(of items: [PdfOutlineItem]) -> [PdfOutlineRow] {
        var rows: [PdfOutlineRow] = []
        append(items, depth: 0, into: &rows)
        return rows
    }

    private static func append(
        _ items: [PdfOutlineItem],
        depth: Int,
        into rows: inout [PdfOutlineRow]
    ) {
        for item in items {
            rows.append(
                PdfOutlineRow(
                    id: rows.count,
                    title: item.title,
                    page: item.pageIndex,
                    depth: depth
                )
            )
            append(item.children, depth: depth + 1, into: &rows)
        }
    }
}

/// The document's own navigation, to its full depth.
struct PdfOutlineList: View {
    let items: [PdfOutlineItem]
    let onGo: (Int) -> Void

    var body: some View {
        List(PdfOutlineRow.rows(of: items)) { row in
            Button {
                if let page = row.page { onGo(page) }
            } label: {
                Text(row.title)
                    .textRole(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, CGFloat(row.depth) * StoryArcSpace.md)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // A destination the file could not resolve is shown and refused rather than
            // hidden: the entry is part of the publication's navigation whether or not it
            // points anywhere this app can reach.
            .disabled(row.page == nil)
        }
        .listStyle(.plain)
    }
}
