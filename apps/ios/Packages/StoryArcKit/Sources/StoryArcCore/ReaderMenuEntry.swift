/// What the reader's menu offers, in the order it offers it.
///
/// `comic-reader`, *Everything else is in the menu, and labelled*:
///
/// > **THEN** it offers the table of contents, bookmarks, search within the publication,
/// > reading themes and reader settings, each named in words rather than by icon alone
///
/// **Why this is a type and not five rows written twice.** Revealed chrome is now two
/// controls, and everything the eleven icons used to do arrives through one of these five
/// doors. Both readers open the same five, in the same order, with the same names — a
/// reader who learns the menu in a comic has learned it in a novel. Two independently
/// hand-written `List`s would drift the first time one of them gained a row, and the drift
/// would be invisible: nothing compiles across the two packages.
///
/// The order is the type's, not each menu's. It runs from *where am I* to *how does this
/// look* to *how does this behave*, which is the order a reader asks those questions in.
///
/// **Absent rather than disabled.** An entry a publication cannot honour is not offered:
/// a scan carries no text, so a comic reader that is images only offers no search row
/// rather than a row that opens an empty box. `ebook-reader` requires exactly that of a
/// control a platform cannot honour, and the readers already applied it to the buttons
/// this menu replaces. So ``allCases`` is what the menu may offer, never what it must.
public enum ReaderMenuEntry: String, CaseIterable, Sendable {
    /// Where the reader is, and everywhere else they could be.
    ///
    /// The publication's own navigation: a table of contents in a book, the thumbnail
    /// browser in a comic. This is also the row the coarse position is drawn behind —
    /// see `comic-reader`'s *Where the reader is, at a glance*.
    case contents

    /// The positions the reader marked, and the marking of this one.
    case bookmarks

    /// Finding words inside this publication.
    case search

    /// The reading themes, which is the surface that then splits in two.
    case themes

    /// How this publication behaves: direction, fit, transition, and the rest.
    case settings

    /// The string key naming this row, resolved in each feature module's own catalogue.
    ///
    /// The key rather than a `LocalizedStringKey`: this target has no string catalogue and
    /// should not gain one for five words. Each reader looks the key up in `.module`,
    /// which is where its own translations already live.
    public var titleKey: String { "reader.menu.\(rawValue)" }

    /// The SF Symbol beside the words. Beside, never instead of — the whole point of the
    /// menu is that these five are read rather than recognised.
    public var systemImage: String {
        switch self {
        case .contents: "list.bullet"
        case .bookmarks: "bookmark"
        case .search: "magnifyingglass"
        case .themes: "textformat"
        case .settings: "slider.horizontal.3"
        }
    }
}
