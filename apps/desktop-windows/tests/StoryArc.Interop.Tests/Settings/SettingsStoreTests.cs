using StoryArc.Interop.Settings;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.Settings;

/// <summary>The settings the preferences page edits and the app reads (desktop-clients tasks 2.47 and 2.47e).</summary>
public sealed class SettingsStoreTests
{
    [Fact]
    public void A_missing_file_gives_the_defaults()
    {
        var store = new SettingsStore(() => null, _ => { });

        Assert.Equal(AppSettings.Default, store.Current);
    }

    [Fact]
    public void An_update_replaces_the_settings_saves_them_and_says_so()
    {
        string? saved = null;
        var raised = new List<AppSettings>();
        var store = new SettingsStore(() => null, text => saved = text);
        store.Changed += raised.Add;

        store.Update(settings => settings with { Accent = AccentChoice.System });

        Assert.Equal(AccentChoice.System, store.Current.Accent);
        Assert.Equal(AccentChoice.System, AppSettings.Restore(saved).Accent);
        Assert.Equal(AccentChoice.System, Assert.Single(raised).Accent);
    }

    [Fact]
    public void An_update_that_changes_nothing_writes_and_says_nothing()
    {
        var writes = 0;
        var raised = 0;
        var store = new SettingsStore(() => null, _ => writes++);
        store.Changed += _ => raised++;

        store.Update(settings => settings with { ClickZonesOn = true });

        Assert.Equal(0, writes);
        Assert.Equal(0, raised);
    }

    [Fact]
    public void The_stored_file_is_read_at_start()
    {
        var text = (AppSettings.Default with { Appearance = AppearanceChoice.Dark, ClickZonesOn = false }).Save();

        var store = new SettingsStore(() => text, _ => { });

        Assert.Equal(AppearanceChoice.Dark, store.Current.Appearance);
        Assert.False(store.Current.ClickZonesOn);
    }

    [Fact]
    public void A_write_that_fails_keeps_the_choice_for_this_run()
    {
        var store = new SettingsStore(() => null, _ => throw new IOException("read-only"));

        store.Update(settings => settings with { Transition = TransitionMode.Fade });

        Assert.Equal(TransitionMode.Fade, store.Current.Transition);
    }

    [Theory]
    [InlineData(AppearanceChoice.System, ThemeKind.System)]
    [InlineData(AppearanceChoice.Light, ThemeKind.Light)]
    [InlineData(AppearanceChoice.Dark, ThemeKind.Dark)]
    [InlineData(AppearanceChoice.OledDark, ThemeKind.Dark)]
    [InlineData(AppearanceChoice.Natural, ThemeKind.System)]
    public void Each_appearance_choice_names_the_theme_the_chrome_takes_now(AppearanceChoice choice, ThemeKind expected)
    {
        Assert.Equal(expected, AppearanceTheme.For(choice));
    }

    [Fact]
    public void The_two_appearances_still_to_be_drawn_say_so_to_the_page()
    {
        Assert.True(AppearanceTheme.IsPending(AppearanceChoice.OledDark));
        Assert.True(AppearanceTheme.IsPending(AppearanceChoice.Natural));
        Assert.False(AppearanceTheme.IsPending(AppearanceChoice.Dark));
    }
}
