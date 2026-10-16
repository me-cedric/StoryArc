using System.Globalization;
using System.Text;

namespace StoryArc.Interop.Text;

/// <summary>
/// Folds text for a search: trimmed, lower-cased with the invariant culture, and with the accents
/// stripped, so "Saga" finds "SAGA" and "Lumiere" finds "Lumière". The library search and the
/// settings search share it; the core's collation (task 2.7) owns sorting, not this.
/// </summary>
public static class TextFold
{
    public static string Fold(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        var decomposed = text.Trim().Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(char.ToLowerInvariant(character));
            }
        }

        return builder.ToString().Normalize(NormalizationForm.FormC);
    }
}
