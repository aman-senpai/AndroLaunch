using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Dialogs;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace AndroLaunch.WinUI.Pages
{
    public sealed class DevicesPage : Page
    {
        private readonly ListView deviceList = new() { SelectionMode = ListViewSelectionMode.Single };
        private readonly StackPanel detailPanel = new() { Spacing = 14 };
        private readonly TextBlock emptyText = new()
        {
            Text = "No devices connected.\nEnable USB debugging, then plug in a device or use Wireless pairing.",
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.7,
            Margin = new Thickness(0, 12, 0, 0)
        };
        private readonly InfoBar statusBar = new()
        {
            IsClosable = false,
            IsOpen = false,
            Title = "Devices",
            Severity = InfoBarSeverity.Informational
        };

        private readonly TextBlock deviceTitle = new()
        {
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        private readonly TextBlock deviceInfo = new() { Opacity = 0.75, TextWrapping = TextWrapping.Wrap };

        private readonly ToggleSwitch wifi = Toggle("Wi-Fi");
        private readonly ToggleSwitch bluetooth = Toggle("Bluetooth");
        private readonly ToggleSwitch mobileData = Toggle("Mobile data");
        private readonly ToggleSwitch airplane = Toggle("Airplane mode");
        private readonly ToggleSwitch location = Toggle("Location");
        private readonly ToggleSwitch doNotDisturb = Toggle("Do not disturb");
        private readonly ToggleSwitch autoRotate = Toggle("Auto-rotate");
        private readonly ToggleSwitch adaptiveBrightness = Toggle("Adaptive brightness");
        private readonly ToggleSwitch darkMode = Toggle("Dark mode");
        private readonly ToggleSwitch clipboardSync = Toggle("Clipboard sync");
        private readonly Slider volume = new()
        {
            Minimum = 0,
            Maximum = 15,
            StepFrequency = 1,
            Value = 7,
            Width = 300
        };
        private readonly TextBlock volumeValue = new() { Text = "7 / 15", Opacity = 0.7 };

        private readonly ComboBox appResolution = new() { MinWidth = 180 };
        private readonly ComboBox mirrorSize = new() { MinWidth = 180 };
        private readonly ComboBox frameRate = new() { MinWidth = 180 };
        private readonly ComboBox bitRate = new() { MinWidth = 180 };
        private readonly ComboBox orientation = new() { MinWidth = 180 };
        private readonly ComboBox cameraFacing = new() { MinWidth = 180 };
        private readonly ComboBox cameraFps = new() { MinWidth = 180 };
        private readonly ComboBox cameraSize = new() { MinWidth = 180 };
        private readonly ComboBox cameraAr = new() { MinWidth = 180 };
        private readonly ToggleSwitch flex = Toggle("Flex display");
        private readonly ToggleSwitch borderless = Toggle("Borderless window");
        private readonly ToggleSwitch audio = Toggle("Audio forwarding");
        private readonly ToggleSwitch clipboardConfig = Toggle("Clipboard auto-sync");

        private static readonly int[] appResolutions = { 360, 540, 720, 900, 1080, 1440, 1600 };
        private static readonly int[] mirrorSizes = { 0, 800, 1024, 1280, 1440, 1600, 1920 };
        private static readonly int[] frameRates = { 0, 30, 60, 90, 120 };
        private static readonly int[] bitRates = { 2, 4, 8, 16, 20 };
        private static readonly string[] orientations = { "Auto", "0", "90", "180", "270" };
        private static readonly string[] cameraFacings = { "Auto", "front", "back", "external" };
        private static readonly int[] cameraFrameRates = { 0, 30, 60, 120, 240 };
        private static readonly int[] cameraSizes = { 0, 3840, 2560, 1920, 1280, 1024, 800, 640 };
        private static readonly string[] cameraAspectRatios = { "Auto", "4:3", "16:9", "1:1", "sensor" };

        private AdbHelper.AdbDeviceInfo? selected;
        private readonly AdbHelper.MirrorConfig fallbackConfig = new();
        private bool updatingToggles;
        private int selectionLoadVersion;

        public DevicesPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) => await RefreshDevicesAsync();
        }

        private UIElement BuildContent()
        {
            var root = new Grid { Padding = new Thickness(28), RowSpacing = 14 };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var titleStack = new StackPanel { Spacing = 2 };
            titleStack.Children.Add(new TextBlock
            {
                Text = "Devices",
                FontSize = 30,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            titleStack.Children.Add(new TextBlock
            {
                Text = "Mirror, manage and control connected Android devices.",
                Opacity = 0.7
            });
            header.Children.Add(titleStack);
            var headerActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var refresh = new Button { Content = "Refresh" };
            refresh.Click += async (_, _) => await RefreshDevicesAsync();
            headerActions.Children.Add(refresh);
            var pairing = new Button
            {
                Content = "Wireless pairing",
                Style = (Style)Application.Current.Resources["AccentButtonStyle"]
            };
            pairing.Click += async (_, _) => await PairingDialog.ShowAsync();
            headerActions.Children.Add(pairing);
            Grid.SetColumn(headerActions, 1);
            header.Children.Add(headerActions);
            Grid.SetRow(header, 0);
            root.Children.Add(header);

            statusBar.Margin = new Thickness(0, 0, 0, 4);
            Grid.SetRow(statusBar, 1);
            root.Children.Add(statusBar);

            var content = new Grid { ColumnSpacing = 18 };
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(330) });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var left = new StackPanel { Spacing = 8 };
            deviceList.SelectionChanged += async (_, _) =>
            {
                selected = (deviceList.SelectedItem as ListViewItem)?.Tag as AdbHelper.AdbDeviceInfo;
                AppState.SelectedSerial = selected?.Serial;
                await LoadSelectedAsync();
            };
            var leftCard = new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8),
                Child = deviceList,
                MinHeight = 300
            };
            left.Children.Add(leftCard);
            left.Children.Add(emptyText);
            Grid.SetColumn(left, 0);
            content.Children.Add(left);

            var scroll = new ScrollViewer
            {
                Content = detailPanel,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            Grid.SetColumn(scroll, 1);
            content.Children.Add(scroll);
            Grid.SetRow(content, 2);
            root.Children.Add(content);

            BuildDetails();
            return root;
        }

        private void BuildDetails()
        {
            detailPanel.Children.Clear();
            detailPanel.Children.Add(deviceTitle);
            detailPanel.Children.Add(deviceInfo);

            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            actions.Children.Add(ActionButton("Mirror", () => RunAsync("Could not mirror", () => AdbHelper.MirrorScreen(RequireSerial()))));
            actions.Children.Add(ActionButton("Camera", () => RunAsync("Could not open camera", () => AdbHelper.MirrorCamera(RequireSerial()))));
            actions.Children.Add(ActionButton("Files", () => App.ShowMainWindow("files", selected?.Serial)));
            actions.Children.Add(ActionButton("Apps", () => App.ShowMainWindow("apps", selected?.Serial)));
            actions.Children.Add(ActionButton("Shell", () => RunAsync("Could not open shell", () => AdbHelper.OpenShell(RequireSerial()))));
            actions.Children.Add(ActionButton("Logcat", () => RunAsync("Could not open logcat", () => AdbHelper.OpenLogcat(RequireSerial()))));
            detailPanel.Children.Add(actions);

            var quick = new StackPanel { Spacing = 10 };
            quick.Children.Add(SectionTitle("Quick settings"));
            var toggles = new Grid { ColumnSpacing = 18, RowSpacing = 2 };
            toggles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            toggles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int i = 0; i < 10; i++)
            {
                toggles.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }
            AddToggle(toggles, wifi, 0, 0, AdbHelper.ToggleWifi);
            AddToggle(toggles, bluetooth, 0, 1, AdbHelper.ToggleBluetooth);
            AddToggle(toggles, mobileData, 1, 0, AdbHelper.ToggleMobileData);
            AddToggle(toggles, airplane, 1, 1, AdbHelper.ToggleAirplaneMode);
            AddToggle(toggles, location, 2, 0, AdbHelper.ToggleLocation);
            AddToggle(toggles, doNotDisturb, 2, 1, AdbHelper.ToggleDoNotDisturb);
            AddToggle(toggles, autoRotate, 3, 0, AdbHelper.ToggleAutoRotate);
            AddToggle(toggles, adaptiveBrightness, 3, 1, AdbHelper.ToggleAdaptiveBrightness);
            AddToggle(toggles, darkMode, 4, 0, AdbHelper.ToggleDarkMode);
            AddToggle(toggles, clipboardSync, 4, 1, ClipboardSyncService.Toggle);
            quick.Children.Add(toggles);
            detailPanel.Children.Add(Card(quick));

            var volumePanel = new StackPanel { Spacing = 6 };
            volumePanel.Children.Add(SectionTitle("Media volume"));
            var volumeRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            volumeRow.Children.Add(volume);
            volumeRow.Children.Add(volumeValue);
            volumePanel.Children.Add(volumeRow);
            volume.ValueChanged += async (_, e) =>
            {
                volumeValue.Text = $"{(int)e.NewValue} / 15";
                if (!updatingToggles && selected is not null)
                {
                    string serial = selected.Serial;
                    int value = (int)e.NewValue;
                    try { await Task.Run(() => AdbHelper.SetVolume(serial, value)); }
                    catch { }
                }
            };
            detailPanel.Children.Add(Card(volumePanel));

            var control = new StackPanel { Spacing = 8 };
            control.Children.Add(SectionTitle("Device control"));
            var controlRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            controlRow.Children.Add(ActionButton("Reboot", async () => await ConfirmAndRunAsync("Reboot device?", "Reboot", () => AdbHelper.Reboot(RequireSerial()))));
            controlRow.Children.Add(ActionButton("Bootloader", async () => await ConfirmAndRunAsync("Reboot to bootloader?", "Reboot", () => AdbHelper.Reboot(RequireSerial(), "bootloader"))));
            controlRow.Children.Add(ActionButton("Recovery", async () => await ConfirmAndRunAsync("Reboot to recovery?", "Reboot", () => AdbHelper.Reboot(RequireSerial(), "recovery"))));
            controlRow.Children.Add(ActionButton("Power off", async () => await ConfirmAndRunAsync("Power off the device?", "Power off", () => AdbHelper.RunAdbCommand($"-s {RequireSerial()} shell reboot -p"))));
            controlRow.Children.Add(ActionButton("Disconnect", async () =>
            {
                if (selected is not null && await Ui.ConfirmAsync("Disconnect", $"Disconnect {selected.Name}?", "Disconnect"))
                {
                    await RunAsync("Could not disconnect", () => AdbHelper.Disconnect(selected.Serial));
                    await RefreshDevicesAsync();
                }
            }));
            control.Children.Add(controlRow);
            detailPanel.Children.Add(Card(control));

            var config = new StackPanel { Spacing = 8 };
            config.Children.Add(SectionTitle("Configuration"));
            FillCombo(appResolution, new[] { "360p", "540p", "720p", "900p", "1080p", "1440p", "1600p" });
            config.Children.Add(ComboRow("App resolution", appResolution, index =>
            {
                var mirrorConfig = Config();
                mirrorConfig.AppResolution = appResolutions[index];
                mirrorConfig.FlexDisplay = false;
                RefreshConfiguration();
            }));
            FillCombo(mirrorSize, new[] { "Original", "800", "1024", "1280", "1440", "1600", "1920" });
            config.Children.Add(ComboRow("Mirroring size", mirrorSize, index =>
            {
                var mirrorConfig = Config();
                mirrorConfig.MaxSize = mirrorSizes[index];
                mirrorConfig.FlexDisplay = false;
                RefreshConfiguration();
            }));
            FillCombo(frameRate, new[] { "Unlimited", "30 fps", "60 fps", "90 fps", "120 fps" });
            config.Children.Add(ComboRow("Frame rate", frameRate, index => Config().MaxFps = frameRates[index]));
            FillCombo(bitRate, new[] { "2 Mbps", "4 Mbps", "8 Mbps", "16 Mbps", "20 Mbps" });
            config.Children.Add(ComboRow("Bit rate", bitRate, index => Config().BitRate = bitRates[index]));
            FillCombo(orientation, new[] { "Auto", "Portrait", "90° left", "180°", "90° right" });
            config.Children.Add(ComboRow("Rotation", orientation, index => Config().Orientation = orientations[index]));
            flex.Toggled += (_, _) =>
            {
                if (!updatingToggles && selected is not null)
                    Config().FlexDisplay = flex.IsOn;
            };
            borderless.Toggled += (_, _) =>
            {
                if (!updatingToggles && selected is not null)
                    Config().Borderless = borderless.IsOn;
            };
            audio.Toggled += (_, _) =>
            {
                if (!updatingToggles && selected is not null)
                    Config().AudioEnabled = audio.IsOn;
            };
            clipboardConfig.Toggled += (_, _) =>
            {
                if (!updatingToggles && selected is not null)
                    Config().ClipboardEnabled = clipboardConfig.IsOn;
            };
            config.Children.Add(flex);
            config.Children.Add(borderless);
            config.Children.Add(audio);
            config.Children.Add(clipboardConfig);

            FillCombo(cameraFacing, new[] { "Auto", "Front", "Back", "External" });
            config.Children.Add(ComboRow("Camera facing", cameraFacing, index => Config().CameraFacing = cameraFacings[index]));
            FillCombo(cameraFps, new[] { "Default", "30 fps", "60 fps", "120 fps", "240 fps" });
            config.Children.Add(ComboRow("Camera frame rate", cameraFps, index => Config().CameraFps = cameraFrameRates[index]));
            FillCombo(cameraSize, new[] { "Original", "3840 (4K)", "2560 (2K)", "1920 (1080p)", "1280 (720p)", "1024", "800 (480p)", "640 (VGA)" });
            config.Children.Add(ComboRow("Camera size", cameraSize, index => Config().CameraSize = cameraSizes[index]));
            FillCombo(cameraAr, new[] { "Auto", "4:3", "16:9", "1:1", "Sensor" });
            config.Children.Add(ComboRow("Camera aspect ratio", cameraAr, index => Config().CameraAr = cameraAspectRatios[index]));
            detailPanel.Children.Add(Card(config));
            RefreshConfiguration();
            detailPanel.Visibility = Visibility.Collapsed;
        }

        private void AddToggle(Grid grid, ToggleSwitch toggle, int row, int column, Action<string, bool> action)
        {
            Grid.SetRow(toggle, row);
            Grid.SetColumn(toggle, column);
            grid.Children.Add(toggle);
            toggle.Toggled += async (_, _) =>
            {
                if (updatingToggles || selected is null)
                {
                    return;
                }
                string serial = selected.Serial;
                bool value = toggle.IsOn;

                try
                {
                    await Task.Run(() => action(serial, value));
                }
                catch (Exception ex)
                {
                    await Ui.ShowErrorAsync("Device setting", ex.Message);
                }
            };
        }

        private static ToggleSwitch Toggle(string header)
        {
            return new ToggleSwitch
            {
                Header = header,
                OnContent = "On",
                OffContent = "Off",
                Margin = new Thickness(0, 2, 0, 2)
            };
        }

        private static TextBlock SectionTitle(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 15,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            };
        }

        private static Border Card(UIElement content)
        {
            return new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14),
                Child = content
            };
        }

        private Button ActionButton(string text, Func<Task> action)
        {
            var button = new Button { Content = text };
            button.Click += async (_, _) => await action();
            return button;
        }

        private Button ActionButton(string text, Action action)
        {
            var button = new Button { Content = text };
            button.Click += (_, _) => action();
            return button;
        }

        private FrameworkElement ComboRow(string label, ComboBox combo, Action<int> changed)
        {
            var panel = new Grid { ColumnSpacing = 12 };
            panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
            panel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var text = new TextBlock
            {
                Text = label,
                VerticalAlignment = VerticalAlignment.Center,
                Opacity = 0.8
            };
            panel.Children.Add(text);
            Grid.SetColumn(combo, 1);
            panel.Children.Add(combo);
            combo.SelectionChanged += (_, _) =>
            {
                if (!updatingToggles && selected is not null && combo.SelectedIndex >= 0)
                {
                    changed(combo.SelectedIndex);
                }
            };
            return panel;
        }

        private static void FillCombo(ComboBox combo, string[] labels)
        {
            foreach (string label in labels)
            {
                combo.Items.Add(label);
            }
        }

        private void RefreshConfiguration()
        {
            var cfg = Config();
            updatingToggles = true;
            try
            {
                appResolution.SelectedIndex = Array.IndexOf(appResolutions, cfg.AppResolution);
                mirrorSize.SelectedIndex = Array.IndexOf(mirrorSizes, cfg.MaxSize);
                frameRate.SelectedIndex = Array.IndexOf(frameRates, cfg.MaxFps);
                bitRate.SelectedIndex = Array.IndexOf(bitRates, cfg.BitRate);
                orientation.SelectedIndex = Array.IndexOf(orientations, cfg.Orientation);
                cameraFacing.SelectedIndex = Array.IndexOf(cameraFacings, cfg.CameraFacing);
                cameraFps.SelectedIndex = Array.IndexOf(cameraFrameRates, cfg.CameraFps);
                cameraSize.SelectedIndex = Array.IndexOf(cameraSizes, cfg.CameraSize);
                cameraAr.SelectedIndex = Array.IndexOf(cameraAspectRatios, cfg.CameraAr);
                flex.IsOn = cfg.FlexDisplay;
                borderless.IsOn = cfg.Borderless;
                audio.IsOn = cfg.AudioEnabled;
                clipboardConfig.IsOn = cfg.ClipboardEnabled;
            }
            finally
            {
                updatingToggles = false;
            }
        }

        private async Task RefreshDevicesAsync()
        {
            statusBar.IsOpen = true;
            statusBar.Severity = InfoBarSeverity.Informational;
            statusBar.Title = "Refreshing devices";
            statusBar.Message = "Looking for adb devices…";
            try
            {
                List<AdbHelper.AdbDeviceInfo> devices = await Task.Run(AdbHelper.GetDevices);
                string? previous = AppState.SelectedSerial;
                deviceList.Items.Clear();
                foreach (AdbHelper.AdbDeviceInfo device in devices)
                {
                    deviceList.Items.Add(new ListViewItem
                    {
                        Tag = device,
                        Content = DeviceRow(device)
                    });
                }

                emptyText.Visibility = devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
                ListViewItem? match = deviceList.Items.Cast<ListViewItem>()
                    .FirstOrDefault(item => (item.Tag as AdbHelper.AdbDeviceInfo)?.Serial == previous)
                    ?? deviceList.Items.Cast<ListViewItem>().FirstOrDefault();
                if (match is not null)
                {
                    deviceList.SelectedItem = match;
                }
                else
                {
                    selected = null;
                    AppState.SelectedSerial = null;
                    await LoadSelectedAsync();
                }

                statusBar.Severity = devices.Count > 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
                statusBar.Title = devices.Count > 0 ? $"{devices.Count} device{(devices.Count == 1 ? "" : "s")} connected" : "No devices connected";
                statusBar.Message = devices.Count > 0 ? "Select a device to manage it." : "Enable USB debugging or use Wireless pairing.";
            }
            catch (Exception ex)
            {
                statusBar.Severity = InfoBarSeverity.Error;
                statusBar.Title = "Could not list devices";
                statusBar.Message = ex.Message;
            }
        }

        private static UIElement DeviceRow(AdbHelper.AdbDeviceInfo device)
        {
            var stack = new StackPanel { Spacing = 1, Padding = new Thickness(2) };
            stack.Children.Add(new TextBlock
            {
                Text = device.Name,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            stack.Children.Add(new TextBlock
            {
                Text = device.Status == "device" ? (device.IsWireless ? "Wireless" : "USB") : device.Status,
                Opacity = 0.6,
                FontSize = 12
            });
            return stack;
        }

        private async Task LoadSelectedAsync()
        {
            int version = ++selectionLoadVersion;
            var device = selected;
            detailPanel.Visibility = Visibility.Collapsed;
            RefreshConfiguration();
            if (device is null)
            {
                detailPanel.Visibility = Visibility.Collapsed;
                return;
            }

            // Keep the previous device's live settings hidden until this device is loaded.
            detailPanel.Visibility = Visibility.Collapsed;
            deviceTitle.Text = device.Name;
            deviceInfo.Text = device.Serial;
            string serial = device.Serial;
            try
            {
                var state = await Task.Run(() => AdbHelper.GetDeviceState(serial));
                var info = await Task.Run(() => AdbHelper.GetDeviceInfo(serial));
                if (version != selectionLoadVersion || selected?.Serial != serial)
                {
                    return;
                }

                deviceInfo.Text = $"{serial}\n{info.Summary}";
                updatingToggles = true;
                try
                {
                    wifi.IsOn = state.Wifi;
                    bluetooth.IsOn = state.Bluetooth;
                    mobileData.IsOn = state.MobileData;
                    airplane.IsOn = state.AirplaneMode;
                    location.IsOn = state.Location;
                    doNotDisturb.IsOn = state.DoNotDisturb;
                    autoRotate.IsOn = state.AutoRotate;
                    adaptiveBrightness.IsOn = state.AdaptiveBrightness;
                    darkMode.IsOn = state.DarkMode;
                    clipboardSync.IsOn = ClipboardSyncService.IsActive(serial);
                }
                finally
                {
                    updatingToggles = false;
                }

                detailPanel.Visibility = Visibility.Visible;
            }
            catch (Exception ex)
            {
                if (version == selectionLoadVersion && selected?.Serial == serial)
                {
                    await Ui.ShowErrorAsync("Device", ex.Message);
                }
            }
        }

        private string RequireSerial()
        {
            return selected?.Serial ?? throw new InvalidOperationException("No device selected.");
        }

        private AdbHelper.MirrorConfig Config() => selected is not null ? AdbHelper.GetConfig(selected.Serial) : fallbackConfig;

        private async Task RunAsync(string title, Action action)
        {
            try
            {
                await Task.Run(action);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync(title, ex.Message);
            }
        }

        private async Task ConfirmAndRunAsync(string message, string primary, Action action)
        {
            if (await Ui.ConfirmAsync("Confirm", message, primary))
            {
                await RunAsync(primary, action);
            }
        }
    }
}
