using System.Text.Json.Nodes;

namespace StoryArc.Interop.Data;

/// <summary>One named block of the diagnostic: key and value lines.</summary>
public sealed record DiagnosticSection(string Name, IReadOnlyList<(string Key, string Value)> Lines);

/// <summary>
/// The diagnostic's text (<c>storyarc_diagnostic_render</c>): the sections the app wrote, with every credential the app holds
/// and every server host name removed in every encoding, then the phones' own rules. Nothing leaves the core with a credential
/// in it, which is what the export of 3.23 relies on.
/// </summary>
public static unsafe class Diagnostics
{
    /// <summary>The report as text. <paramref name="heldCredentials"/> are the credentials in the vault now, so the core can find them.</summary>
    public static string Render(string title, IReadOnlyList<DiagnosticSection> sections, IReadOnlyList<string> heldCredentials)
    {
        var request = new JsonObject
        {
            ["title"] = title,
            ["sections"] = new JsonArray(sections.Select(section => (JsonNode?)new JsonObject
            {
                ["name"] = section.Name,
                ["lines"] = new JsonArray(section.Lines.Select(line => (JsonNode?)new JsonArray(line.Key, line.Value)).ToArray()),
            }).ToArray()),
            ["secrets"] = new JsonArray(heldCredentials.Select(credential => (JsonNode?)credential).ToArray()),
        };
        return NativeCore.CallJson(NativeMethods.storyarc_diagnostic_render, "storyarc_diagnostic_render", request.ToJsonString());
    }
}

/// <summary>What a folder weighs, for the storage view (<c>storyarc_storage_bytes</c>): every file under it. A missing folder weighs nothing.</summary>
public static unsafe class StorageBytes
{
    public static long Of(string folder)
    {
        var bytes = NativeCore.Utf8(folder);
        ulong total = 0;
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_storage_bytes(data, (nuint)bytes.Length, &total), "storyarc_storage_bytes");
        }

        return checked((long)total);
    }
}
