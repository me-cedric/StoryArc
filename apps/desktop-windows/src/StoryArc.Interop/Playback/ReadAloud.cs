using System.Text;

namespace StoryArc.Interop.Playback;

/// <summary>A sentence to speak, and where it sits in the publication so the page can follow the voice.</summary>
/// <param name="LocatorJson">The locator of the resource it is in, or <c>null</c> when the host has none for it.</param>
public sealed record Sentence(string Text, int ChapterIndex, string? LocatorJson);

/// <summary>
/// Splits a chapter's text into the sentences a voice speaks: at a full stop, a question or an
/// exclamation mark followed by white space, and at a paragraph break. Abbreviations are not
/// special-cased: a sentence that is short is still spoken whole, and nothing is skipped. Empty
/// stretches are dropped.
/// </summary>
public static class SentenceSplitter
{
    public static IReadOnlyList<string> Split(string text)
    {
        var sentences = new List<string>();
        var current = new StringBuilder();
        for (var index = 0; index < text.Length; index++)
        {
            var character = text[index];
            if (character == '\n' && index + 1 < text.Length && text[index + 1] == '\n')
            {
                Flush(sentences, current);
                continue;
            }

            current.Append(character == '\n' ? ' ' : character);
            if ((character is '.' or '?' or '!' or '…') && (index + 1 == text.Length || char.IsWhiteSpace(text[index + 1])))
            {
                Flush(sentences, current);
            }
        }

        Flush(sentences, current);
        return sentences;
    }

    private static void Flush(List<string> sentences, StringBuilder current)
    {
        var trimmed = current.ToString().Trim();
        if (trimmed.Length > 0)
        {
            sentences.Add(trimmed);
        }

        current.Clear();
    }
}

/// <summary>
/// The read-aloud session's queue (desktop-clients task 4.20; ebook-reader "Reading aloud"): absent
/// where the system has no voice, otherwise one sentence at a time through the chapters in reading
/// order, carrying on into the next chapter without being asked and ending at the last sentence of
/// the publication, where the highlight is withdrawn and the transport leaves. The chapters' text is
/// fetched by the host as the queue reaches them, so a long book is never extracted whole.
/// </summary>
public sealed class ReadAloudModel
{
    private readonly int _voiceCount;
    private readonly int _chapterCount;
    private readonly Func<int, IReadOnlyList<Sentence>> _sentencesOf;
    private IReadOnlyList<Sentence> _chapter = [];
    private int _chapterIndex = -1;
    private int _sentenceIndex = -1;

    /// <param name="voiceCount">How many voices the system offers; zero makes the control absent.</param>
    /// <param name="chapterCount">The reading order's length.</param>
    /// <param name="sentencesOf">The sentences of a chapter, fetched when the voice reaches it.</param>
    public ReadAloudModel(int voiceCount, int chapterCount, Func<int, IReadOnlyList<Sentence>> sentencesOf)
    {
        _voiceCount = voiceCount;
        _chapterCount = chapterCount;
        _sentencesOf = sentencesOf;
    }

    /// <summary>Whether the read-aloud control exists at all: a device with no voice shows none, and nothing says it failed.</summary>
    public bool IsAvailable => _voiceCount > 0 && _chapterCount > 0;

    /// <summary>The sentence being spoken, or <c>null</c> before the start and after the end.</summary>
    public Sentence? Current =>
        _sentenceIndex >= 0 && _sentenceIndex < _chapter.Count ? _chapter[_sentenceIndex] : null;

    public bool HasEnded { get; private set; }

    /// <summary>
    /// Starts at <paramref name="chapterIndex"/>, at the sentence that holds <paramref name="sentenceIndex"/>, or the first
    /// sentence with text at or after that chapter. Answers the first sentence, or <c>null</c> when the publication has
    /// nothing to say from there, in which case <see cref="HasEnded"/> is set.
    /// </summary>
    public Sentence? Start(int chapterIndex, int sentenceIndex = 0)
    {
        if (!IsAvailable)
        {
            HasEnded = true;
            return null;
        }

        HasEnded = false;
        _chapterIndex = Math.Clamp(chapterIndex, 0, _chapterCount - 1);
        _chapter = _sentencesOf(_chapterIndex);
        _sentenceIndex = Math.Clamp(sentenceIndex, 0, Math.Max(0, _chapter.Count - 1));
        return Current ?? Next();
    }

    /// <summary>The next sentence, across the chapter boundary when this chapter is spoken; <c>null</c> at the end of the publication.</summary>
    public Sentence? Next()
    {
        if (HasEnded)
        {
            return null;
        }

        _sentenceIndex++;
        while (_sentenceIndex >= _chapter.Count)
        {
            if (_chapterIndex + 1 >= _chapterCount)
            {
                HasEnded = true;
                _sentenceIndex = _chapter.Count;
                return null;
            }

            _chapterIndex++;
            _chapter = _sentencesOf(_chapterIndex);
            _sentenceIndex = 0;
        }

        return Current;
    }

    /// <summary>The previous sentence, back across a chapter boundary; the first sentence of the publication stays put.</summary>
    public Sentence? Previous()
    {
        if (!IsAvailable)
        {
            return null;
        }

        HasEnded = false;
        while (_sentenceIndex <= 0)
        {
            if (_chapterIndex <= 0)
            {
                _sentenceIndex = 0;
                return Current;
            }

            _chapterIndex--;
            _chapter = _sentencesOf(_chapterIndex);
            _sentenceIndex = _chapter.Count;
        }

        _sentenceIndex--;
        return Current;
    }

    /// <summary>Where the voice got to, for the progress record: the chapter and the sentence, or <c>null</c> before the start.</summary>
    public (int Chapter, int Sentence)? Place => _chapterIndex < 0 ? null : (_chapterIndex, Math.Max(0, _sentenceIndex));
}

/// <summary>
/// The text of an XHTML chapter for a voice: tags dropped, <c>script</c> and <c>style</c> bodies with
/// them, block boundaries as paragraph breaks, the common entities decoded, and white space folded.
/// </summary>
public static class XhtmlText
{
    private static readonly string[] BlockTags = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "br", "tr", "section", "article", "blockquote", "aside", "figcaption", "td"];

    public static string Strip(string xhtml)
    {
        var text = new StringBuilder(xhtml.Length);
        var index = 0;
        while (index < xhtml.Length)
        {
            var open = xhtml.IndexOf('<', index);
            if (open < 0)
            {
                text.Append(xhtml, index, xhtml.Length - index);
                break;
            }

            text.Append(xhtml, index, open - index);
            var close = xhtml.IndexOf('>', open);
            if (close < 0)
            {
                break;
            }

            var tag = xhtml[(open + 1)..close].Trim();
            var name = TagName(tag);
            if (name is "script" or "style")
            {
                var end = xhtml.IndexOf("</" + name, close, StringComparison.OrdinalIgnoreCase);
                index = end < 0 ? xhtml.Length : xhtml.IndexOf('>', end) + 1;
                continue;
            }

            if (tag.StartsWith("!--", StringComparison.Ordinal))
            {
                var end = xhtml.IndexOf("-->", open, StringComparison.Ordinal);
                index = end < 0 ? xhtml.Length : end + 3;
                continue;
            }

            if (BlockTags.Contains(name))
            {
                text.Append("\n\n");
            }

            index = close + 1;
        }

        var decoded = System.Net.WebUtility.HtmlDecode(text.ToString());
        return string.Join("\n\n", decoded.Split("\n\n", StringSplitOptions.RemoveEmptyEntries)
            .Select(paragraph => string.Join(' ', paragraph.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)))
            .Where(paragraph => paragraph.Length > 0));
    }

    private static string TagName(string tag)
    {
        var body = tag.TrimStart('/').TrimEnd('/');
        var end = body.IndexOfAny([' ', '\t', '\n', '\r', '/']);
        return (end < 0 ? body : body[..end]).ToLowerInvariant();
    }
}
