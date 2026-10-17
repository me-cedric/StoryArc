using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop;
using StoryArc.Interop.Credentials;
using StoryArc.Interop.Network;
using StoryArc.Interop.Sources;
using StoryArc.Windows.Shell;
using Windows.System;

namespace StoryArc.Windows;

/// <summary>
/// The sources page (desktop-clients task 3.21): the network sources over the core, each with how it stands, in grey and never red, and the
/// add sheet. A share states its dialect and whether it is encrypted; a server that cannot be reached, a share that is missing and a sign-in that
/// was refused are each named apart; an untrusted certificate shows its fingerprint to pin. Windows offers no discovery of shares to the app,
/// which the page says once, and the address field is the way in. The credential goes to the vault and is never part of the source's record.
/// </summary>
public sealed partial class SourcesPage : UserControl
{
    private AppHost? _host;

    public SourcesPage()
    {
        InitializeComponent();
    }

    private NetworkServices? Network => _host?.Network;

    internal void Initialize(AppHost host)
    {
        _host = host;
        PageTitle.Text = Strings.Get("settings_sources");
        DiscoveryNote.Text = Strings.Get("desktop_w3_sources_discoveryAbsent");
        AddButton.Content = Strings.Get("sources_add");
        EmptyNote.Text = Strings.Get("sources_none");
        if (Network is { } network)
        {
            network.Changed += Rebuild;
        }

        Rebuild();
    }

    private void Rebuild()
    {
        SourcesPanel.Children.Clear();
        var sources = Network?.Sources.Sources ?? [];
        EmptyNote.Visibility = sources.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        AddButton.IsEnabled = Network is not null;
        foreach (var source in sources)
        {
            SourcesPanel.Children.Add(Row(source));
        }
    }

    private Border Row(NetworkSource source)
    {
        var check = Network?.CheckOf(source.Id);
        var state = SourceMessages.State(check, source);
        var isGrey = check is not { IsConnected: true };

        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = source.Name, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        text.Children.Add(Grey(SourceMessages.KindTitle(source.Kind) + " · " + source.Address));
        var stateLine = Grey(state);
        if (!isGrey)
        {
            stateLine.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        }

        text.Children.Add(stateLine);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        actions.Children.Add(ActionButton(Strings.Get("desktop_w3_sources_browse"), () => _ = BrowseAsync(source)));
        actions.Children.Add(ActionButton(Strings.Get("desktop_w3_sources_test"), () => _ = TestAsync(source)));
        if (check?.Failure?.Problem is SourceProblem.SignInRejected or SourceProblem.CredentialNotKept)
        {
            actions.Children.Add(ActionButton(Strings.Get("catalogue_signIn_submit"), () => _ = SignInAgainAsync(source)));
        }

        actions.Children.Add(ActionButton(Strings.Get("sources_rename"), () => _ = RenameAsync(source)));
        actions.Children.Add(ActionButton(Strings.Get("sources_remove"), () => _ = RemoveAsync(source)));

        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(text);
        Grid.SetColumn(actions, 1);
        grid.Children.Add(actions);
        AutomationProperties.SetName(grid, source.Name + ", " + state);
        return new Border
        {
            Child = grid,
            Padding = new Thickness(16, 12, 16, 12),
            BorderThickness = new Thickness(1),
            CornerRadius = (CornerRadius)Application.Current.Resources["ControlCornerRadius"],
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        };
    }

    private static TextBlock Grey(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
        Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
    };

    private static Button ActionButton(string label, Action click)
    {
        var button = new Button { Content = label };
        button.Click += (sender, args) => click();
        return button;
    }

    private void OnAdd(object sender, RoutedEventArgs args) => _ = AddAsync();

    /// <summary>The add sheet: kind, name, address, who, and the credential. It checks the source through the core and adds it only when it answers.</summary>
    private async Task AddAsync()
    {
        if (Network is not { } network)
        {
            return;
        }

        var kinds = new[] { NetworkSourceKind.NetworkShare, NetworkSourceKind.OpdsCatalogue, NetworkSourceKind.KavitaServer };
        var kind = new ComboBox { Header = Strings.Get("desktop_w3_sources_kind"), MinWidth = 280 };
        foreach (var each in kinds)
        {
            kind.Items.Add(SourceMessages.KindTitle(each));
        }

        kind.SelectedIndex = 0;
        var name = new TextBox { Header = Strings.Get("desktop_w3_sources_name") };
        var address = new TextBox { Header = Strings.Get("catalogue_address_label"), PlaceholderText = "smb://nas/comics" };
        var user = new TextBox { Header = Strings.Get("smb_user_label") };
        var password = new PasswordBox { Header = Strings.Get("smb_password_label") };
        var token = new PasswordBox { Header = Strings.Get("catalogue_signIn_token"), Visibility = Visibility.Collapsed };
        var message = Grey(string.Empty);
        message.Visibility = Visibility.Collapsed;
        var trust = new Button { Content = Strings.Get("catalogue_untrusted_trust"), Visibility = Visibility.Collapsed };
        CertificateChallenge? pending = null;

        kind.SelectionChanged += (sender, args) =>
        {
            var selected = kinds[Math.Max(0, kind.SelectedIndex)];
            user.Visibility = selected == NetworkSourceKind.KavitaServer ? Visibility.Collapsed : Visibility.Visible;
            password.Visibility = selected == NetworkSourceKind.KavitaServer ? Visibility.Collapsed : Visibility.Visible;
            token.Visibility = selected == NetworkSourceKind.NetworkShare ? Visibility.Collapsed : Visibility.Visible;
            token.Header = Strings.Get(selected == NetworkSourceKind.KavitaServer ? "kavita_key_label" : "catalogue_signIn_token");
            address.PlaceholderText = selected switch
            {
                NetworkSourceKind.NetworkShare => "smb://nas/comics",
                NetworkSourceKind.OpdsCatalogue => "https://books.example/opds",
                _ => "https://kavita.example",
            };
        };
        trust.Click += (sender, args) =>
        {
            if (pending is { } challenge)
            {
                network.Trust(challenge);
                pending = null;
                trust.Visibility = Visibility.Collapsed;
                message.Text = string.Empty;
                message.Visibility = Visibility.Collapsed;
            }
        };

        var panel = new StackPanel { Spacing = 12, MinWidth = 380 };
        foreach (UIElement element in new UIElement[] { kind, name, address, user, password, token, message, trust })
        {
            panel.Children.Add(element);
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Strings.Get("sources_add"),
            Content = new ScrollViewer { Content = panel, MaxHeight = 520 },
            PrimaryButtonText = Strings.Get("smb_connect"),
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        string? notice = null;
        dialog.PrimaryButtonClick += async (sender, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                dialog.IsPrimaryButtonEnabled = false;
                var selected = kinds[Math.Max(0, kind.SelectedIndex)];
                var entered = selected switch
                {
                    NetworkSourceKind.KavitaServer => new SourceSecrets(ApiKey: token.Password),
                    NetworkSourceKind.OpdsCatalogue => new SourceSecrets(Password: password.Password, Token: token.Password),
                    _ => new SourceSecrets(Password: password.Password),
                };
                var outcome = await network.AddSourceAsync(selected, name.Text, address.Text, user.Text, port: null, entered);
                if (outcome.Source is null)
                {
                    args.Cancel = true;
                    message.Text = outcome.Failure is { } failure ? SourceMessages.For(failure, selected) : Strings.Get("smb_error_unexpected");
                    message.Visibility = Visibility.Visible;
                    pending = outcome.Failure?.Certificate;
                    if (pending is { } challenge)
                    {
                        message.Text = Strings.Get("catalogue_untrusted_explanation") + Environment.NewLine
                            + Strings.Get("catalogue_untrusted_fingerprint") + ": " + challenge.Fingerprint;
                        trust.Visibility = Visibility.Visible;
                    }
                }
                else if (outcome.Credential is { NeedsSignIn: true } kept)
                {
                    notice = kept.Outcome == CredentialOutcome.TooLong
                        ? Strings.Get("desktop_w3_sources_credentialTooLong")
                        : string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_sources_credentialRefused___"), kept.Failure ?? string.Empty);
                }
                else if (outcome.Credential is { Notice: { Length: > 0 } sessionNotice })
                {
                    // No secure store is running: the core's grey line names what supplies one, and the source works for this session.
                    notice = sessionNotice;
                }
            }
            finally
            {
                dialog.IsPrimaryButtonEnabled = true;
                deferral.Complete();
            }
        };

        _ = await dialog.ShowAsync();
        if (notice is not null)
        {
            _ = await Info(notice).ShowAsync();
        }
    }

    private ContentDialog Info(string text) => new()
    {
        XamlRoot = XamlRoot,
        Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap },
        CloseButtonText = Strings.Get("settings_done"),
    };

    private async Task TestAsync(NetworkSource source)
    {
        if (Network is { } network)
        {
            _ = await network.TestAsync(source);
        }
    }

    private async Task SignInAgainAsync(NetworkSource source)
    {
        if (Network is not { } network)
        {
            return;
        }

        var password = new PasswordBox { Header = Strings.Get(source.Kind == NetworkSourceKind.KavitaServer ? "kavita_key_label" : "smb_password_label") };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = source.Name,
            Content = password,
            PrimaryButtonText = Strings.Get("catalogue_signIn_submit"),
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        var entered = source.Kind == NetworkSourceKind.KavitaServer ? new SourceSecrets(ApiKey: password.Password) : new SourceSecrets(Password: password.Password);
        var saved = network.SignInAgain(source, entered);
        if (saved.NeedsSignIn)
        {
            _ = await Info(saved.Outcome == CredentialOutcome.TooLong
                ? Strings.Get("desktop_w3_sources_credentialTooLong")
                : string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_sources_credentialRefused___"), saved.Failure ?? string.Empty)).ShowAsync();
            return;
        }

        _ = await network.TestAsync(source);
    }

    private async Task RenameAsync(NetworkSource source)
    {
        var field = new TextBox { Text = source.Name, Header = Strings.Get("sources_rename_field") };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Strings.Get("sources_rename_title"),
            Content = field,
            PrimaryButtonText = Strings.Get("sources_rename_save"),
            CloseButtonText = Strings.Get("sources_rename_cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            Network?.Rename(source, field.Text);
        }
    }

    private async Task RemoveAsync(NetworkSource source)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = string.Format(CultureInfo.CurrentCulture, Strings.Get("sources_remove_title___"), source.Name),
            Content = new TextBlock { Text = Strings.Get("sources_remove_footer"), TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = Strings.Get("sources_remove"),
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            Network?.RemoveSource(source);
        }
    }

    /// <summary>
    /// Browses a source in a dialog: a share's folders and files, a catalogue's pages with a Download on each entry that offers a file the app reads,
    /// or a Kavita server's libraries, series and chapters with the progress it holds. A failure is a grey line, and the source stays usable.
    /// </summary>
    private async Task BrowseAsync(NetworkSource source)
    {
        if (Network is not { } network)
        {
            return;
        }

        var list = new ListView { MinWidth = 420, MaxHeight = 420, SelectionMode = ListViewSelectionMode.None };
        var note = Grey(string.Empty);
        var back = new Button { Content = "‹" };
        AutomationProperties.SetName(back, Strings.Get("smb_up"));
        var search = new TextBox { PlaceholderText = Strings.Get("catalogue_search_prompt"), Visibility = Visibility.Collapsed };
        var history = new Stack<Func<Task>>();
        Func<Task>? current = null;

        async Task Go(Func<Task> load, bool push = true)
        {
            if (push && current is not null)
            {
                history.Push(current);
            }

            current = load;
            back.IsEnabled = history.Count > 0;
            note.Text = string.Empty;
            try
            {
                await load();
            }
            catch (StoryArcException error)
            {
                list.Items.Clear();
                note.Text = SourceMessages.For(SourceFailure.Of(error), source.Kind);
            }
        }

        void AddRow(string title, string? detail, Func<Task>? open, Button? action = null)
        {
            var line = new Grid { ColumnSpacing = 12 };
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var text = new StackPanel();
            text.Children.Add(new TextBlock { Text = title, TextTrimming = TextTrimming.CharacterEllipsis });
            if (detail is not null)
            {
                text.Children.Add(Grey(detail));
            }

            line.Children.Add(text);
            if (action is not null)
            {
                Grid.SetColumn(action, 1);
                line.Children.Add(action);
            }

            var item = new ListViewItem { Content = line, IsEnabled = true };
            if (open is not null)
            {
                item.Tapped += async (sender, args) => await Go(open);
            }

            list.Items.Add(item);
        }

        Func<Task> LoadShareFolder(string path) => async () =>
        {
            var entries = await network.ListShareAsync(source, path);
            list.Items.Clear();
            note.Text = Strings.Get("desktop_w3_sources_shareListOnly");
            foreach (var entry in entries)
            {
                AddRow(
                    entry.Name,
                    entry.IsDirectory ? null : StoryArc.Interop.Data.DownloadQueues.Size(entry.Length),
                    entry.IsDirectory ? LoadShareFolder(entry.Path) : null);
            }
        };

        Func<Task> LoadCatalogue(string? url, string? terms) => async () =>
        {
            var page = await network.OpdsAsync(source, url, terms);
            list.Items.Clear();
            search.Visibility = page.Searchable ? Visibility.Visible : Visibility.Collapsed;
            if (page.LocalOnly)
            {
                note.Text = Strings.Get("catalogue_search_local");
                return;
            }

            foreach (var section in page.Navigation ?? [])
            {
                AddRow(section.Title, section.Count is { } count ? count.ToString(CultureInfo.CurrentCulture) : null, LoadCatalogue(section.Href, null));
            }

            foreach (var entry in page.Publications ?? [])
            {
                var download = new Button { Content = Strings.Get("catalogue_acquire_download"), IsEnabled = entry.CanDownload };
                var captured = entry;
                download.Click += (sender, args) => network.Download(source, captured);
                AddRow(entry.Title, entry.Authors is { Count: > 0 } authors ? string.Join(", ", authors) : null, null, download);
            }

            if (page.Next is { } next)
            {
                AddRow(Strings.Get("catalogue_group_more"), null, LoadCatalogue(next, null));
            }
        };

        Func<Task> LoadKavitaLibraries() => async () =>
        {
            var libraries = await network.KavitaLibrariesAsync(source);
            list.Items.Clear();
            note.Text = Strings.Get("desktop_w3_sources_kavitaDownloadUnavailable");
            foreach (var library in libraries)
            {
                AddRow(library.Name, null, LoadKavitaSeries(library.Id));
            }
        };

        Func<Task> LoadKavitaSeries(long library) => async () =>
        {
            var series = await network.KavitaSeriesAsync(source, library);
            list.Items.Clear();
            foreach (var each in series)
            {
                AddRow(each.Name, string.Format(CultureInfo.CurrentCulture, Strings.Get("sources_detail_progress__lld__lld"), each.PagesRead, each.Pages), LoadKavitaChapters(each.Id));
            }
        };

        Func<Task> LoadKavitaChapters(long series) => async () =>
        {
            var volumes = await network.KavitaVolumesAsync(source, series);
            list.Items.Clear();
            foreach (var chapter in volumes.SelectMany(volume => volume.Chapters ?? []))
            {
                AddRow(chapter.Title ?? chapter.Number, string.Format(CultureInfo.CurrentCulture, Strings.Get("sources_detail_progress__lld__lld"), chapter.PagesRead, chapter.Pages), null);
            }
        };

        back.Click += async (sender, args) =>
        {
            if (history.Count > 0)
            {
                await Go(history.Pop(), push: false);
            }
        };
        search.KeyDown += async (sender, args) =>
        {
            if (args.Key == VirtualKey.Enter && source.Kind == NetworkSourceKind.OpdsCatalogue)
            {
                var terms = search.Text;
                await Go(LoadCatalogue(null, terms));
            }
        };

        var content = new StackPanel { Spacing = 8 };
        content.Children.Add(back);
        content.Children.Add(search);
        content.Children.Add(note);
        content.Children.Add(list);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = source.Name,
            Content = content,
            CloseButtonText = Strings.Get("settings_done"),
        };
        var first = source.Kind switch
        {
            NetworkSourceKind.NetworkShare => LoadShareFolder(string.Empty),
            NetworkSourceKind.OpdsCatalogue => LoadCatalogue(null, null),
            _ => LoadKavitaLibraries(),
        };
        _ = Go(first);
        _ = await dialog.ShowAsync();
    }
}
