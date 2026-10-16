using System.Text.RegularExpressions;
using StoryArc.Interop.Settings;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.Settings;

/// <summary>
/// The chrome accent setting, test first (desktop-clients task 2.47e, after 2.23e): the scenarios
/// of desktop-experience "The interface accent and the system appearance" over the settings record.
/// </summary>
public sealed partial class ChromeAccentTests
{
    private static readonly AccentPalette WindowsBlue = new(
        Argb.Parse("#FF0078D4"),
        Argb.Parse("#FF2E8BDE"),
        Argb.Parse("#FF5EA5E8"),
        Argb.Parse("#FF8EC0F0"),
        Argb.Parse("#FF005FB8"),
        Argb.Parse("#FF004C96"),
        Argb.Parse("#FF003A74"));

    [GeneratedRegex("""<Color x:Key="StoryArcBrandAccent">(#[0-9A-F]{8})</Color>""")]
    private static partial Regex BrandAccentToken();

    [Fact]
    public void The_brand_colour_is_the_generated_token()
    {
        var tokens = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "StoryArcTokens.xaml"));
        var match = BrandAccentToken().Match(tokens);

        Assert.True(match.Success, "no StoryArcBrandAccent colour in StoryArcTokens.xaml");
        Assert.Equal(Argb.Parse(match.Groups[1].Value), ChromeAccent.Brand);
    }

    [Fact]
    public void A_reader_who_never_chose_gets_the_brand_colour_whatever_the_system_accent()
    {
        Assert.Equal(AccentChoice.StoryArc, AppSettings.Default.Accent);
        Assert.Equal(AccentPalette.Uniform(ChromeAccent.Brand), ChromeAccent.Resolve(AppSettings.Default.Accent, WindowsBlue));
        Assert.Equal(AccentPalette.Uniform(ChromeAccent.Brand), ChromeAccent.Resolve(AppSettings.Default.Accent, null));
    }

    [Fact]
    public void Choosing_the_system_accent_takes_it_at_once_with_its_shades()
    {
        var chosen = AppSettings.Default with { Accent = AccentChoice.System };

        Assert.Equal(WindowsBlue, ChromeAccent.Resolve(chosen.Accent, WindowsBlue));
    }

    [Fact]
    public void A_later_change_of_the_system_accent_recolours_the_chrome_with_no_restart()
    {
        var green = AccentPalette.Uniform(Argb.Parse("#FF10893E"));

        var before = ChromeAccent.Resolve(AccentChoice.System, WindowsBlue);
        var after = ChromeAccent.Resolve(AccentChoice.System, green);

        Assert.Equal(WindowsBlue, before);
        Assert.Equal(green, after);
    }

    [Fact]
    public void A_system_with_no_accent_colour_hides_the_choice_and_keeps_the_brand()
    {
        Assert.False(ChromeAccent.OffersSystemChoice(null));
        Assert.True(ChromeAccent.OffersSystemChoice(WindowsBlue));
        Assert.Equal(AccentPalette.Uniform(ChromeAccent.Brand), ChromeAccent.Resolve(AccentChoice.System, null));
    }

    [Fact]
    public void A_colour_taken_from_a_cover_is_the_same_under_both_choices()
    {
        var cover = Argb.Parse("#FFC87C5E");

        Assert.Equal(cover, ChromeAccent.ReaderAccent(cover, AccentChoice.StoryArc));
        Assert.Equal(cover, ChromeAccent.ReaderAccent(cover, AccentChoice.System));
    }

    [Fact]
    public void The_settings_record_round_trips_and_a_damaged_file_gives_the_defaults()
    {
        var chosen = new AppSettings(AccentChoice.System, AppearanceChoice.OledDark, false, TransitionMode.Fade);

        Assert.Equal(chosen, AppSettings.Restore(chosen.Save()));
        Assert.Contains("\"accent\": \"System\"", chosen.Save());
        Assert.Equal(AppSettings.Default, AppSettings.Restore(null));
        Assert.Equal(AppSettings.Default, AppSettings.Restore("{ broken"));
        Assert.Equal(AppSettings.Default, AppSettings.Restore("""{"accent":"Magenta"}"""));
    }

    [Fact]
    public void The_click_zones_are_on_when_nothing_is_stored()
    {
        Assert.True(AppSettings.Default.ClickZonesOn);
        Assert.True(AppSettings.Restore("{}").ClickZonesOn, "a file without the key must read as the default, on");
        Assert.Equal(AppSettings.Default, AppSettings.Restore("{}"));
        Assert.False(AppSettings.Restore("""{"clickZonesOn":false}""").ClickZonesOn);
    }

    [Fact]
    public void Argb_parses_and_prints_the_token_form()
    {
        Assert.Equal(new Argb(0xFF, 0x8A, 0x4D, 0xF0), Argb.Parse("#FF8A4DF0"));
        Assert.Equal("#FF8A4DF0", Argb.Parse("#FF8A4DF0").ToString());
        Assert.Throws<FormatException>(() => Argb.Parse("8A4DF0"));
    }
}
