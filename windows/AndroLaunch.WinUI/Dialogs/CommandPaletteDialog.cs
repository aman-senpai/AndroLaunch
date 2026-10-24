using Androlaunch.Core;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.System;

namespace AndroLaunch.WinUI.Dialogs;

public static class CommandPaletteDialog
{
    private sealed record ActionItem(string Id, string Title, string Detail, Func<Task> Execute);
    private static bool showing;

    public static async Task ShowAsync()
    {
        if (showing) return;
        showing = true;
        try { await ShowCoreAsync(); }
        finally { showing = false; }
    }

    private static async Task ShowCoreAsync()
    {
        var search = new TextBox { PlaceholderText = "Search actions, favorite apps, and saved commands…" };
        AutomationProperties.SetName(search, "Search quick actions");
        var devicePicker = new ComboBox { Header = "Target device", HorizontalAlignment = HorizontalAlignment.Stretch };
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single, MinHeight = 160, MaxHeight = 240 };
        AutomationProperties.SetName(list, "Quick actions, favorites first, then recent actions");
        var favorite = new Button { Content = "Add to favorites", IsEnabled = false };
        var loadApps = new Button { Content = "Include installed apps", IsEnabled = false };
        var refresh = new Button { Content = "Refresh devices" };
        var status = new TextBlock { Text = "Checking connected devices…", TextWrapping = TextWrapping.Wrap, Opacity = 0.75 };
        AutomationProperties.SetLiveSetting(status, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
        var panel = new StackPanel { Spacing = 10, MinWidth = 420, MaxWidth = 640 };
        panel.Children.Add(search);
        panel.Children.Add(devicePicker);
        var buttons = new Grid { ColumnSpacing = 8, RowSpacing = 8 };
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        buttons.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetColumn(loadApps, 1);
        Grid.SetRow(refresh, 1);
        Grid.SetColumnSpan(refresh, 2);
        buttons.Children.Add(favorite); buttons.Children.Add(loadApps); buttons.Children.Add(refresh);
        panel.Children.Add(buttons);
        panel.Children.Add(status);
        panel.Children.Add(list);
        panel.Children.Add(new TextBlock { Text = "Favorites and recent actions are stored on this PC. Device actions always use the target selected above. Enter runs the selected action.", TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        var dialog = new ContentDialog
        {
            Title = "Quick actions", Content = new ScrollViewer { Content = panel, MaxHeight = 460 }, PrimaryButtonText = "Run", CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary, XamlRoot = App.MainWindowInstance.Content.XamlRoot
        };
        var actions = new List<ActionItem>();
        string? serial = null;
        string deviceName = "";
        bool busy = false;
        ActionItem? selected = null;
        string? loadedAppsSerial = null;

        void Filter()
        {
            string? selectedId = (list.SelectedItem as ListViewItem)?.Tag is ActionItem old ? old.Id : null;
            list.Items.Clear();
            foreach (var action in actions.Where(action => $"{action.Title} {action.Detail}".Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(action => QuickAccessStore.IsFavorite(action.Id))
                .ThenBy(action => QuickAccessStore.RecentIndex(action.Id) is int index && index >= 0 ? index : int.MaxValue)
                .ThenBy(action => action.Title, StringComparer.CurrentCultureIgnoreCase))
            {
                var text = new StackPanel { Spacing = 2 };
                text.Children.Add(new TextBlock { Text = (QuickAccessStore.IsFavorite(action.Id) ? "★ " : "") + action.Title, TextWrapping = TextWrapping.Wrap });
                text.Children.Add(new TextBlock { Text = action.Detail, TextWrapping = TextWrapping.Wrap, Opacity = 0.65, FontSize = 12 });
                var row = new ListViewItem { Content = text, Tag = action, HorizontalContentAlignment = HorizontalAlignment.Stretch };
                AutomationProperties.SetName(row, $"{action.Title}. {action.Detail}");
                list.Items.Add(row);
                if (action.Id == selectedId) list.SelectedItem = row;
            }
            if (list.SelectedIndex < 0 && list.Items.Count > 0) list.SelectedIndex = 0;
            dialog.IsPrimaryButtonEnabled = !busy && list.SelectedItem is not null;
            favorite.IsEnabled = !busy && list.SelectedItem is not null;
            if (list.Items.Count == 0) status.Text = "No matching actions. Try another search, or include installed apps.";
        }
        void AddApp(string package, string title, string target)
        {
            string id = $"app:{target}:{package}";
            if (actions.Any(action => action.Id == id)) return;
            actions.Add(new(id, $"Launch {title}", $"{package} • {deviceName}", () => Task.Run(() => AdbHelper.LaunchApp(target, package))));
        }
        void Rebuild()
        {
            actions.Clear();
            loadedAppsSerial = null;
            void Page(string id, string title, string page, string detail) => actions.Add(new(id, title, detail, () => { App.ShowMainWindow(page, serial); return Task.CompletedTask; }));
            Page("devices", "Devices", "devices", "Connection status and everyday device controls • Ctrl+1");
            Page("apps", "Apps", "apps", "Browse, install, and manage apps • Ctrl+2");
            Page("files", "Files", "files", "Browse files and transfer documents • Ctrl+3");
            Page("settings", "Settings", "settings", "Dependencies, preferences, and optional developer tools");
            Page("emulators", "Emulators", "emulators", "Developer tools • Manage Android Virtual Devices");
            actions.Add(new("setup", "Connect a device", "USB debugging, authorization, and dependency setup", () => OnboardingDialog.ShowAsync()));
            actions.Add(new("pair", "Pair wirelessly", "Pair with an Android 11+ device on the local network", () => PairingDialog.ShowAsync()));
            actions.Add(new("commands", "Manage saved commands", "Developer tools • Review commands before running them", () => CommandManagerDialog.ShowAsync()));
            if (serial is string target)
            {
                actions.Add(new($"mirror:{target}", "Mirror screen", $"{deviceName} • Ctrl+M", async () =>
                {
                    var compatible = await ToolCompatibility.CheckScrcpyAsync();
                    if (!compatible.IsCompatible) throw new InvalidOperationException(compatible.Summary);
                    MirrorPresetStore.Restore(target);
                    await Task.Run(() => AdbHelper.MirrorScreen(target));
                }));
                actions.Add(new($"capture:{target}", "Capture screen", $"Screenshot or record {deviceName} • Ctrl+Shift+S", () => CaptureDialog.ShowAsync(target)));
                foreach (string package in QuickAccessStore.KnownAppPackages(target)) AddApp(package, package, target);
                foreach (var command in AdbHelper.GetSavedCommands())
                {
                    var saved = command;
                    actions.Add(new($"command:{saved.Id}", saved.Name, $"Saved command • {(saved.IsHostCommand ? "This PC" : deviceName)} • {saved.Command}", async () =>
                    {
                        if (!await Ui.ConfirmAsync($"Run {saved.Name}?", $"Target: {(saved.IsHostCommand ? "This PC" : deviceName + " (" + target + ")")}\n\n{saved.Command}\n\nOnly run commands you trust.", "Run command")) return;
                        AdbHelper.RunShellCommand(target, saved, (output, success) => App.MainWindowInstance.DispatcherQueue.TryEnqueue(async () =>
                        {
                            if (success) await Ui.ShowTextAsync(saved.Name, output);
                            else await Ui.ShowErrorAsync($"{saved.Name} failed", output);
                        }));
                    }));
                }
            }
            loadApps.IsEnabled = !busy && serial is not null && loadedAppsSerial != serial;
            Filter();
        }
        async Task RefreshAsync()
        {
            if (busy) return;
            busy = true; refresh.IsEnabled = devicePicker.IsEnabled = loadApps.IsEnabled = false; dialog.IsPrimaryButtonEnabled = false;
            string? previous = serial ?? AppState.SelectedSerial;
            try
            {
                var devices = await Task.Run(AdbHelper.GetDevices);
                devicePicker.Items.Clear();
                foreach (var device in devices.Where(device => device.Status == "device"))
                    devicePicker.Items.Add(new ComboBoxItem { Content = $"{device.Name} • {(device.IsWireless ? "Wireless" : "USB")} • {device.Serial}", Tag = device });
                serial = null;
                int index = -1;
                for (int i = 0; i < devicePicker.Items.Count; i++)
                    if (((ComboBoxItem)devicePicker.Items[i]).Tag is AdbHelper.AdbDeviceInfo device && device.Serial == previous) index = i;
                devicePicker.SelectedIndex = index >= 0 ? index : devicePicker.Items.Count == 1 ? 0 : -1;
                status.Text = devicePicker.Items.Count == 0 ? "No authorized device. Use Connect a device for USB authorization guidance, or Pair wirelessly."
                    : devicePicker.SelectedIndex < 0 ? "Choose a target device to enable device actions." : "Favorites appear first, followed by recent actions.";
            }
            catch (Exception ex) { status.Text = ex.Message; }
            finally { busy = false; refresh.IsEnabled = devicePicker.IsEnabled = true; Rebuild(); }
        }
        devicePicker.SelectionChanged += (_, _) =>
        {
            var device = (devicePicker.SelectedItem as ComboBoxItem)?.Tag as AdbHelper.AdbDeviceInfo;
            serial = device?.Serial;
            deviceName = device?.Name ?? "";
            if (serial is not null) AppState.SelectedSerial = serial;
            Rebuild();
        };
        search.TextChanged += (_, _) => Filter();
        search.KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Down && list.Items.Count > 0)
            {
                list.Focus(FocusState.Keyboard); list.SelectedIndex = Math.Max(0, list.SelectedIndex); args.Handled = true;
            }
        };
        list.SelectionChanged += (_, _) =>
        {
            var action = (list.SelectedItem as ListViewItem)?.Tag as ActionItem;
            dialog.IsPrimaryButtonEnabled = favorite.IsEnabled = action is not null && !busy;
            favorite.Content = action is not null && QuickAccessStore.IsFavorite(action.Id) ? "Remove favorite" : "Add to favorites";
        };
        favorite.Click += (_, _) =>
        {
            if ((list.SelectedItem as ListViewItem)?.Tag is not ActionItem action) return;
            try { QuickAccessStore.ToggleFavorite(action.Id); Filter(); }
            catch (Exception ex) { status.Text = $"Could not save favorites: {ex.Message}"; }
        };
        loadApps.Click += async (_, _) =>
        {
            if (serial is not string target || busy) return;
            busy = true; loadApps.IsEnabled = devicePicker.IsEnabled = refresh.IsEnabled = false; dialog.IsPrimaryButtonEnabled = false;
            status.Text = "Loading installed apps…";
            try
            {
                var apps = await Task.Run(() => AdbHelper.GetApps(target));
                foreach (var app in apps) AddApp(app.PackageName, app.Name, target);
                loadedAppsSerial = target;
                status.Text = "Search an installed app, then add it to favorites for quick access next time.";
            }
            catch (Exception ex) { status.Text = ex.Message; }
            finally { busy = false; devicePicker.IsEnabled = refresh.IsEnabled = true; loadApps.IsEnabled = loadedAppsSerial != serial; Filter(); }
        };
        refresh.Click += async (_, _) => await RefreshAsync();
        dialog.Opened += async (_, _) => { await RefreshAsync(); search.Focus(FocusState.Programmatic); };
        dialog.PrimaryButtonClick += (_, args) =>
        {
            if (busy || (list.SelectedItem as ListViewItem)?.Tag is not ActionItem action) { args.Cancel = true; return; }
            selected = action;
        };
        dialog.Closing += (_, args) => { if (busy) args.Cancel = true; };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || selected is null) return;
        try
        {
            await selected.Execute();
            try { QuickAccessStore.RecordAction(selected.Id); }
            catch (Exception ex) { await Ui.ShowErrorAsync("Action completed; history not saved", ex.Message); }
        }
        catch (Exception ex) { await Ui.ShowErrorAsync("Action could not complete", ex.Message); }
    }
}
