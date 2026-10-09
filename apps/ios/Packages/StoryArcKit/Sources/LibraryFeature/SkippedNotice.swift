internal import SwiftUI

internal import DesignSystem
internal import Formats

/// What the library says about the publications it could not open.
///
/// **This replaces `ScanSummary`, and every difference is a requirement.** That view was a
/// Liquid Glass capsule floating in a `safeAreaBar`, reading `library.skipped %lld`, on a
/// six-second `dwell` that removed it. `library-browsing`'s *What could not be opened*
/// forbids all three: the notice names a publication rather than counting it, "stays until
/// the reader dismisses it or resolves it", and "does not float over the shelf's content in
/// a way that obscures a cover".
///
/// So it is **inline above the shelf**, opaque, taking its own space. That is the whole of
/// not obscuring a cover: a translucent capsule over a grid of artwork obscures whatever
/// scrolls under it, which is what the removed view's own doc comment described happening
/// at the largest text size.
///
/// **No timer, and nothing that keeps one.** There is no `@State` for visibility here on
/// purpose: what is shown is a function of ``SkippedPublications/notice``, which is the
/// model's, so a redraw cannot lose it and a reader who dismissed it cannot have it come
/// back. The only local state is whether the list is open.
///
/// Android draws the same three states from `SkippedNotice`.
struct SkippedNotice: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let skipped: SkippedPublications
    let dismiss: () -> Void

    /// Whether the list is open. The only thing here a reader can change that the model
    /// does not already hold.
    @State private var isListShown = false

    var body: some View {
        content
            .sheet(isPresented: $isListShown) {
                SkippedList(entries: skipped.entries)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch skipped.notice {
        case .nothing:
            EmptyView()
        case let .one(name, reason):
            banner(sentence: Text("library.skipped.one \(name)", bundle: .module), reason: reason)
        case let .several(count):
            banner(sentence: Text("library.skipped \(count)", bundle: .module), reason: nil)
        case .reachable:
            // Dismissed, and the way back. `library-browsing`: "the list remains reachable
            // from the library, so a reader who dismissed it in the middle of something can
            // come back to it" — and "the count is not shown again for the same
            // publications", which is why this one carries no number.
            HStack {
                openReachableList
                Spacer(minLength: 0)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.xs)
        }
    }

    /// The notice in the iOS 26 idiom: a warning symbol, the sentence, a borderless *Show*
    /// and the system's own close button. No tinted capsule: that is Android's Material tonal
    /// button, and this platform draws a secondary action as plain tinted text.
    ///
    /// **The controls drop under the sentence at the accessibility text sizes, and a capture at
    /// the largest one is why.** At `accessibility-extra-extra-extra-large` the sentence takes
    /// three lines in half the window and a named control beside it is cut off. A control whose
    /// name is truncated is not the named control `library-browsing` asks for, and no unit test
    /// can see it, because the width that truncates it is the window's. At the ordinary sizes
    /// the sentence wraps beside the controls. `ViewThatFits` chose the stacked form for any
    /// long file name, because it measures a sentence on one line.
    private func banner(sentence: Text, reason: SkipReason?) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    HStack(alignment: .top, spacing: StoryArcSpace.sm) {
                        warning
                        message(sentence, reason: reason)
                        close
                    }
                    show
                }
            } else {
                HStack(spacing: StoryArcSpace.sm) {
                    warning
                    message(sentence, reason: reason)
                    show
                    close
                }
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, and this is the point of the view. The material this used to draw on let
        // the cover behind it through.
        .background(theme.palette.surfaceRaised)
    }

    /// Decoration: the sentence already says what failed, so a screen reader skips the symbol.
    private var warning: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(StoryArcColor.Status.danger)
            .accessibilityHidden(true)
    }

    private func message(_ sentence: Text, reason: SkipReason?) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            sentence
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textPrimary)
            // `publication-formats`' refusal, in the reader's language: the scan hands over a
            // case and `SkipReasonWords` says what it means. Shown here only when there is one
            // publication to attribute it to; several reasons belong in the list, where each
            // sits beside its own name.
            if let reason {
                reason.sentence
                    .textRole(.caption)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One stop for a screen reader rather than two, so the notice is announced once and
        // says both halves. `library-browsing`: "it is announced once, naming the publication
        // where there is one and the count where there are several".
        .accessibilityElement(children: .combine)
    }

    /// The way to the list, and it is a control with a name.
    ///
    /// `library-browsing`: "the way to the list is a control with a name, not the whole
    /// notice". Nothing here carries a tap gesture, which is what makes that true rather than
    /// merely stated: a banner that is itself a button is announced as one, and a reader who
    /// wanted to dismiss it opens a sheet instead.
    private var show: some View {
        Button { isListShown = true } label: {
            Text("library.skipped.show", bundle: .module)
                .textRole(.subheadline)
                .hitRegion()
        }
        .buttonStyle(.borderless)
    }

    /// The system's close button. Its role names it and draws it; the label is for a screen
    /// reader, which hears the same word the notice always used.
    private var close: some View {
        Button(role: .close, action: dismiss)
            .labelStyle(.iconOnly)
            .buttonStyle(HitRegionButtonStyle(.glass))
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("library.skipped.dismiss", bundle: .module))
    }

    /// What is left after a dismissal: no sentence, so the control carries the whole name.
    private var openReachableList: some View {
        Button { isListShown = true } label: {
            Label {
                Text("library.skipped.list", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .textRole(.footnote)
            .hitRegion(alignment: .leading)
        }
        .buttonStyle(.borderless)
    }
}

/// Every publication the library could not open, each with its own reason.
///
/// `library-browsing`: the notice "leads to a list naming each with its own reason", and
/// "the reasons are not merged: two files that failed differently say different things". A
/// list is what makes that visible — the notice above it can only carry one sentence, and
/// the count was what carrying none looked like.
struct SkippedList: View {
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.theme) private var theme

    let entries: [SkippedPublications.Entry]

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                    Text(entry.name)
                        .textRole(.body)
                        .foregroundStyle(theme.palette.textPrimary)
                    entry.reason.sentence
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                // One stop per publication, naming it and saying why. Two would make a
                // reader swipe twice per row to learn one fact.
                .accessibilityElement(children: .combine)
            }
            .navigationTitle(Text("library.skipped.list", bundle: .module))
            // Inline, because the large title truncated this one to *"What couldn’t be
            // open…"* on an iPhone at the default text size — a large title takes one line
            // and does not wrap.
            //
            // Guarded: this package builds for macOS too, so that the pure targets can be
            // tested on the host with no simulator (see `Package.swift`), and the modifier is
            // unavailable there. `pnpm test:ios` is what caught it — the simulator build had
            // been green for three captures.
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismissSheet() } label: {
                        Text("library.select.done", bundle: .module)
                    }
                }
            }
        }
    }
}
