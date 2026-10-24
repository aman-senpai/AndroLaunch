using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Dialogs;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml.Automation;
using System.Text.RegularExpressions;
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
            Text = "Connect an Android device with a data-capable USB cable, unlock it, and enable Developer options → USB debugging. Accept the RSA permission prompt on the device. For Wi-Fi, use Wireless pairing on the same network.",
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
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap
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
        private readonly ToggleSwitch clipboardSync = Toggle("Background clipboard bridge");
        private readonly Slider volume = new()
        {
            Minimum = 0,
            Maximum = 15,
            StepFrequency = 1,
            Value = 7,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        private readonly TextBlock volumeValue = new() { Text = "Not loaded", Opacity = 0.7, TextWrapping = TextWrapping.Wrap };

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
        private readonly ToggleSwitch clipboardConfig = Toggle("Forward clipboard during a scrcpy session");

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
        private bool refreshing;
        private bool replacingDevices;
        private bool settingPending;
        private string? rememberedSerial = AppState.SelectedSerial;
        private string currentPreset = "Balanced";
        private readonly ComboBox preset = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
        private readonly TextBlock presetDescription = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.75 };
        private readonly TextBlock clipboardStatus = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.75 };
        private readonly TextBlock settingsStatus = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.75 };
        private readonly InfoBar connectionBar = new() { IsClosable = false };
        private readonly StackPanel quickSettings = new() { Spacing = 10 };
        private readonly Grid quickToggles = new() { ColumnSpacing = 12, RowSpacing = 2 };
        private readonly ContentControl quickSettingsHost = new()
        {
            IsEnabled = false,
            HorizontalContentAlignment = HorizontalAlignment.Stretch
        };
        private readonly ContentControl quickTogglesHost = new()
        {
            IsEnabled = false,
            HorizontalContentAlignment = HorizontalAlignment.Stretch
        };
        private readonly List<Button> deviceActions = new();
        private Button? cameraButton;
        private Button? refreshButton;
        private int confirmedVolume;
        private bool volumeAvailable;

        public DevicesPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) => await RefreshDevicesAsync();
        }

        private UIElement BuildContent()
        {
            var root = new Grid { Padding = new Thickness(24), RowSpacing = 14 };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var header = new StackPanel { Spacing = 8 };
            header.Children.Add(new TextBlock
            {
                Text = "Devices", FontSize = 30, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            header.Children.Add(new TextBlock
            {
                Text = "Mirror, manage and control connected Android devices.",
                Opacity = 0.7, TextWrapping = TextWrapping.Wrap
            });
            refreshButton = new Button { Content = "Refresh devices" };
            refreshButton.Click += async (_, _) => await RefreshDevicesAsync();
            var pairing = new Button { Content = "Wireless pairing" };
            pairing.Click += async (_, _) =>
            {
                await PairingDialog.ShowAsync();
                await RefreshDevicesAsync();
            };
            header.Children.Add(ActionGrid(refreshButton, pairing));
            root.Children.Add(header);
            Grid.SetRow(statusBar, 1);
            root.Children.Add(statusBar);

            var content = new Grid { ColumnSpacing = 18, RowSpacing = 12 };
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            var left = new StackPanel { Spacing = 8 };
            AutomationProperties.SetName(deviceList, "Connected Android devices");
            deviceList.SelectionChanged += async (_, _) =>
            {
                if (replacingDevices || deviceList.SelectedItem is not ListViewItem item) return;
                selected = item.Tag as AdbHelper.AdbDeviceInfo;
                rememberedSerial = selected?.Serial;
                AppState.SelectedSerial = rememberedSerial;
                await LoadSelectedAsync();
            };
            left.Children.Add(new Border
            {
                Visibility = Visibility.Collapsed,
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8), Child = deviceList
            });
            left.Children.Add(emptyText);
            content.Children.Add(left);
            var scroll = new ScrollViewer
            {
                Content = detailPanel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            content.Children.Add(scroll);
            content.SizeChanged += (_, e) =>
            {
                bool narrow = e.NewSize.Width < 850;
                content.ColumnDefinitions[0].Width = narrow ? new GridLength(1, GridUnitType.Star) : new GridLength(280);
                content.ColumnDefinitions[1].Width = narrow ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
                Grid.SetColumn(scroll, narrow ? 0 : 1);
                Grid.SetRow(scroll, narrow ? 1 : 0);
                Grid.SetRowSpan(scroll, narrow ? 1 : 2);
                Grid.SetRowSpan(left, narrow ? 1 : 2);
                deviceList.MaxHeight = narrow ? 150 : double.PositiveInfinity;
            };
            Grid.SetRow(content, 2);
            root.Children.Add(content);
            BuildDetails();
            return root;
        }

        private void BuildDetails()
        {
            detailPanel.Children.Add(deviceTitle);
            detailPanel.Children.Add(deviceInfo);
            detailPanel.Children.Add(connectionBar);

            var mirror = ActionButton("Mirror device", () => StartMirrorAsync(false));
            mirror.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
            cameraButton = ActionButton("Camera", () => StartMirrorAsync(true));
            detailPanel.Children.Add(ActionGrid(mirror,
                ActionButton("Files", () => App.ShowMainWindow("files", RequireSerial())),
                ActionButton("Apps", () => App.ShowMainWindow("apps", RequireSerial())),
                ActionButton("Capture", () => CaptureDialog.ShowAsync(RequireSerial()))));

            var presets = new StackPanel { Spacing = 8 };
            presets.Children.Add(SectionTitle("Mirror preset"));
            FillCombo(preset, MirrorPresetStore.Names);
            AutomationProperties.SetName(preset, "Mirror quality preset for this device");
            presets.Children.Add(preset);
            presets.Children.Add(presetDescription);
            preset.SelectionChanged += async (_, _) =>
            {
                if (updatingToggles || selected is null || preset.SelectedIndex < 0) return;
                currentPreset = MirrorPresetStore.Names[preset.SelectedIndex];
                MirrorPresetStore.Apply(currentPreset, Config());
                RefreshConfiguration();
                await SaveConfigurationAsync();
            };
            detailPanel.Children.Add(Card(presets));

            quickSettings.Children.Add(settingsStatus);
            var toggles = quickToggles;
            toggles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            toggles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int i = 0; i < 9; i++) toggles.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            AddToggle(toggles, wifi, 0, 0, AdbHelper.ToggleWifi, s => s.Wifi);
            AddToggle(toggles, bluetooth, 0, 1, AdbHelper.ToggleBluetooth, s => s.Bluetooth);
            AddToggle(toggles, mobileData, 1, 0, AdbHelper.ToggleMobileData, s => s.MobileData);
            AddToggle(toggles, airplane, 1, 1, AdbHelper.ToggleAirplaneMode, s => s.AirplaneMode);
            AddToggle(toggles, location, 2, 0, AdbHelper.ToggleLocation, s => s.Location);
            AddToggle(toggles, doNotDisturb, 2, 1, AdbHelper.ToggleDoNotDisturb, s => s.DoNotDisturb);
            AddToggle(toggles, autoRotate, 3, 0, AdbHelper.ToggleAutoRotate, s => s.AutoRotate);
            AddToggle(toggles, adaptiveBrightness, 3, 1, AdbHelper.ToggleAdaptiveBrightness, s => s.AdaptiveBrightness);
            AddToggle(toggles, darkMode, 4, 0, AdbHelper.ToggleDarkMode, s => s.DarkMode);
            toggles.SizeChanged += (_, e) =>
            {
                bool narrow = e.NewSize.Width < 420;
                for (int i = 0; i < toggles.Children.Count; i++)
                {
                    if (toggles.Children[i] is FrameworkElement toggle)
                    {
                        Grid.SetRow(toggle, narrow ? i : i / 2);
                        Grid.SetColumn(toggle, narrow ? 0 : i % 2);
                    }
                }
                toggles.ColumnDefinitions[1].Width = narrow ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
            };
            quickTogglesHost.Content = toggles;
            quickSettings.Children.Add(quickTogglesHost);
            quickSettings.Children.Add(SectionTitle("Media volume"));
            AutomationProperties.SetName(volume, "Device media volume");
            quickSettings.Children.Add(volume);
            quickSettings.Children.Add(volumeValue);
            volume.ValueChanged += async (_, e) =>
            {
                if (updatingToggles) return;
                volumeValue.Text = $"{(int)e.NewValue} / {(int)volume.Maximum}";
                if (selected is null || settingPending || !volumeAvailable) return;
                string serial = RequireSerial();
                int previous = confirmedVolume;
                int requested = (int)e.NewValue;
                settingPending = true;
                quickSettingsHost.IsEnabled = false;
                deviceList.IsEnabled = false;
                try
                {
                    var actual = await Task.Run(() => SetVolumeChecked(serial, requested));
                    ApplyVolume(actual);
                    if (actual.Value != requested)
                        await Ui.ShowErrorAsync("Android limited the volume",
                            $"{serial}\nRequested {requested}; the device reports {actual.Value}. The slider shows the actual device value. Check Android's media-volume limits or use the device volume buttons.");
                }
                catch (Exception ex)
                {
                    updatingToggles = true;
                    volume.Value = previous;
                    volumeValue.Text = $"{previous} / {(int)volume.Maximum} — change not confirmed";
                    updatingToggles = false;
                    await Ui.ShowErrorAsync("Media volume was not confirmed",
                        $"{serial}\n{ex.Message}\nUse the device's volume buttons, or reconnect and Refresh devices to read the current volume.");
                }
                finally
                {
                    settingPending = false;
                    quickSettingsHost.IsEnabled = selected?.Status == "device";
                    deviceList.IsEnabled = true;
                }
            };
            quickSettingsHost.Content = quickSettings;
            detailPanel.Children.Add(new Expander
            {
                Header = "Quick device settings", Content = quickSettingsHost,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
            });

            var clipboard = new StackPanel { Spacing = 8 };
            clipboard.Children.Add(clipboardSync);
            clipboard.Children.Add(clipboardStatus);
            clipboard.Children.Add(new TextBlock
            {
                Text = "Separate from clipboard forwarding in an open Mirror session. Background PC → Android delivery requires the ADB Clipboard companion (ch.pete.adbclipboard) installed and allowed on the device. Android → PC depends on scrcpy clipboard support and Android policy; delivery is not guaranteed.",
                TextWrapping = TextWrapping.Wrap, Opacity = 0.75
            });
            clipboardSync.OnContent = "Enabled — pause to stop";
            clipboardSync.OffContent = "Paused";
            clipboardSync.Toggled += async (_, _) => await ToggleClipboardAsync();
            detailPanel.Children.Add(new Expander
            {
                Header = "Background clipboard bridge", Content = clipboard,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
            });

            var config = new StackPanel { Spacing = 8 };
            FillCombo(appResolution, new[] { "360p", "540p", "720p", "900p", "1080p", "1440p", "1600p" });
            config.Children.Add(ComboRow("App resolution", appResolution, index =>
            {
                Config().AppResolution = appResolutions[index];
                Config().FlexDisplay = false;
            }));
            FillCombo(mirrorSize, new[] { "Original", "800", "1024", "1280", "1440", "1600", "1920" });
            config.Children.Add(ComboRow("Mirror size", mirrorSize, index =>
            {
                Config().MaxSize = mirrorSizes[index];
                Config().FlexDisplay = false;
            }));
            FillCombo(frameRate, new[] { "Unlimited", "30 fps", "60 fps", "90 fps", "120 fps" });
            config.Children.Add(ComboRow("Frame rate", frameRate, index => Config().MaxFps = frameRates[index]));
            FillCombo(bitRate, new[] { "2 Mbps", "4 Mbps", "8 Mbps", "16 Mbps", "20 Mbps" });
            config.Children.Add(ComboRow("Bit rate", bitRate, index => Config().BitRate = bitRates[index]));
            FillCombo(orientation, new[] { "Auto", "Portrait", "90° left", "180°", "90° right" });
            config.Children.Add(ComboRow("Rotation", orientation, index => Config().Orientation = orientations[index]));
            BindConfigurationToggle(flex, value => Config().FlexDisplay = value);
            BindConfigurationToggle(borderless, value => Config().Borderless = value);
            BindConfigurationToggle(audio, value => Config().AudioEnabled = value);
            BindConfigurationToggle(clipboardConfig, value => Config().ClipboardEnabled = value);
            config.Children.Add(flex);
            config.Children.Add(borderless);
            config.Children.Add(audio);
            config.Children.Add(clipboardConfig);
            config.Children.Add(new TextBlock
            {
                Text = "Session forwarding applies only while scrcpy is running. It does not enable the separate background bridge.",
                TextWrapping = TextWrapping.Wrap, Opacity = 0.75
            });
            detailPanel.Children.Add(new Expander
            {
                Header = "Advanced mirror settings", Content = config,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
            });

            var camera = new StackPanel { Spacing = 8 };
            camera.Children.Add(cameraButton);
            camera.Children.Add(new TextBlock
            {
                Text = "Requires Android 12 or newer and scrcpy 4.0 or newer. Available sizes and frame rates depend on the camera.",
                TextWrapping = TextWrapping.Wrap, Opacity = 0.75
            });
            FillCombo(cameraFacing, new[] { "Auto", "Front", "Back", "External" });
            camera.Children.Add(ComboRow("Camera facing", cameraFacing, index => Config().CameraFacing = cameraFacings[index]));
            FillCombo(cameraFps, new[] { "Default", "30 fps", "60 fps", "120 fps", "240 fps" });
            camera.Children.Add(ComboRow("Camera frame rate", cameraFps, index => Config().CameraFps = cameraFrameRates[index]));
            FillCombo(cameraSize, new[] { "Original", "3840 (4K)", "2560 (2K)", "1920 (1080p)", "1280 (720p)", "1024", "800 (480p)", "640 (VGA)" });
            camera.Children.Add(ComboRow("Camera size", cameraSize, index => Config().CameraSize = cameraSizes[index]));
            FillCombo(cameraAr, new[] { "Auto", "4:3", "16:9", "1:1", "Sensor" });
            camera.Children.Add(ComboRow("Aspect ratio", cameraAr, index => Config().CameraAr = cameraAspectRatios[index]));
            detailPanel.Children.Add(new Expander
            {
                Header = "Camera and advanced camera settings", Content = camera,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
            });

            var developer = new StackPanel { Spacing = 8 };
            developer.Children.Add(new TextBlock
            {
                Text = "These actions can interrupt work on the selected device. Save device work first.",
                TextWrapping = TextWrapping.Wrap, Opacity = 0.75
            });
            developer.Children.Add(ActionGrid(
                ActionButton("Shell", () => RunAsync("Could not open shell", () => AdbHelper.OpenShell(RequireSerial()))),
                ActionButton("Logcat", () => RunAsync("Could not open logcat", () => AdbHelper.OpenLogcat(RequireSerial()))),
                ActionButton("Reboot", () => ConfirmDeviceActionAsync("Reboot", "Restart Android? Open device work may be lost.", serial => AdbHelper.Reboot(serial))),
                ActionButton("Bootloader", () => ConfirmDeviceActionAsync("Bootloader", "Restart into the bootloader? Android apps will stop.", serial => AdbHelper.Reboot(serial, "bootloader"))),
                ActionButton("Recovery", () => ConfirmDeviceActionAsync("Recovery", "Restart into recovery? Android apps will stop.", serial => AdbHelper.Reboot(serial, "recovery"))),
                ActionButton("Power off", () => ConfirmDeviceActionAsync("Power off", "Turn off this device? You will need to turn it back on physically.", serial => AdbHelper.RunAdbCommand($"-s {Quote(serial)} shell reboot -p"))),
                ActionButton("Disconnect Wi-Fi", async () =>
                {
                    string serial = RequireSerial();
                    if (selected?.IsWireless != true)
                    {
                        await Ui.ShowErrorAsync("USB device", "To disconnect this USB device, unplug its cable. No ADB disconnect command was sent.");
                        return;
                    }
                    await ConfirmDeviceActionAsync("Disconnect", "End this wireless connection? Reconnect with Wireless pairing.", target => AdbHelper.Disconnect(target));
                })));
            detailPanel.Children.Add(new Expander
            {
                Header = "Developer and power actions", Content = developer,
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
            });
            RefreshConfiguration();
            detailPanel.Visibility = Visibility.Collapsed;
        }

        private void AddToggle(Grid grid, ToggleSwitch toggle, int row, int column,
            Action<string, bool> action, Func<AdbHelper.DeviceState, bool> read)
        {
            Grid.SetRow(toggle, row);
            Grid.SetColumn(toggle, column);
            grid.Children.Add(toggle);
            toggle.Toggled += async (_, _) =>
            {
                if (updatingToggles || selected is null || settingPending) return;
                string serial = RequireSerial();
                bool requested = toggle.IsOn;
                bool previous = !requested;
                settingPending = true;
                quickSettingsHost.IsEnabled = false;
                deviceList.IsEnabled = false;
                settingsStatus.Text = $"Applying {toggle.Header}…";
                try
                {
                    var state = await Task.Run(() =>
                    {
                        action(serial, requested);
                        return ReadDeviceStateChecked(serial);
                    });
                    ApplyState(state);
                    if (read(state) != requested)
                        throw new InvalidOperationException("Android did not apply the requested value. The current device value has been restored.");
                    settingsStatus.Text = "Settings read back from the device. Some Android versions restrict these controls.";
                }
                catch (Exception ex)
                {
                    updatingToggles = true;
                    toggle.IsOn = previous;
                    updatingToggles = false;
                    settingsStatus.Text = "Change not confirmed. Refresh devices to reload settings, or use Android Settings.";
                    await Ui.ShowErrorAsync($"{toggle.Header} was not confirmed",
                        $"{serial}\n{ex.Message}\nIf the connection dropped, reconnect and Refresh devices. Otherwise change this setting directly on Android.");
                }
                finally
                {
                    settingPending = false;
                    quickSettingsHost.IsEnabled = selected?.Status == "device";
                    deviceList.IsEnabled = true;
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
            var button = new Button { Content = text, HorizontalAlignment = HorizontalAlignment.Stretch };
            AutomationProperties.SetName(button, text);
            deviceActions.Add(button);
            button.Click += async (_, _) =>
            {
                button.IsEnabled = false;
                deviceList.IsEnabled = false;
                try
                {
                    RequireSerial();
                    await action();
                }
                catch (Exception ex)
                {
                    await Ui.ShowErrorAsync(text, $"{selected?.Serial}\n{ex.Message}\nReconnect and Refresh devices if the device is no longer available.");
                }
                finally
                {
                    button.IsEnabled = selected?.Status == "device";
                    deviceList.IsEnabled = true;
                }
            };
            return button;
        }

        private Button ActionButton(string text, Action action) => ActionButton(text, () =>
        {
            action();
            return Task.CompletedTask;
        });

        private FrameworkElement ComboRow(string label, ComboBox combo, Action<int> changed)
        {
            var panel = new StackPanel { Spacing = 4 };
            panel.Children.Add(new TextBlock { Text = label, Opacity = 0.8, TextWrapping = TextWrapping.Wrap });
            combo.MinWidth = 0;
            combo.HorizontalAlignment = HorizontalAlignment.Stretch;
            AutomationProperties.SetName(combo, label);
            panel.Children.Add(combo);
            combo.SelectionChanged += async (_, _) =>
            {
                if (updatingToggles || selected is null || combo.SelectedIndex < 0) return;
                changed(combo.SelectedIndex);
                currentPreset = "Custom";
                RefreshConfiguration();
                await SaveConfigurationAsync();
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
                preset.SelectedIndex = Array.IndexOf(MirrorPresetStore.Names, currentPreset);
                presetDescription.Text = MirrorPresetStore.Descriptions[Math.Max(0, preset.SelectedIndex)];
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
            if (refreshing || settingPending) return;
            refreshing = true;
            if (refreshButton is not null) refreshButton.IsEnabled = false;
            deviceList.IsEnabled = false;
            SetActionsEnabled(false);
            statusBar.IsOpen = true;
            statusBar.Severity = InfoBarSeverity.Informational;
            statusBar.Title = "Refreshing devices";
            statusBar.Message = "Looking for adb devices…";
            try
            {
                var devices = await Task.Run(AdbHelper.GetDevices);
                replacingDevices = true;
                try
                {
                    deviceList.Items.Clear();
                    foreach (var device in devices)
                    {
                        var item = new ListViewItem { Tag = device, Content = DeviceRow(device) };
                        AutomationProperties.SetName(item, $"{device.Name}, {device.Serial}, {device.Status}");
                        deviceList.Items.Add(item);
                    }
                    var match = deviceList.Items.Cast<ListViewItem>().FirstOrDefault(
                        item => (item.Tag as AdbHelper.AdbDeviceInfo)?.Serial == rememberedSerial);
                    if (rememberedSerial is null)
                        match = deviceList.Items.Cast<ListViewItem>().FirstOrDefault();
                    deviceList.SelectedItem = match;
                    selected = match?.Tag as AdbHelper.AdbDeviceInfo;
                    if (selected is not null)
                    {
                        rememberedSerial = selected.Serial;
                        AppState.SelectedSerial = rememberedSerial;
                    }
                }
                finally { replacingDevices = false; }

                emptyText.Visibility = devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
                bool ready = devices.Any(device => device.Status == "device");
                statusBar.Severity = ready ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
                statusBar.Title = devices.Count == 0 ? "No devices connected" : $"{devices.Count} device{(devices.Count == 1 ? "" : "s")} found";
                statusBar.Message = selected is null && rememberedSerial is not null
                    ? $"Waiting for {rememberedSerial}. Its selection is remembered. Reconnect it and Refresh devices, or explicitly select another device."
                    : ready ? "Select a device to manage it. Refresh reloads its connection and settings."
                    : "Unlock the device and accept USB debugging. For offline devices, reconnect the cable or pair again on Wi-Fi, then Refresh devices.";
                await LoadSelectedAsync();
            }
            catch (Exception ex)
            {
                statusBar.Severity = InfoBarSeverity.Error;
                statusBar.Title = "Could not list devices";
                statusBar.Message = $"{ex.Message}\nCheck ADB in Setup, reconnect the device, then Refresh devices. Your selected device has not been forgotten.";
            }
            finally
            {
                if (deviceList.Parent is Border deviceCard)
                    deviceCard.Visibility = deviceList.Items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
                refreshing = false;
                deviceList.IsEnabled = true;
                if (refreshButton is not null) refreshButton.IsEnabled = true;
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
                Text = $"{device.Serial}\n{(device.Status == "device" ? (device.IsWireless ? "Wireless · ready" : "USB · ready") : device.Status)}",
                Opacity = 0.6,
                FontSize = 12
            });
            return stack;
        }

        private async Task LoadSelectedAsync()
        {
            int version = ++selectionLoadVersion;
            var device = selected;
            SetActionsEnabled(false);
            quickSettingsHost.IsEnabled = false;
            quickTogglesHost.IsEnabled = false;
            volumeAvailable = false;
            volume.IsEnabled = false;
            if (device is null)
            {
                detailPanel.Visibility = Visibility.Collapsed;
                return;
            }
            string serial = device.Serial;
            deviceTitle.Text = device.Name;
            deviceInfo.Text = $"{serial} · {(device.IsWireless ? "Wireless" : "USB")} · {device.Status}";
            detailPanel.Visibility = Visibility.Visible;
            try
            {
                currentPreset = MirrorPresetStore.Load(serial, Config());
                RefreshConfiguration();
            }
            catch (Exception ex)
            {
                currentPreset = "Custom";
                RefreshConfiguration();
                statusBar.IsOpen = true;
                statusBar.Severity = InfoBarSeverity.Warning;
                statusBar.Title = "Could not load mirror preferences";
                statusBar.Message = $"{ex.Message} Current settings remain available; check access to {AppSettingsStore.SettingsDirectory}.";
            }
            UpdateClipboardStatus();
            connectionBar.IsOpen = device.Status != "device";
            connectionBar.Severity = InfoBarSeverity.Warning;
            connectionBar.Title = device.Status == "unauthorized" ? "Authorize this computer on Android" : "Device is not ready";
            connectionBar.Message = device.Status == "unauthorized"
                ? "Unlock this device and accept the RSA fingerprint prompt for USB debugging. If no prompt appears, reconnect USB; you can revoke USB debugging authorizations in Android Developer options and authorize again."
                : $"ADB reports “{device.Status}”. Reconnect the USB data cable, or use Wireless pairing again on the same network. No device actions will run until it is ready.";
            var reconnect = new Button { Content = "Reconnect and refresh" };
            reconnect.Click += async (_, _) =>
            {
                reconnect.IsEnabled = false;
                try { await Task.Run(() => AdbHelper.RunAdbCommand($"-s {Quote(serial)} reconnect")); }
                catch (Exception ex)
                {
                    connectionBar.Message = $"{ex.Message}\nReconnect physically or pair again, then Refresh devices.";
                }
                finally
                {
                    await RefreshDevicesAsync();
                    reconnect.IsEnabled = true;
                }
            };
            connectionBar.ActionButton = reconnect;
            if (device.Status != "device")
            {
                clipboardSync.IsEnabled = ClipboardSyncService.IsActive(serial);
                return;
            }
            SetActionsEnabled(true);
            if (cameraButton is not null) cameraButton.IsEnabled = false;
            clipboardSync.IsEnabled = true;
            quickSettingsHost.IsEnabled = true;
            settingsStatus.Text = "Reading settings from the device…";
            volumeValue.Text = "Reading media volume…";
            var info = await Task.Run(() => AdbHelper.GetDeviceInfo(serial));
            if (version != selectionLoadVersion || selected?.Serial != serial) return;
            deviceInfo.Text = $"{serial} · {(device.IsWireless ? "Wireless" : "USB")} · ready\n{info.Summary}";
            if (cameraButton is not null)
            {
                cameraButton.IsEnabled = info.ApiLevel >= 31;
                ToolTipService.SetToolTip(cameraButton, info.ApiLevel >= 31
                    ? "Open the device camera through scrcpy." : "Camera mirroring requires Android 12 (API 31) or newer.");
            }
            try
            {
                var state = await Task.Run(() => ReadDeviceStateChecked(serial));
                if (version != selectionLoadVersion || selected?.Serial != serial) return;
                ApplyState(state);
                quickTogglesHost.IsEnabled = true;
                settingsStatus.Text = "Settings read from the device. Android may restrict changes; each change is checked.";
            }
            catch (Exception ex)
            {
                if (version != selectionLoadVersion || selected?.Serial != serial) return;
                settingsStatus.Text = $"Quick settings unavailable: {ex.Message}\nUse Android Settings, or reconnect and Refresh devices to retry.";
            }
            try
            {
                var actual = await Task.Run(() => ReadVolumeChecked(serial));
                if (version != selectionLoadVersion || selected?.Serial != serial) return;
                ApplyVolume(actual);
                volumeAvailable = true;
                volume.IsEnabled = true;
            }
            catch (Exception ex)
            {
                if (version != selectionLoadVersion || selected?.Serial != serial) return;
                volumeValue.Text = $"Media volume unavailable: {ex.Message}\nUse device volume buttons. Refresh devices retries the read.";
            }
        }

        private string RequireSerial()
        {
            if (selected is null) throw new InvalidOperationException("Select a connected device first.");
            if (selected.Status != "device")
                throw new InvalidOperationException($"Device {selected.Serial} is {selected.Status}. Unlock and authorize it, or reconnect and Refresh devices.");
            return selected.Serial;
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

        private async Task ConfirmDeviceActionAsync(string title, string warning, Action<string> action)
        {
            string serial = RequireSerial();
            string name = selected!.Name;
            if (await Ui.ConfirmAsync($"{title} — {name}", $"{name}\nDevice: {serial}\n\n{warning}", title))
            {
                await RunAsync($"Could not {title.ToLowerInvariant()} {name} ({serial})", () => action(serial));
                await RefreshDevicesAsync();
            }
        }

        private static Grid ActionGrid(params Button[] buttons)
        {
            var grid = new Grid { ColumnSpacing = 8, RowSpacing = 8 };
            for (int i = 0; i < 4; i++) grid.ColumnDefinitions.Add(new ColumnDefinition());
            for (int i = 0; i < buttons.Length; i++)
            {
                grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                buttons[i].HorizontalAlignment = HorizontalAlignment.Stretch;
                grid.Children.Add(buttons[i]);
            }
            void Arrange(double width)
            {
                int columns = Math.Max(1, Math.Min(4, (int)(width / 140)));
                for (int i = 0; i < 4; i++)
                    grid.ColumnDefinitions[i].Width = i < columns ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
                for (int i = 0; i < buttons.Length; i++)
                {
                    Grid.SetRow(buttons[i], i / columns);
                    Grid.SetColumn(buttons[i], i % columns);
                }
            }
            grid.SizeChanged += (_, e) => Arrange(e.NewSize.Width);
            Arrange(280);
            return grid;
        }

        private void BindConfigurationToggle(ToggleSwitch toggle, Action<bool> changed)
        {
            toggle.Toggled += async (_, _) =>
            {
                if (updatingToggles || selected is null) return;
                changed(toggle.IsOn);
                currentPreset = "Custom";
                RefreshConfiguration();
                await SaveConfigurationAsync();
            };
        }

        private async Task SaveConfigurationAsync()
        {
            if (selected is null) return;
            try { MirrorPresetStore.Save(selected.Serial, currentPreset, Config()); }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Mirror preferences were not saved",
                    $"{selected.Serial}\n{ex.Message}\nThe settings work for this session. Check access to {AppSettingsStore.SettingsDirectory} and select the preset again to retry saving.");
            }
        }

        private async Task StartMirrorAsync(bool camera)
        {
            string serial = RequireSerial();
            var compatibility = await ToolCompatibility.CheckScrcpyAsync();
            if (!compatibility.IsCompatible)
            {
                await Ui.ShowErrorAsync("scrcpy needs attention", $"{compatibility.Summary}\nOpen Setup to install a supported version, then try again.");
                return;
            }
            await RunAsync(camera ? "Could not open camera" : "Could not mirror", () =>
            {
                if (camera) AdbHelper.MirrorCamera(serial);
                else AdbHelper.MirrorScreen(serial);
            });
        }

        private void SetActionsEnabled(bool enabled)
        {
            foreach (var button in deviceActions) button.IsEnabled = enabled;
            clipboardSync.IsEnabled = enabled;
        }

        private void UpdateClipboardStatus()
        {
            updatingToggles = true;
            bool enabled = selected is not null && ClipboardSyncService.IsActive(selected.Serial);
            clipboardSync.IsOn = enabled;
            clipboardStatus.Text = enabled
                ? "Background bridge enabled (requested). Delivery and helper-process health are not verified. Pause stops this device's background bridge."
                : "Paused. No background clipboard bridge is requested for this device.";
            updatingToggles = false;
        }

        private async Task ToggleClipboardAsync()
        {
            if (updatingToggles || selected is null) return;
            if (settingPending)
            {
                UpdateClipboardStatus();
                return;
            }
            string serial = selected.Serial;
            bool enable = clipboardSync.IsOn;
            settingPending = true;
            quickSettingsHost.IsEnabled = false;
            clipboardSync.IsEnabled = false;
            deviceList.IsEnabled = false;
            clipboardStatus.Text = enable ? "Checking scrcpy and the Android companion…" : "Pausing the background bridge…";
            try
            {
                if (enable)
                {
                    RequireSerial();
                    var compatibility = await ToolCompatibility.CheckScrcpyAsync();
                    if (!compatibility.IsCompatible) throw new InvalidOperationException(compatibility.Summary);
                    string companion = await Task.Run(() => AdbHelper.RunAdbCommand($"-s {Quote(serial)} shell pm path ch.pete.adbclipboard"));
                    if (!companion.Contains("package:", StringComparison.Ordinal))
                        throw new InvalidOperationException("Install and allow the ADB Clipboard companion (ch.pete.adbclipboard) on this device before enabling PC → Android background delivery. Session forwarding in Mirror does not need this companion.");
                }
                await Task.Run(() => ClipboardSyncService.Toggle(serial, enable));
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Background clipboard bridge", $"{serial}\n{ex.Message}\nThe separate Mirror-session clipboard setting is unchanged.");
            }
            finally
            {
                settingPending = false;
                quickSettingsHost.IsEnabled = selected?.Status == "device";
                UpdateClipboardStatus();
                clipboardSync.IsEnabled = selected?.Status == "device" || ClipboardSyncService.IsActive(serial);
                deviceList.IsEnabled = true;
            }
        }

        private void ApplyState(AdbHelper.DeviceState state)
        {
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
            }
            finally { updatingToggles = false; }
        }

        private static AdbHelper.DeviceState ReadDeviceStateChecked(string serial)
        {
            string command = "shell \"settings get global wifi_on; settings get global bluetooth_on; " +
                "settings get global mobile_data; cmd uimode night; settings get global airplane_mode_on; " +
                "settings get secure location_mode; settings get global zen_mode; " +
                "settings get system accelerometer_rotation; settings get system screen_brightness_mode\"";
            string[] lines = AdbHelper.RunAdbCommand($"-s {Quote(serial)} {command}")
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length != 9) throw new InvalidOperationException("Android did not return all requested settings.");
            int Number(int index)
            {
                if (!int.TryParse(lines[index].Trim(), out int value))
                    throw new InvalidOperationException("This Android version does not expose all quick settings over ADB.");
                return value;
            }
            Match night = Regex.Match(lines[3], @"\b(yes|no|auto)\b", RegexOptions.IgnoreCase);
            if (!night.Success) throw new InvalidOperationException("Android did not report its dark-mode setting.");
            return new AdbHelper.DeviceState
            {
                Wifi = Number(0) == 1, Bluetooth = Number(1) == 1, MobileData = Number(2) == 1,
                DarkMode = night.Groups[1].Value.Equals("yes", StringComparison.OrdinalIgnoreCase),
                AirplaneMode = Number(4) == 1, Location = Number(5) > 0,
                DoNotDisturb = Number(6) > 0, AutoRotate = Number(7) == 1, AdaptiveBrightness = Number(8) == 1
            };
        }

        private static (int Value, int Minimum, int Maximum) ReadVolumeChecked(string serial)
        {
            try { return Read("cmd media_session"); }
            catch { return Read("media"); }

            (int Value, int Minimum, int Maximum) Read(string command)
            {
                string output = AdbHelper.RunAdbCommand($"-s {Quote(serial)} shell {command} volume --stream 3 --get");
                Match match = Regex.Match(output, @"volume is\s+(\d+)\s+in range\s+\[(\d+)\.\.(\d+)\]", RegexOptions.IgnoreCase);
                if (!match.Success) throw new InvalidOperationException("Android did not return a readable media-volume value and range.");
                int value = int.Parse(match.Groups[1].Value);
                int minimum = int.Parse(match.Groups[2].Value);
                int maximum = int.Parse(match.Groups[3].Value);
                if (maximum <= minimum || value < minimum || value > maximum)
                    throw new InvalidOperationException("Android returned an invalid media-volume range.");
                return (value, minimum, maximum);
            }
        }

        private static (int Value, int Minimum, int Maximum) SetVolumeChecked(string serial, int value)
        {
            try
            {
                AdbHelper.RunAdbCommand($"-s {Quote(serial)} shell cmd media_session volume --stream 3 --set {value}");
            }
            catch
            {
                AdbHelper.RunAdbCommand($"-s {Quote(serial)} shell media volume --stream 3 --set {value}");
            }
            var actual = ReadVolumeChecked(serial);
            return actual;
        }

        private void ApplyVolume((int Value, int Minimum, int Maximum) actual)
        {
            updatingToggles = true;
            try
            {
                volume.Minimum = actual.Minimum;
                volume.Maximum = actual.Maximum;
                volume.Value = actual.Value;
                confirmedVolume = actual.Value;
                volumeValue.Text = $"{actual.Value} / {actual.Maximum}";
            }
            finally { updatingToggles = false; }
        }

        private static string Quote(string value) => $"\"{value.Replace("\"", "\\\"")}\"";
    }
}
