using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.SystemSettings;

/// <summary>Appearance, text size, contrast and motion through the system settings (desktop-clients task 2.45).</summary>
public sealed class SystemAppearanceTests
{
    [Fact]
    public void Transparency_off_or_increased_contrast_draws_the_chrome_opaque()
    {
        Assert.Equal(ChromeMaterial.Translucent, SystemAppearance.Material(SystemSettingsSnapshot.Default));
        Assert.Equal(ChromeMaterial.Opaque, SystemAppearance.Material(SystemSettingsSnapshot.Default with { TransparencyEffectsEnabled = false }));
        Assert.Equal(ChromeMaterial.Opaque, SystemAppearance.Material(SystemSettingsSnapshot.Default with { HighContrast = true }));
    }

    [Fact]
    public void Reduced_motion_gives_a_fast_fade_and_turns_the_curl_off()
    {
        var reduced = SystemSettingsSnapshot.Default with { AnimationsEnabled = false };

        Assert.Equal(MotionPolicy.FastFade, SystemAppearance.Motion(reduced));
        Assert.Equal(TransitionMode.Fade, SystemAppearance.EffectiveTransition(TransitionMode.Curl, reduced, isCurlAvailable: true));
        Assert.Equal(TransitionMode.Fade, SystemAppearance.EffectiveTransition(TransitionMode.Slide, reduced, isCurlAvailable: true));
    }

    [Fact]
    public void The_curl_where_it_is_not_available_shows_as_the_nearest_mode()
    {
        Assert.Equal(TransitionMode.Slide, SystemAppearance.EffectiveTransition(TransitionMode.Curl, SystemSettingsSnapshot.Default, isCurlAvailable: false));
        Assert.Equal(TransitionMode.Curl, SystemAppearance.EffectiveTransition(TransitionMode.Curl, SystemSettingsSnapshot.Default, isCurlAvailable: true));
        Assert.Equal(TransitionMode.Scroll, SystemAppearance.EffectiveTransition(TransitionMode.Scroll, SystemSettingsSnapshot.Default, isCurlAvailable: false));
    }

    [Fact]
    public void At_the_largest_text_size_the_library_is_a_list()
    {
        var largest = SystemSettingsSnapshot.Default with { TextScaleFactor = 2.25 };
        var large = SystemSettingsSnapshot.Default with { TextScaleFactor = 2.0 };

        Assert.Equal(LibraryPresentation.List, SystemAppearance.Library(largest, LibraryPresentation.Grid));
        Assert.Equal(LibraryPresentation.Grid, SystemAppearance.Library(large, LibraryPresentation.Grid));
        Assert.Equal(LibraryPresentation.List, SystemAppearance.Library(large, LibraryPresentation.List));
    }
}
