using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace StoryArc.Interop.Tests.Support;

/// <summary>One request a <see cref="LocalServer"/> received: the method, the path and the headers, names in lower case.</summary>
internal sealed record LocalRequest(string Method, string Path, IReadOnlyDictionary<string, string> Headers);

/// <summary>What a <see cref="LocalServer"/> answers.</summary>
internal sealed record LocalResponse(int Status, byte[] Body, string ContentType, IReadOnlyDictionary<string, string>? Headers = null);

/// <summary>
/// A small HTTP/1.1 server on a free loopback port, closing each connection after its answer: enough for the core's
/// HTTP client to fetch a catalogue page or a file from, in a test that has to run on any host with no mock to start.
/// </summary>
internal sealed class LocalServer : IDisposable
{
    private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
    private readonly Func<LocalRequest, LocalResponse> _handler;
    private readonly CancellationTokenSource _stop = new();

    public LocalServer(Func<LocalRequest, LocalResponse> handler)
    {
        _handler = handler;
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        _ = Task.Run(AcceptAsync);
    }

    public int Port { get; }

    public string Root => $"http://127.0.0.1:{Port}/";

    /// <summary>A server that answers every request with <paramref name="body"/>.</summary>
    public static LocalServer Serving(byte[] body, string contentType) => new(_ => new LocalResponse(200, body, contentType));

    private async Task AcceptAsync()
    {
        while (!_stop.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(_stop.Token);
            }
            catch (Exception error) when (error is OperationCanceledException or ObjectDisposedException or SocketException)
            {
                return;
            }

            _ = Task.Run(() => Answer(client));
        }
    }

    private void Answer(TcpClient client)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream();
                using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
                var line = reader.ReadLine();
                if (string.IsNullOrEmpty(line))
                {
                    return;
                }

                var parts = line.Split(' ');
                var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                while (reader.ReadLine() is { Length: > 0 } header)
                {
                    var colon = header.IndexOf(':');
                    if (colon > 0)
                    {
                        headers[header[..colon].ToLowerInvariant()] = header[(colon + 1)..].Trim();
                    }
                }

                var response = _handler(new LocalRequest(parts[0], parts.Length > 1 ? parts[1] : "/", headers));
                var head = new StringBuilder()
                    .Append(System.Globalization.CultureInfo.InvariantCulture, $"HTTP/1.1 {response.Status} X\r\n")
                    .Append(System.Globalization.CultureInfo.InvariantCulture, $"Content-Type: {response.ContentType}\r\n")
                    .Append(System.Globalization.CultureInfo.InvariantCulture, $"Content-Length: {response.Body.Length}\r\n")
                    .Append("Connection: close\r\n");
                foreach (var (name, value) in response.Headers ?? new Dictionary<string, string>())
                {
                    _ = head.Append(System.Globalization.CultureInfo.InvariantCulture, $"{name}: {value}\r\n");
                }

                var headBytes = Encoding.ASCII.GetBytes(head.Append("\r\n").ToString());
                stream.Write(headBytes);
                stream.Write(response.Body);
                stream.Flush();
            }
            catch (Exception error) when (error is IOException or SocketException or ObjectDisposedException)
            {
                // The client went away mid-answer: a cancelled download does exactly that.
            }
        }
    }

    public void Dispose()
    {
        _stop.Cancel();
        _listener.Stop();
        _stop.Dispose();
    }
}

/// <summary>
/// A mock server from <c>scripts/</c> (<c>opds-server.mjs</c>, <c>kavita-server.mjs</c>) started with node on a free port.
/// It needs node on the PATH; a host without it skips the test and says why, as the core's own tests skip a case whose
/// fixture is not running.
/// </summary>
internal sealed class MockServer : IDisposable
{
    private readonly Process _process;

    private MockServer(Process process, int port)
    {
        _process = process;
        Port = port;
    }

    public int Port { get; }

    /// <summary>The server, or <c>null</c> with <paramref name="reason"/> when node is missing or the script did not answer.</summary>
    public static MockServer? TryStart(string script, string corpusFolder, out string reason)
    {
        var scripts = Path.Combine(RepositoryRoot(), "scripts", script);
        var port = FreePort();
        var info = new ProcessStartInfo("node")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        info.ArgumentList.Add(scripts);
        info.ArgumentList.Add(corpusFolder);
        info.ArgumentList.Add("--port");
        info.ArgumentList.Add(port.ToString(System.Globalization.CultureInfo.InvariantCulture));

        Process? process;
        try
        {
            process = Process.Start(info);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            reason = "node is not on the PATH";
            return null;
        }

        if (process is null)
        {
            reason = "node did not start";
            return null;
        }

        var server = new MockServer(process, port);
        var until = Stopwatch.StartNew();
        while (until.Elapsed < TimeSpan.FromSeconds(15))
        {
            if (process.HasExited)
            {
                reason = $"{script} exited with {process.ExitCode}";
                server.Dispose();
                return null;
            }

            try
            {
                using var probe = new TcpClient();
                probe.Connect(IPAddress.Loopback, port);
                reason = string.Empty;
                return server;
            }
            catch (SocketException)
            {
                Thread.Sleep(100);
            }
        }

        reason = $"{script} did not listen on {port} in 15 seconds";
        server.Dispose();
        return null;
    }

    public void Dispose()
    {
        try
        {
            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // Already gone.
        }

        _process.Dispose();
    }

    private static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    private static string RepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "scripts", "opds-server.mjs")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new InvalidOperationException("scripts/opds-server.mjs is not above " + AppContext.BaseDirectory);
    }
}

/// <summary>The one way a test that needs a fixture it cannot start says so, so the report names the reason instead of passing quietly.</summary>
internal static class Skip
{
    /// <summary>Writes the reason to the test output and answers <c>true</c>: <c>if (Skip.Because(output, reason)) return;</c>.</summary>
    public static bool Because(Xunit.Abstractions.ITestOutputHelper output, string reason)
    {
        output.WriteLine("skipped: " + reason);
        return true;
    }
}
