using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Library;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Tests.Library;

/// <summary>
/// The collections and reading lists screens, model first (desktop-clients task 3.23a, as 3.15a): membership, the pinned order, the offline edit
/// queue shown in grey, a reading list's progress, and the cover rule. The rules that change a shelf run in the core; these are the rules about
/// how the screens read the result.
/// </summary>
public sealed class ShelfScreensTests
{
    private const string Crossover = "44444444-4444-4444-4444-444444444444";
    private const string Images = "33333333-3333-3333-3333-333333333333";

    private static LibraryRecord Book(string name, double progress = 0, string? unreadable = null) =>
        LibraryViewModelTests.Record("C:\\Comics\\" + name + ".cbz", name, progress: progress, unreadable: unreadable) with
        {
            Core = new CorePublication(new CoreIdentity(NormalizedPath: "/" + name + ".cbz"), "cbz", name),
        };

    private static ShelvesState Shelves(params ShelfOp[] ops) => ShelfRules.Apply(ShelvesState.Empty, ops);

    [Fact]
    public void A_shelf_made_on_a_phone_finds_the_same_publication_by_its_stable_id()
    {
        Assert.Equal("path:/a.cbz", ShelfMemberId.Of(Book("a")));
        Assert.Equal("srv:s:9", ShelfMemberId.Of(new CoreIdentity(ServerSourceId: "s", ServerRemoteId: "9", ContentDigest: "d")));
        Assert.Equal("sha:d1", ShelfMemberId.Of(new CoreIdentity(ContentDigest: "d1")));
        Assert.Equal("path:", ShelfMemberId.Of(new CoreIdentity()));
        Assert.Equal("path:C:\\x.cbz", ShelfMemberId.Of(LibraryViewModelTests.Record("C:\\x.cbz", "x")));
    }

    [Fact]
    public void Membership_is_added_in_bulk_removed_and_shown_as_checkmarks_for_each_publication()
    {
        var a = Book("a");
        var b = Book("b");
        var shelves = Shelves(
            ShelfOp.CreateCollection("Image Comics", Images),
            ShelfOp.CreateList("Crossover", Crossover));
        var collection = shelves.Find(Images)!;
        var list = shelves.Find(Crossover)!;

        var added = ShelfRules.Apply(shelves, [
            ShelfMembership.Adding(collection, [ShelfMemberId.Of(a), ShelfMemberId.Of(b)]),
            ShelfMembership.Adding(list, [ShelfMemberId.Of(b)]),
        ]);

        Assert.Equal(new[] { "Image Comics" }, ShelfMembership.Containing(added, a).Select(shelf => shelf.Name));
        Assert.Equal(new[] { "Image Comics", "Crossover" }, ShelfMembership.Containing(added, b).Select(shelf => shelf.Name));

        var removed = ShelfRules.Apply(added, [
            .. ShelfMembership.Removing(added.Find(Images)!, [ShelfMemberId.Of(b)]),
            .. ShelfMembership.Removing(added.Find(Crossover)!, [ShelfMemberId.Of(b)]),
        ]);

        Assert.DoesNotContain(ShelfMembership.Containing(removed, b), shelf => shelf.Name == "Crossover");
        Assert.Equal(new[] { "path:/a.cbz" }, removed.Find(Images)!.Members);
    }

    [Fact]
    public void Pinned_shelves_keep_the_order_they_were_pinned_in_and_a_pin_can_be_moved()
    {
        var shelves = Shelves(
            ShelfOp.CreateCollection("Zeta", Images),
            ShelfOp.CreateList("Alpha", Crossover),
            ShelfOp.CreateCollection("Beta", "55555555-5555-5555-5555-555555555555"));
        var zeta = shelves.Find(Images)!;
        var alpha = shelves.Find(Crossover)!;
        var beta = shelves.Find("55555555-5555-5555-5555-555555555555")!;

        var pinned = PinnedShelves.None.Pinning(zeta).Pinning(alpha).Pinning(zeta);

        Assert.Equal(new[] { "collection:" + Images, "list:" + Crossover }, pinned.Tokens);
        Assert.Equal(new[] { "Zeta", "Alpha", "Beta" }, pinned.Ordering(shelves.All).Select(shelf => shelf.Name));

        var moved = pinned.Moving(alpha, 0);
        Assert.Equal(new[] { "Alpha", "Zeta", "Beta" }, moved.Ordering(shelves.All).Select(shelf => shelf.Name));
        Assert.Equal(moved.Tokens, moved.Moving(beta, 0).Tokens);
        Assert.Equal(new[] { "list:" + Crossover }, moved.Unpinning(zeta).Tokens);

        var afterDelete = ShelfRules.Apply(shelves, [ShelfOp.DeleteCollection(Images)]);
        Assert.Equal(new[] { "list:" + Crossover }, moved.Pruned(afterDelete).Tokens);
    }

    [Fact]
    public void A_pinned_order_survives_the_library_document_both_ways()
    {
        var shelves = Shelves(ShelfOp.CreateCollection("Zeta", Images), ShelfOp.CreateList("Alpha", Crossover));
        var pinned = PinnedShelves.None.Pinning(shelves.Find(Crossover)!).Pinning(shelves.Find(Images)!);
        var snapshot = LibrarySnapshots.Build([], new PinBook(), shelves, [], pinned.Tokens);

        var written = LibraryDocuments.Export(snapshot, "1.0.0", "windows", DateTimeOffset.UnixEpoch);
        var merged = LibraryDocuments.Import(LibraryDocuments.ToFileBytes(written), "{}", "windows");

        Assert.Equal(pinned.Tokens, merged.PinnedShelves());
    }

    [Fact]
    public void A_collection_lists_its_members_by_title_a_list_keeps_the_readers_order_and_a_missing_member_stays_in_grey()
    {
        var library = new[] { Book("b"), Book("a"), Book("c", unreadable: "damaged") };
        var shelves = Shelves(
            ShelfOp.CreateCollection("Set", Images),
            ShelfOp.AddMembers(Images, ["path:/b.cbz", "path:/a.cbz", "path:/gone.cbz"]),
            ShelfOp.CreateList("Order", Crossover),
            ShelfOp.Append(Crossover, ["path:/c.cbz", "path:/b.cbz", "path:/a.cbz"]));

        var set = ShelfPageModel.From(shelves.Find(Images)!, library);
        var order = ShelfPageModel.From(shelves.Find(Crossover)!, library);

        Assert.Equal(new[] { "a", "b", "path:/gone.cbz" }, set.Rows.Select(row => row.Title));
        Assert.Equal(new[] { true, true, false }, set.Rows.Select(row => row.IsAvailable));
        Assert.Equal(new[] { "c", "b", "a" }, order.Rows.Select(row => row.Title));
        Assert.False(order.Rows[0].IsAvailable, "an unreadable file is listed and not offered");
    }

    [Fact]
    public void A_reading_list_counts_what_is_finished_over_what_the_library_reports_and_names_the_next_entry()
    {
        var library = new[] { Book("a", progress: 1), Book("b", progress: 0.4), Book("c") };
        var shelves = Shelves(
            ShelfOp.CreateList("Order", Crossover),
            ShelfOp.Append(Crossover, ["path:/a.cbz", "path:/b.cbz", "path:/unknown.cbz", "path:/c.cbz"]));

        var page = ShelfPageModel.From(shelves.Find(Crossover)!, library);

        var progress = page.Progress!;
        Assert.Equal(1, progress.Finished);
        Assert.Equal(3, progress.Reported);
        Assert.Equal(1.0 / 3, progress.Fraction, precision: 6);
        Assert.Equal("path:/b.cbz", progress.NextId);
        Assert.Equal("path:/c.cbz", page.NextAfter("path:/b.cbz"));
        Assert.Equal("path:/b.cbz", page.NextAfter("path:/a.cbz"));
        Assert.Null(page.NextAfter("path:/c.cbz"));
        Assert.Null(ShelfPageModel.From(shelves.Find(Crossover)!, []).Progress!.NextId);
    }

    [Fact]
    public void An_edit_waiting_for_a_server_shows_in_grey_after_the_servers_own_rows_with_its_title()
    {
        var key = new ShelfKey("server", 7, ShelfType.ReadingList);
        var list = new Shelf(ShelfType.ReadingList, "server-list", "Server list", ["path:/a.cbz"], null, "server");
        var pending = new PendingShelfEdit(key, "srv:server:9", "Waiting for the server", DateTimeOffset.UnixEpoch);

        var page = ShelfPageModel.From(list, [Book("a")], [pending]);

        Assert.Equal(new[] { "a", "Waiting for the server" }, page.Rows.Select(row => row.Title));
        Assert.Equal(new[] { false, true }, page.Rows.Select(row => row.IsPending));
        Assert.False(page.Rows[1].IsAvailable, "a pending row cannot be opened until the server has it");
        Assert.False(list.IsLocal);
        Assert.Null(page.NextAfter("srv:server:9"));
    }

    [Fact]
    public void A_shelfs_tile_shows_the_chosen_cover_or_the_first_four_available_members()
    {
        var library = Enumerable.Range(0, 6).Select(index => Book("m" + index)).Append(Book("broken", unreadable: "damaged")).ToList();
        var members = library.Select(record => ShelfMemberId.Of(record)).ToList();
        var shelves = Shelves(ShelfOp.CreateCollection("Set", Images), ShelfOp.AddMembers(Images, ["path:/broken.cbz", .. members.Take(6)]));

        var composite = ShelfPageModel.From(shelves.Find(Images)!, library);
        Assert.Equal(new[] { "path:/m0.cbz", "path:/m1.cbz", "path:/m2.cbz", "path:/m3.cbz" }, composite.CoverIds);

        var chosen = ShelfRules.Apply(shelves, [ShelfOp.SetCollectionCover(Images, "path:/m5.cbz")]);
        Assert.Equal(new[] { "path:/m5.cbz" }, ShelfPageModel.From(chosen.Find(Images)!, library).CoverIds);

        var unavailableChoice = ShelfRules.Apply(shelves, [ShelfOp.SetCollectionCover(Images, "path:/broken.cbz")]);
        Assert.Equal(4, ShelfPageModel.From(unavailableChoice.Find(Images)!, library).CoverIds.Count);
        Assert.Empty(ShelfPageModel.From(Shelves(ShelfOp.CreateCollection("Empty", Images)).Find(Images)!, library).CoverIds);
    }

    [Fact]
    public void Home_draws_only_the_pinned_shelves_that_have_something_to_open_in_the_order_pinned()
    {
        var library = new[] { Book("a"), Book("b") };
        var shelves = Shelves(
            ShelfOp.CreateCollection("First", Images),
            ShelfOp.AddMembers(Images, ["path:/a.cbz"]),
            ShelfOp.CreateList("Second", Crossover),
            ShelfOp.Append(Crossover, ["path:/b.cbz"]),
            ShelfOp.CreateCollection("Empty", "55555555-5555-5555-5555-555555555555"),
            ShelfOp.CreateCollection("Unpinned", "66666666-6666-6666-6666-666666666666"));
        var pinned = PinnedShelves.None
            .Pinning(shelves.Find(Crossover)!)
            .Pinning(shelves.Find(Images)!)
            .Pinning(shelves.Find("55555555-5555-5555-5555-555555555555")!);

        var rows = HomeShelfRows.From(shelves, pinned, library);

        Assert.Equal(new[] { "Second", "First" }, rows.Select(page => page.Shelf.Name));
        Assert.Empty(HomeShelfRows.From(shelves, PinnedShelves.None, library));
    }
}
