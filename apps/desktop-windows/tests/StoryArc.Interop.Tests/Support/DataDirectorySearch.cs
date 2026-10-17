using System.Text;

namespace StoryArc.Interop.Tests.Support;

/// <summary>
/// Searches every file under a folder for a known credential in every encoding a careless writer might have used
/// (desktop-experience, "Searching the app's files": none holds it, in any encoding). A hit names the file and the encoding.
/// </summary>
internal static class DataDirectorySearch
{
    /// <summary>The files under <paramref name="folder"/> that hold <paramref name="credential"/>, each with the encoding that matched.</summary>
    public static IReadOnlyList<string> Hits(string folder, string credential)
    {
        var needles = Encodings(credential).ToList();
        var hits = new List<string>();
        foreach (var file in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories))
        {
            var bytes = File.ReadAllBytes(file);
            foreach (var (name, needle) in needles)
            {
                if (bytes.AsSpan().IndexOf(needle) >= 0)
                {
                    hits.Add($"{Path.GetRelativePath(folder, file)} ({name})");
                }
            }
        }

        return hits;
    }

    /// <summary>The credential as bytes in each encoding: UTF-8, both UTF-16 orders, Latin-1, hex, base64 at each alignment, percent and JSON escapes, and reversed.</summary>
    public static IEnumerable<(string Name, byte[] Needle)> Encodings(string credential)
    {
        var utf8 = Encoding.UTF8.GetBytes(credential);
        yield return ("UTF-8", utf8);
        yield return ("UTF-16 little endian", Encoding.Unicode.GetBytes(credential));
        yield return ("UTF-16 big endian", Encoding.BigEndianUnicode.GetBytes(credential));
        yield return ("Latin-1", Encoding.Latin1.GetBytes(credential));
        yield return ("hex", Encoding.ASCII.GetBytes(Convert.ToHexString(utf8)));
        yield return ("lower hex", Encoding.ASCII.GetBytes(Convert.ToHexStringLower(utf8)));
        yield return ("percent", Encoding.ASCII.GetBytes(Uri.EscapeDataString(credential)));
        var characters = credential.ToCharArray();
        Array.Reverse(characters);
        yield return ("reversed", Encoding.UTF8.GetBytes(new string(characters)));

        // Base64 of a credential inside a longer string depends on where it starts, so each of the three alignments is searched,
        // keeping only the groups of three bytes that hold nothing but the credential.
        for (var offset = 0; offset < 3; offset++)
        {
            var padded = new byte[offset + utf8.Length];
            utf8.CopyTo(padded, offset);
            var encoded = Convert.ToBase64String(padded);
            var start = offset == 0 ? 0 : 4;
            var end = padded.Length / 3 * 4;
            if (end - start >= 8)
            {
                yield return ($"base64 at offset {offset}", Encoding.ASCII.GetBytes(encoded[start..end]));
            }
        }
    }
}
