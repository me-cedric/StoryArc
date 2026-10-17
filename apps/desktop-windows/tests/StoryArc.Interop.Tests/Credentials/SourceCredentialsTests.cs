using System.Text;
using StoryArc.Interop;
using StoryArc.Interop.Credentials;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Sources;
using StoryArc.Interop.Tests.Support;

namespace StoryArc.Interop.Tests.Credentials;

/// <summary>
/// Credentials through the core's vault (desktop-clients task 3.22; desktop-experience, "Secrets in the system's own store"). On
/// Windows the vault is Credential Manager; on the hosts that run this suite it is the session-only store, which is the path a
/// machine with no secure store takes. The 2560-byte rule and the search of the data directory hold on both.
/// </summary>
public sealed class SourceCredentialsTests : IDisposable
{
    private const string SourceId = "11111111-1111-1111-1111-111111111111";

    private readonly CoreRuntime _runtime = CoreRuntime.Create();
    private readonly CredentialVault _vault;
    private readonly SourceCredentials _credentials;

    public SourceCredentialsTests()
    {
        _vault = CredentialVault.Open(_runtime);
        _credentials = new SourceCredentials(_vault);
    }

    public void Dispose()
    {
        // The vault is shared with the real Credential Manager on Windows: leave nothing behind.
        _credentials.Forget(new NetworkSource(SourceId, NetworkSourceKind.OpdsCatalogue, "x", "https://x.example/"));
        _vault.Dispose();
        _runtime.Dispose();
    }

    [Fact]
    public void A_password_goes_to_the_vault_and_comes_back_and_forgetting_the_source_removes_it()
    {
        var saved = _credentials.Save(SourceId, CredentialField.Password, "hunter2-session");

        Assert.True(saved.Outcome is CredentialOutcome.Stored or CredentialOutcome.SessionOnly);
        Assert.False(saved.NeedsSignIn);
        Assert.Equal("hunter2-session", _credentials.Load(SourceId, CredentialField.Password));

        var source = new NetworkSource(SourceId, NetworkSourceKind.NetworkShare, "NAS", "smb://nas/comics", Username: "reader");
        Assert.True(_credentials.Holds(source));
        _credentials.Forget(source);
        Assert.Null(_credentials.Load(SourceId, CredentialField.Password));
        Assert.False(_credentials.Holds(source));
    }

    [Fact]
    public void Without_a_secure_store_the_first_save_says_once_what_supplies_one()
    {
        if (OperatingSystem.IsWindows())
        {
            // Credential Manager is there: nothing to say, and the credential is kept past the session.
            Assert.Equal(CredentialOutcome.Stored, _credentials.Save(SourceId, CredentialField.Token, "t").Outcome);
            return;
        }

        var first = _credentials.Save(SourceId, CredentialField.Token, "one");
        var second = _credentials.Save(SourceId, CredentialField.Token, "two");

        Assert.Equal(CredentialOutcome.SessionOnly, first.Outcome);
        Assert.False(string.IsNullOrWhiteSpace(first.Notice), "the grey line names the fix");
        Assert.Equal(CredentialOutcome.SessionOnly, second.Outcome);
        Assert.Null(second.Notice);
        Assert.Equal("two", _credentials.Load(SourceId, CredentialField.Token));
    }

    [Theory]
    [InlineData(2559, true)]
    [InlineData(2560, true)]
    [InlineData(2561, false)]
    [InlineData(4000, false)]
    public void A_token_is_kept_up_to_2560_bytes_and_refused_by_name_beyond(int bytes, bool kept)
    {
        var token = new string('k', bytes);

        var saved = _credentials.Save(SourceId, CredentialField.Token, token);

        Assert.Equal(kept, SourceCredentials.Fits(token));
        if (kept)
        {
            Assert.False(saved.NeedsSignIn);
            Assert.Equal(token, _credentials.Load(SourceId, CredentialField.Token));
        }
        else
        {
            Assert.Equal(CredentialOutcome.TooLong, saved.Outcome);
            Assert.True(saved.NeedsSignIn);
            Assert.Contains("2560", saved.Failure, StringComparison.Ordinal);
            Assert.Null(_credentials.Load(SourceId, CredentialField.Token));
        }
    }

    [Fact]
    public void The_limit_counts_bytes_not_characters_and_a_refused_longer_credential_keeps_no_older_copy()
    {
        // 1300 two-byte characters are 2600 bytes: under the limit as text, over it as the blob the store keeps.
        var wide = new string('é', 1300);
        Assert.Equal(1300, wide.Length);
        Assert.False(SourceCredentials.Fits(wide));

        _ = _credentials.Save(SourceId, CredentialField.Token, "old-token");
        var refused = _credentials.Save(SourceId, CredentialField.Token, wide);

        Assert.Equal(CredentialOutcome.TooLong, refused.Outcome);
        Assert.Null(_credentials.Load(SourceId, CredentialField.Token));
    }

    [Fact]
    public void No_file_the_app_writes_holds_a_credential_in_any_encoding_not_even_a_long_token_or_one_typed_into_an_address()
    {
        var longToken = "tok_" + new string(Enumerable.Range(0, 2400).Select(index => (char)('a' + (index * 7 % 26))).ToArray());
        Assert.True(SourceCredentials.Fits(longToken));
        const string password = "hunter2-p4ssw0rd";
        using var data = Corpus.TemporaryFolder();

        // A reader pastes an address with the sign-in inside it, and enters a token for a catalogue.
        var added = NetworkSourceList.Empty.Adding(NetworkSourceKind.NetworkShare, "NAS", $"smb://reader:{password}@nas.local/comics");
        Assert.Equal("smb://nas.local/comics", added.Source.Address);
        _ = _credentials.Save(added.Source.Id, CredentialField.Password, added.Typed.Password!);
        var catalogue = added.List.Adding(NetworkSourceKind.OpdsCatalogue, "Books", "https://books.example/opds");
        _ = _credentials.Save(catalogue.Source.Id, CredentialField.Token, longToken);

        // Every file the app keeps, written the way the app writes it.
        File.WriteAllText(Path.Combine(data.FullPath, "network-sources.json"), catalogue.List.Save());
        var queue = DownloadQueues.Apply(DownloadQueue.Empty, [QueueOp.Queue("p", "P", "https://books.example/p.cbz", catalogue.Source.Id)]).Queue;
        File.WriteAllText(Path.Combine(data.FullPath, "downloads.json"), queue.Save());
        File.WriteAllText(Path.Combine(data.FullPath, "shelves.json"), ShelvesState.Empty.Save());
        var pins = new PinBook();
        pins.Add("books.example", "AB:CD");
        File.WriteAllText(Path.Combine(data.FullPath, "pins.json"), pins.Save());
        File.WriteAllText(Path.Combine(data.FullPath, "settings.json"), AppSettings.Default.Save());
        using (var progress = ProgressStore.Open(Path.Combine(data.FullPath, "progress.sqlite")))
        {
            progress.Write(CoreProgress.Page(new CoreIdentity(ContentDigest: "d1"), 3, 10, DateTimeOffset.UnixEpoch));
        }

        var snapshot = LibrarySnapshots.Build(
            catalogue.List.ToDocumentSources(new HashSet<string>()), pins, ShelvesState.Empty, []);
        File.WriteAllText(
            Path.Combine(data.FullPath, "library.json"),
            LibraryDocuments.Export(snapshot, "1.0.0", "windows", DateTimeOffset.UnixEpoch));
        File.WriteAllText(
            Path.Combine(data.FullPath, "diagnostic.txt"),
            Diagnostics.Render(
                "StoryArc diagnostic",
                [new DiagnosticSection("sources", [("address", $"smb://reader:{password}@nas.local/comics"), ("token", longToken)])],
                [password, longToken]));

        Assert.Equal(longToken, _credentials.Load(catalogue.Source.Id, CredentialField.Token));
        Assert.Equal(password, _credentials.Load(added.Source.Id, CredentialField.Password));
        Assert.Empty(DataDirectorySearch.Hits(data.FullPath, password));
        Assert.Empty(DataDirectorySearch.Hits(data.FullPath, longToken));
        Assert.Empty(DataDirectorySearch.Hits(data.FullPath, Convert.ToBase64String(Encoding.UTF8.GetBytes(password))));

        _credentials.Forget(added.Source);
        _credentials.Forget(catalogue.Source);
    }

    [Fact]
    public void The_search_itself_finds_a_credential_in_each_encoding_so_a_clean_result_means_something()
    {
        const string credential = "needle-0123456789-needle";
        using var data = Corpus.TemporaryFolder();
        var written = new Dictionary<string, byte[]>
        {
            ["utf8"] = Encoding.UTF8.GetBytes("x" + credential + "y"),
            ["utf16le"] = Encoding.Unicode.GetBytes(credential),
            ["utf16be"] = Encoding.BigEndianUnicode.GetBytes(credential),
            ["hex"] = Encoding.ASCII.GetBytes(Convert.ToHexString(Encoding.UTF8.GetBytes(credential))),
            ["base64-0"] = Encoding.ASCII.GetBytes(Convert.ToBase64String(Encoding.UTF8.GetBytes(credential))),
            ["base64-1"] = Encoding.ASCII.GetBytes(Convert.ToBase64String(Encoding.UTF8.GetBytes("a" + credential))),
            ["base64-2"] = Encoding.ASCII.GetBytes(Convert.ToBase64String(Encoding.UTF8.GetBytes("ab" + credential))),
        };
        foreach (var (name, bytes) in written)
        {
            File.WriteAllBytes(Path.Combine(data.FullPath, name), bytes);
        }

        var hits = DataDirectorySearch.Hits(data.FullPath, credential);

        foreach (var name in written.Keys)
        {
            Assert.Contains(hits, hit => hit.StartsWith(name + " ", StringComparison.Ordinal));
        }
    }
}
