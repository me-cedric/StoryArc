internal import SwiftUI

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

    var body: some View {
        Menu {
            group("library.filter.readState", isActive: !model.query.readStates.isEmpty) {
                ForEach(ReadState.allCases, id: \.self) { state in
                    Toggle(isOn: readState(state)) {
                        Text(state.titleKey, bundle: .module)
                    }
                }
            }

            formats
            values("library.filter.language", languageNames, \.languages)
            values("library.filter.publisher", pairs(model.availablePublishers), \.publishers)
            values("library.filter.genre", pairs(model.availableGenres), \.genres)
            values("library.filter.tag", pairs(model.availableTags), \.tags)
            decades

            if model.query.hasFilters {
                Divider()
                Button(role: .destructive) {
                    model.clearFilters()
                } label: {
                    Text("library.filter.clear", bundle: .module)
                }
            }
        } label: {
            Label {
                Text("library.filter", bundle: .module)
            } icon: {
                Image(
                    systemName: model.query.hasFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
        // The count, spoken rather than drawn as a badge a menu label cannot carry.
        .accessibilityValue(
            model.query.hasFilters
                ? Text("library.filter.active \(model.query.activeFilterCount)", bundle: .module)
                : Text(verbatim: "")
        )
    }

    // MARK: - Groups

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
