public import SwiftUI

internal import DesignSystem

/// What changed in the version just installed, shown once and then dismissed.
///
/// **Drawn the way Apple draws it**, which is what the owner asked for: a large heading, a
/// short column of rows each carrying an icon, a heading and one sentence, and a single
/// action pinned at the foot. Four rows rather than a changelog — a reader who opens a
/// reading app is there to read, and `settings-and-about` says this "SHALL never let that
/// get in the way".
///
/// **The action is `Continue`, not `Done`, and it is the only one.** The requirement asks
/// that "one action dismisses it", and a sheet with a Continue *and* a Close is two ways to
/// do the same thing. Swiping it down is the platform's own second way and is not ours to
/// remove; it costs nothing here because the version was recorded before this was drawn —
/// see ``WhatsNew/onLaunch(store:)``.
///
/// **The rows scroll and the action does not.** `settings-and-about` at the largest
/// accessibility text size: "the screen scrolls if it must, and the dismissing action stays
/// reachable without scrolling past the content". A `safeAreaInset` is what holds that: the
/// button is outside the scroll view and the scroll view is inset by its height, so nothing
/// is drawn under it either.
public struct WhatsNewSheet: View {
    @Environment(\.theme) private var theme

    private let release: WhatsNewRelease
    private let onDismiss: () -> Void

    public init(release: WhatsNewRelease, onDismiss: @escaping () -> Void) {
        self.release = release
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
                    Text("whatsnew.title", bundle: .module)
                        .textRole(.display)
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("whatsnew.version \(release.version)", bundle: .module)
                        .textRole(.subheadline)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                WhatsNewNotes(notes: release.notes)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.top, StoryArcSpace.xxl)
            .padding(.bottom, StoryArcSpace.lg)
        }
        .background(theme.palette.surfaceCanvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: onDismiss) {
                Text("whatsnew.continue", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.lg)
            .background(.bar)
        }
    }
}

/// The same rows, every release of them, reached from About.
///
/// `settings-and-about`: what changed "is reachable from the About screen, along with the
/// entries for earlier versions", **and** "reaching it that way does not change what the app
/// considers seen". The second half is why this view takes a list of releases and nothing
/// else: there is no store here to write to. ``WhatsNewWiringTests`` is the tripwire that
/// keeps one from arriving.
///
/// One screen rather than a list of versions leading to a screen each. Two of these releases
/// will fit on a phone for years, and a reader who came here to re-read one sentence should
/// not have to guess which version it was in.
public struct WhatsNewHistory: View {
    @Environment(\.theme) private var theme

    private let releases: [WhatsNewRelease]

    public init(releases: [WhatsNewRelease] = WhatsNew.releases) {
        self.releases = releases
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.xxl) {
                ForEach(releases) { release in
                    VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                        Text("whatsnew.version \(release.version)", bundle: .module)
                            .textRole(.title3)
                            .foregroundStyle(theme.palette.textPrimary)
                        WhatsNewNotes(notes: release.notes)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(Text("whatsnew.about", bundle: .module))
    }
}

/// One release's rows, so the sheet and the About screen cannot draw them differently.
private struct WhatsNewNotes: View {
    @Environment(\.theme) private var theme

    let notes: [WhatsNewNote]

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
            ForEach(notes) { note in
                HStack(alignment: .top, spacing: StoryArcSpace.lg) {
                    // **A fixed column, which is the point of it.** The symbol carries no
                    // text, so it has nothing to say at a larger text size — and at the
                    // largest one a scaling icon takes a third of the line and squeezes the
                    // sentence beside it into a column of syllables. Android's row holds the
                    // same width in dp for the same reason, which Material states outright:
                    // do not resize a component that contains no text.
                    Image(systemName: note.symbolName)
                        .font(.system(size: iconPointSize))
                        .foregroundStyle(theme.palette.accent)
                        .frame(width: iconColumnWidth, alignment: .center)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(note.title, bundle: .module)
                            .textRole(.headline)
                            .foregroundStyle(theme.palette.textPrimary)
                        Text(note.body, bundle: .module)
                            .textRole(.subheadline)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Wide enough for the widest symbol drawn at ``iconPointSize``, and no wider.
    private var iconColumnWidth: CGFloat { 34 }
    private var iconPointSize: CGFloat { 26 }
}
