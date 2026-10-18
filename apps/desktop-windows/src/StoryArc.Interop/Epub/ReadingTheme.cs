using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Epub;

/// <summary>The six reading-theme presets of <c>reading-themes</c>, in the order the grid shows them.</summary>
public enum ThemePreset
{
    Original,
    Quiet,
    Paper,
    Bold,
    Calm,
    Focus,
}

/// <summary>The typefaces offered: the publisher's, the system serif and sans, and the five that <c>packages/fonts</c> bundles.</summary>
public enum ReaderTypeface
{
    Publisher,
    Serif,
    Sans,
    Literata,
    SourceSerif,
    EbGaramond,
    Bitter,
    AtkinsonHyperlegible,
}

/// <summary>How text is aligned: as the publisher set it, left, or justified.</summary>
public enum ReaderTextAlignment
{
    Publisher,
    Left,
    Justified,
}

/// <summary>The axes of <c>reading-themes</c>, none added and none dropped.</summary>
public enum ThemeAxis
{
    FontSize,
    FontFamily,
    BoldText,
    LineSpacing,
    CharacterSpacing,
    WordSpacing,
    ParagraphSpacing,
    Margins,
    TextAlignment,
    Hyphenation,
}

/// <summary>
/// The reader's own typography over a preset: the phones' <c>ThemeValues</c> with the same defaults, the
/// font size as a percentage of the publication's own (desktop-clients wave 4; <c>ebook-reader</c>,
/// "Typography controls").
/// </summary>
public sealed record ThemeValues(
    ReaderTypeface Typeface = ReaderTypeface.Publisher,
    int FontSize = 100,
    bool IsBold = false,
    double LineHeight = 1.4,
    double LetterSpacing = 0,
    double WordSpacing = 0,
    double ParagraphSpacing = 0.5,
    double PageMargins = 1,
    ReaderTextAlignment TextAlignment = ReaderTextAlignment.Publisher,
    bool IsHyphenated = false);

/// <summary>
/// The look of the EPUB reader, kept per PC: the preset, the reader's typography, scroll or pages, the
/// brightness, and the light and dark pair the page follows when the system appearance changes. Saved as JSON
/// through a source-generated context; a missing or damaged file gives the defaults.
/// </summary>
public sealed record EpubLook(
    ThemePreset Preset = ThemePreset.Original,
    ThemeValues? Values = null,
    bool Scrolls = false,
    double Brightness = 1,
    bool FollowsAppearance = false,
    ThemePreset LightTheme = ThemePreset.Paper,
    ThemePreset DarkTheme = ThemePreset.Focus)
{
    [JsonIgnore]
    public ThemeValues Typography => Values ?? new ThemeValues();

    /// <summary>Whether the reader moved an axis away from the defaults, which the active swatch says as "Modified".</summary>
    [JsonIgnore]
    public bool IsModified => Typography != new ThemeValues();

    /// <summary>The preset the page shows for a system appearance: the pair when the look follows it, else the chosen preset.</summary>
    public ThemePreset PresetFor(bool systemIsDark) =>
        !FollowsAppearance ? Preset : systemIsDark ? DarkTheme : LightTheme;

    public string Save() => JsonSerializer.Serialize(this, EpubLookJsonContext.Default.EpubLook);

    public static EpubLook Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return new EpubLook();
        }

        try
        {
            var look = JsonSerializer.Deserialize(text, EpubLookJsonContext.Default.EpubLook) ?? new EpubLook();
            return look with
            {
                Brightness = Math.Clamp(look.Brightness, ReadingThemes.MinimumBrightness, 1),
                Values = look.Typography with { FontSize = ReadingThemes.NearestSize(look.Typography.FontSize) },
            };
        }
        catch (JsonException)
        {
            return new EpubLook();
        }
    }
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, UseStringEnumConverter = true)]
[JsonSerializable(typeof(EpubLook))]
internal sealed partial class EpubLookJsonContext : JsonSerializerContext;

/// <summary>
/// The rules of <c>reading-themes</c> the Windows reader applies, platform-free so they test on any host: the size
/// ladder, the slider ranges, which axes the publisher's styles govern, the preset colours from the design tokens,
/// and the axes a <c>theme</c> message carries to the renderer. The Mac's <c>EpubTypography</c> is the twin.
/// </summary>
public static class ReadingThemes
{
    /// <summary>The discrete font sizes, in percent: nine steps, weighted upward.</summary>
    public static IReadOnlyList<int> FontSizes { get; } = [70, 80, 90, 100, 115, 130, 150, 175, 200];

    /// <summary>The base gutter one margin step stands for, in CSS pixels.</summary>
    public const double GutterUnit = 24;

    /// <summary>The dimmest the page goes; the renderer darkens it by the difference from one.</summary>
    public const double MinimumBrightness = 0.5;

    /// <summary>Only Original keeps the publication's own stylesheet.</summary>
    public static bool KeepsPublisherStyles(this ThemePreset preset) => preset == ThemePreset.Original;

    /// <summary>The axes the publisher's stylesheet governs; under Original they are shown unavailable, never as live controls.</summary>
    public static bool RequiresPublisherStylesOff(this ThemeAxis axis) => axis is ThemeAxis.LineSpacing or ThemeAxis.CharacterSpacing
        or ThemeAxis.WordSpacing or ThemeAxis.ParagraphSpacing or ThemeAxis.TextAlignment or ThemeAxis.Hyphenation;

    /// <summary>Whether an axis reaches the page under <paramref name="preset"/>.</summary>
    public static bool IsEffective(ThemeAxis axis, ThemePreset preset) => !(preset.KeepsPublisherStyles() && axis.RequiresPublisherStylesOff());

    /// <summary>The span a slider covers, or <c>null</c> for the ladder, the pickers and the switches.</summary>
    public static (double Minimum, double Maximum)? SliderRange(this ThemeAxis axis) => axis switch
    {
        ThemeAxis.LineSpacing => (1.0, 2.5),
        ThemeAxis.CharacterSpacing => (0, 0.25),
        ThemeAxis.WordSpacing => (0, 0.5),
        ThemeAxis.ParagraphSpacing => (0, 2.0),
        ThemeAxis.Margins => (0.5, 2.5),
        _ => null,
    };

    /// <summary>One adjustment: a tenth of the range.</summary>
    public static double Step(this ThemeAxis axis) => axis.SliderRange() is { } range ? (range.Maximum - range.Minimum) / 10 : 0;

    /// <summary>The CSS family the renderer matches on, or <c>null</c> for the publication's own.</summary>
    public static string? CssFamily(this ReaderTypeface typeface) => typeface switch
    {
        ReaderTypeface.Serif => "serif",
        ReaderTypeface.Sans => "sans-serif",
        ReaderTypeface.Literata => "Literata",
        ReaderTypeface.SourceSerif => "Source Serif 4",
        ReaderTypeface.EbGaramond => "EB Garamond",
        ReaderTypeface.Bitter => "Bitter",
        ReaderTypeface.AtkinsonHyperlegible => "Atkinson Hyperlegible",
        _ => null,
    };

    /// <summary>The name of the face's files in <c>packages/fonts</c>, without a suffix, or <c>null</c> for the three not bundled.</summary>
    public static string? FileStem(this ReaderTypeface typeface) => typeface switch
    {
        ReaderTypeface.Literata => "Literata",
        ReaderTypeface.SourceSerif => "SourceSerif4",
        ReaderTypeface.EbGaramond => "EBGaramond",
        ReaderTypeface.Bitter => "Bitter",
        ReaderTypeface.AtkinsonHyperlegible => "AtkinsonHyperlegible",
        _ => null,
    };

    /// <summary>The next step up the ladder, or the same at the top.</summary>
    public static int LargerSize(int size) => FontSizes[Math.Min(IndexOfSize(size) + 1, FontSizes.Count - 1)];

    /// <summary>The next step down the ladder, or the same at the bottom.</summary>
    public static int SmallerSize(int size) => FontSizes[Math.Max(IndexOfSize(size) - 1, 0)];

    /// <summary>The step nearest <paramref name="size"/>, so a hand-edited file lands on the ladder.</summary>
    public static int NearestSize(int size) => FontSizes.MinBy(step => Math.Abs(step - size));

    private static int IndexOfSize(int size) => FontSizes.ToList().IndexOf(NearestSize(size));

    /// <summary>
    /// A preset's background and text, <c>#rrggbb</c>, from the <c>readingThemes</c> design tokens (the values
    /// <c>StoryArcTokens.xaml</c> carries, which a test holds this table to).
    /// </summary>
    public static (string Background, string Text) Colours(ThemePreset preset) => preset switch
    {
        ThemePreset.Quiet => ("#161310", "#c7c3bf"),
        ThemePreset.Paper => ("#f5f1ec", "#1d1a17"),
        ThemePreset.Bold => ("#fcfcfc", "#060606"),
        ThemePreset.Calm => ("#3f3329", "#e5d9c4"),
        ThemePreset.Focus => ("#040303", "#e7e4e0"),
        _ => ("#fcfcfa", "#131110"),
    };

    /// <summary>The darken filter the renderer takes, in percent, for a brightness from one half to one.</summary>
    public static int Darken(double brightness) =>
        (int)Math.Round((1 - Math.Clamp(brightness, MinimumBrightness, 1)) * 100, MidpointRounding.AwayFromZero);

    /// <summary>
    /// Every axis of a <c>theme</c> message: the preset's colours (none under Original, which keeps the book's),
    /// the reader's size, face, weight, margins and scroll under every preset, and the spacings and alignment only
    /// when publisher styles are off. A theme message replaces every axis, so the whole set goes each time.
    /// </summary>
    public static JsonObject Axes(ThemePreset preset, ThemeValues values, bool scroll, double brightness)
    {
        var axes = new JsonObject { ["publisherStyles"] = preset.KeepsPublisherStyles() };
        if (!preset.KeepsPublisherStyles())
        {
            var (background, text) = Colours(preset);
            axes["backgroundColor"] = background;
            axes["textColor"] = text;
        }

        if (preset == ThemePreset.Bold || values.IsBold)
        {
            axes["fontWeight"] = 1.5;
        }

        axes["fontSize"] = NearestSize(values.FontSize) / 100.0;
        axes["pageGutter"] = Math.Round(values.PageMargins * GutterUnit);
        axes["scroll"] = scroll;
        if (values.Typeface.CssFamily() is { } family)
        {
            axes["fontFamily"] = family;
        }

        if (!preset.KeepsPublisherStyles())
        {
            axes["lineHeight"] = values.LineHeight;
            axes["letterSpacing"] = values.LetterSpacing;
            axes["wordSpacing"] = values.WordSpacing;
            axes["paragraphSpacing"] = values.ParagraphSpacing;
            if (values.IsHyphenated)
            {
                axes["hyphens"] = true;
            }

            switch (values.TextAlignment)
            {
                case ReaderTextAlignment.Left:
                    axes["textAlign"] = "left";
                    break;
                case ReaderTextAlignment.Justified:
                    axes["textAlign"] = "justify";
                    break;
            }
        }

        if (Darken(brightness) is > 0 and var darken)
        {
            axes["darkenFilter"] = darken;
        }

        return axes;
    }

    /// <summary>A slider's value in words for the label beside it and for Narrator: "1.5 times", "0.15 em".</summary>
    public static string ValueText(ThemeAxis axis, double value) => axis is ThemeAxis.LineSpacing or ThemeAxis.Margins
        ? value.ToString("0.##", CultureInfo.CurrentCulture) + "×"
        : value.ToString("0.###", CultureInfo.CurrentCulture) + " em";
}
