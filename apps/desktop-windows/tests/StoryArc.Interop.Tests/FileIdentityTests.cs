namespace StoryArc.Interop.Tests;

/// <summary>The identity an EPUB, a PDF or an audiobook file is filed under, through <c>storyarc_file_identity</c>.</summary>
public sealed class FileIdentityTests
{
    [Fact]
    public void A_file_is_known_by_its_content_digest_and_keeps_it_when_copied_elsewhere()
    {
        using var folder = Corpus.TemporaryFolder();
        var source = Corpus.Path("comics/text-pages.pdf");
        var copy = Path.Combine(folder.FullPath, "renamed.pdf");
        File.Copy(source, copy);

        var original = FileIdentity.Of(source);
        var moved = FileIdentity.Of(copy);

        Assert.NotNull(original.ContentDigest);
        Assert.NotEmpty(original.ContentDigest);
        Assert.DoesNotContain("path-", original.ContentDigest, StringComparison.Ordinal);
        Assert.Equal(original.ContentDigest, moved.ContentDigest);
        Assert.NotEqual(original.NormalizedPath, moved.NormalizedPath);
    }

    [Fact]
    public void A_missing_file_is_named_not_found()
    {
        using var folder = Corpus.TemporaryFolder();
        var error = Assert.Throws<StoryArcException>(() => FileIdentity.Of(Path.Combine(folder.FullPath, "gone.epub")));
        Assert.Equal(StoryArcStatus.NotFound, error.Status);
    }
}
