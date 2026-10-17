namespace StoryArc.Interop.Settings;

/// <summary>
/// The licence notices the About page shows (desktop-clients task 6.3): the generated
/// <c>THIRD_PARTY_NOTICES.md</c>, copied beside the executable at build and read at run time. The
/// <see cref="Components"/> are the rows of its tables, so the page and its test can say which
/// libraries the file lists without parsing anything the generator does not guarantee.
/// </summary>
public sealed record Acknowledgements(string Text, IReadOnlyList<string> Components)
{
    /// <summary>The file's name in the package, the same as in the repository.</summary>
    public const string FileName = "THIRD_PARTY_NOTICES.md";

    /// <summary>The notices read from <paramref name="path"/>, or <c>null</c> when the file is missing or empty: a packaging bug the page says so.</summary>
    public static Acknowledgements? Load(string path)
    {
        try
        {
            return File.Exists(path) ? From(File.ReadAllText(path)) : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static Acknowledgements? From(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        // A table row of the generator: "| [Name](url) | ...". The name is what sits in the brackets.
        var components = text.Split('\n')
            .Select(line => line.TrimStart())
            .Where(line => line.StartsWith("| [", StringComparison.Ordinal) && line.IndexOf(']') > 3)
            .Select(line => line[3..line.IndexOf(']')])
            .ToList();
        return new Acknowledgements(text, components);
    }
}
