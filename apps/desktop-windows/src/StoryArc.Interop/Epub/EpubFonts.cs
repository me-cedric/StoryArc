using System.Text;

namespace StoryArc.Interop.Epub;

/// <summary>
/// The reading faces the phones bundle, served to the renderer on the book's own origin (<c>ebook-reader</c>,
/// "Bundled typefaces"). Every chapter the host serves links one stylesheet of <c>@font-face</c> rules, and the
/// faces it names are the files of <c>packages/fonts</c>, so the renderer's <c>fontFamily</c> finds them by the
/// family name the phones use. The Mac's <c>EpubFonts</c> is the twin.
/// </summary>
public static class EpubFonts
{
    /// <summary>The folder on the origin the faces are served from.</summary>
    public const string Folder = "storyarc-fonts/";

    /// <summary>The stylesheet every chapter links.</summary>
    public const string Sheet = Folder + "faces.css";

    /// <summary>Every file the stylesheet names, without the suffix, so the app project and a test can check each is there.</summary>
    public static IReadOnlyList<string> Files { get; } =
    [
        "Literata", "Literata-Italic", "SourceSerif4", "SourceSerif4-Italic", "EBGaramond", "EBGaramond-Italic",
        "Bitter", "Bitter-Italic", "AtkinsonHyperlegible-Regular", "AtkinsonHyperlegible-Italic",
        "AtkinsonHyperlegible-Bold", "AtkinsonHyperlegible-BoldItalic",
    ];

    /// <summary>The <c>@font-face</c> rules: the four variable families upright and italic, Atkinson Hyperlegible's four static files.</summary>
    public static string Css { get; } = string.Join("\n", new[]
    {
        Rule(ReaderTypeface.Literata, "Literata", "normal", "300 700"),
        Rule(ReaderTypeface.Literata, "Literata-Italic", "italic", "300 700"),
        Rule(ReaderTypeface.SourceSerif, "SourceSerif4", "normal", "300 700"),
        Rule(ReaderTypeface.SourceSerif, "SourceSerif4-Italic", "italic", "300 700"),
        Rule(ReaderTypeface.EbGaramond, "EBGaramond", "normal", "400 700"),
        Rule(ReaderTypeface.EbGaramond, "EBGaramond-Italic", "italic", "400 700"),
        Rule(ReaderTypeface.Bitter, "Bitter", "normal", "300 700"),
        Rule(ReaderTypeface.Bitter, "Bitter-Italic", "italic", "300 700"),
        Rule(ReaderTypeface.AtkinsonHyperlegible, "AtkinsonHyperlegible-Regular", "normal", "400"),
        Rule(ReaderTypeface.AtkinsonHyperlegible, "AtkinsonHyperlegible-Italic", "italic", "400"),
        Rule(ReaderTypeface.AtkinsonHyperlegible, "AtkinsonHyperlegible-Bold", "normal", "700"),
        Rule(ReaderTypeface.AtkinsonHyperlegible, "AtkinsonHyperlegible-BoldItalic", "italic", "700"),
    });

    private static string Rule(ReaderTypeface face, string file, string style, string weight) =>
        "@font-face{font-family:\"" + face.CssFamily() + "\";src:url(\"" + file + ".ttf\") format(\"truetype\");"
        + "font-style:" + style + ";font-weight:" + weight + ";font-display:swap}";

    /// <summary>
    /// The stylesheet, or a face file <paramref name="face"/> reads by its name without the suffix; <c>null</c> for any
    /// other path, a name the sheet does not list, or a file the app does not carry.
    /// </summary>
    public static EpubResource? Resource(string href, Func<string, byte[]?> face)
    {
        if (!href.StartsWith(Folder, StringComparison.Ordinal))
        {
            return null;
        }

        if (href == Sheet)
        {
            return new EpubResource(Encoding.UTF8.GetBytes(Css), "text/css");
        }

        var name = href[Folder.Length..];
        if (!name.EndsWith(".ttf", StringComparison.Ordinal) || !Files.Contains(name[..^4]))
        {
            return null;
        }

        return face(name[..^4]) is { } bytes ? new EpubResource(bytes, "font/ttf") : null;
    }

    /// <summary>
    /// A chapter with the stylesheet linked before its head closes; anything else unchanged. The <c>rel</c> carries a
    /// second token on purpose: the toolkit adds its default stylesheet only to a chapter with no
    /// <c>link[rel='stylesheet']</c>, and a token list still loads the sheet without matching that selector.
    /// </summary>
    public static byte[] Linking(byte[] body, string mediaType, string sheetUrl)
    {
        if (!mediaType.StartsWith("application/xhtml+xml", StringComparison.OrdinalIgnoreCase)
            && !mediaType.StartsWith("text/html", StringComparison.OrdinalIgnoreCase))
        {
            return body;
        }

        var text = Encoding.UTF8.GetString(body);
        var close = text.IndexOf("</head>", StringComparison.OrdinalIgnoreCase);
        if (close < 0)
        {
            return body;
        }

        var link = "<link rel=\"stylesheet storyarc-fonts\" type=\"text/css\" href=\"" + sheetUrl + "\"/>";
        return Encoding.UTF8.GetBytes(text.Insert(close, link));
    }
}
