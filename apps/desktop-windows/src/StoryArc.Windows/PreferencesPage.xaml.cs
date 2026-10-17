using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Settings;
using StoryArc.Interop.SystemSettings;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The settings page (desktop-clients tasks 2.47 and 2.47e). What it shows, and what a search
/// leaves, is <see cref="PreferencesIndex"/>; what it edits is <see cref="SettingsStore"/>. A
/// setting whose feature is not built yet shows as a titled row with no control, so the page
/// already has the shape of the design and each later task adds only its control here.
/// </summary>
public sealed partial class PreferencesPage : UserControl
{
    private AppHost? _host;

    private AppHost Host => _host ?? throw new InvalidOperationException("Initialize runs before the page is used.");

    public PreferencesPage()
    {
        InitializeComponent();
    }

    internal void Initialize(AppHost host)
    {
        _host = host;
        PageTitle.Text = Strings.Get("settings_title");
        Search.PlaceholderText = Strings.Get("settings_search");
        AutomationProperties.SetName(Search, Strings.Get("settings_search"));
        Rebuild(string.Empty);
    }

    private void OnSearchChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => Rebuild(sender.Text);

    private void Rebuild(string query)
    {
        Results.Children.Clear();
        var sections = PreferencesIndex.Search(query);
        if (sections.Count == 0)
        {
            Results.Children.Add(Note(string.Format(CultureInfo.CurrentCulture, Strings.Get("settings_search_empty___"), query.Trim())));
            return;
        }

        foreach (var section in sections)
        {
            var rows = section.Entries.Select(Row).OfType<UIElement>().ToList();
            if (rows.Count == 0)
            {
                continue;
            }

            Results.Children.Add(new TextBlock
            {
                Text = Strings.Get(section.TitleKey),
                Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
                Margin = new Thickness(0, 8, 0, 0),
            });
            foreach (var row in rows)
            {
                Results.Children.Add(row);
            }
        }
    }

    /// <summary>One row, or <c>null</c> when the setting is not offered on this system.</summary>
    private Border? Row(PreferenceEntry entry)
    {
        var title = Strings.Get(entry.TitleKey, entry.Title);
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = title, TextWrapping = TextWrapping.Wrap });

        var note = Note(string.Empty);
        note.Visibility = Visibility.Collapsed;
        text.Children.Add(note);

        FrameworkElement? editor;
        switch (entry.Id)
        {
            case "appearance":
                editor = AppearanceChoiceBox(title, note);
                break;
            case "accent":
                if (!ChromeAccent.OffersSystemChoice(Host.SystemWatcher.SystemAccent()))
                {
                    return null;
                }

                editor = AccentChoiceBox(title);
                break;
            case "transparency":
                SetNote(note, Strings.Get("settings_transparency_note", "Follows the Windows setting for transparency effects."));
                editor = null;
                break;
            case "clickZones":
                editor = ClickZonesSwitch(title);
                break;
            case "transition":
                editor = TransitionChoiceBox(title);
                break;
            default:
                editor = null;
                break;
        }

        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(text);
        if (editor is not null)
        {
            Grid.SetColumn(editor, 1);
            grid.Children.Add(editor);
        }

        AutomationProperties.SetAutomationId(grid, "Preference_" + entry.Id);
        return new Border { Style = (Style)Resources["PreferenceRow"], Child = grid };
    }

    private ComboBox AppearanceChoiceBox(string name, TextBlock note)
    {
        var current = Host.Settings.Current.Appearance;
        ShowPendingNote(note, current);
        return Choice(
            name,
            [
                (AppearanceChoice.System, Strings.Get("appearance_system")),
                (AppearanceChoice.Light, Strings.Get("appearance_light")),
                (AppearanceChoice.Dark, Strings.Get("appearance_dark")),
                (AppearanceChoice.OledDark, Strings.Get("appearance_oledDark")),
                (AppearanceChoice.Natural, Strings.Get("appearance_natural")),
            ],
            current,
            choice =>
            {
                Host.Settings.Update(settings => settings with { Appearance = choice });
                ShowPendingNote(note, choice);
            });
    }

    private ComboBox AccentChoiceBox(string name) => Choice(
        name,
        [
            // The brand name is the same in every language, as the window title is.
            (AccentChoice.StoryArc, "StoryArc"),
            (AccentChoice.System, Strings.Get("appearance_system")),
        ],
        Host.Settings.Current.Accent,
        choice => Host.Settings.Update(settings => settings with { Accent = choice }));

    private ComboBox TransitionChoiceBox(string name) => Choice(
        name,
        [
            (TransitionMode.Slide, Strings.Get("reader_transition_slide")),
            (TransitionMode.Fade, Strings.Get("reader_transition_fade")),
            (TransitionMode.Scroll, Strings.Get("reader_transition_scrollVertical")),
        ],
        Host.Settings.Current.Transition,
        choice => Host.Settings.Update(settings => settings with { Transition = choice }));

    private ToggleSwitch ClickZonesSwitch(string name)
    {
        var toggle = new ToggleSwitch { IsOn = Host.Settings.Current.ClickZonesOn };
        toggle.Toggled += (sender, args) => Host.Settings.Update(settings => settings with { ClickZonesOn = toggle.IsOn });
        AutomationProperties.SetName(toggle, name);
        return toggle;
    }

    private static ComboBox Choice<T>(string name, IReadOnlyList<(T Value, string Label)> options, T current, Action<T> apply)
        where T : struct
    {
        var box = new ComboBox { MinWidth = 180 };
        foreach (var (_, label) in options)
        {
            box.Items.Add(label);
        }

        box.SelectedIndex = options.ToList().FindIndex(option => EqualityComparer<T>.Default.Equals(option.Value, current));
        box.SelectionChanged += (sender, args) =>
        {
            if (box.SelectedIndex >= 0)
            {
                apply(options[box.SelectedIndex].Value);
            }
        };
        AutomationProperties.SetName(box, name);
        return box;
    }

    private static void ShowPendingNote(TextBlock note, AppearanceChoice choice)
    {
        if (AppearanceTheme.IsPending(choice))
        {
            SetNote(note, Strings.Get("settings_appearance_pending", "Saved. This appearance is drawn in a later version; the chrome shows the nearest one for now."));
        }
        else
        {
            note.Visibility = Visibility.Collapsed;
        }
    }

    private static void SetNote(TextBlock note, string text)
    {
        note.Text = text;
        note.Visibility = Visibility.Visible;
    }

    private TextBlock Note(string text) => new() { Text = text, Style = (Style)Resources["PreferenceNote"] };
}
