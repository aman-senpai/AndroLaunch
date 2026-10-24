using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AndroLaunch.WinUI.Pages
{
    public sealed class AppsPage : Page
    {
        private readonly ListView appList = new() { SelectionMode = ListViewSelectionMode.Single };
        private readonly AutoSuggestBox search = new()
        {
            PlaceholderText = "Search apps",
            Width = 300
        };
        private readonly ComboBox deviceCombo = new() { MinWidth = 250 };
        private readonly InfoBar status = new()
        {
            IsClosable = false,
            IsOpen = true,
            Title = "Apps",
            Severity = InfoBarSeverity.Informational
        };
        private readonly TextBlock countText = new() { Opacity = 0.65 };
        private readonly Button launchButton = new() { Content = "Launch", IsEnabled = false };
        private readonly Button favoriteButton = new() { Content = "Add to favorites", IsEnabled = false };
        private readonly MenuFlyoutItem clearButton = new() { Text = "Clear app data…", IsEnabled = false };
        private readonly MenuFlyoutItem versionButton = new() { Text = "App version", IsEnabled = false };
        private readonly MenuFlyoutItem permissionsButton = new() { Text = "Permissions", IsEnabled = false };
        private readonly MenuFlyoutItem apkButton = new() { Text = "Export APK…", IsEnabled = false };
        private readonly MenuFlyoutItem logcatButton = new() { Text = "Developer: Open Logcat", IsEnabled = false };
        private readonly MenuFlyoutItem uninstallButton = new() { Text = "Uninstall app…", IsEnabled = false };
        private readonly Button installButton = new() { Content = "Install APK…", IsEnabled = false };

        private List<AdbHelper.AppInfo> allApps = new();
        private bool loading;

        public AppsPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) => await LoadDevicesAsync();
            AutomationProperties.SetName(search, "Search installed apps, Control F");
            AutomationProperties.SetName(deviceCombo, "Target device for app actions");
            var find = new KeyboardAccelerator { Key = VirtualKey.F, Modifiers = VirtualKeyModifiers.Control };
            find.Invoked += (_, args) => { search.Focus(FocusState.Keyboard); args.Handled = true; };
            KeyboardAccelerators.Add(find);
        }

        private UIElement BuildContent()
        {
            var root = new Grid { Padding = new Thickness(28), RowSpacing = 14 };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var header = new StackPanel { Spacing = 10 };
            var titles = new StackPanel { Spacing = 2 };
            titles.Children.Add(new TextBlock
            {
                Text = "Apps",
                FontSize = 30,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            titles.Children.Add(new TextBlock
            {
                Text = "Launch, inspect and manage installed Android apps.",
                Opacity = 0.7
            });
            header.Children.Add(titles);
            var right = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                VerticalAlignment = VerticalAlignment.Center
            };
            right.Children.Add(deviceCombo);
            var refresh = new Button { Content = "Refresh" };
            refresh.Click += async (_, _) => await LoadAppsAsync();
            right.Children.Add(refresh);
            right.Children.Add(installButton);
            right.HorizontalAlignment = HorizontalAlignment.Left;
            header.Children.Add(right);
            Grid.SetRow(header, 0);
            root.Children.Add(header);

            Grid.SetRow(status, 1);
            root.Children.Add(status);

            var searchRow = new StackPanel { Spacing = 10 };
            searchRow.Children.Add(search);
            var actions = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
                HorizontalAlignment = HorizontalAlignment.Left
            };
            actions.Children.Add(launchButton);
            actions.Children.Add(favoriteButton);
            var more = new Button { Content = "More actions" };
            var menu = new MenuFlyout();
            menu.Items.Add(versionButton);
            menu.Items.Add(permissionsButton);
            menu.Items.Add(apkButton);
            menu.Items.Add(logcatButton);
            menu.Items.Add(new MenuFlyoutSeparator());
            menu.Items.Add(clearButton);
            menu.Items.Add(uninstallButton);
            more.Flyout = menu;
            actions.Children.Add(more);
            searchRow.Children.Add(actions);
            Grid.SetRow(searchRow, 2);
            root.Children.Add(searchRow);

            search.TextChanged += (_, _) => FilterApps();
            search.QuerySubmitted += (_, _) => FilterApps();
            deviceCombo.SelectionChanged += async (_, _) =>
            {
                if (deviceCombo.SelectedItem is ComboBoxItem item && item.Tag is string serial)
                {
                    AppState.SelectedSerial = serial;
                    await LoadAppsAsync();
                }
            };
            appList.SelectionChanged += (_, _) => UpdateButtons();
            appList.DoubleTapped += async (_, _) => await LaunchSelectedAsync();

            var listCard = new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8),
                Child = appList
            };
            Grid.SetRow(listCard, 3);
            root.Children.Add(listCard);

            var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            footer.Children.Add(countText);
            Grid.SetRow(footer, 4);
            root.Children.Add(footer);

            launchButton.Click += async (_, _) => await LaunchSelectedAsync();
            favoriteButton.Click += async (_, _) =>
            {
                if (SelectedApp is not { } app || Serial is not string serial) return;
                try
                {
                    QuickAccessStore.ToggleFavorite($"app:{serial}:{app.PackageName}");
                    UpdateButtons();
                }
                catch (Exception ex) { await Ui.ShowErrorAsync("Favorite was not saved", ex.Message); }
            };
            clearButton.Click += async (_, _) => await ClearSelectedAsync();
            versionButton.Click += async (_, _) => await ShowVersionAsync();
            permissionsButton.Click += async (_, _) => await ShowPermissionsAsync();
            apkButton.Click += async (_, _) => await ExportApkAsync();
            logcatButton.Click += (_, _) => RunSelected("Could not open logcat", serial => AdbHelper.OpenLogcat(serial));
            uninstallButton.Click += async (_, _) => await UninstallSelectedAsync();
            installButton.Click += async (_, _) => await InstallApkAsync();

            return root;
        }

        private string? Serial => (deviceCombo.SelectedItem as ComboBoxItem)?.Tag as string;

        private AdbHelper.AppInfo? SelectedApp =>
            (appList.SelectedItem as ListViewItem)?.Tag as AdbHelper.AppInfo;

        private async Task LoadDevicesAsync()
        {
            try
            {
                List<AdbHelper.AdbDeviceInfo> devices = await Task.Run(AdbHelper.GetDevices);
                deviceCombo.Items.Clear();
                foreach (AdbHelper.AdbDeviceInfo device in devices.Where(device => device.Status == "device"))
                {
                    deviceCombo.Items.Add(new ComboBoxItem
                    {
                        Content = $"{device.Name} • {device.Serial}",
                        Tag = device.Serial
                    });
                }

                if (deviceCombo.Items.Count == 0)
                {
                    SetStatus("No devices connected", "Enable USB debugging or pair wirelessly.", InfoBarSeverity.Warning);
                    UpdateButtons();
                    return;
                }

                int index = 0;
                if (!string.IsNullOrWhiteSpace(AppState.SelectedSerial))
                {
                    for (int i = 0; i < deviceCombo.Items.Count; i++)
                    {
                        if ((deviceCombo.Items[i] as ComboBoxItem)?.Tag as string == AppState.SelectedSerial)
                        {
                            index = i;
                            break;
                        }
                    }
                }

                deviceCombo.SelectedIndex = index;
                await LoadAppsAsync();
            }
            catch (Exception ex)
            {
                SetStatus("Could not list devices", ex.Message, InfoBarSeverity.Error);
            }
        }

        private async Task LoadAppsAsync()
        {
            if (Serial is not string serial || loading)
            {
                return;
            }

            loading = true;
            SetStatus("Loading apps", "Reading installed apps from the device…", InfoBarSeverity.Informational);
            UpdateButtons();
            try
            {
                allApps = await Task.Run(() => AdbHelper.GetApps(serial));
                FilterApps();
                SetStatus($"{allApps.Count} apps", "Select an app to launch or manage it.", InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                SetStatus("Could not load apps", ex.Message, InfoBarSeverity.Error);
            }
            finally
            {
                loading = false;
                UpdateButtons();
            }
        }

        private void FilterApps()
        {
            string query = search.Text.Trim();
            List<AdbHelper.AppInfo> filtered = string.IsNullOrWhiteSpace(query)
                ? allApps
                : allApps.Where(app =>
                    app.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    app.PackageName.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();

            appList.Items.Clear();
            foreach (AdbHelper.AppInfo app in filtered)
            {
                var row = new Grid { ColumnSpacing = 12 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Children.Add(new TextBlock
                {
                    Text = app.Name,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                var package = new TextBlock
                {
                    Text = app.PackageName,
                    Opacity = 0.55,
                    FontSize = 12,
                    TextTrimming = TextTrimming.CharacterEllipsis
                };
                Grid.SetColumn(package, 1);
                row.Children.Add(package);
                appList.Items.Add(new ListViewItem { Tag = app, Content = row });
            }

            countText.Text = $"{filtered.Count} of {allApps.Count} apps";
            UpdateButtons();
        }

        private void UpdateButtons()
        {
            deviceCombo.IsEnabled = !loading;
            installButton.IsEnabled = Serial is not null && !loading;
            bool has = SelectedApp is not null && !loading;
            launchButton.IsEnabled = has;
            favoriteButton.IsEnabled = has;
            favoriteButton.Content = SelectedApp is { } favoriteApp && Serial is string favoriteSerial &&
                QuickAccessStore.IsFavorite($"app:{favoriteSerial}:{favoriteApp.PackageName}") ? "Remove favorite" : "Add to favorites";
            clearButton.IsEnabled = has;
            versionButton.IsEnabled = has;
            permissionsButton.IsEnabled = has;
            apkButton.IsEnabled = has;
            logcatButton.IsEnabled = Serial is not null;
            uninstallButton.IsEnabled = has;
        }

        private async Task LaunchSelectedAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            try
            {
                var compatibility = await ToolCompatibility.CheckScrcpyAsync();
                if (!compatibility.IsCompatible) throw new InvalidOperationException(compatibility.Summary);
                MirrorPresetStore.Restore(serial);
                SetStatus("Launching", app.Name, InfoBarSeverity.Informational);
                await Task.Run(() => AdbHelper.LaunchApp(serial, app.PackageName));
                SetStatus("Launched", app.Name, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not launch app", ex.Message);
            }
        }

        private async Task ClearSelectedAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            if (!await Ui.ConfirmAsync("Clear app data", $"Clear all data for {app.Name} ({app.PackageName}) on {DeviceIdentity(serial)}?\n\nAccounts, preferences, and local app data will be permanently removed. This cannot be undone.", "Clear data"))
            {
                return;
            }

            try
            {
                await Task.Run(() => AdbHelper.ClearAppData(serial, app.PackageName));
                SetStatus("App data cleared", app.Name, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not clear app data", ex.Message);
            }
        }

        private async Task ShowVersionAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            try
            {
                string output = await Task.Run(() => AdbHelper.GetAppVersion(serial, app.PackageName));
                await Ui.ShowTextAsync($"{app.Name} - Version", output);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not read app version", ex.Message);
            }
        }

        private async Task ShowPermissionsAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            try
            {
                string output = await Task.Run(() => AdbHelper.GetAppPermissions(serial, app.PackageName));
                await Ui.ShowTextAsync($"{app.Name} - Permissions", output);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not read app permissions", ex.Message);
            }
        }

        private async Task InstallApkAsync()
        {
            if (Serial is not string serial || loading) return;
            var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.Downloads };
            picker.FileTypeFilter.Add(".apk");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            var file = await picker.PickSingleFileAsync();
            if (file is null) return;
            loading = true;
            UpdateButtons();
            try
            {
                SetStatus("Installing APK", file.Name, InfoBarSeverity.Informational);
                await Task.Run(() => AdbHelper.InstallApk(serial, file.Path));
                loading = false;
                await LoadAppsAsync();
                SetStatus("APK installed", file.Name, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not install APK", ex.Message);
            }
            finally
            {
                loading = false;
                UpdateButtons();
            }
        }

        private async Task ExportApkAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            var picker = new FileSavePicker
            {
                SuggestedFileName = app.Name + ".apk",
                SuggestedStartLocation = PickerLocationId.Downloads
            };
            picker.FileTypeChoices.Add("Android package", new List<string> { ".apk" });
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            Windows.Storage.StorageFile? file = await picker.PickSaveFileAsync();
            if (file is null)
            {
                return;
            }

            try
            {
                await Task.Run(() => AdbHelper.ExportApk(serial, app.PackageName, file.Path));
                SetStatus("APK saved", file.Path, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not export APK", ex.Message);
            }
        }

        private async Task UninstallSelectedAsync()
        {
            if (SelectedApp is not AdbHelper.AppInfo app || Serial is not string serial)
            {
                return;
            }

            if (!await Ui.ConfirmAsync("Uninstall app", $"Uninstall {app.Name} ({app.PackageName}) from {DeviceIdentity(serial)}?\n\nThe app and its local data will be removed. This cannot be undone.", "Uninstall"))
            {
                return;
            }

            try
            {
                await Task.Run(() => AdbHelper.UninstallApp(serial, app.PackageName));
                await LoadAppsAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not uninstall app", ex.Message);
            }
        }

        private void RunSelected(string title, Action<string> action)
        {
            if (Serial is not string serial)
            {
                return;
            }

            try
            {
                action(serial);
            }
            catch (Exception ex)
            {
                _ = Ui.ShowErrorAsync(title, ex.Message);
            }
        }

        private string DeviceIdentity(string serial) =>
            $"{(deviceCombo.SelectedItem as ComboBoxItem)?.Content ?? "Android device"} (serial: {serial})";

        private void SetStatus(string title, string message, InfoBarSeverity severity)
        {
            status.IsOpen = true;
            status.Title = title;
            status.Message = message;
            status.Severity = severity;
        }
    }
}
