using StoryArc.Interop.Settings;

namespace StoryArc.Interop.Tests.Settings;

/// <summary>The About page's licence notices (task 6.3): the generated file lists PDFium and libarchive, and a missing file is a named failure, not a crash.</summary>
public sealed class AcknowledgementsTests
{
    private static Acknowledgements Repository() =>
        Acknowledgements.Load(Corpus.RepositoryPath(Acknowledgements.FileName))
        ?? throw new InvalidOperationException("THIRD_PARTY_NOTICES.md is not in the repository root.");

    [Fact]
    public void The_generated_notices_list_pdfium_and_libarchive()
    {
        var notices = Repository();

        Assert.Contains(notices.Components, name => name.StartsWith("PDFium", StringComparison.Ordinal));
        Assert.Contains(notices.Components, name => name.StartsWith("libarchive", StringComparison.Ordinal));
        Assert.Contains(notices.Components, name => name.StartsWith("NuGet ", StringComparison.Ordinal));
        Assert.Contains(notices.Components, name => name.StartsWith("Rust ", StringComparison.Ordinal));
    }

    [Fact]
    public void The_components_are_the_names_between_the_brackets_of_each_table_row()
    {
        var notices = Acknowledgements.From("# Notices\n| Component | Licence |\n| --- | --- |\n| [Foo 1.0](https://x) | `MIT` |\n  | [Bar](https://y) | `ISC` |\n");

        Assert.Equal(new[] { "Foo 1.0", "Bar" }, notices!.Components);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   \n")]
    public void An_empty_text_is_no_notices(string? text) => Assert.Null(Acknowledgements.From(text));

    [Fact]
    public void A_file_that_is_not_there_is_no_notices()
    {
        Assert.Null(Acknowledgements.Load(Path.Combine(Path.GetTempPath(), "storyarc-no-such-notices.md")));
    }
}
