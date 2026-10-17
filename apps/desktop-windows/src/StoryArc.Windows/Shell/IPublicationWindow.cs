using StoryArc.Interop.Shell;

namespace StoryArc.Windows.Shell;

/// <summary>What the host asks of every window that reads one publication: the comic reader, the EPUB reader and the PDF reader.</summary>
internal interface IPublicationWindow
{
    /// <summary>The file path: the key of the window registry, the session and the recent list.</summary>
    string PublicationId { get; }

    /// <summary>What the session file keeps for the window.</summary>
    ReaderWindowState State();

    /// <summary>A command of the menu or a shortcut the host did not answer itself.</summary>
    void Run(string commandId);

    void Activate();

    void Close();
}
