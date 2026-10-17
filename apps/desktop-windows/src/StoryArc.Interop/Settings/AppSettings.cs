using System.Text.Json;
using System.Text.Json.Serialization;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Settings;

/// <summary>The chrome accent: the StoryArc brand colour, or the system's accent (design.md, Open Question 1).</summary>
public enum AccentChoice
{
    StoryArc,
    System,
}

/// <summary>The appearance choices of the settings (docs/designs/desktop/windows.md, section 5).</summary>
public enum AppearanceChoice
{
    System,
    Light,
    Dark,
    OledDark,
    Natural,
}

/// <summary>
/// The settings record the preferences page edits and the app reads at launch. Saved as JSON
/// through a source-generated context; a missing or damaged file gives <see cref="Default"/>, so a
/// bad file never costs a reader their library (desktop-clients tasks 2.47 and 2.47e).
/// </summary>
public sealed record AppSettings(
    [property: JsonConverter(typeof(JsonStringEnumConverter<AccentChoice>))] AccentChoice Accent = AccentChoice.StoryArc,
    [property: JsonConverter(typeof(JsonStringEnumConverter<AppearanceChoice>))] AppearanceChoice Appearance = AppearanceChoice.System,
    bool ClickZonesOn = true,
    [property: JsonConverter(typeof(JsonStringEnumConverter<TransitionMode>))] TransitionMode Transition = TransitionMode.Slide)
{
    /// <summary>
    /// What a reader who has chosen nothing gets: the brand accent, the system appearance, the
    /// click zones on (design.md, Open Question 2) and the slide transition until the curl lands.
    /// The constructor defaults are also what a file that lacks a key gives, so an older file
    /// opens with the new keys at their defaults.
    /// </summary>
    public static AppSettings Default { get; } = new();

    public string Save() => JsonSerializer.Serialize(this, AppSettingsJsonContext.Default.AppSettings);

    public static AppSettings Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Default;
        }

        try
        {
            return JsonSerializer.Deserialize(text, AppSettingsJsonContext.Default.AppSettings) ?? Default;
        }
        catch (JsonException)
        {
            return Default;
        }
    }
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(AppSettings))]
internal sealed partial class AppSettingsJsonContext : JsonSerializerContext;
