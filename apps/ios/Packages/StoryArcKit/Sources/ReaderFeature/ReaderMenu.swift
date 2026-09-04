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
// **One action is the load-bearing half.** Eleven icons became five doors, and a door that
// leads to another door would have traded recognition for depth. So the pickers are *in*
// the menu with their current value beside them, rather than behind a Settings row: a
// reader who opens the menu to change the reading direction changes it there. What opens a
// surface of its own is what already was one — the thumbnail browser, the PDF text sheet,
// the adjustment controls.
//
// `ReaderMenuTests` asserts both halves: that each of ``ReaderMenuEntry``'s rows is here
// with its own name, and that every control the chrome used to draw is still reachable.
//
// Rows a publication cannot honour are absent rather than disabled, which is the rule this
// reader already applied to the buttons these rows replace: a scan carries no text, so it
// offers no search row instead of a row that opens an empty box.
//
// The members are internal rather than private because `ReaderView.body` is in another
// file, and a `private` member of an extension cannot be reached from it.
extension ReaderView {

    /// The menu's contents, as the sheet presents them.
    var readerMenu: some View {
        NavigationStack {
            List {
                Section {
                    contentsRow

                    // `comic-reader`: the slider is offered "where pages are the unit a
                    // reader moves in". One page is not a unit anybody moves in.
                    if model.pages.count > 1 {
                        pageSliderRow
                    }
                }

                Section {
                    // Marks and search both live in the PDF text sheet, which opens on the
                    // tab the row names — that is what makes each of them one action rather
                    // than two. Absent for a comic and for a scan: `ebook-reader` hides a
                    // text-dependent control rather than disabling it, and there is no text
                    // layer to search.
                    if pdfText != nil {
                        menuRow(.bookmarks) { openText(on: .marks) }
                        menuRow(.search) { openText(on: .search) }
                    }

                    menuRow(.themes) {
                        isShowingMenu = false
                        isAdjusting = true
                    }
                }

                chapterSection

                Section {
                    settingsRows
                } header: {
                    Text(LocalizedStringKey(ReaderMenuEntry.settings.titleKey), bundle: .module)
                }

                skippedSection
            }
            // The whole menu's words, on a material the page tints — see
            // ``ReaderMenuOnGlassTests``. `.plain` is what stops each row's label taking the
            // environment tint, which `ThemeResolver` sets to `theme.accent`: nine accent
            // rows on glass that had picked up a salmon page is what the September sweep
            // photographed, and it named this sheet the first thing a design reviewer should
            // look at. `storyArcGlassText` is what they state instead — a hierarchical style
            // while the material is live, the palette's own neutral once Reduce Transparency
            // or Increase Contrast has made the ground knowable again.
            //
            // On the list rather than on each row, deliberately. `GlassIsUntintedTests`
            // exists because a rule written in one file was reintroduced at five call sites
            // that never opened it, and a menu grows rows.
            .buttonStyle(.plain)
            .storyArcGlassText(.primary)
            .navigationTitle(Text(verbatim: model.publication.displayTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { isShowingMenu = false } label: {
                        Text("reader.menu.done", bundle: .module)
                    }
                }
            }
        }
        // Half height by default so the page stays visible behind it: every choice in here
        // changes what the page looks like, and `comic-reader` asks for the chrome to float
        // over the page rather than replace it.
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// The thumbnail browser, on its own surface.
    ///
    /// `comic-reader`: "every page is shown in a scrollable strip with the current page
    /// marked, and tapping one jumps to it". It was drawn over the page with the chrome
    /// behind it; a sheet is where the same strip goes now that the chrome is two buttons.
    var thumbnailSheet: some View {
        NavigationStack {
            ScrollView {
                ThumbnailStrip(model: model, currentIndex: model.currentIndex) { index in
                    // A jump, like the slider's: it leaves the same mark, so the way back
                    // from a mis-tap in a three-hundred-page strip is one control.
                    jump(to: index)
                    isBrowsingThumbnails = false
                }
            }
            .navigationTitle(Text(LocalizedStringKey(ReaderMenuEntry.contents.titleKey), bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { isBrowsingThumbnails = false } label: {
                        Text("reader.menu.done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// One labelled row, named by the entry rather than by this file.
    ///
    /// ``ReaderMenuEntry`` owns the five names and their order, so both readers open the
    /// same menu and neither can quietly rename a row.
    func menuRow(_ entry: ReaderMenuEntry, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(entry.titleKey), bundle: .module)
            } icon: {
                Image(systemName: entry.systemImage)
            }
        }
    }

    /// Opens the PDF text sheet on one of its tabs, with the menu out of the way.
    ///
    /// Two sheets cannot be presented from one view at once, so the menu closes first. The
    /// tab is what turns "search" and "bookmarks" into two rows that each take one action
    /// rather than one row and a segmented control to hunt through.
    private func openText(on tab: PdfTextTab) {
        findingTab = tab
        isShowingMenu = false
        isFindingText = true
    }

    /// Moving between the publications of a series, when there are any.
    @ViewBuilder
    private var chapterSection: some View {
        if previousInSeries != nil || nextInSeries != nil {
            Section { chapterRow }
        }
    }

    /// How many entries the archive could not give us, when any.
    ///
    /// `publication-formats`: a damaged archive opens "whatever pages it can read and states
    /// how many were skipped". It was drawn over the page until now, which made it one more
    /// thing between the reader and the artwork; it is a fact about the file, and the menu is
    /// where this reader's facts live.
    @ViewBuilder
    private var skippedSection: some View {
        if model.skippedPageCount > 0 {
            Section {
                Text("reader.skipped \(model.skippedPageCount)", bundle: .module)
                    .textRole(.caption)
                    .storyArcGlassText(.secondary)
            }
        }
    }
}
