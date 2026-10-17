using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;
using StoryArc.Interop.Sources;

namespace StoryArc.Interop.Tests.Sources;

/// <summary>The network sources of desktop-clients task 3.21: their records, the addresses typed into them, and each failure named apart.</summary>
public sealed class NetworkSourcesTests
{
    [Theory]
    [InlineData("smb://reader:hunter2@nas.local/comics", "smb://nas.local/comics", "reader", "hunter2")]
    [InlineData("https://ada:love%40lace@books.example/opds", "https://books.example/opds", "ada", "love@lace")]
    [InlineData("https://ada@books.example/opds", "https://books.example/opds", "ada", null)]
    [InlineData("smb://nas.local/comics", "smb://nas.local/comics", null, null)]
    [InlineData("\\\\nas\\comics", "\\\\nas\\comics", null, null)]
    [InlineData("  https://books.example/opds  ", "https://books.example/opds", null, null)]
    public void A_sign_in_typed_into_an_address_is_split_out_so_the_record_never_holds_it(string typed, string address, string? user, string? password)
    {
        var split = TypedAddress.From(typed);

        Assert.Equal(address, split.Address);
        Assert.Equal(user, split.Username);
        Assert.Equal(password, split.Password);
    }

    [Theory]
    [InlineData("smb://nas.local/comics", "nas.local")]
    [InlineData("https://books.example:8443/opds", "books.example")]
    [InlineData("\\\\nas\\comics", "nas")]
    public void A_source_without_a_name_shows_its_host(string typed, string host)
    {
        var added = NetworkSourceList.Empty.Adding(NetworkSourceKind.NetworkShare, "  ", typed);

        Assert.Equal(host, added.Source.Name);
    }

    [Fact]
    public void A_source_added_keeps_no_credential_and_the_list_survives_a_save_and_a_restore()
    {
        var shares = NetworkSourceList.Empty.Adding(NetworkSourceKind.NetworkShare, "NAS", "smb://reader:hunter2@nas.local/comics", port: 4445);
        var kavita = shares.List.Adding(NetworkSourceKind.KavitaServer, "Kavita", "https://kavita.example");

        var saved = kavita.List.Save();

        Assert.DoesNotContain("hunter2", saved, StringComparison.Ordinal);
        Assert.Contains("\"networkShare\"", saved, StringComparison.Ordinal);
        var restored = NetworkSourceList.Restore(saved);
        Assert.Equal(2, restored.Sources.Count);
        Assert.Equal(shares.Source, restored.Find(shares.Source.Id));
        Assert.Equal("reader", restored.Find(shares.Source.Id)!.Username);
        Assert.Equal(4445, restored.Find(shares.Source.Id)!.Port);
        Assert.Equal(new[] { "apiKey" }, kavita.Source.CredentialFields);
        Assert.Empty(NetworkSourceList.Restore("{not json").Sources);
        Assert.Empty(NetworkSourceList.Restore(null).Sources);
    }

    [Fact]
    public void A_source_is_renamed_removed_and_never_renamed_to_nothing()
    {
        var added = NetworkSourceList.Empty.Adding(NetworkSourceKind.OpdsCatalogue, "Books", "https://books.example/opds");

        var renamed = added.List.Renaming(added.Source.Id, "  Library  ");
        Assert.Equal("Library", renamed.Find(added.Source.Id)!.Name);
        Assert.Equal("Library", renamed.Renaming(added.Source.Id, " ").Find(added.Source.Id)!.Name);
        Assert.Empty(renamed.Without(added.Source.Id).Sources);
    }

    [Fact]
    public void The_sources_a_phone_added_arrive_as_needing_a_sign_in_and_a_phones_folder_does_not()
    {
        var document = File.ReadAllBytes(Corpus.Path("library/written-by-ios.json"));
        var merged = LibraryDocuments.Import(document, "{}", "windows");

        var adopted = NetworkSourceList.Empty.Adopting(merged.Sources());

        Assert.Equal(new[] { "Comics NAS", "Kavita" }, adopted.Sources.Select(source => source.Name).Order());
        var share = adopted.Sources.Single(source => source.Kind == NetworkSourceKind.NetworkShare);
        Assert.Equal("reader", share.Username);
        Assert.Equal("smb://nas.local/comics", share.Address);
        Assert.Same(adopted, adopted.Adopting(merged.Sources()));
        var needSignIn = adopted.Sources.Select(source => source.Id).ToHashSet();
        Assert.All(adopted.ToDocumentSources(needSignIn), source => Assert.True(source.NeedsSignIn));
    }

    [Theory]
    [InlineData(StoryArcStatus.Unreachable, "the server cannot be reached", SourceProblem.HostUnreachable)]
    [InlineData(StoryArcStatus.NotFound, "the server has no share of that name", SourceProblem.NotFound)]
    [InlineData(StoryArcStatus.Unauthorized, "the server refused the sign-in", SourceProblem.SignInRejected)]
    [InlineData(StoryArcStatus.Unsupported, "the server speaks only SMB 1, which is disabled for security reasons. Turn on SMB 2 in the server", SourceProblem.Smb1Only)]
    [InlineData(StoryArcStatus.Unsupported, "the share requires encryption. This connection cannot provide it", SourceProblem.EncryptionRequired)]
    [InlineData(StoryArcStatus.Storage, "Credential Manager refused", SourceProblem.CredentialNotKept)]
    [InlineData(StoryArcStatus.Unreadable, "the share failed: odd", SourceProblem.Unexpected)]
    public void Each_failure_of_a_source_is_named_apart_from_the_others(StoryArcStatus status, string message, SourceProblem expected)
    {
        var failure = SourceFailure.Of(new StoryArcException("storyarc_smb_connect", status, message));

        Assert.Equal(expected, failure.Problem);
        Assert.Equal(message, failure.Remedy);
        Assert.Null(failure.Certificate);
    }

    [Fact]
    public void An_untrusted_certificate_carries_its_fingerprint_to_the_pin_sheet_and_never_reads_as_a_wrong_password()
    {
        var failure = SourceFailure.Of(new StoryArcException(
            "storyarc_opds_feed",
            StoryArcStatus.Unauthorized,
            "nas.local presented a certificate this system does not trust; its fingerprint is AB:CD"));

        Assert.Equal(SourceProblem.CertificateNotTrusted, failure.Problem);
        Assert.Equal(new CertificateChallenge("nas.local", "AB:CD"), failure.Certificate);
    }
}
