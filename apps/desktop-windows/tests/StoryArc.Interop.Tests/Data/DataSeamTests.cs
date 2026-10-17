using System.Text;
using System.Text.Json.Nodes;
using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Tests.Data;

/// <summary>
/// The wave 3 data seam through the C# wrappers: the download queue's rules, the shelves and their offline edits, the library
/// document, sealed credentials, the diagnostic and what a folder weighs. Each test is the Rust seam test of
/// <c>storyarc-ffi/tests/wave3.rs</c> written the way the Windows app calls it.
/// </summary>
public sealed class DataSeamTests
{
    private const string ShelfId = "33333333-3333-3333-3333-333333333333";

    [Fact]
    public void A_metered_connection_holds_what_the_policy_queued_and_a_failure_is_retried_after_two_seconds()
    {
        var queue = DownloadQueue.Empty;

        var outcome = DownloadQueues.Apply(
            queue,
            [
                QueueOp.Queue("a", "A", "https://books.example/a.cbz"),
                QueueOp.Queue("b", "B", "https://books.example/b.cbz"),
                QueueOp.Fail("a", QueueFailure.Network, retryable: true),
                QueueOp.Hold(ConnectionState.Metered, new DownloadPolicySettings(), used: 0),
            ],
            ConnectionState.Metered,
            new DownloadPolicySettings());

        var held = outcome.Queue.Get("b")!;
        Assert.Equal(DownloadStatus.Paused, held.Status);
        Assert.Equal("waitingForUnmetered", held.Pause);
        var failed = outcome.Queue.Get("a")!;
        Assert.Equal(DownloadStatus.Failed, failed.Status);
        Assert.Equal("network", failed.FailureKind);
        Assert.Equal(1, failed.Attempts);
        Assert.Equal(new RetryAfter("a", 2), Assert.Single(outcome.Retry));
        Assert.Empty(outcome.Startable);
    }

    [Fact]
    public void An_unmetered_connection_releases_the_held_rows_and_a_row_started_by_hand_runs_on_a_metered_one()
    {
        var policy = new DownloadPolicySettings();
        var held = DownloadQueues.Apply(
            DownloadQueue.Empty,
            [
                QueueOp.Queue("a", "A", "x"),
                QueueOp.Queue("hand", "Hand", "x", startedByHand: true),
                QueueOp.Hold(ConnectionState.Metered, policy, used: 0),
            ],
            ConnectionState.Metered,
            policy);

        Assert.Equal(DownloadStatus.Paused, held.Queue.Get("a")!.Status);
        Assert.Equal(new[] { "hand" }, held.Startable);

        var back = DownloadQueues.Apply(held.Queue, [QueueOp.Hold(ConnectionState.Unmetered, policy, used: 0)], ConnectionState.Unmetered, policy);

        Assert.Equal(DownloadStatus.Queued, back.Queue.Get("a")!.Status);
        Assert.Contains("a", back.Startable);
    }

    [Fact]
    public void A_connection_that_changes_mid_download_pauses_the_running_row_and_progress_survives_a_save_and_a_restore()
    {
        var policy = new DownloadPolicySettings();
        var running = DownloadQueues.Apply(
            DownloadQueue.Empty,
            [QueueOp.Queue("a", "A", "x"), QueueOp.Advance("a", 5, 10)]).Queue;
        // The seam has no operation that marks a row running: a row in flight stays queued, with its bytes.
        Assert.Equal(DownloadStatus.Queued, running.Get("a")!.Status);

        var paused = DownloadQueues.Apply(running, [QueueOp.Hold(ConnectionState.Metered, policy, used: 5)]).Queue;

        var row = paused.Get("a")!;
        Assert.Equal(DownloadStatus.Paused, row.Status);
        Assert.Equal(5, row.DownloadedBytes);
        Assert.Equal(0.5, row.Fraction);

        // A kill leaves a running row on disk; the next launch finds it queued, with its bytes kept.
        var afterKill = DownloadQueue.Restore(running.Save());
        Assert.Equal(DownloadStatus.Queued, afterKill.Get("a")!.Status);
        Assert.Equal(5, afterKill.Get("a")!.DownloadedBytes);
        Assert.Equal(DownloadQueue.Empty.Json, DownloadQueue.Restore("{not json").Json);
    }

    [Fact]
    public void No_connection_waits_in_grey_and_an_unsupported_container_fails_for_good()
    {
        var policy = new DownloadPolicySettings();

        var offline = DownloadQueues.Apply(
            DownloadQueue.Empty,
            [QueueOp.Queue("a", "A", "x"), QueueOp.Hold(ConnectionState.Offline, policy, used: 0)],
            ConnectionState.Offline,
            policy);
        Assert.Equal("waitingForNetwork", offline.Queue.Get("a")!.Pause);
        Assert.Empty(offline.Startable);

        var unsupported = DownloadQueues.Apply(
            DownloadQueue.Empty,
            [QueueOp.Queue("a", "A", "x"), QueueOp.Fail("a", QueueFailure.Unsupported("CB7"), retryable: false)]);
        Assert.Equal("unsupported", unsupported.Queue.Get("a")!.FailureKind);
        Assert.Equal("CB7", unsupported.Queue.Get("a")!.FailureDetail);
        Assert.Empty(unsupported.Retry);
    }

    [Fact]
    public void Bytes_that_arrive_whole_and_will_not_open_are_requeued_once_and_then_fail()
    {
        var first = DownloadQueues.Apply(
            DownloadQueue.Empty,
            [QueueOp.Queue("a", "A", "x"), QueueOp.FailVerification("a", QueueFailure.Unreadable)]);
        Assert.Equal(DownloadStatus.Queued, first.Queue.Get("a")!.Status);
        Assert.Equal(1, first.Queue.Get("a")!.VerificationFailures);

        var second = DownloadQueues.Apply(first.Queue, [QueueOp.FailVerification("a", QueueFailure.Unreadable)]);

        Assert.Equal(DownloadStatus.Failed, second.Queue.Get("a")!.Status);
        Assert.Equal("unreadable", second.Queue.Get("a")!.FailureKind);
    }

    [Theory]
    [InlineData(ConnectionState.Unmetered, 3)]
    [InlineData(ConnectionState.Metered, 1)]
    [InlineData(ConnectionState.Offline, 0)]
    public void The_hosts_bound_is_the_number_the_core_says_may_start(ConnectionState network, int bound)
    {
        var policy = new DownloadPolicySettings(UnmeteredOnly: false);
        var ops = Enumerable.Range(0, 10).Select(index => QueueOp.Queue($"r{index}", "R", "x")).ToList();

        var outcome = DownloadQueues.Apply(DownloadQueue.Empty, ops, network, policy);

        Assert.Equal(bound, policy.ConcurrencyFor(network));
        Assert.Equal(bound, outcome.Startable.Count);
    }

    [Fact]
    public void A_collection_gains_members_and_a_cover_and_a_reading_list_keeps_its_order()
    {
        var shelves = ShelfRules.Apply(
            ShelvesState.Empty,
            [
                ShelfOp.CreateCollection("Image Comics", ShelfId),
                ShelfOp.AddMembers(ShelfId, ["path:/a.cbz", "path:/b.cbz"]),
                ShelfOp.SetCollectionCover(ShelfId, "path:/b.cbz"),
                ShelfOp.CreateList("Reading order", "44444444-4444-4444-4444-444444444444"),
                ShelfOp.Append("44444444-4444-4444-4444-444444444444", ["z", "y", "x"]),
                ShelfOp.MoveEntry("44444444-4444-4444-4444-444444444444", "x", 0),
            ]);

        var collection = Assert.Single(shelves.Collections);
        Assert.Equal("Image Comics", collection.Name);
        Assert.Equal(new[] { "path:/a.cbz", "path:/b.cbz" }, collection.Members);
        Assert.Equal("path:/b.cbz", collection.CoverMemberId);
        Assert.True(collection.IsLocal);
        Assert.Equal(new[] { "x", "z", "y" }, Assert.Single(shelves.Lists).Members);

        var restored = ShelvesState.Restore(shelves.Save());
        Assert.Equal(shelves.Json, restored.Json);
        Assert.Empty(ShelvesState.Restore("[1,2").Collections);
    }

    [Fact]
    public void An_edit_for_the_same_entry_replaces_the_earlier_one_and_the_core_pushes_what_nobody_else_touched()
    {
        var key = new ShelfKey("server", 7, ShelfKind.ReadingList);
        var earlier = new PendingShelfEdit(key, "b", "B", new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        var later = earlier with { Title = "B again", MadeAt = earlier.MadeAt.AddMinutes(5) };
        var queue = ShelfEditQueue.Empty
            .Recording(new ShelfBaseline(key, ["a"]))
            .Queueing(earlier)
            .Queueing(later);

        Assert.Equal("B again", Assert.Single(queue.Edits).Title);

        var pull = ShelfRules.Pull(queue, [new ShelfSnapshot(key, ["a"])]);

        Assert.Equal("b", Assert.Single(pull.ToPush).Entry);
        Assert.Empty(pull.Conflicts);

        // The server's list changed under the edit: the edit is discarded and the reader is told what was dropped.
        var conflicted = ShelfRules.Pull(queue, [new ShelfSnapshot(key, ["a", "c"])]);
        Assert.Empty(conflicted.ToPush);
        var conflict = Assert.Single(conflicted.Conflicts);
        Assert.Equal("b", Assert.Single(conflict.Discarded).Entry);
        Assert.Equal(queue, ShelfEditQueue.Restore(queue.Save()), new QueueComparer());
    }

    [Fact]
    public void A_pending_edit_shows_after_the_servers_own_rows_oldest_first_and_a_server_that_did_not_answer_is_no_conflict()
    {
        var key = new ShelfKey("server", 7, ShelfKind.ReadingList);
        var first = new PendingShelfEdit(key, "p1", "Pending one", DateTimeOffset.UnixEpoch.AddMinutes(1));
        var second = new PendingShelfEdit(key, "p2", "Pending two", DateTimeOffset.UnixEpoch.AddMinutes(2));
        var landed = new PendingShelfEdit(key, "a", "A", DateTimeOffset.UnixEpoch);

        var rows = ShelfRules.Project([new ShelfRow("a", "A", false)], [second, landed, first]);

        Assert.Equal(new[] { "a", "p1", "p2" }, rows.Select(row => row.Id));
        Assert.Equal(new[] { false, true, true }, rows.Select(row => row.IsPending));

        var queue = ShelfEditQueue.Empty.Queueing(first);
        var pull = ShelfRules.Pull(queue, []);
        Assert.Empty(pull.ToPush);
        Assert.Empty(pull.Conflicts);
    }

    [Fact]
    public void A_phone_document_imports_exports_and_syncs_and_an_unplugged_folder_is_unreachable_not_an_error()
    {
        var document = File.ReadAllBytes(Corpus.Path("library/written-by-ios.json"));

        var merged = LibraryDocuments.Import(document, "{}", "windows");

        Assert.Equal(3, merged.ProgressRecords().Count);
        Assert.Equal(new[] { "nas.local" }, merged.PinsAdded);
        Assert.Contains(merged.Pins(), pin => pin == new CertificatePin("nas.local", "AB:CD:EF:01"));
        Assert.Contains(merged.Sources(), source => source.Kind == "networkShare" && source.NeedsSignIn);
        Assert.Equal("Image Comics", merged.Shelves().Collections.Single().Name);

        var written = JsonNode.Parse(LibraryDocuments.Export(merged.SnapshotJson, "1.0.0", "windows", DateTimeOffset.FromUnixTimeSeconds(1_800_000_000)))!;
        Assert.Equal("windows", written["writtenBy"]!.GetValue<string>());
        Assert.Equal("Image Comics", written["library"]!["collections"]![0]!["name"]!.GetValue<string>());

        using var folder = Corpus.TemporaryFolder();
        var synced = LibraryDocuments.Sync(folder.FullPath, "windows", "1.0.0", DateTimeOffset.FromUnixTimeSeconds(1_800_000_000), merged.SnapshotJson);
        Assert.Empty(synced.Copies);
        Assert.True(File.Exists(Path.Combine(folder.FullPath, "StoryArc Library.json")));

        var unplugged = Assert.Throws<StoryArcException>(
            () => LibraryDocuments.Sync(Path.Combine(folder.FullPath, "unplugged"), "windows", "1", DateTimeOffset.UnixEpoch, "{}"));
        Assert.Equal(StoryArcStatus.Unreachable, unplugged.Status);
    }

    [Fact]
    public void A_document_from_a_newer_app_is_refused_naming_both_versions()
    {
        var newer = JsonNode.Parse(File.ReadAllText(Corpus.Path("library/written-by-ios.json")))!;
        newer["formatVersion"] = 9;

        var error = Assert.Throws<StoryArcException>(
            () => LibraryDocuments.Import(Encoding.UTF8.GetBytes(newer.ToJsonString()), "{}", "windows"));

        Assert.Equal(StoryArcStatus.Unsupported, error.Status);
        Assert.Contains("format 9", error.CoreMessage);
    }

    [Fact]
    public void Credentials_travel_only_sealed_and_a_wrong_passphrase_opens_nothing()
    {
        const string id = "11111111-1111-1111-1111-111111111111";
        var sealedJson = LibraryDocuments.SealCredentials("pässphrase", new Dictionary<string, string> { [id] = "hunter2" });
        Assert.DoesNotContain("hunter2", sealedJson, StringComparison.Ordinal);

        var opened = LibraryDocuments.OpenCredentials("pässphrase", sealedJson);
        Assert.Equal("hunter2", opened[id]);

        var wrong = Assert.Throws<StoryArcException>(() => LibraryDocuments.OpenCredentials("wrong", sealedJson));
        Assert.Equal(StoryArcStatus.Unauthorized, wrong.Status);

        var exported = LibraryDocuments.Export(
            "{}", "1.0.0", "windows", DateTimeOffset.UnixEpoch, passphrase: "pässphrase", credentials: new Dictionary<string, string> { [id] = "hunter2" });
        Assert.DoesNotContain("hunter2", exported, StringComparison.Ordinal);
        Assert.NotNull(JsonNode.Parse(exported)!["secrets"]);
    }

    [Fact]
    public void The_diagnostic_never_shows_a_held_credential_or_a_host_name()
    {
        var text = Diagnostics.Render(
            "StoryArc diagnostic",
            [new DiagnosticSection("source", [("address", "smb://reader:hunter2-session@nas.local/comics")])],
            ["hunter2-session"]);

        Assert.Contains("[source]", text, StringComparison.Ordinal);
        Assert.DoesNotContain("hunter2-session", text, StringComparison.Ordinal);
        Assert.DoesNotContain("nas.local", text, StringComparison.Ordinal);
    }

    [Fact]
    public void A_folder_weighs_what_its_files_weigh_and_a_missing_one_nothing()
    {
        using var folder = Corpus.TemporaryFolder();
        File.WriteAllBytes(Path.Combine(folder.FullPath, "a.cbz"), new byte[1000]);
        Directory.CreateDirectory(Path.Combine(folder.FullPath, "nested"));
        File.WriteAllBytes(Path.Combine(folder.FullPath, "nested", "b.cbz"), new byte[234]);

        Assert.Equal(1234, StorageBytes.Of(folder.FullPath));
        Assert.Equal(0, StorageBytes.Of(Path.Combine(folder.FullPath, "gone")));
    }

    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(999, "999 B")]
    public void A_size_reads_as_a_reader_reads_it(long bytes, string expected)
    {
        Assert.Equal(expected, DownloadQueues.Size(bytes));
    }

    /// <summary>Compares two queues by what they save, since the record holds lists.</summary>
    private sealed class QueueComparer : IEqualityComparer<ShelfEditQueue>
    {
        public bool Equals(ShelfEditQueue? x, ShelfEditQueue? y) => x?.Save() == y?.Save();

        public int GetHashCode(ShelfEditQueue obj) => obj.Save().GetHashCode(StringComparison.Ordinal);
    }
}
