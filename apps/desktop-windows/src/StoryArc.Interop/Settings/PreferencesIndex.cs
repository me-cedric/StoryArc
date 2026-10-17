using StoryArc.Interop.Text;

namespace StoryArc.Interop.Settings;

/// <summary>The groups of the settings page, in their order (docs/designs/desktop/windows.md, section 5).</summary>
public enum PreferencesGroup
{
    Sources,
    Appearance,
    Reading,
    DownloadsAndStorage,
    Language,
    Privacy,
    About,
}

/// <summary>
/// One setting the page shows. <see cref="TitleKey"/> is the generated string resource for its
/// title where one exists; <see cref="Title"/> is the English text the page falls back to.
/// <see cref="Keywords"/> are what the search matches beside the title.
/// </summary>
public sealed record PreferenceEntry(string Id, PreferencesGroup Group, string TitleKey, string Title, IReadOnlyList<string> Keywords);

/// <summary>A group with the entries of it that match a search, in their order.</summary>
public sealed record PreferencesSection(PreferencesGroup Group, string TitleKey, IReadOnlyList<PreferenceEntry> Entries);

/// <summary>
/// The settings page's index and its search (desktop-clients task 2.47; desktop-experience
/// "Searching the preferences"): a word shows only the settings that match, grouped under their
/// sections, and an empty result is the page's business to say in grey.
/// </summary>
public static class PreferencesIndex
{
    public static IReadOnlyList<PreferenceEntry> All { get; } =
    [
        new("sources", PreferencesGroup.Sources, "settings_sources", "Sources", ["folder", "server", "opds", "kavita", "smb", "share", "remove", "refresh"]),
        new("addSource", PreferencesGroup.Sources, "library_addSource", "Add a source", ["folder", "server", "opds", "kavita", "smb"]),
        new("appearance", PreferencesGroup.Appearance, "settings_appearance", "Appearance", ["theme", "light", "dark", "oled", "natural", "system"]),
        new("accent", PreferencesGroup.Appearance, "settings_accent", "Accent colour", ["colour", "color", "brand", "system", "windows"]),
        new("transparency", PreferencesGroup.Appearance, "settings_transparency", "Transparency effects", ["mica", "acrylic", "opaque", "windows setting"]),
        new("readingDefaults", PreferencesGroup.Reading, "reading_defaults", "Reading defaults", ["fit", "direction", "spread", "page"]),
        new("clickZones", PreferencesGroup.Reading, "reading_tapZones", "Turn pages by clicking the edges", ["click", "tap", "zone", "edge", "turn"]),
        new("transition", PreferencesGroup.Reading, "reader_transition", "Page transition", ["curl", "slide", "fade", "scroll", "motion"]),
        new("matte", PreferencesGroup.Reading, "reading_matte", "Page matte", ["background", "black", "white", "sepia"]),
        new("downloads", PreferencesGroup.DownloadsAndStorage, "settings_downloads", "Downloads", ["queue", "wi-fi", "metered", "storage"]),
        new("storage", PreferencesGroup.DownloadsAndStorage, "settings_storage", "Storage", ["cache", "covers", "clear", "space", "disk"]),
        new("sync", PreferencesGroup.DownloadsAndStorage, "sync_title", "Sync", ["folder", "document", "phone", "devices", "position"]),
        new("language", PreferencesGroup.Language, "settings_language", "Language", ["english", "français", "deutsch", "español", "system"]),
        new("privacy", PreferencesGroup.Privacy, "settings_privacy", "Privacy", ["cover lookup", "network", "diagnostic", "export"]),
        new("version", PreferencesGroup.About, "about_version", "Version", ["build", "update"]),
        new("licences", PreferencesGroup.About, "about_licence", "Licences", ["acknowledgements", "open source", "third party"]),
        new("whatsNew", PreferencesGroup.About, "whatsnew_title", "What's new", ["release", "changes"]),
        new("acknowledgements", PreferencesGroup.About, "about_acknowledgements", "Acknowledgements", ["licence", "credits"]),
        new("reportProblem", PreferencesGroup.About, "about_report", "Report a problem", ["bug", "issue", "github"]),
    ];

    private static readonly IReadOnlyDictionary<PreferencesGroup, string> GroupTitleKeys = new Dictionary<PreferencesGroup, string>
    {
        [PreferencesGroup.Sources] = "settings_sources",
        [PreferencesGroup.Appearance] = "settings_appearance",
        [PreferencesGroup.Reading] = "settings_reading",
        [PreferencesGroup.DownloadsAndStorage] = "settings_downloads",
        [PreferencesGroup.Language] = "settings_language",
        [PreferencesGroup.Privacy] = "settings_privacy",
        [PreferencesGroup.About] = "settings_about",
    };

    public static string TitleKeyOf(PreferencesGroup group) => GroupTitleKeys[group];

    /// <summary>
    /// The sections to show for <paramref name="query"/>: every group with every entry when the
    /// query is blank, otherwise only the entries whose title or keywords hold the query, folded
    /// for case and accents, under their groups. An empty list means nothing matched.
    /// </summary>
    public static IReadOnlyList<PreferencesSection> Search(string? query)
    {
        var folded = TextFold.Fold(query ?? string.Empty);
        var matching = string.IsNullOrEmpty(folded)
            ? All
            : All.Where(entry => Matches(entry, folded)).ToList();

        return Enum.GetValues<PreferencesGroup>()
            .Select(group => new PreferencesSection(group, TitleKeyOf(group), matching.Where(entry => entry.Group == group).ToList()))
            .Where(section => section.Entries.Count > 0)
            .ToList();
    }

    private static bool Matches(PreferenceEntry entry, string foldedQuery) =>
        TextFold.Fold(entry.Title).Contains(foldedQuery, StringComparison.Ordinal)
        || entry.Keywords.Any(keyword => TextFold.Fold(keyword).Contains(foldedQuery, StringComparison.Ordinal));
}
