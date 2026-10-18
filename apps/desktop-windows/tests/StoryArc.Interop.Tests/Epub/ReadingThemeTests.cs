using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using StoryArc.Interop.Epub;

namespace StoryArc.Interop.Tests.Epub;

/// <summary>
/// The EPUB reader's typography and themes on Windows (<c>ebook-reader</c>, "Reflowable rendering" and "Reader themes"):
/// the axes a theme message carries, the publisher-styles rule, the bundled faces on the book's origin, the preset
/// colours held to the design tokens, and the look a PC keeps.
/// </summary>
public sealed partial class ReadingThemeTests
{
    [Fact]
    public void Every_axis_reaches_the_renderer_under_a_preset_that_drops_publisher_styles()
    {
        var values = new ThemeValues(ReaderTypeface.Literata, 130, true, 1.8, 0.1, 0.2, 1.2, 2, ReaderTextAlignment.Justified, true);

        var axes = ReadingThemes.Axes(ThemePreset.Paper, values, scroll: true, brightness: 0.8);

        Assert.False(axes["publisherStyles"]!.GetValue<bool>());
        Assert.Equal("#f5f1ec", axes["backgroundColor"]!.GetValue<string>());
        Assert.Equal("#1d1a17", axes["textColor"]!.GetValue<string>());
        Assert.Equal(1.3, axes["fontSize"]!.GetValue<double>());
        Assert.Equal("Literata", axes["fontFamily"]!.GetValue<string>());
        Assert.Equal(1.5, axes["fontWeight"]!.GetValue<double>());
        Assert.Equal(48, axes["pageGutter"]!.GetValue<double>());
        Assert.True(axes["scroll"]!.GetValue<bool>());
        Assert.Equal(1.8, axes["lineHeight"]!.GetValue<double>());
        Assert.Equal(0.1, axes["letterSpacing"]!.GetValue<double>());
        Assert.Equal(0.2, axes["wordSpacing"]!.GetValue<double>());
        Assert.Equal(1.2, axes["paragraphSpacing"]!.GetValue<double>());
        Assert.Equal("justify", axes["textAlign"]!.GetValue<string>());
        Assert.True(axes["hyphens"]!.GetValue<bool>());
        Assert.Equal(20, axes["darkenFilter"]!.GetValue<int>());
    }

    [Fact]
    public void Original_keeps_the_publishers_styles_and_sends_none_of_the_axes_they_govern()
    {
        var values = new ThemeValues(ReaderTypeface.Bitter, 150, LineHeight: 2, TextAlignment: ReaderTextAlignment.Left, IsHyphenated: true);

        var axes = ReadingThemes.Axes(ThemePreset.Original, values, scroll: false, brightness: 1);

        Assert.True(axes["publisherStyles"]!.GetValue<bool>());
        Assert.Equal(1.5, axes["fontSize"]!.GetValue<double>());
        Assert.Equal("Bitter", axes["fontFamily"]!.GetValue<string>());
        foreach (var governed in new[] { "backgroundColor", "textColor", "lineHeight", "letterSpacing", "wordSpacing", "paragraphSpacing", "textAlign", "hyphens", "darkenFilter" })
        {
            Assert.False(axes.ContainsKey(governed), governed);
        }

        Assert.All(Enum.GetValues<ThemeAxis>(), axis =>
            Assert.Equal(axis is ThemeAxis.FontSize or ThemeAxis.FontFamily or ThemeAxis.BoldText or ThemeAxis.Margins, ReadingThemes.IsEffective(axis, ThemePreset.Original)));
        Assert.All(Enum.GetValues<ThemeAxis>(), axis => Assert.True(ReadingThemes.IsEffective(axis, ThemePreset.Focus)));
    }

    [Fact]
    public void The_size_ladder_has_nine_steps_and_stops_at_each_end()
    {
        Assert.Equal(9, ReadingThemes.FontSizes.Count);
        Assert.Equal(115, ReadingThemes.LargerSize(100));
        Assert.Equal(90, ReadingThemes.SmallerSize(100));
        Assert.Equal(200, ReadingThemes.LargerSize(200));
        Assert.Equal(70, ReadingThemes.SmallerSize(70));
        Assert.Equal(115, ReadingThemes.NearestSize(118));
        Assert.Equal(1.0, ReadingThemes.SliderRange(ThemeAxis.LineSpacing)!.Value.Minimum);
        Assert.Equal(2.5, ReadingThemes.SliderRange(ThemeAxis.LineSpacing)!.Value.Maximum);
        Assert.Equal(0.15, ReadingThemes.Step(ThemeAxis.LineSpacing), 6);
        Assert.Null(ReadingThemes.SliderRange(ThemeAxis.FontSize));
    }

    [Fact]
    public void The_preset_colours_are_the_reading_theme_tokens()
    {
        var tokens = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "StoryArcTokens.xaml"));

        foreach (var preset in Enum.GetValues<ThemePreset>())
        {
            var (background, text) = ReadingThemes.Colours(preset);
            Assert.Equal(background, Token(tokens, preset + "Bg"));
            Assert.Equal(text, Token(tokens, preset + "Fg"));
        }
    }

    [Fact]
    public void The_five_bundled_faces_are_served_on_the_books_origin_and_every_chapter_links_them()
    {
        var chapter = Encoding.UTF8.GetBytes("<html><head><title>One</title></head><body>One</body></html>");
        var host = new EpubHost(
            "fixture-1",
            () => "{}",
            () => "[]",
            href => href == "OEBPS/ch1.xhtml" ? new EpubResource(chapter, "application/xhtml+xml") : null,
            () => [],
            name => File.ReadAllBytes(Corpus.RepositoryPath("packages/fonts/" + name + ".ttf")));

        var sheet = host.Answer(host.Origin + EpubFonts.Sheet, EpubRequestContext.Stylesheet);
        Assert.Equal(200, sheet.Status);
        var css = Encoding.UTF8.GetString(sheet.Body.Span);
        foreach (var face in new[] { ReaderTypeface.Literata, ReaderTypeface.SourceSerif, ReaderTypeface.EbGaramond, ReaderTypeface.Bitter, ReaderTypeface.AtkinsonHyperlegible })
        {
            Assert.Contains("font-family:\"" + face.CssFamily() + "\"", css, StringComparison.Ordinal);
        }

        foreach (var file in EpubFonts.Files)
        {
            var font = host.Answer(host.Origin + EpubFonts.Folder + file + ".ttf", EpubRequestContext.Font);
            Assert.Equal(200, font.Status);
            Assert.Equal("font/ttf", font.MediaType);
            Assert.True(font.Body.Length > 1000, file);
        }

        Assert.Equal(404, host.Answer(host.Origin + EpubFonts.Folder + "Other.ttf", EpubRequestContext.Font).Status);
        var linked = Encoding.UTF8.GetString(host.Answer(host.Origin + "OEBPS/ch1.xhtml", EpubRequestContext.Document).Body.Span);
        Assert.Contains("<link rel=\"stylesheet storyarc-fonts\" type=\"text/css\" href=\"storyarc-epub://fixture-1/storyarc-fonts/faces.css\"/></head>", linked, StringComparison.Ordinal);
        Assert.NotNull(host.Answer(host.Origin + EpubFonts.Sheet, EpubRequestContext.Stylesheet).Header("Content-Security-Policy"));
    }

    [Fact]
    public void The_look_is_kept_and_follows_the_appearance_with_the_chosen_pair()
    {
        var look = new EpubLook(ThemePreset.Calm, new ThemeValues(FontSize: 150), true, 0.7, true, ThemePreset.Bold, ThemePreset.Quiet);

        var restored = EpubLook.Restore(look.Save());

        Assert.Equal(look, restored);
        Assert.True(restored.IsModified);
        Assert.Equal(ThemePreset.Quiet, restored.PresetFor(systemIsDark: true));
        Assert.Equal(ThemePreset.Bold, restored.PresetFor(systemIsDark: false));
        Assert.Equal(ThemePreset.Calm, (restored with { FollowsAppearance = false }).PresetFor(systemIsDark: true));
        Assert.Equal(new EpubLook(), EpubLook.Restore("{ not json"));
        Assert.False(new EpubLook().IsModified);
        Assert.Equal(0.5, EpubLook.Restore("""{"brightness":0.1}""").Brightness);
    }

    [Fact]
    public void A_theme_message_carries_the_preset_name_and_its_axes()
    {
        var json = new HostCommands().Theme("paper", ReadingThemes.Axes(ThemePreset.Paper, new ThemeValues(), false, 1));

        var theme = JsonNode.Parse(json)!["theme"]!;
        Assert.Equal("paper", theme["name"]!.GetValue<string>());
        Assert.Equal("#f5f1ec", theme["axes"]!["backgroundColor"]!.GetValue<string>());
    }

    private static string Token(string tokens, string name)
    {
        var match = TokenColour().Match(tokens[tokens.IndexOf("StoryArcReadingThemes" + name + "\"", StringComparison.Ordinal)..]);
        return "#" + match.Groups[1].Value.ToLowerInvariant();
    }

    [GeneratedRegex(">#FF([0-9A-Fa-f]{6})<")]
    private static partial Regex TokenColour();
}
