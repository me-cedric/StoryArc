using System.Text;

namespace StoryArc.Interop.Opening;

/// <summary>
/// The paths in a command line (desktop-clients task 2.42; desktop-experience "The command line").
/// A second launch redirected to the running app arrives as one string, and so does a Jump List
/// item's arguments, so the string is split here by the rules of <c>CommandLineToArgvW</c>: blanks
/// separate, double quotes group, and backslashes are literal except before a quote, where 2n
/// backslashes give n and start or end a quoted run, and 2n+1 give n and a literal quote.
/// </summary>
public static class LaunchArguments
{
    /// <summary>The arguments of <paramref name="commandLine"/>, in order.</summary>
    public static IReadOnlyList<string> Split(string commandLine)
    {
        var arguments = new List<string>();
        var current = new StringBuilder();
        var inQuotes = false;
        var hasArgument = false;
        var index = 0;
        while (index < commandLine.Length)
        {
            var c = commandLine[index];
            if (c == '\\')
            {
                var start = index;
                while (index < commandLine.Length && commandLine[index] == '\\')
                {
                    index++;
                }

                var count = index - start;
                if (index < commandLine.Length && commandLine[index] == '"')
                {
                    current.Append('\\', count / 2);
                    if (count % 2 == 1)
                    {
                        current.Append('"');
                        index++;
                    }
                }
                else
                {
                    current.Append('\\', count);
                }

                hasArgument = true;
                continue;
            }

            if (c == '"')
            {
                inQuotes = !inQuotes;
                hasArgument = true;
            }
            else if (char.IsWhiteSpace(c) && !inQuotes)
            {
                if (hasArgument)
                {
                    arguments.Add(current.ToString());
                    current.Clear();
                    hasArgument = false;
                }
            }
            else
            {
                current.Append(c);
                hasArgument = true;
            }

            index++;
        }

        if (hasArgument)
        {
            arguments.Add(current.ToString());
        }

        return arguments;
    }

    /// <summary>
    /// The paths among <paramref name="arguments"/>: everything that is not an option. When the list
    /// starts with the executable, as <c>Environment.GetCommandLineArgs</c> and a redirected command
    /// line do, pass <paramref name="skipExecutable"/>.
    /// </summary>
    public static IReadOnlyList<string> Paths(IEnumerable<string> arguments, bool skipExecutable) =>
        arguments
            .Skip(skipExecutable ? 1 : 0)
            .Where(argument => argument.Length > 0 && !argument.StartsWith('-'))
            .ToList();

    /// <summary>
    /// The paths in a launch's argument string. A redirected launch and an execution alias may or
    /// may not carry the executable first; a leading token that names an <c>.exe</c> is the
    /// executable, never a publication, so it is dropped either way.
    /// </summary>
    public static IReadOnlyList<string> PathsIn(string? commandLine)
    {
        if (string.IsNullOrWhiteSpace(commandLine))
        {
            return [];
        }

        var arguments = Split(commandLine);
        var startsWithExecutable = arguments.Count > 0 && arguments[0].EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
        return Paths(arguments, startsWithExecutable);
    }

    /// <summary>A path as one argument, quoted so <see cref="Split"/> gives it back whole: what a Jump List item carries.</summary>
    public static string Quote(string path)
    {
        var builder = new StringBuilder("\"");
        var backslashes = 0;
        foreach (var c in path)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }

            builder.Append('\\', c == '"' ? (backslashes * 2) + 1 : backslashes);
            backslashes = 0;
            builder.Append(c);
        }

        builder.Append('\\', backslashes * 2).Append('"');
        return builder.ToString();
    }
}
