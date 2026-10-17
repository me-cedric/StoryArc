using System.Runtime.InteropServices;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The Win32 calls the shell needs, each quoted from its Microsoft Learn page. Everything
/// else goes through the Windows App SDK.
/// </summary>
internal static partial class Win32
{
    /// <summary>
    /// <c>user32.dll</c> <c>GetDpiForWindow(HWND)</c>: the DPI of the window's monitor, 96 at
    /// 100 percent. <c>AppWindow.Resize</c> and <c>Move</c> take physical pixels, so every size in
    /// device-independent pixels is multiplied by this over 96.
    /// </summary>
    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint hwnd);

    /// <summary>
    /// <c>kernel32.dll</c> <c>SetThreadExecutionState(EXECUTION_STATE)</c> (winbase.h): takes the
    /// flags, returns the previous state, or zero when it fails. The flags are in
    /// <see cref="Interop.SystemSettings.DisplayKeepAwake"/>, which owns the call.
    /// </summary>
    [LibraryImport("kernel32.dll")]
    internal static partial uint SetThreadExecutionState(uint esFlags);

    /// <summary>
    /// <c>user32.dll</c> <c>ShowCursor(BOOL)</c> (winuser.h): TRUE increments the display count,
    /// FALSE decrements it, and the cursor shows while the count is zero or more. The return value
    /// is the new count. <see cref="CursorHider"/> balances the calls.
    /// </summary>
    [LibraryImport("user32.dll")]
    internal static partial int ShowCursor([MarshalAs(UnmanagedType.Bool)] bool bShow);

    /// <summary>
    /// <c>ole32.dll</c> <c>CoWaitForMultipleObjects(DWORD dwFlags, DWORD dwTimeout, ULONG cHandles,
    /// LPHANDLE pHandles, LPDWORD lpdwindex)</c> (combaseapi.h): waits on handles while pumping COM
    /// calls, which a plain wait on an STA thread does not.
    /// </summary>
    [LibraryImport("ole32.dll")]
    internal static partial int CoWaitForMultipleObjects(uint dwFlags, uint dwTimeout, uint cHandles, nint[] pHandles, out uint lpdwindex);

    /// <summary>Waits for <paramref name="handle"/> without blocking COM on this thread: <c>CWMO_DEFAULT</c>, <c>INFINITE</c>.</summary>
    internal static void WaitPumping(WaitHandle handle)
    {
        const uint Default = 0;
        const uint Infinite = 0xFFFFFFFF;
        var added = false;
        try
        {
            handle.SafeWaitHandle.DangerousAddRef(ref added);
            _ = CoWaitForMultipleObjects(Default, Infinite, 1, [handle.SafeWaitHandle.DangerousGetHandle()], out _);
        }
        finally
        {
            if (added)
            {
                handle.SafeWaitHandle.DangerousRelease();
            }
        }
    }
}

/// <summary>
/// Hides the pointer over a resting reader and shows it again on the first movement
/// (desktop-experience, "Revealing chrome"). One call each way, however often it is asked, so the
/// system's display count is never left below zero.
/// </summary>
internal sealed class CursorHider
{
    private bool _isHidden;

    public void SetHidden(bool hidden)
    {
        if (hidden == _isHidden)
        {
            return;
        }

        _ = Win32.ShowCursor(!hidden);
        _isHidden = hidden;
    }
}
