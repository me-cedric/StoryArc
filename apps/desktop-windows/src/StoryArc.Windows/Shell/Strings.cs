using Microsoft.Windows.ApplicationModel.Resources;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The app's strings, generated from the iOS catalogues into <c>Strings/&lt;lang&gt;/Resources.resw</c>
/// (<c>pnpm strings:desktop</c>). <c>Microsoft.Windows.ApplicationModel.Resources.ResourceManager</c>
/// reads the language the user set and falls back to English; <c>ResourceMap.TryGetValue</c>
/// answers <c>null</c> for a key the catalogue does not hold, which is how a menu label the
/// catalogue has not gained yet falls back to its English text instead of a blank.
/// </summary>
internal static class Strings
{
    private static readonly ResourceMap Map = new ResourceManager().MainResourceMap;

    /// <summary>The string of <paramref name="key"/> in the user's language, or <paramref name="fallback"/> when the catalogue lacks it.</summary>
    public static string Get(string key, string fallback)
    {
        var value = Map.TryGetValue("Resources/" + key)?.ValueAsString;
        return string.IsNullOrEmpty(value) ? fallback : value;
    }

    /// <summary>A string the catalogue is known to hold. The key itself shows when it does not, so a blank never ships unnoticed.</summary>
    public static string Get(string key) => Get(key, key);
}
