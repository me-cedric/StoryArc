internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The one door out of the two-control chrome, and everything behind it.
//
// `comic-reader`, *Everything else is in the menu, and labelled*: "it offers the table of
// contents, bookmarks, search within the publication, reading themes and reader settings,
// each named in words rather than by icon alone … every control that was reachable from
// the reader before this change is reachable from here in one action."
//
// ``ReaderMenuEntry`` owns the five names and the order, and the comic reader's menu is
// built from the same type. A reader who learns the menu in one has learned it in the other
// — which was not true of five glass pills whose glyphs differed between the two readers.
//
// **One action is the load-bearing half.** The contents sheet already held four panels
// behind a segmented control; four rows that each open it on their own panel is the
// difference between one action and two.
//
// `ReaderMenuTests` asserts both halves.
extension EpubReaderView {

    /// The menu's contents, as the sheet presents them.
    var readerMenu: some View {
        NavigationStack {
            List {
                Section {
                    contentsRow
                    menuRow(.bookmarks) { openContents(on: .bookmarks) }
                    bookmarkThisPositionRow
                    menuRow(.search) { openContents(on: .search) }
                    // Not one of the five doors, and offered anyway: highlights and notes
                    // were reachable before this change, from the same sheet's fourth panel,
                    // and `comic-reader` requires everything that was reachable to stay
                    // reachable in one action.
                    Button { openContents(on: .annotations) } label: {
                        Label {
                            Text("annotations.title", bundle: .module)
                        } icon: {
                            Image(systemName: "highlighter")
                        }
                    }
                }

                Section {
                    menuRow(.themes) {
                        isShowingMenu = false
                        isShowingTheme = true
                    }
                    readAloudRow
                } header: {
                    Text(LocalizedStringKey(ReaderMenuEntry.settings.titleKey), bundle: .module)
                }
            }
            .navigationTitle(Text(verbatim: model.publication.displayTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { isShowingMenu = false } label: {
                        Text("epub.menu.done", bundle: .module)
                    }
                }
            }
        }
        // Half height by default so the page stays visible behind it, which is the same
        // reason the theme sheet is presented that way: every choice in here changes what
        // the page looks like.
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// One labelled row, named by the entry rather than by this file.
    func menuRow(_ entry: ReaderMenuEntry, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(entry.titleKey), bundle: .module)
            } icon: {
                Image(systemName: entry.systemImage)
            }
        }
    }

    /// The contents row: where the reader is, and where else they could be.
    ///
    /// One element, spoken once. The line is a second line of this row rather than a separate
    /// thing to swipe to, and `comic-reader` is explicit that "the text is what conveys the
    /// position".
    var contentsRow: some View {
        Button { openContents(on: .contents) } label: { progressRow }
            .accessibilityElement(children: .combine)
    }

    /// Marking this position, or unmarking it.
    ///
    /// One row, not an add beside a remove: `ebook-reader` marks a *position*, and a
    /// position is either marked or it is not. A glass pill whose filled and hollow
    /// bookmark glyphs were the only statement of which, until now.
    private var bookmarkThisPositionRow: some View {
        Button { Task { await model.toggleBookmark() } } label: {
            Label {
                Text(model.isPageBookmarked ? "bookmarks.remove" : "bookmarks.add", bundle: .module)
            } icon: {
                Image(systemName: model.isPageBookmarked ? "bookmark.fill" : "bookmark")
            }
        }
    }

    /// Starting and stopping the voice.
    ///
    /// Absent, not disabled, when the publication has no text Readium can extract.
    /// `ebook-reader` says a control a platform cannot honour is "absent rather than empty",
    /// and this app does not ship a button that does nothing.
    @ViewBuilder
    private var readAloudRow: some View {
        if model.canReadAloud {
            Button {
                if model.readAloud.isActive {
                    model.stopReadAloud()
                } else {
                    isShowingMenu = false
                    model.startReadAloud()
                }
            } label: {
                Label {
                    Text(model.readAloud.isActive ? "readaloud.stop" : "readaloud.start",
                         bundle: .module)
                } icon: {
                    Image(systemName: model.readAloud.isActive
                        ? "speaker.wave.2.fill"
                        : "speaker.wave.2")
                }
            }
        }
    }

    /// Opens the contents sheet on one of its four panels, with the menu out of the way.
    ///
    /// Two sheets cannot be presented from one view at once, so the menu closes first.
    private func openContents(on tab: ContentsTab) {
        contentsTab = tab
        isShowingMenu = false
        isShowingContents = true
    }
}
