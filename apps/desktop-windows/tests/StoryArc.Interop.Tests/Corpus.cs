namespace StoryArc.Interop.Tests;

/// <summary>
/// The shared publication corpus, <c>packages/test-fixtures</c>: the files the Rust core, the phones
/// and these tests all read, so a page decoded here is the page every other suite decodes. Found by
/// walking up from the test output folder to the folder that holds <c>manifest.json</c>.
/// </summary>
internal static class Corpus
{
    private static readonly Lazy<string> Root = new(FindRoot);

    /// <summary>The absolute path of a corpus file, for example <c>comics/large-page.cbz</c>.</summary>
    public static string Path(string relative) =>
        System.IO.Path.Combine(Root.Value, relative.Replace('/', System.IO.Path.DirectorySeparatorChar));

    /// <summary>A fresh empty folder under the system's temporary folder, removed by the caller's <c>using</c>.</summary>
    public static TemporaryFolder TemporaryFolder() => new();

    private static string FindRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = System.IO.Path.Combine(directory.FullName, "packages", "test-fixtures");
            if (File.Exists(System.IO.Path.Combine(candidate, "manifest.json")))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new InvalidOperationException("packages/test-fixtures/manifest.json is not above " + AppContext.BaseDirectory);
    }
}

/// <summary>A temporary folder that deletes itself and everything in it.</summary>
internal sealed class TemporaryFolder : IDisposable
{
    public TemporaryFolder()
    {
        FullPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "storyarc-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(FullPath);
    }

    public string FullPath { get; }

    /// <summary>Copies a corpus file into this folder under its own name and returns the copy's path.</summary>
    public string Copy(string corpusRelative)
    {
        var source = Corpus.Path(corpusRelative);
        var target = System.IO.Path.Combine(FullPath, System.IO.Path.GetFileName(source));
        File.Copy(source, target);
        return target;
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(FullPath, recursive: true);
        }
        catch (IOException)
        {
            // A handle the core still holds on Windows; the system's temp cleaner takes it later.
        }
    }
}
