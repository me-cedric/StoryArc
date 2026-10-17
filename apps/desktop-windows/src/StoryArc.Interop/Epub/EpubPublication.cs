namespace StoryArc.Interop.Epub;

/// <summary>One resource of the container: its bytes and the media type the package document declares.</summary>
public sealed record EpubResource(byte[] Bytes, string MediaType);

/// <summary>
/// An EPUB the core has opened (<c>storyarc_epub_open</c>, desktop-clients task 4.16 over lane C's 4.3):
/// the Readium Web Publication Manifest and the positions list the renderer takes, and each
/// resource of the container by its path, for the scheme handler. The manifest's self link is the
/// <c>selfUrl</c> the host passes, so every other href is a container path the host resolves
/// against that origin.
/// </summary>
public sealed unsafe class EpubPublication : CoreHandle
{
    private EpubPublication()
    {
    }

    /// <summary>
    /// Opens <paramref name="path"/> with <paramref name="selfUrl"/> as the manifest's own address. A
    /// file that is not an EPUB throws with <see cref="StoryArcStatus.Unsupported"/>; one with no
    /// package document with <see cref="StoryArcStatus.Unreadable"/>.
    /// </summary>
    public static EpubPublication Open(string path, string selfUrl)
    {
        var pathBytes = NativeCore.Utf8(path);
        var selfBytes = NativeCore.Utf8(selfUrl);
        void* opened = null;
        fixed (byte* pathData = pathBytes)
        fixed (byte* selfData = selfBytes)
        {
            NativeCore.Check(
                NativeMethods.storyarc_epub_open(pathData, (nuint)pathBytes.Length, selfData, (nuint)selfBytes.Length, &opened),
                "storyarc_epub_open");
        }

        var epub = new EpubPublication();
        epub.Adopt(opened);
        return epub;
    }

    /// <summary>The manifest as the UTF-8 JSON the core wrote: metadata, readingOrder, resources, toc and the self link.</summary>
    public string ManifestJson() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_epub_manifest((void*)pointer, &buffer), "storyarc_epub_manifest");
        return NativeCore.TakeString(buffer);
    });

    /// <summary>The positions list as a JSON array of locators, the numbers the phones show.</summary>
    public string PositionsJson() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_epub_positions((void*)pointer, &buffer), "storyarc_epub_positions");
        return NativeCore.TakeString(buffer);
    });

    /// <summary>
    /// The resource at the container path <paramref name="href"/> (for example <c>OEBPS/ch1.xhtml</c>),
    /// or <c>null</c> when the container has none there. Any other failure throws.
    /// </summary>
    public EpubResource? Resource(string href)
    {
        var hrefBytes = NativeCore.Utf8(href);
        return Use(pointer =>
        {
            StoryArcBuffer bytes = default;
            StoryArcBuffer mediaType = default;
            int status;
            fixed (byte* data = hrefBytes)
            {
                status = NativeMethods.storyarc_epub_resource((void*)pointer, data, (nuint)hrefBytes.Length, &bytes, &mediaType);
            }

            if (status == NativeMethods.STORYARC_ERROR_NOT_FOUND)
            {
                NativeMethods.storyarc_buffer_free(bytes);
                NativeMethods.storyarc_buffer_free(mediaType);
                return null;
            }

            NativeCore.Check(status, "storyarc_epub_resource");
            return new EpubResource(NativeCore.Take(bytes), NativeCore.TakeString(mediaType));
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_epub_free((void*)handle);
        return true;
    }
}
