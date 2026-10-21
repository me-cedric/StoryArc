using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>Where each kind of Windows install keeps its files (shared-release-train, design D5).</summary>
public sealed class DataRootTests
{
    private static readonly string Exe = Path.Combine("C:", "Apps", "StoryArc");
    private static readonly string Local = Path.Combine("C:", "Users", "reader", "AppData", "Local");

    [Fact]
    public void The_msix_keeps_the_package_folder_even_beside_a_portable_marker()
    {
        var package = Path.Combine(Local, "Packages", "com.mecedric.StoryArc", "LocalState");
        Assert.Equal(package, DataRoot.Resolve(package, Exe, Local, _ => true));
    }

    [Fact]
    public void The_installed_copy_uses_its_own_folder_in_local_app_data()
    {
        Assert.Equal(Path.Combine(Local, "StoryArc"), DataRoot.Resolve(null, Exe, Local, _ => false));
    }

    [Fact]
    public void The_portable_copy_keeps_its_data_beside_the_executable()
    {
        var marker = Path.Combine(Exe, DataRoot.PortableMarker);
        Assert.Equal(Path.Combine(Exe, "data"), DataRoot.Resolve(null, Exe, Local, path => path == marker));
    }
}
