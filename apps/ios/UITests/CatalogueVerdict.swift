import XCTest

/// What the catalogue's gate does with one finding of the platform audit.
enum CatalogueVerdict: Equatable {
    case fail
    /// A contrast finding on `knownContrastFaults`, by the element's name.
    case known(String)
    case report
}

/// Sorts one finding. A contrast finding fails when it names an element that is not a known
/// fault of this screen. Two kinds of contrast finding are reported and do not fail:
///
/// - one that names no element, because nobody can fix what it does not name;
/// - one on an element that the window cuts or that a bar covers (`bars`). The audit then
///   measures the text through the bar's glass or against the screen edge, and the reader
///   scrolls the text out from under the bar to read it.
@MainActor
func catalogueVerdict(
    for issue: XCUIAccessibilityAuditIssue,
    on screen: String,
    window: CGRect? = nil,
    bars: [CGRect] = [],
    known: [KnownContrastFault] = knownContrastFaults
) -> CatalogueVerdict {
    switch issue.auditType {
    case .hitRegion, .sufficientElementDescription:
        return .fail
    case .contrast:
        guard let element = issue.element else { return .report }
        let frame: CGRect = element.frame
        if let window, !window.contains(frame) { return .report }
        if bars.contains(where: { $0.intersects(frame) }) { return .report }
        let name: String = element.label.isEmpty ? element.identifier : element.label
        let isKnown: Bool = known.contains { $0.screen == screen && $0.element == name }
        return isKnown ? .known(name) : .fail
    default:
        return .report
    }
}

/// A contrast finding that stands for now, on one screen of the catalogue, with its reason.
///
/// `screen` is the name a test passes to `auditCatalogue`. `element` is the label of the element
/// that the audit names, or its identifier when it has no label. The Android checks in
/// `:core:snapshots` keep the same kind of list (`KnownFault`).
///
/// A steady fault must occur on every run, or its test fails, so the list drains: fix the fault,
/// then remove its entry. A fault that is not steady (`isSteady: false`) is one that the platform
/// audit names on some runs and not on others, for the same screen. It does not fail when it is
/// absent, and its reason says why it comes and goes.
struct KnownContrastFault {
    let screen: String
    let element: String
    let why: String
    let isSteady: Bool

    init(screen: String, element: String, why: String, isSteady: Bool = true) {
        self.screen = screen
        self.element = element
        self.why = why
        self.isSteady = isSteady
    }
}

private let footer = """
    A system section footer or header: the system's secondary label on the grouped background \
    of the sheet, about 3.9 to 1 on the drawn frame. One text style for the 21 footers and 25 \
    headers of the app is a change of its own.
    """

private let glassProminent = """
    The onAccent label on the accent fill of a glass-prominent button, about 4.9 to 1 on the \
    drawn frame. The audit measures the glass highlight of the fill.
    """

private let aboveTheTabBar = """
    About 6 to 1 on the drawn frame. The audit names it in the band just above the tab \
    bar, where the scroll edge effect changes what is behind the text.
    """

private let showOnTheNotice = """
    The accent text of the skipped notice on its opaque surface, about 6 to 1 on the drawn \
    frame. The audit names it on some runs and not on others: on 2026-10-10 two clean runs \
    named it on different screens of the three that show the notice.
    """

private let coverAndTitle = """
    The element is a cover without art and its title together. The audit compares the title \
    with the cover's colour in the same frame. The title is the primary text colour on the \
    page. In the order of the CI job on 2026-10-10 (iOS 26.5) Home showed other cards first, \
    and the audit did not name it.
    """

private let underTheCheckedNotice = """
    A title in the primary text colour, in the band just above the tab bar. The scroll edge \
    effect fades the band, and the "Libraries checked just now" notice covers part of it for a \
    few seconds after launch. Which title sits there depends on what the runs before it left \
    on the screen, so the audit names it on some runs and not on others.
    """

/// Each entry was measured on two clean runs on 2026-10-10 (iPhone 17 Pro, iOS 26.2, with the
/// seed and the corpus that `pnpm test:ios:audit` writes). The entries for "Foreign Codec" and
/// for "Harbour Lights" on Search were measured on 2026-10-10 in the order of the CI job (iPhone
/// 17 Pro, iOS 26.5): the seed, the UI audit walks, then the corpus.
let knownContrastFaults: [KnownContrastFault] = [
    KnownContrastFault(screen: "01 Home", element: "Broken Transfer", why: coverAndTitle, isSteady: false),
    KnownContrastFault(
        screen: "05 Publication page", element: "On this device, readable with no network", why: aboveTheTabBar
    ),
    KnownContrastFault(screen: "06 Publication page without a cover", element: "Read", why: glassProminent),
    KnownContrastFault(screen: "08 Compact player bar", element: "Listen", why: glassProminent),
    KnownContrastFault(
        screen: "09 Settings root",
        element: "Reset settings",
        why: """
            The system's destructive red on a white row, about 3.6 to 1. The system draws the \
            destructive role of the button.
            """
    ),
    KnownContrastFault(
        screen: "10 Sources list",
        element: "Move your libraries, shelves, settings and reading positions to another device as one file.",
        why: footer
    ),
    KnownContrastFault(screen: "10 Sources list", element: "Sync", why: footer),
    KnownContrastFault(
        screen: "10 Sources list",
        element: "Keep your reading positions, shelves and settings the same on all your devices, "
            + "through a place you choose.",
        why: footer
    ),
    KnownContrastFault(
        screen: "10 Sources list",
        element: "Every device you want to keep the same must be able to reach this place.",
        why: footer
    ),
    KnownContrastFault(
        screen: "10 Sources list",
        element: "StoryArc syncs when you open the app and when you close a book. In the background, "
            + "iOS can let StoryArc sync from time to time, or never.",
        why: footer
    ),
    KnownContrastFault(
        screen: "12 Sync section",
        element: "Move your libraries, shelves, settings and reading positions to another device as one file.",
        why: footer
    ),
    KnownContrastFault(screen: "12 Sync section", element: "Sync", why: footer),
    KnownContrastFault(
        screen: "12 Sync section",
        element: "Keep your reading positions, shelves and settings the same on all your devices, "
            + "through a place you choose.",
        why: footer
    ),
    KnownContrastFault(
        screen: "12 Sync section",
        element: "Every device you want to keep the same must be able to reach this place.",
        why: footer
    ),
    KnownContrastFault(
        screen: "12 Sync section",
        element: "StoryArc syncs when you open the app and when you close a book. In the background, "
            + "iOS can let StoryArc sync from time to time, or never.",
        why: footer
    ),
    KnownContrastFault(
        screen: "13 Downloads and storage",
        element: "This counts what StoryArc downloaded or imported. A folder you added is readable without "
            + "a network too, and its files are not counted here. Everything on this device, and anything "
            + "still arriving, is in Downloads.",
        why: footer
    ),
    KnownContrastFault(screen: "14 Search at rest", element: "M4B", why: aboveTheTabBar),
    KnownContrastFault(
        screen: "03 Library grid, with the rail when the shelf has one",
        element: "Show",
        why: showOnTheNotice,
        isSteady: false
    ),
    KnownContrastFault(screen: "04 Library list", element: "Show", why: showOnTheNotice, isSteady: false),
    KnownContrastFault(
        screen: "04 Library list", element: "Foreign Codec", why: underTheCheckedNotice, isSteady: false
    ),
    KnownContrastFault(
        screen: "14 Search at rest", element: "Harbour Lights", why: underTheCheckedNotice, isSteady: false
    ),
    KnownContrastFault(
        screen: "18 Library with the skipped notice", element: "Show", why: showOnTheNotice, isSteady: false
    ),
]
