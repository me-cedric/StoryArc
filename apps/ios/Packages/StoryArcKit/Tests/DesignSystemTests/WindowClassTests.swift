import Testing

@testable import DesignSystem

/// What decides the layout, and — more to the point — what does not.
///
/// `native-experience` asks for a sidebar on a large screen and for a layout that
/// "reflows continuously" when the window is resized, and for an Android foldable to be
/// followed through folding, unfolding and the half-open posture. All four are the same
/// question if the only input is the window's width, and four different questions if a
/// device check creeps in. These tests exist to keep it the first kind.
///
/// Android's `WindowClassTest` asserts the same table against the same number.
@Suite("Window class")
struct WindowClassTests {

    @Test("A phone-width window gets one column")
    func narrowIsCompact() {
        // 440 is an iPhone 17 Pro Max in portrait; 320 is the narrowest thing iOS has
        // ever shipped. Neither has room for a sidebar and a legible cover beside it.
        #expect(StoryArcWindowClass.of(width: 320) == .compact)
        #expect(StoryArcWindowClass.of(width: 440) == .compact)
        #expect(StoryArcWindowClass.of(width: 599) == .compact)
    }

    @Test("A window at the threshold gets the sidebar, and one point below it does not")
    func thresholdIsInclusive() {
        #expect(StoryArcWindowClass.of(width: 599).showsSidebar == false)
        #expect(StoryArcWindowClass.of(width: 600).showsSidebar)
        #expect(StoryArcWindowClass.of(width: 600) == .expanded)
    }

    @Test("A tablet-width window gets the sidebar")
    func wideIsExpanded() {
        // 744 is an iPad mini in portrait, 1024 an iPad Pro in landscape, 2064 an iPad
        // Pro at full width on an external display.
        #expect(StoryArcWindowClass.of(width: 744) == .expanded)
        #expect(StoryArcWindowClass.of(width: 1024) == .expanded)
        #expect(StoryArcWindowClass.of(width: 2064) == .expanded)
    }

    @Test("A width that has not been measured yet is treated as narrow")
    func unmeasuredIsCompact() {
        // The first frame reports zero. The one-column layout fits every window and the
        // sidebar does not, so this is the safe way to be wrong for a frame.
        #expect(StoryArcWindowClass.of(width: 0) == .compact)
    }

    @Test("Only the width is asked, so a fold is an ordinary resize")
    func widthIsTheOnlyInput() {
        // The whole foldable requirement, stated as an assertion: an unfold is a window
        // that grew, a fold is one that shrank, and half-open is a window somewhere in
        // between. Nothing here can tell which of those happened, which is the point —
        // there is no posture branch to get wrong, and no device to check.
        let folded = StoryArcWindowClass.of(width: 400)
        let halfOpen = StoryArcWindowClass.of(width: 600)
        let unfolded = StoryArcWindowClass.of(width: 840)
        #expect(folded == .compact)
        #expect(halfOpen == .expanded)
        #expect(unfolded == .expanded)
        // And the same width always answers the same thing, whichever direction it
        // arrived from.
        #expect(StoryArcWindowClass.of(width: 400) == folded)
        #expect(StoryArcWindowClass.of(width: 840) == unfolded)
    }

    @Test("Exactly two classes, because there is exactly one layout decision")
    func twoClasses() {
        // A third class would need a third layout to justify it, and there is not one:
        // a window either has room for the sidebar or it does not.
        #expect(StoryArcWindowClass.allCases.count == 2)
        #expect(StoryArcWindowClass.allCases.filter(\.showsSidebar) == [.expanded])
    }

    @Test("The measure is capped above the width that earns a sidebar")
    func theMeasureIsWiderThanTheThreshold() {
        // Both numbers are layout constants and a test cannot see a rendered line length, so
        // what is pinned is the **relationship**, which is the part that can go wrong
        // silently: a cap at or below `sidebarWidthThreshold` would clamp content in the
        // narrowest window that has a sidebar at all, and the first sign of it would be a
        // screenshot nobody was looking at.
        #expect(StoryArcWindowClass.maxContentWidth > StoryArcWindowClass.sidebarWidthThreshold)
        #expect(StoryArcWindowClass.maxContentWidth == 720)
    }
}
