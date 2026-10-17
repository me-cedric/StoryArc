using StoryArc.Interop.Playback;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>The read-aloud queue and the sleep rule for playback of desktop-clients task 4.20.</summary>
public sealed class ReadAloudTests
{
    private static IReadOnlyList<Sentence> ChapterOf(int index) => index switch
    {
        0 => [new("First one.", 0, null), new("Second one.", 0, null)],
        1 => [],
        2 => [new("Last one.", 2, "{\"href\":\"ch3\"}")],
        _ => throw new ArgumentOutOfRangeException(nameof(index)),
    };

    [Fact]
    public void Without_a_voice_the_control_is_absent_and_nothing_starts()
    {
        var model = new ReadAloudModel(voiceCount: 0, chapterCount: 3, ChapterOf);

        Assert.False(model.IsAvailable);
        Assert.Null(model.Start(0));
        Assert.True(model.HasEnded);
    }

    [Fact]
    public void The_voice_carries_on_into_the_next_chapter_skips_an_empty_one_and_ends_at_the_last_sentence()
    {
        var fetched = new List<int>();
        var model = new ReadAloudModel(1, 3, index =>
        {
            fetched.Add(index);
            return ChapterOf(index);
        });

        Assert.Equal("First one.", model.Start(0)?.Text);
        Assert.Equal(new[] { 0 }, fetched);
        Assert.Equal("Second one.", model.Next()?.Text);
        Assert.Equal("Last one.", model.Next()?.Text);
        Assert.Equal(new[] { 0, 1, 2 }, fetched);
        Assert.Equal((2, 0), model.Place);
        Assert.Null(model.Next());
        Assert.True(model.HasEnded);
        Assert.Null(model.Current);
        Assert.Null(model.Next());
    }

    [Fact]
    public void Previous_goes_back_across_a_chapter_and_the_first_sentence_stays_put()
    {
        var model = new ReadAloudModel(1, 3, ChapterOf);
        _ = model.Start(2);

        Assert.Equal("Second one.", model.Previous()?.Text);
        Assert.Equal("First one.", model.Previous()?.Text);
        Assert.Equal("First one.", model.Previous()?.Text);
        Assert.Equal((0, 0), model.Place);
    }

    [Fact]
    public void Starting_in_an_empty_chapter_speaks_the_next_one_that_has_words_and_a_silent_tail_ends_at_once()
    {
        var model = new ReadAloudModel(1, 3, ChapterOf);
        Assert.Equal("Last one.", model.Start(1)?.Text);

        var silent = new ReadAloudModel(1, 1, _ => []);
        Assert.Null(silent.Start(0));
        Assert.True(silent.HasEnded);
    }

    [Fact]
    public void Sentences_split_at_terminal_marks_and_paragraph_breaks_and_nothing_is_dropped()
    {
        var sentences = SentenceSplitter.Split("Call me Ishmael. Some years ago—never mind how long—I thought I would sail!\nWhy not?\n\nA new paragraph without a mark\nstill one sentence… Done.");

        Assert.Equal(
            new[] { "Call me Ishmael.", "Some years ago—never mind how long—I thought I would sail!", "Why not?", "A new paragraph without a mark still one sentence…", "Done." },
            sentences);
        Assert.Empty(SentenceSplitter.Split("  \n\n "));
        Assert.Equal(new[] { "3.5 is a number." }, SentenceSplitter.Split("3.5 is a number."));
    }

    [Fact]
    public void The_system_is_kept_from_sleeping_only_while_the_session_plays()
    {
        var calls = new List<uint>();
        var keep = new PlaybackKeepAwake(flags =>
        {
            calls.Add(flags);
            return 1;
        });
        var session = new PlaybackSession().Started();

        keep.SessionChanged(session);
        keep.SessionChanged(session);
        Assert.True(keep.IsHeld);
        Assert.Equal(new[] { DisplayKeepAwake.EsContinuous | DisplayKeepAwake.EsSystemRequired }, calls);

        keep.SessionChanged(session.Interrupted());
        Assert.False(keep.IsHeld);
        Assert.Equal(DisplayKeepAwake.EsContinuous, calls[^1]);
        Assert.Equal(2, calls.Count);

        keep.SessionChanged(session.Stopped());
        Assert.Equal(2, calls.Count);

        var refused = new PlaybackKeepAwake(_ => 0);
        refused.SessionChanged(session);
        Assert.False(refused.IsHeld);
    }

    [Fact]
    public void A_chapters_markup_reads_as_paragraphs_with_scripts_styles_and_comments_dropped()
    {
        const string xhtml = """
            <?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title><style>p { color: red }</style></head>
            <body><!-- a note --><h1>Chapter   One</h1><p>Call me <em>Ishmael</em>.&nbsp;It&#8217;s true.</p>
            <script>track("x")</script><p>Second<br/>line.</p></body></html>
            """;

        var text = XhtmlText.Strip(xhtml);

        Assert.Equal("One\n\nChapter One\n\nCall me Ishmael. It\u2019s true.\n\nSecond\n\nline.", text);
        Assert.Equal(new[] { "One", "Chapter One", "Call me Ishmael.", "It\u2019s true.", "Second", "line." }, SentenceSplitter.Split(text));
    }
}
