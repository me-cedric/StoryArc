internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// Searching inside the book, in the sheet the contents and the bookmarks already share.
//
// `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it".
// The third thing a reader opens this sheet to do is find a word, and it is the same question
// — where in this book do I go — so it is the same sheet.
//
// Android's `SearchInBook` draws the same rows.

/// The field, and what it found.
struct SearchInBook: View {
    @Environment(\.theme) private var theme

    let model: EpubReaderModel
    let onGo: (SearchMatch) -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query) {
                Text("search.field", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.bottom, StoryArcSpace.sm)
            .onChange(of: query) { _, new in
                Task { await model.search(new) }
            }

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.isSearching, model.matches.isEmpty {
            // Said while it runs, because a long book takes a moment and a list that is
            // merely empty looks like an answer.
            VStack(spacing: StoryArcSpace.sm) {
                ProgressView()
                Text("search.running", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty, model.matches.isEmpty {
            Text("search.none \(query)", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(StoryArcSpace.gutter)
        } else {
            List(model.matches) { match in
                Button { onGo(match) } label: { row(match) }
                    .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func row(_ match: SearchMatch) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            if !match.chapter.isEmpty {
                Text(match.chapter)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
            // The match is emboldened inside its own line rather than shown as a separate
            // field. A row that read "context / match / context" in three styles would be
            // three things to read; one sentence with the word standing out is one.
            Text(line(match))
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func line(_ match: SearchMatch) -> AttributedString {
        var line = AttributedString()
        if !match.snippet.before.isEmpty {
            line += AttributedString(match.snippet.before + " ")
        }
        var hit = AttributedString(match.snippet.match)
        hit.font = .body.bold()
        line += hit
        if !match.snippet.after.isEmpty {
            line += AttributedString(" " + match.snippet.after)
        }
        return line
    }
}
