namespace StoryArc.Interop.Settings;

/// <summary>A colour as the token file and <c>Windows.UI.Color</c> both carry it.</summary>
public readonly record struct Argb(byte A, byte R, byte G, byte B)
{
    /// <summary>Reads <c>#AARRGGBB</c>, the form of the generated token file.</summary>
    public static Argb Parse(string hex)
    {
        if (hex.Length != 9 || hex[0] != '#')
        {
            throw new FormatException($"Expected #AARRGGBB, got '{hex}'.");
        }

        var value = Convert.ToUInt32(hex[1..], 16);
        return new Argb((byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value);
    }

    public override string ToString() => $"#{A:X2}{R:X2}{G:X2}{B:X2}";
}

/// <summary>
/// The seven values WinUI reads for an accent: <c>SystemAccentColor</c> and its three light and
/// three dark shades. The brand palette is one value seven times (the brand accent is the same on
/// both appearances by design); the system palette carries the shades Windows computes.
/// </summary>
public sealed record AccentPalette(Argb Base, Argb Light1, Argb Light2, Argb Light3, Argb Dark1, Argb Dark2, Argb Dark3)
{
    public static AccentPalette Uniform(Argb colour) => new(colour, colour, colour, colour, colour, colour, colour);
}

/// <summary>
/// The chrome accent setting (desktop-clients task 2.47e, after 2.23e; desktop-experience "The
/// interface accent and the system appearance"). The brand colour when nothing is stored, the
/// system accent once the reader chooses it, and a later change of the system accent reaching the
/// chrome at once because the app resolves again on every change. A colour taken from a cover
/// stays inside the readers under both choices.
/// </summary>
public static class ChromeAccent
{
    /// <summary>The <c>StoryArcBrandAccent</c> token. A test holds it to the generated token file.</summary>
    public static Argb Brand { get; } = new(0xFF, 0x8A, 0x4D, 0xF0);

    /// <summary>Whether the settings show the System choice: only where the system offers an accent colour.</summary>
    public static bool OffersSystemChoice(AccentPalette? systemAccent) => systemAccent is not null;

    /// <summary>The palette the chrome paints with, under <paramref name="choice"/> and what the system offers now.</summary>
    public static AccentPalette Resolve(AccentChoice choice, AccentPalette? systemAccent) =>
        choice == AccentChoice.System && systemAccent is not null ? systemAccent : AccentPalette.Uniform(Brand);

    /// <summary>The accent a reader shows for a cover: the cover's own colour, whatever the chrome choice.</summary>
    public static Argb ReaderAccent(Argb coverColour, AccentChoice choice) => coverColour;
}
