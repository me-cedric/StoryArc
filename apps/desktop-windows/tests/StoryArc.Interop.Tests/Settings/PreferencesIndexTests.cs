using StoryArc.Interop.Settings;
using StoryArc.Interop.Text;

namespace StoryArc.Interop.Tests.Settings;

/// <summary>The preferences search (desktop-clients task 2.47; desktop-experience "Searching the preferences").</summary>
public sealed class PreferencesIndexTests
{
    [Fact]
    public void A_blank_search_shows_every_group_with_every_setting_in_the_design_order()
    {
        var sections = PreferencesIndex.Search("");

        Assert.Equal(Enum.GetValues<PreferencesGroup>(), sections.Select(section => section.Group));
        Assert.Equal(PreferencesIndex.All.Count, sections.Sum(section => section.Entries.Count));
        Assert.Equal(PreferencesGroup.Sources, sections[0].Group);
        Assert.Equal(PreferencesGroup.About, sections[^1].Group);
    }

    [Fact]
    public void A_word_shows_only_the_settings_that_match_grouped_under_their_sections()
    {
        var sections = PreferencesIndex.Search("colour");

        var appearance = Assert.Single(sections);
        Assert.Equal(PreferencesGroup.Appearance, appearance.Group);
        var accent = Assert.Single(appearance.Entries);
        Assert.Equal("accent", accent.Id);
    }

    [Fact]
    public void The_search_folds_case_and_accents_and_reads_keywords()
    {
        Assert.Contains(PreferencesIndex.Search("FRANCAIS"), section => section.Group == PreferencesGroup.Language);
        Assert.Contains(PreferencesIndex.Search("français"), section => section.Group == PreferencesGroup.Language);
        Assert.Contains(PreferencesIndex.Search("  Kavita "), section => section.Group == PreferencesGroup.Sources);
        Assert.Contains(PreferencesIndex.Search("curl").SelectMany(section => section.Entries), entry => entry.Id == "transition");
    }

    [Fact]
    public void A_word_that_matches_nothing_gives_an_empty_result()
    {
        Assert.Empty(PreferencesIndex.Search("zzzz"));
    }

    [Fact]
    public void Every_group_has_a_title_key_and_every_entry_a_unique_id()
    {
        foreach (var group in Enum.GetValues<PreferencesGroup>())
        {
            Assert.StartsWith("settings_", PreferencesIndex.TitleKeyOf(group));
        }

        var ids = PreferencesIndex.All.Select(entry => entry.Id).ToList();
        Assert.Equal(ids.Count, ids.Distinct(StringComparer.Ordinal).Count());
    }

    [Theory]
    [InlineData("Lumière", "lumiere")]
    [InlineData("  SAGA ", "saga")]
    [InlineData("", "")]
    [InlineData("   ", "")]
    public void Text_folds_for_case_accents_and_edges(string text, string expected)
    {
        Assert.Equal(expected, TextFold.Fold(text));
    }
}
