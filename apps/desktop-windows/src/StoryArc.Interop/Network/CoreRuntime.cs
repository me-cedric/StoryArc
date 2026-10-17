namespace StoryArc.Interop.Network;

/// <summary>What the system says about the connection (<c>storyarc_network_state</c>).</summary>
public enum ConnectionState
{
    /// <summary>Not metered, or the system does not say: the spec treats an undescribed connection as not metered.</summary>
    Unmetered = 0,

    /// <summary>The system marks the connection metered: a phone tether, a capped plan, a data saver.</summary>
    Metered = 1,

    /// <summary>No connection at all.</summary>
    Offline = 2,
}

/// <summary>
/// The core's one runtime (<c>storyarc_runtime_new</c>), created when the app starts and freed when it quits.
/// Every network handle, the vault and the metered flag are made from it, and each of them keeps it alive
/// through <see cref="CoreHandle"/>'s <c>Retain</c>, so the core's rule "free the runtime after every handle
/// made from it" holds whatever order the app disposes in. The runtime is shared between threads by design
/// (it is a reference-counted tokio runtime), so a call on it is not serialised.
/// </summary>
public sealed unsafe class CoreRuntime : CoreHandle
{
    private CoreRuntime()
    {
    }

    public static CoreRuntime Create()
    {
        void* opened = null;
        NativeCore.Check(NativeMethods.storyarc_runtime_new(&opened), "storyarc_runtime_new");
        var runtime = new CoreRuntime();
        runtime.Adopt(opened);
        return runtime;
    }

    /// <summary>
    /// What the system says about the connection now: <see cref="ConnectionState.Metered"/> for a metered
    /// network and for a data saver, <see cref="ConnectionState.Offline"/> for none, and
    /// <see cref="ConnectionState.Unmetered"/> otherwise, undescribed included.
    /// </summary>
    public ConnectionState Connection() => UseShared(pointer =>
    {
        var state = 0;
        NativeCore.Check(NativeMethods.storyarc_network_state((void*)pointer, &state), "storyarc_network_state");
        return (ConnectionState)state;
    });

    /// <summary>Runs <paramref name="call"/> with the runtime's pointer, held for the length of the call.</summary>
    internal T Borrow<T>(Func<nint, T> call) => UseShared(call);

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_runtime_free((void*)handle);
        return true;
    }
}
