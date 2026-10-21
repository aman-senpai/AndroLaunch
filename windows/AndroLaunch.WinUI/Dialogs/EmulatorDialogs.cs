using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AndroLaunch.WinUI.Dialogs
{
    public sealed class AvdCreationResult
    {
        public string Name { get; set; } = "";
        public string ImageId { get; set; } = "";
        public string? DeviceId { get; set; }
        public AvdOptions Options { get; set; } = new();
    }

    public static class EmulatorDialogs
    {
        private sealed class ImageChoice
        {
            public SystemImageInfo Image { get; init; } = new();
            public override string ToString() => Image.DisplayName;
        }

        private sealed class ProfileChoice
        {
            public HardwareProfile Profile { get; init; } = new();
            public override string ToString() => string.IsNullOrWhiteSpace(Profile.Oem)
                ? Profile.Name
                : $"{Profile.Name} ({Profile.Oem})";
        }

        public static async Task<AvdCreationResult?> CreateAvdAsync(
            IEnumerable<SystemImageInfo> images,
            IEnumerable<HardwareProfile> profiles)
        {
            List<SystemImageInfo> installed = images.Where(image => image.IsDownloaded).ToList();
            var name = new TextBox { PlaceholderText = "Pixel 8 API 35" };
            var image = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            foreach (SystemImageInfo systemImage in installed)
            {
                image.Items.Add(new ImageChoice { Image = systemImage });
            }
            if (image.Items.Count > 0)
            {
                image.SelectedIndex = 0;
            }

            var device = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            device.Items.Add(new ProfileChoice { Profile = new HardwareProfile { Id = "", Name = "Default device" } });
            foreach (HardwareProfile profile in profiles)
            {
                device.Items.Add(new ProfileChoice { Profile = profile });
            }
            device.SelectedIndex = 0;

            var ram = new NumberBox { Minimum = 512, Maximum = 32768, Value = 2048, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline };
            var storage = new NumberBox { Minimum = 512, Maximum = 131072, Value = 4096, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline };
            var sdCard = new NumberBox { Minimum = 0, Maximum = 65536, Value = 512, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline };
            var camera = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            camera.Items.Add("emulated");
            camera.Items.Add("webcam0");
            camera.Items.Add("none");
            camera.SelectedIndex = 0;
            var gpu = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
            gpu.Items.Add("auto");
            gpu.Items.Add("host");
            gpu.Items.Add("swiftshader_indirect");
            gpu.Items.Add("angle_indirect");
            gpu.SelectedIndex = 0;

            var gps = new CheckBox { Content = "GPS", IsChecked = true };
            var keyboard = new CheckBox { Content = "Hardware keyboard", IsChecked = true };
            var frame = new CheckBox { Content = "Show device frame", IsChecked = true };

            var panel = new StackPanel { Spacing = 10, MinWidth = 480 };
            panel.Children.Add(Labeled("Name", name));
            panel.Children.Add(Labeled("System image", image));
            if (installed.Count == 0)
            {
                panel.Children.Add(new InfoBar
                {
                    IsOpen = true,
                    IsClosable = false,
                    Severity = InfoBarSeverity.Warning,
                    Title = "No installed system images",
                    Message = "Download an image from the System images tab first."
                });
            }
            panel.Children.Add(Labeled("Device template", device));
            var numbers = new Grid { ColumnSpacing = 8 };
            numbers.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            numbers.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            numbers.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            FrameworkElement ramPanel = Labeled("RAM (MB)", ram);
            FrameworkElement storagePanel = Labeled("Storage (MB)", storage);
            FrameworkElement sdPanel = Labeled("SD card (MB)", sdCard);
            numbers.Children.Add(ramPanel);
            Grid.SetColumn(storagePanel, 1);
            numbers.Children.Add(storagePanel);
            Grid.SetColumn(sdPanel, 2);
            numbers.Children.Add(sdPanel);
            panel.Children.Add(numbers);
            var choices = new Grid { ColumnSpacing = 8 };
            choices.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            choices.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            choices.Children.Add(Labeled("Camera", camera));
            var gpuPanel = Labeled("GPU", gpu);
            Grid.SetColumn(gpuPanel, 1);
            choices.Children.Add(gpuPanel);
            panel.Children.Add(choices);
            var checks = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
            checks.Children.Add(gps);
            checks.Children.Add(keyboard);
            checks.Children.Add(frame);
            panel.Children.Add(checks);

            var dialog = new ContentDialog
            {
                Title = "Create Android Virtual Device",
                Content = new ScrollViewer { Content = panel, MaxHeight = 560 },
                PrimaryButtonText = "Create",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                IsPrimaryButtonEnabled = false,
                XamlRoot = App.MainWindowInstance.Content.XamlRoot
            };
            void UpdateCreateEnabled()
            {
                dialog.IsPrimaryButtonEnabled = image.SelectedItem is ImageChoice &&
                    !string.IsNullOrWhiteSpace(name.Text) &&
                    double.IsFinite(ram.Value) && double.IsFinite(storage.Value) &&
                    double.IsFinite(sdCard.Value);
            }
            name.TextChanged += (_, _) => UpdateCreateEnabled();
            image.SelectionChanged += (_, _) => UpdateCreateEnabled();
            ram.ValueChanged += (_, _) => UpdateCreateEnabled();
            storage.ValueChanged += (_, _) => UpdateCreateEnabled();
            sdCard.ValueChanged += (_, _) => UpdateCreateEnabled();

            if (await dialog.ShowAsync() != ContentDialogResult.Primary ||
                image.SelectedItem is not ImageChoice selectedImage)
            {
                return null;
            }

            return new AvdCreationResult
            {
                Name = name.Text.Trim(),
                ImageId = selectedImage.Image.Id,
                DeviceId = (device.SelectedItem as ProfileChoice)?.Profile.Id,
                Options = new AvdOptions
                {
                    RamMB = (int)ram.Value,
                    StorageMB = (int)storage.Value,
                    SdCardMB = (int)sdCard.Value,
                    CameraBack = camera.SelectedItem?.ToString() ?? "emulated",
                    GpuMode = gpu.SelectedItem?.ToString() ?? "auto",
                    Gps = gps.IsChecked == true,
                    Keyboard = keyboard.IsChecked == true,
                    ShowDeviceFrame = frame.IsChecked == true
                }
            };
        }

        public static async Task<LaunchFlags?> EditLaunchFlagsAsync(string avdName, LaunchFlags original)
        {
            LaunchFlags flags = original.Clone();
            var panel = new StackPanel { Spacing = 8, MinWidth = 480 };

            void Check(string label, bool value, Action<bool> setter)
            {
                var box = new CheckBox { Content = label, IsChecked = value };
                box.Checked += (_, _) => setter(true);
                box.Unchecked += (_, _) => setter(false);
                panel.Children.Add(box);
            }

            void Text(string label, string value, Action<string> setter)
            {
                var box = new TextBox { Text = value, PlaceholderText = label };
                box.TextChanged += (_, _) => setter(box.Text.Trim());
                panel.Children.Add(Labeled(label, box));
            }

            void Choice(string label, string[] values, string selected, Action<string> setter)
            {
                var combo = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
                foreach (string option in values)
                {
                    combo.Items.Add(option);
                }
                int index = Array.FindIndex(values, value => string.Equals(value, selected, StringComparison.OrdinalIgnoreCase));
                combo.SelectedIndex = index >= 0 ? index : 0;
                combo.SelectionChanged += (_, _) => setter(combo.SelectedItem?.ToString() ?? values[0]);
                panel.Children.Add(Labeled(label, combo));
            }

            panel.Children.Add(new TextBlock { Text = "Core", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
            Check("No audio", flags.NoAudio, value => flags.NoAudio = value);
            Check("No window", flags.NoWindow, value => flags.NoWindow = value);
            Check("Verbose", flags.Verbose, value => flags.Verbose = value);
            Check("No skin", flags.NoSkin, value => flags.NoSkin = value);
            Check("Qt hide window", flags.QtHideWindow, value => flags.QtHideWindow = value);

            panel.Children.Add(new TextBlock { Text = "Boot", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            Check("Wipe data", flags.WipeData, value => flags.WipeData = value);
            Check("Read only", flags.ReadOnly, value => flags.ReadOnly = value);
            Check("No boot animation", flags.NoBootAnim, value => flags.NoBootAnim = value);
            Check("No JNI", flags.NoJni, value => flags.NoJni = value);

            panel.Children.Add(new TextBlock { Text = "Snapshot", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            Check("No snapshot save", flags.NoSnapshotSave, value => flags.NoSnapshotSave = value);
            Check("No snapshot load", flags.NoSnapshotLoad, value => flags.NoSnapshotLoad = value);
            Text("Snapshot name", flags.Snapshot, value => flags.Snapshot = value);

            panel.Children.Add(new TextBlock { Text = "Hardware", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            Choice("GPU", new[] { "auto", "host", "swiftshader_indirect", "angle_indirect", "off" }, flags.GpuMode, value => flags.GpuMode = value);
            Text("RAM (MB)", flags.MemoryMB, value => flags.MemoryMB = value);
            Text("Cores", flags.Cores, value => flags.Cores = value);
            Text("Port", flags.Port, value => flags.Port = value);

            panel.Children.Add(new TextBlock { Text = "Network", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            Choice("Speed", new[] { "full", "gsm", "hscsd", "gprs", "edge", "umts", "hsdpa", "lte", "evdo" }, flags.NetSpeed, value => flags.NetSpeed = value);
            Choice("Delay", new[] { "none", "gprs", "edge", "umts" }, flags.NetDelay, value => flags.NetDelay = value);
            Text("HTTP proxy", flags.HttpProxy, value => flags.HttpProxy = value);
            Text("DNS", flags.DnsServer, value => flags.DnsServer = value);

            panel.Children.Add(new TextBlock { Text = "Camera & extra", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
            Choice("Camera back", new[] { "AVD default", "emulated", "webcam0", "none" }, flags.CameraBack.Length == 0 ? "AVD default" : flags.CameraBack, value => flags.CameraBack = value == "AVD default" ? "" : value);
            Choice("Camera front", new[] { "AVD default", "emulated", "webcam0", "none" }, flags.CameraFront.Length == 0 ? "AVD default" : flags.CameraFront, value => flags.CameraFront = value == "AVD default" ? "" : value);
            Text("Timezone", flags.Timezone, value => flags.Timezone = value);
            Text("tcpdump file", flags.Tcpdump, value => flags.Tcpdump = value);

            var dialog = new ContentDialog
            {
                Title = $"Launch options - {avdName}",
                Content = new ScrollViewer { Content = panel, MaxHeight = 580 },
                PrimaryButtonText = "Apply",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = App.MainWindowInstance.Content.XamlRoot
            };

            return await dialog.ShowAsync() == ContentDialogResult.Primary ? flags : null;
        }

        private static FrameworkElement Labeled(string label, Control control)
        {
            var panel = new StackPanel { Spacing = 3 };
            panel.Children.Add(new TextBlock { Text = label, Opacity = 0.75, FontSize = 12 });
            panel.Children.Add(control);
            return panel;
        }
    }
}
