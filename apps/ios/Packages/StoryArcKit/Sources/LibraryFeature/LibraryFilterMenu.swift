internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What the library is narrowed to.
///
/// `library-browsing`: the groups combine with AND, the active count is visible on
/// the control, and one action clears them all. None of that changed when the
/// groups went from two to seven — what changed is that each group is now a
/// submenu. A flat menu listing every publisher, genre and tag a real library holds
/// would run past the bottom of the screen long before the reader reached "Clear
/// filters", and the reader would have to scroll a menu to undo a mistake.
///
/// Split out of `LibraryBrowsingControls` for the same reason it grew: the menu is
/// now longer than the two controls it used to sit beside.
struct FilterMenu: View {
    let model: LibraryModel

    /// The download group, which is not on the query.
    ///
    /// ``DownloadFilter`` says why it is not: the query is the value both platforms encode,
    /// and a case added to it is a change to `StoryArcCore` and to Android's mirror. So the
    /// screen owns it and this menu is handed it, the way ``ScopeMenu`` is handed the
    /// availability axis.
    @Binding var downloads: DownloadFilter

    /// The primary axis, cleared with the filters and counted with none of them.
    ///
    /// See ``LibraryNarrowing/activeCount``: availability has a control of its own that states it
    /// while it is set, so it is not part of the badge — and *Clear filters* still puts it
    /// back, because a cleared shelf that is still showing only what is on this device is a
    /// shelf as empty as the reader found it.
    @Binding var availability: LibraryAvailability

    var body: some View {
        Menu {
            // First, as on Android, and for the reason its own `FilterSection` gives:
            // narrowing to one library is the newest of these groups and the one that
            // changed shape. It was a scope with a control of its own in the toolbar, which
            // silently narrowed the search as well and which a reader could be left in
            // without noticing. It is a filter now — cleared by the action that clears every
            // other filter, and counted in the same badge.
            libraries

            group("library.filter.readState", isActive: !model.query.readStates.isEmpty) {
                ForEach(ReadState.allCases, id: \.self) { state in
                    Toggle(isOn: readState(state)) {
                        Text(state.titleKey, bundle: .module)
                    }
                }
            }

            downloadState
            formats
            values("library.filter.language", languageNames, \.languages)
            values("library.filter.publisher", pairs(model.availablePublishers), \.publishers)
            values("library.filter.genre", pairs(model.availableGenres), \.genres)
            values("library.filter.tag", pairs(model.availableTags), \.tags)
            decades

            if narrowing.isActive {
                Divider()
                Button(role: .destructive, action: clear) {
                    Text("library.filter.clear", bundle: .module)
                }
            }
        } label: {
            // **The count is drawn now, and it used to be spoken only.** The comment this
            // replaced said a menu label "cannot carry" a badge, which is true of
            // `.badge(_:)` and not of the label's own content: a glyph and a number beside it
            // is a label like any other. So a reader who could not hear VoiceOver knew *that*
            // the shelf was narrowed — the funnel fills — and never by how much, on a screen
            // whose whole job is to show them a set they have narrowed. `design.md` forbids a
            // state carried by appearance alone, and one filter looked exactly like six.
            HStack(spacing: StoryArcSpace.hair) {
                Image(
                    systemName: narrowing.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                if narrowing.isActive {
                    // Monospaced digits so the toolbar item does not resize as the count
                    // crosses from one glyph width to another while a reader is using it.
                    Text(narrowing.activeCount, format: .number)
                        .monospacedDigit()
                }
            }
            // The words, for a reader who gets neither the glyph nor the digit.
            .accessibilityLabel(Text("library.filter", bundle: .module))
        }
        .accessibilityValue(
            narrowing.isActive
                ? Text("library.filter.active \(narrowing.activeCount)", bundle: .module)
                : Text(verbatim: "")
        )
    }

    /// Everything this control narrows by, and what it says about it.
    ///
    /// Not `model.query` alone: the library narrowing, the download group and the
    /// availability axis are kept in three places for three good reasons, and until
    /// ``LibraryNarrowing`` existed each call site joined them up for itself — which is how
    /// the count came to omit the one narrowing a reader could not otherwise see.
    private var narrowing: LibraryNarrowing {
        LibraryNarrowing(query: model.query, downloads: downloads, availability: availability)
    }

    /// One action, everything it undoes.
    private func clear() {
        let cleared = narrowing.cleared()
        model.query = cleared.query
        downloads = cleared.downloads
        availability = cleared.availability
    }

    // MARK: - Groups

    /// Which library, when there is more than one to choose between.
    ///
    /// A radio list rather than the checkboxes most groups use: the shelf shows one library
    /// or all of them, so ticking two answers would be the same as ticking neither. "Any
    /// library" is how the group is turned back off, which is the same act as unticking the
    /// last value anywhere else.
    @ViewBuilder
    private var libraries: some View {
        let offered = LibraryNarrowing.offeredLibraries(in: model.registry)
        if !offered.isEmpty {
            group("library.filter.library", isActive: narrowing.isScoped) {
                Picker(selection: scope) {
                    ForEach(offered, id: \.self) { scope in
                        name(of: scope).tag(scope)
                    }
                } label: {
                    Text("library.filter.library", bundle: .module)
                }
            }
        }
    }

    /// What one library is called in the group.
    ///
    /// "Any library" rather than "Everywhere" for the unnarrowed case: the word belongs to
    /// the availability axis in the control next door, and two rows reading "Everywhere" in
    /// one toolbar would be two different promises wearing one name.
    private func name(of scope: LibraryScope) -> Text {
        guard let name = model.registry.name(of: scope.sourceID) else {
            return Text("library.availability.from.all", bundle: .module)
        }
        return Text(name)
    }

    private var scope: Binding<LibraryScope> {
        Binding(get: { model.query.scope }, set: { model.query.scope = $0 })
    }

    /// One group of alternatives, and whether the reader has set any of them.
    ///
    /// The tick on the label is the only thing that says a collapsed group is
    /// narrowing the view. Without it the badge would report three active filters
    /// and the menu would look untouched.
    @ViewBuilder
    private func group(
        _ title: LocalizedStringKey,
        isActive: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            if isActive {
                Label { Text(title, bundle: .module) } icon: { Image(systemName: "checkmark") }
            } else {
                Text(title, bundle: .module)
            }
        }
    }

    /// Whether the app fetched it, per `library-browsing`'s *Filtering offline*.
    ///
    /// A radio list rather than the toggles most groups use, and for the reason the decade
    /// group is one: a publication is downloaded or it is not, so ticking both answers is
    /// the same as ticking neither. "Downloaded or not" is how the group is turned back
    /// off, and it is the group's own name because that is exactly what it shows.
    ///
    /// Always offered, unlike the groups below it. A library with nothing downloaded still
    /// answers "Not downloaded" usefully — that is the question asked the night before a
    /// journey — and an empty result to "Downloaded" is an answer rather than a dead end.
    @ViewBuilder
    private var downloadState: some View {
        group("library.filter.download", isActive: downloads.isActive) {
            Picker(selection: $downloads) {
                Text("library.filter.download", bundle: .module).tag(DownloadFilter.either)
                Text("library.filter.download.yes", bundle: .module).tag(DownloadFilter.downloaded)
                Text("library.filter.download.no", bundle: .module).tag(DownloadFilter.notDownloaded)
            } label: {
                Text("library.filter.download", bundle: .module)
            }
        }
    }

    /// Formats, named by the domain rather than by a string table: "CBZ" is "CBZ"
    /// in all four languages.
    @ViewBuilder
    private var formats: some View {
        if !model.availableFormats.isEmpty {
            group("library.filter.format", isActive: !model.query.formats.isEmpty) {
                ForEach(model.availableFormats, id: \.self) { value in
                    Toggle(isOn: format(value)) { Text(verbatim: value.displayName) }
                }
            }
        }
    }

    /// A group over values the publications themselves supply.
    ///
    /// Omitted entirely when the library holds none: an empty "Genre" submenu tells
    /// the reader nothing and costs a tap to find out.
    @ViewBuilder
    private func values(
        _ title: LocalizedStringKey,
        _ available: [FilterValue],
        _ facet: WritableKeyPath<LibraryQuery, Set<String>>
    ) -> some View {
        if !available.isEmpty {
            group(title, isActive: !model.query[keyPath: facet].isEmpty) {
                ForEach(available) { value in
                    Toggle(isOn: chosen(value.id, in: facet)) { Text(verbatim: value.label) }
                }
            }
        }
    }

    /// The year range, offered as the decades the library actually spans.
    ///
    /// A radio list rather than the toggles every other group uses, because a range
    /// is one answer and not a set of them. "Any year" is how it is turned back off
    /// — the same act as unticking the last value in any other group.
    @ViewBuilder
    private var decades: some View {
        if !model.availableDecades.isEmpty {
            group("library.filter.decade", isActive: model.query.years.isActive) {
                Picker(selection: decade) {
                    Text("library.filter.decade.any", bundle: .module).tag(Int?.none)
                    ForEach(model.availableDecades, id: \.self) { start in
                        Text("library.filter.decade \(start)", bundle: .module).tag(Int?.some(start))
                    }
                } label: {
                    Text("library.filter.decade", bundle: .module)
                }
            }
        }
    }

    // MARK: - Bindings

    private func readState(_ state: ReadState) -> Binding<Bool> {
        Binding(
            get: { model.query.readStates.contains(state) },
            set: { on in
                if on { model.query.readStates.insert(state) } else { model.query.readStates.remove(state) }
            }
        )
    }

    private func format(_ value: PublicationFormat) -> Binding<Bool> {
        Binding(
            get: { model.query.formats.contains(value) },
            set: { on in
                if on { model.query.formats.insert(value) } else { model.query.formats.remove(value) }
            }
        )
    }

    /// Reads and writes the live query rather than a captured copy: a menu stays
    /// open across several taps, and a set captured when it was built would undo
    /// the tap before last.
    private func chosen(
        _ value: String, in facet: WritableKeyPath<LibraryQuery, Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { model.query[keyPath: facet].contains(value) },
            set: { on in
                if on {
                    model.query[keyPath: facet].insert(value)
                } else {
                    model.query[keyPath: facet].remove(value)
                }
            }
        )
    }

    /// The chosen decade, as the year its range starts at.
    ///
    /// `nil` when no range is set — and also when a range was set that is not a
    /// decade, which the query allows and this control cannot draw. Showing nothing
    /// selected is the honest answer to that.
    private var decade: Binding<Int?> {
        Binding(
            get: { model.query.years.from },
            set: { start in
                model.query.years = start.map { YearRange(from: $0, to: $0 + 9) } ?? YearRange()
            }
        )
    }

    // MARK: - Values

    /// Languages named in themselves. A reader looking for Deutsch is not helped by
    /// "German", which is the same rule the language setting follows.
    private var languageNames: [FilterValue] {
        model.availableLanguages.map { FilterValue(id: $0, label: InterfaceLanguage.name(of: $0)) }
    }

    private func pairs(_ values: [String]) -> [FilterValue] {
        values.map { FilterValue(id: $0, label: $0) }
    }
}

/// One value a filter group offers: what it matches, and what it is called.
///
/// The two differ for a language — the query holds "de" and the reader reads
/// "Deutsch" — and are the same string everywhere else.
struct FilterValue: Identifiable, Hashable {
    let id: String
    let label: String
}
