public import StoryArcCore

/// The per-series reading-mode choices, split out of `ReaderModel.swift` at its line cap
/// (AGENTS.md §5) — D18 needed a stored `PlayerCentre` and a stored `VoiceStoppedNotice` in
/// the primary declaration, which is the one place a Swift extension cannot reach, so this
/// self-contained family of one-line setters is what moved to make room. Each goes through
/// ``ReaderModel/remember(_:)``, the one path that both reads and writes the shelf's settings;
/// nothing here needs more of `ReaderModel` than that and ``ReaderModel/settings``, both
/// already internal for ``ReaderMatte``'s ``ReaderModel/chooseMatte(_:)`` to reach the same way.
public extension ReaderModel {
    /// Chooses a transition, for this shelf, from now on.
    func choose(_ transition: PageTransition) {
        remember(settings.settingTransition(transition))
    }

    /// Overrides the scroll axis, which `page-transitions` requires to be possible.
    func choose(_ axis: ScrollAxis) {
        remember(settings.settingScrollAxis(axis))
    }

    /// Reads this shelf the other way round, from now on.
    func choose(_ direction: ReadingDirection) {
        remember(settings.settingReadingDirection(direction))
    }

    /// Shifts the spread pairing by one, or puts it back, for this shelf from now on.
    ///
    /// `comic-reader` asks for the offset "for publications whose cover throws the
    /// pairing off", and that is a fact about the series rather than about the reader —
    /// so it is remembered where the reading mode is, and issue two opens paired right.
    func chooseSpreadOffset(_ isOffset: Bool) {
        remember(settings.settingSpreadOffset(isOffset))
    }

    /// Shows or hides the line between pages in a continuous scroll.
    func choosePageSeparator(_ isShown: Bool) {
        remember(settings.settingPageSeparator(isShown))
    }

    /// Sizes the page a different way, for this shelf from now on.
    ///
    /// `comic-reader` requires the fit to persist "per series". It used to be one value
    /// for the whole library, so fit-to-width chosen for a manga changed how every other
    /// comic opened; it is now kept where the other six per-series reader choices are.
    func choose(_ fit: PageFit) {
        remember(settings.settingFit(fit))
    }
}
