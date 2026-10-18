using System.Globalization;
using System.Text.Json.Nodes;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using StoryArc.Interop.Epub;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The reading themes of the EPUB window (<c>ebook-reader</c>, "Reader themes" and "Reflowable rendering"): a surface of two
/// levels in one flyout. The first holds the six presets as swatches, the size stepper, the page mode, the brightness and the
/// appearance pair, and one action as wide as the grid that opens the second; the second holds the axes over a specimen in the
/// active theme. Each change reaches the page behind the flyout at once, through one <c>theme</c> message
/// (<see cref="ReadingThemes.Axes"/>). The rules are in StoryArc.Interop; this file only draws them.
/// </summary>
public sealed partial class EpubReaderWindow
{
    /// <summary>The faces a swatch's specimen is set in: each preset's own voice, as the phones' preset table names it.</summary>
    private static readonly Dictionary<ThemePreset, ReaderTypeface> SpecimenFace = new()
    {
        [ThemePreset.Original] = ReaderTypeface.Serif,
        [ThemePreset.Quiet] = ReaderTypeface.SourceSerif,
        [ThemePreset.Paper] = ReaderTypeface.Literata,
        [ThemePreset.Bold] = ReaderTypeface.Sans,
        [ThemePreset.Calm] = ReaderTypeface.EbGaramond,
        [ThemePreset.Focus] = ReaderTypeface.Bitter,
    };

    private TextBlock? _specimen;
    private Border? _specimenFrame;

    private ThemePreset ActivePreset => _look.PresetFor(Root.ActualTheme == ElementTheme.Dark);

    /// <summary>The tool bar's labels, in the reader's language.</summary>
    private void LabelTools()
    {
        Label(BackButton, Strings.Get("desktop_w4_epub_back", "Back"));
        Label(ContentsButton, Strings.Get("contents_title", "Contents"));
        Label(SearchButton, Strings.Get("reader_menu_search", "Search"));
        Label(MarksButton, Strings.Get("desktop_w4_epub_marks", "Bookmarks and Highlights"));
        Label(ThemeButton, Strings.Get("reader_menu_themes_EpubReaderFeature", "Reading themes"));
        SearchBox.PlaceholderText = Strings.Get("search_field", "Search in this book");
        AutomationProperties.SetName(SearchBox, Strings.Get("search_field", "Search in this book"));
        ShowBookmark();
    }

    private static void Label(AppBarButton button, string text)
    {
        button.Label = text;
        ToolTipService.SetToolTip(button, text);
    }

    /// <summary>Every axis in force: the preset the appearance picks, the reader's typography, scroll or pages, the brightness.</summary>
    private JsonObject CurrentAxes() => ReadingThemes.Axes(ActivePreset, _look.Typography, _look.Scrolls, _look.Brightness);

    /// <summary>Puts the look on the page. A theme message replaces every axis, so the whole set goes each time.</summary>
    private void ApplyTheme()
    {
        Post(_commands.Theme(ActivePreset.ToString().ToLowerInvariant(), CurrentAxes()));
        ShowSpecimen();
    }

    private void ChangeLook(Func<EpubLook, EpubLook> change)
    {
        _look = change(_look);
        try
        {
            File.WriteAllText(StateFiles.EpubLookPath, _look.Save());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Kept for this window; the next change tries again.
        }

        ApplyTheme();
    }

    private void ChangeTypography(Func<ThemeValues, ThemeValues> change) =>
        ChangeLook(look => look with { Values = change(look.Typography) });

    private void OnThemeOpening(object? sender, object args) => ShowPresets();

    // The first level: presets and nothing else of the axes.
    private void ShowPresets()
    {
        ThemePanel.Children.Clear();
        _specimen = null;
        _specimenFrame = null;

        var grid = new Grid { ColumnSpacing = 8, RowSpacing = 8 };
        for (var column = 0; column < 3; column++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }

        foreach (var preset in Enum.GetValues<ThemePreset>())
        {
            var index = (int)preset;
            if (index % 3 == 0)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }

            var swatch = Swatch(preset);
            Grid.SetColumn(swatch, index % 3);
            Grid.SetRow(swatch, index / 3);
            grid.Children.Add(swatch);
        }

        ThemePanel.Children.Add(grid);

        // One action, as wide as the grid and as tall as a swatch row's text, opens the axes.
        var customise = new Button
        {
            Content = Strings.Get("theme_customise", "Customise"),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            MinHeight = 44,
            Style = (Style)Application.Current.Resources["AccentButtonStyle"],
        };
        customise.Click += (sender, args) => ShowAxes();
        ThemePanel.Children.Add(customise);

        ThemePanel.Children.Add(SizeStepper());
        ThemePanel.Children.Add(Switch(Strings.Get("theme_pageTurn_scroll", "Continuous scroll"), _look.Scrolls, on => ChangeLook(look => look with { Scrolls = on })));
        ThemePanel.Children.Add(BrightnessSlider());

        var follows = Switch(Strings.Get("appearance_linkTheme", "Match the reading theme to the app"), _look.FollowsAppearance, on =>
        {
            ChangeLook(look => look with { FollowsAppearance = on });
            ShowPresets();
        });
        ThemePanel.Children.Add(follows);
        if (_look.FollowsAppearance)
        {
            ThemePanel.Children.Add(PresetPicker(Strings.Get("appearance_linkTheme_light", "Light theme"), _look.LightTheme, preset => ChangeLook(look => look with { LightTheme = preset })));
            ThemePanel.Children.Add(PresetPicker(Strings.Get("appearance_linkTheme_dark", "Dark theme"), _look.DarkTheme, preset => ChangeLook(look => look with { DarkTheme = preset })));
        }
    }

    /// <summary>
    /// One preset as its own swatch: a specimen of real letterforms and the name in the preset's background, text colour, face
    /// and weight; the active one outlined and announced as selected, and marked modified when the typography moved.
    /// </summary>
    private Button Swatch(ThemePreset preset)
    {
        var (background, text) = ReadingThemes.Colours(preset);
        var foreground = new SolidColorBrush(ColourOf(text));
        var isActive = preset == ActivePreset;
        var name = PresetName(preset);
        var weight = preset == ThemePreset.Bold ? FontWeights.Bold : FontWeights.Normal;
        var content = new StackPanel { Spacing = 2, HorizontalAlignment = HorizontalAlignment.Center };
        content.Children.Add(new TextBlock
        {
            Text = Strings.Get("theme_specimen_second", "Aa Bb 123"),
            FontSize = 20,
            FontWeight = weight,
            FontFamily = FamilyOf(SpecimenFace[preset]),
            Foreground = foreground,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        content.Children.Add(new TextBlock { Text = name, FontWeight = weight, Foreground = foreground, HorizontalAlignment = HorizontalAlignment.Center, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center });
        if (isActive && _look.IsModified)
        {
            content.Children.Add(new TextBlock { Text = Strings.Get("theme_modified", "Modified"), Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], Foreground = foreground, HorizontalAlignment = HorizontalAlignment.Center });
        }

        var button = new Button
        {
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = new SolidColorBrush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            Content = new Border
            {
                Background = new SolidColorBrush(ColourOf(background)),
                BorderBrush = isActive ? (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"] : (Brush)Application.Current.Resources["ControlStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(isActive ? 3 : 1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(6, 10, 6, 10),
                MinHeight = 76,
                Child = content,
            },
        };
        AutomationProperties.SetName(button, isActive && _look.IsModified ? name + ", " + Strings.Get("theme_modified", "Modified") : name);
        if (isActive)
        {
            AutomationProperties.SetItemStatus(button, Strings.Get("desktop_w4_epub_selected", "Selected"));
        }

        button.Click += (sender, args) =>
        {
            // Picking a preset was the whole errand: it applies and the surface closes. With the appearance pair on, the pick
            // replaces the half of the pair the app is showing now.
            ChangeLook(look => !look.FollowsAppearance ? look with { Preset = preset }
                : Root.ActualTheme == ElementTheme.Dark ? look with { DarkTheme = preset } : look with { LightTheme = preset });
            ThemeFlyout.Hide();
        };
        return button;
    }

    /// <summary>The size ladder: smaller, the size in words, larger. Nine steps, never a free slider.</summary>
    private StackPanel SizeStepper()
    {
        var size = _look.Typography.FontSize;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var smaller = new Button { Content = new FontIcon { Glyph = "" }, IsEnabled = size > ReadingThemes.FontSizes[0] };
        AutomationProperties.SetName(smaller, Strings.Get("theme_fontSize_smaller", "Smaller"));
        ToolTipService.SetToolTip(smaller, Strings.Get("theme_fontSize_smaller", "Smaller"));
        smaller.Click += (sender, args) =>
        {
            ChangeTypography(values => values with { FontSize = ReadingThemes.SmallerSize(values.FontSize) });
            Redraw();
        };
        var larger = new Button { Content = new FontIcon { Glyph = "" }, IsEnabled = size < ReadingThemes.FontSizes[^1] };
        AutomationProperties.SetName(larger, Strings.Get("theme_fontSize_larger", "Larger"));
        ToolTipService.SetToolTip(larger, Strings.Get("theme_fontSize_larger", "Larger"));
        larger.Click += (sender, args) =>
        {
            ChangeTypography(values => values with { FontSize = ReadingThemes.LargerSize(values.FontSize) });
            Redraw();
        };
        var value = new TextBlock
        {
            Text = string.Format(CultureInfo.CurrentCulture, Strings.Get("theme_fontSize_percent__lld", "{0}% of the publisher’s size"), size),
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        };
        row.Children.Add(smaller);
        row.Children.Add(larger);
        row.Children.Add(value);

        var block = new StackPanel { Spacing = 4 };
        block.Children.Add(new TextBlock { Text = Strings.Get("theme_fontSize", "Text size"), Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        block.Children.Add(row);
        return block;
    }

    private Slider BrightnessSlider()
    {
        var slider = new Slider
        {
            Header = Strings.Get("theme_brightness", "Brightness"),
            Minimum = ReadingThemes.MinimumBrightness * 100,
            Maximum = 100,
            StepFrequency = 5,
            Value = _look.Brightness * 100,
            ThumbToolTipValueConverter = new PercentText(),
        };
        AutomationProperties.SetName(slider, Strings.Get("theme_brightness", "Brightness"));
        slider.ValueChanged += (sender, args) => ChangeLook(look => look with { Brightness = args.NewValue / 100 });
        return slider;
    }

    private ComboBox PresetPicker(string header, ThemePreset selected, Action<ThemePreset> pick)
    {
        var box = new ComboBox { Header = header, HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var preset in Enum.GetValues<ThemePreset>())
        {
            box.Items.Add(PresetName(preset));
        }

        box.SelectedIndex = (int)selected;
        AutomationProperties.SetName(box, header);
        box.SelectionChanged += (sender, args) =>
        {
            if (box.SelectedIndex >= 0)
            {
                pick((ThemePreset)box.SelectedIndex);
            }
        };
        return box;
    }

    // The second level: the axes, over a specimen in the active theme.
    private void ShowAxes()
    {
        ThemePanel.Children.Clear();
        var preset = ActivePreset;
        var values = _look.Typography;

        var back = new Button { Content = Strings.Get("theme_presets", "Themes") };
        back.Click += (sender, args) => ShowPresets();
        ThemePanel.Children.Add(back);

        _specimen = new TextBlock { Text = Strings.Get("theme_preview_sample", "The light had gone out of the afternoon by the time she reached the landing."), TextWrapping = TextWrapping.Wrap };
        _specimenFrame = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(12), Child = _specimen };
        AutomationProperties.SetName(_specimenFrame, Strings.Get("theme_preview", "Preview"));
        ThemePanel.Children.Add(_specimenFrame);
        ShowSpecimen();

        ThemePanel.Children.Add(SizeStepper());

        var faces = new ComboBox { Header = Strings.Get("theme_axis_fontFamily", "Typeface"), HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var face in Enum.GetValues<ReaderTypeface>())
        {
            faces.Items.Add(TypefaceName(face));
        }

        faces.SelectedIndex = (int)values.Typeface;
        AutomationProperties.SetName(faces, Strings.Get("theme_axis_fontFamily", "Typeface"));
        faces.SelectionChanged += (sender, args) =>
        {
            if (faces.SelectedIndex >= 0)
            {
                ChangeTypography(current => current with { Typeface = (ReaderTypeface)faces.SelectedIndex });
            }
        };
        ThemePanel.Children.Add(faces);
        ThemePanel.Children.Add(Switch(Strings.Get("theme_axis_boldText", "Bold text"), values.IsBold, on => ChangeTypography(current => current with { IsBold = on })));
        ThemePanel.Children.Add(AxisSlider(ThemeAxis.Margins, Strings.Get("theme_axis_margins", "Margins"), values.PageMargins, (current, value) => current with { PageMargins = value }));

        // The axes the publisher's stylesheet governs: under Original they are shown unavailable with the reason and one action
        // that drops the publisher's styles, never as live controls that do nothing.
        var governed = new StackPanel { Spacing = 12 };
        governed.Children.Add(AxisSlider(ThemeAxis.LineSpacing, Strings.Get("theme_axis_lineSpacing", "Line spacing"), values.LineHeight, (current, value) => current with { LineHeight = value }));
        governed.Children.Add(AxisSlider(ThemeAxis.CharacterSpacing, Strings.Get("theme_axis_characterSpacing", "Character spacing"), values.LetterSpacing, (current, value) => current with { LetterSpacing = value }));
        governed.Children.Add(AxisSlider(ThemeAxis.WordSpacing, Strings.Get("theme_axis_wordSpacing", "Word spacing"), values.WordSpacing, (current, value) => current with { WordSpacing = value }));
        governed.Children.Add(AxisSlider(ThemeAxis.ParagraphSpacing, Strings.Get("theme_axis_paragraphSpacing", "Paragraph spacing"), values.ParagraphSpacing, (current, value) => current with { ParagraphSpacing = value }));
        var alignment = new ComboBox { Header = Strings.Get("theme_axis_textAlignment", "Text alignment"), HorizontalAlignment = HorizontalAlignment.Stretch };
        alignment.Items.Add(Strings.Get("theme_alignment_publisher", "Publisher"));
        alignment.Items.Add(Strings.Get("theme_alignment_left", "Left"));
        alignment.Items.Add(Strings.Get("theme_alignment_justified", "Justified"));
        alignment.SelectedIndex = (int)values.TextAlignment;
        AutomationProperties.SetName(alignment, Strings.Get("theme_axis_textAlignment", "Text alignment"));
        alignment.SelectionChanged += (sender, args) =>
        {
            if (alignment.SelectedIndex >= 0)
            {
                ChangeTypography(current => current with { TextAlignment = (ReaderTextAlignment)alignment.SelectedIndex });
            }
        };
        governed.Children.Add(alignment);
        governed.Children.Add(Switch(Strings.Get("theme_axis_hyphenation", "Hyphenation"), values.IsHyphenated, on => ChangeTypography(current => current with { IsHyphenated = on })));

        var inert = !ReadingThemes.IsEffective(ThemeAxis.LineSpacing, preset);
        if (inert)
        {
            var reason = new StackPanel { Spacing = 4 };
            reason.Children.Add(new TextBlock { Text = Strings.Get("theme_publisherStyles_title", "The publisher’s styling is in use"), Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], TextWrapping = TextWrapping.Wrap });
            reason.Children.Add(new TextBlock { Text = Strings.Get("theme_publisherStyles_reason", "Original keeps the book exactly as it was published, so these controls follow the book."), TextWrapping = TextWrapping.Wrap, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] });
            var drop = new Button { Content = Strings.Get("theme_publisherStyles_action", "Use StoryArc’s typography") };
            drop.Click += (sender, args) =>
            {
                // Paper is the preset the phones fall back to when the publisher's styles are dropped.
                ChangeLook(look => look.FollowsAppearance
                    ? Root.ActualTheme == ElementTheme.Dark ? look with { DarkTheme = ThemePreset.Paper } : look with { LightTheme = ThemePreset.Paper }
                    : look with { Preset = ThemePreset.Paper });
                ShowAxes();
            };
            reason.Children.Add(drop);
            ThemePanel.Children.Add(reason);
            foreach (var control in governed.Children.OfType<Control>())
            {
                control.IsEnabled = false;
            }

            foreach (var panel in governed.Children.OfType<StackPanel>())
            {
                foreach (var control in panel.Children.OfType<Control>())
                {
                    control.IsEnabled = false;
                }
            }
        }

        ThemePanel.Children.Add(governed);

        var reset = new Button
        {
            Content = string.Format(CultureInfo.CurrentCulture, Strings.Get("theme_restore_named___", "Restore {0}"), PresetName(preset)),
            IsEnabled = _look.IsModified,
        };
        reset.Click += (sender, args) =>
        {
            ChangeLook(look => look with { Values = new ThemeValues() });
            ShowAxes();
        };
        ThemePanel.Children.Add(reset);
    }

    /// <summary>A slider for one fine axis, with its value in numbers beside its label rather than an unlabelled position on a track.</summary>
    private StackPanel AxisSlider(ThemeAxis axis, string label, double value, Func<ThemeValues, double, ThemeValues> set)
    {
        var (minimum, maximum) = axis.SliderRange()!.Value;
        var text = new TextBlock { Text = ReadingThemes.ValueText(axis, value), Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };
        var slider = new Slider { Minimum = minimum, Maximum = maximum, StepFrequency = axis.Step(), SmallChange = axis.Step(), Value = value };
        AutomationProperties.SetName(slider, label);
        slider.ValueChanged += (sender, args) =>
        {
            var rounded = Math.Round(args.NewValue, 3);
            text.Text = ReadingThemes.ValueText(axis, rounded);
            ChangeTypography(current => set(current, rounded));
        };
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        head.Children.Add(new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap });
        head.Children.Add(text);
        var block = new StackPanel { Spacing = 2 };
        block.Children.Add(head);
        block.Children.Add(slider);
        return block;
    }

    private static ToggleSwitch Switch(string header, bool isOn, Action<bool> changed)
    {
        var toggle = new ToggleSwitch { Header = header, IsOn = isOn };
        AutomationProperties.SetName(toggle, header);
        toggle.Toggled += (sender, args) => changed(toggle.IsOn);
        return toggle;
    }

    /// <summary>The level open now, drawn again after a change that alters its controls.</summary>
    private void Redraw()
    {
        if (_specimen is null)
        {
            ShowPresets();
        }
        else
        {
            ShowAxes();
        }
    }

    /// <summary>The specimen over which the axes are set: the active theme's colours, the reader's face, size and weight.</summary>
    private void ShowSpecimen()
    {
        if (_specimen is null || _specimenFrame is null)
        {
            return;
        }

        var (background, text) = ReadingThemes.Colours(ActivePreset);
        var values = _look.Typography;
        _specimenFrame.Background = new SolidColorBrush(ColourOf(background));
        _specimen.Foreground = new SolidColorBrush(ColourOf(text));
        _specimen.FontSize = 15 * values.FontSize / 100.0;
        _specimen.FontWeight = values.IsBold || ActivePreset == ThemePreset.Bold ? FontWeights.Bold : FontWeights.Normal;
        _specimen.FontFamily = FamilyOf(values.Typeface);
        _specimen.LineHeight = ReadingThemes.IsEffective(ThemeAxis.LineSpacing, ActivePreset) ? _specimen.FontSize * values.LineHeight : 0;
    }

    private static string PresetName(ThemePreset preset) =>
        Strings.Get("theme_preset_" + preset.ToString().ToLowerInvariant(), preset.ToString());

    private static string TypefaceName(ReaderTypeface face) => face switch
    {
        ReaderTypeface.Publisher => Strings.Get("theme_typeface_publisher", "Publisher"),
        ReaderTypeface.Serif => Strings.Get("theme_typeface_serif", "Serif"),
        ReaderTypeface.Sans => Strings.Get("theme_typeface_sans", "Sans"),
        ReaderTypeface.Literata => Strings.Get("theme_typeface_literata", "Literata"),
        ReaderTypeface.SourceSerif => Strings.Get("theme_typeface_sourceSerif", "Source Serif"),
        ReaderTypeface.EbGaramond => Strings.Get("theme_typeface_ebGaramond", "EB Garamond"),
        ReaderTypeface.Bitter => Strings.Get("theme_typeface_bitter", "Bitter"),
        // Labelled as designed for low vision wherever it is offered (reading-themes).
        _ => Strings.Get("theme_typeface_atkinson", "Atkinson Hyperlegible") + " — " + Strings.Get("theme_typeface_lowVision", "Designed for low vision"),
    };

    /// <summary>The XAML family of a face: the bundled file beside the app for the five, the system's own for the rest.</summary>
    private static FontFamily FamilyOf(ReaderTypeface face) => face switch
    {
        ReaderTypeface.Sans => new FontFamily("Segoe UI Variable Text"),
        ReaderTypeface.Serif or ReaderTypeface.Publisher => new FontFamily("Cambria"),
        _ => new FontFamily("ms-appx:///Assets/Fonts/" + FirstFile(face) + ".ttf#" + face.CssFamily()),
    };

    private static string FirstFile(ReaderTypeface face) => face == ReaderTypeface.AtkinsonHyperlegible ? "AtkinsonHyperlegible-Regular" : face.FileStem()!;

    private static global::Windows.UI.Color ColourOf(string hex) => ColorHelper.FromArgb(
        255,
        byte.Parse(hex.AsSpan(1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
        byte.Parse(hex.AsSpan(3, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
        byte.Parse(hex.AsSpan(5, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture));

    /// <summary>The brightness slider's thumb says its value in percent.</summary>
    private sealed partial class PercentText : Microsoft.UI.Xaml.Data.IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, string language) =>
            string.Format(CultureInfo.CurrentCulture, Strings.Get("theme_brightness_percent__lld", "{0}%"), System.Convert.ToInt32(value, CultureInfo.InvariantCulture));

        public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotSupportedException();
    }
}
