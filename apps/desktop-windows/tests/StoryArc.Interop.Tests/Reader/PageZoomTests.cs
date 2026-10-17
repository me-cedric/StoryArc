using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>
/// The zoom model (desktop-clients task 2.40, after 2.13): the same pure tests the iOS model has,
/// in C#. Scenarios of desktop-experience "Zoom and pan with a pointer".
/// </summary>
public sealed class PageZoomTests
{
    private static readonly Extent Portrait = new(1000, 1500);
    private static readonly Extent Landscape = new(1600, 900);

    [Fact]
    public void Fit_to_screen_scales_the_page_inside_the_viewport_and_every_mode_is_a_multiple_of_it()
    {
        var fitted = PageZoom.Fitted(Portrait, Landscape);
        Assert.Equal(600, fitted.Width, 6);
        Assert.Equal(900, fitted.Height, 6);
        Assert.Equal(1, PageZoom.FitScale(PageFit.Screen, Portrait, Landscape));
        Assert.Equal(1600.0 / 600.0, PageZoom.FitScale(PageFit.Width, Portrait, Landscape), 6);
        Assert.Equal(1, PageZoom.FitScale(PageFit.Height, Portrait, Landscape));
        Assert.Equal(1000.0 / 600.0, PageZoom.FitScale(PageFit.Original, Portrait, Landscape), 6);
    }

    [Fact]
    public void A_small_scan_at_its_own_size_never_sits_below_fit_to_screen()
    {
        var small = new Extent(300, 450);

        Assert.Equal(1, PageZoom.FitScale(PageFit.Original, small, Landscape));
    }

    [Fact]
    public void An_empty_image_fits_to_nothing_and_opens_at_one()
    {
        Assert.Equal(Extent.Zero, PageZoom.Fitted(Extent.Zero, Landscape));
        Assert.Equal(1, PageZoom.FitScale(PageFit.Width, Extent.Zero, Landscape));
    }

    [Fact]
    public void A_double_click_zooms_in_from_the_fit_and_a_second_one_fits_the_page_again()
    {
        const double fit = 1;

        var zoomed = PageZoom.DoubleClickTarget(fit, fit);
        Assert.Equal(2.5, zoomed);
        Assert.True(PageZoom.IsZoomedPastFit(zoomed, fit));

        Assert.Equal(fit, PageZoom.DoubleClickTarget(zoomed, fit));
        Assert.False(PageZoom.IsZoomedPastFit(fit * 1.005, fit), "a view's own rounding must not read as past fit");
    }

    [Fact]
    public void A_double_click_from_a_fit_wider_than_the_screen_zooms_in_from_that_fit_and_never_past_the_ceiling()
    {
        const double widthFit = 2.6667;

        Assert.Equal(PageZoom.Ceiling, PageZoom.DoubleClickTarget(widthFit, widthFit));
        Assert.Equal(widthFit, PageZoom.DoubleClickTarget(PageZoom.Ceiling, widthFit));
    }

    [Fact]
    public void A_key_beyond_a_limit_does_nothing()
    {
        Assert.Equal(PageZoom.Ceiling, PageZoom.StepIn(PageZoom.Ceiling));
        Assert.Equal(PageZoom.Floor, PageZoom.StepOut(PageZoom.Floor));
        Assert.Equal(1.25, PageZoom.StepIn(1));
        Assert.Equal(PageZoom.Ceiling, PageZoom.StepIn(5.9));
        Assert.Equal(PageZoom.Floor, PageZoom.StepOut(1.1));
    }

    [Fact]
    public void The_wheel_with_the_modifier_steps_once_per_notch_in_either_direction()
    {
        Assert.Equal(1.25, PageZoom.WheelZoom(1, 120));
        Assert.Equal(1.25 * 1.25, PageZoom.WheelZoom(1, 240), 6);
        Assert.Equal(1, PageZoom.WheelZoom(1.25, -120));
        Assert.Equal(2, PageZoom.WheelZoom(2, 0));
        Assert.Equal(PageZoom.Ceiling, PageZoom.WheelZoom(PageZoom.Ceiling, 120));
    }

    [Fact]
    public void A_zoomed_page_pans_within_its_bounds_and_a_fitted_page_does_not_pan()
    {
        Assert.Equal(0, PageZoom.ClampOffset(50, 600, 1600));
        Assert.Equal(0, PageZoom.ClampOffset(-20, 1800, 1600));
        Assert.Equal(200, PageZoom.ClampOffset(999, 1800, 1600));
        Assert.Equal(120, PageZoom.ClampOffset(120, 1800, 1600));
    }

    [Fact]
    public void Zooming_about_the_pointer_keeps_the_pixel_under_it()
    {
        // Content 1000 wide at scale 1, viewport 1000, pointer at 400 with no offset: at scale 2
        // the content is 2000 wide and the pixel that was at 400 is now at 800, so the offset is 400.
        Assert.Equal(400, PageZoom.OffsetZoomedAbout(0, 400, 1, 2, 2000, 1000));
        Assert.Equal(0, PageZoom.OffsetZoomedAbout(400, 400, 2, 1, 1000, 1000));
        Assert.Equal(1000, PageZoom.OffsetZoomedAbout(900, 900, 1, 2, 2000, 1000));
    }
}
