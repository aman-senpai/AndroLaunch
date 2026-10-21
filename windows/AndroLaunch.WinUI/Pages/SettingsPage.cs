using System;
using System.IO;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Dialogs;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AndroLaunch.WinUI.Pages
{
    public sealed class SettingsPage : Page
    {
        private readonly TextBox toolsPath = PathBox();
        private readonly TextBox avdPath = PathBox();
        private readonly TextBox imagesPath = PathBox();
        private readonly TextBox emulatorPath = PathBox();
        private readonly TextBox adbPath = PathBox();
        private readonly TextBox scrcpyPath = PathBox();
        private readonly InfoBar statusBar = new()
        {
            IsClosable = false,
            IsOpen = false,
            Margin = new Thickness(0, 0, 0, 4)
        };
        private readonly ToggleSwitch startupSwitch = new()
        {
            Header = "Run at startup",
            OnContent = "Enabled",
            OffContent = "Disabled"
        };

        public SettingsPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) =>
            {
                LoadSettings();
                await CheckToolsAsync();
            };
        }

        private UIElement BuildContent()
        {
            var root = new StackPanel { Spacing = 18, MaxWidth = 900, HorizontalAlignment = HorizontalAlignment.Left };
            root.Children.Add(new TextBlock
            {
                Text = "Settings",
                FontSize = 30,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            root.Children.Add(new TextBlock
            {
                Text = "Tool paths, Android SDK discovery and Windows startup.",
                Opacity = 0.7
            });

            statusBar.Severity = InfoBarSeverity.Informational;
            root.Children.Add(statusBar);

            var adbCard = new StackPanel { Spacing = 10 };
            adbCard.Children.Add(SectionTitle("ADB status"));
            var adbRow = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8
            };
            var checkAdb = new Button { Content = "Check ADB" };
            checkAdb.Click += async (_, _) => await CheckToolsAsync();
            adbRow.Children.Add(checkAdb);
            var setup = new Button { Content = "Setup guide" };
            setup.Click += async (_, _) => await OnboardingDialog.ShowAsync();
            adbRow.Children.Add(setup);
            adbCard.Children.Add(adbRow);
            root.Children.Add(Card(adbCard));

            var sdkCard = new StackPanel { Spacing = 12 };
            sdkCard.Children.Add(SectionTitle("Android SDK"));
            sdkCard.Children.Add(PathRow("Command-line tools", toolsPath, "Select the folder containing sdkmanager.bat and avdmanager.bat", isFolder: true));
            sdkCard.Children.Add(PathRow("AVD folder", avdPath, "Select the AVD storage folder", isFolder: true));
            sdkCard.Children.Add(PathRow("System images", imagesPath, "Select the SDK root for downloaded images", isFolder: true));
            sdkCard.Children.Add(PathRow("Emulator", emulatorPath, "Select emulator.exe", isFolder: false));
            var sdkActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var autoDetect = new Button
            {
                Content = "Auto-detect SDK",
                Style = (Style)Application.Current.Resources["AccentButtonStyle"]
            };
            autoDetect.Click += (_, _) => AutoDetect();
            sdkActions.Children.Add(autoDetect);
            var save = new Button { Content = "Save" };
            save.Click += async (_, _) => await SaveAsync();
            sdkActions.Children.Add(save);
            var checkTools = new Button { Content = "Check tools" };
            checkTools.Click += async (_, _) => await CheckToolsAsync();
            sdkActions.Children.Add(checkTools);
            sdkCard.Children.Add(sdkActions);
            root.Children.Add(Card(sdkCard));

            var toolsCard = new StackPanel { Spacing = 12 };
            toolsCard.Children.Add(SectionTitle("Tool overrides"));
            toolsCard.Children.Add(PathRow("adb", adbPath, "Optional override for adb.exe", isFolder: false));
            toolsCard.Children.Add(PathRow("scrcpy", scrcpyPath, "Optional override for scrcpy.exe", isFolder: false));
            root.Children.Add(Card(toolsCard));

            var windowsCard = new StackPanel { Spacing = 12 };
            windowsCard.Children.Add(SectionTitle("Windows"));
            startupSwitch.IsOn = StartupService.IsEnabled;
            startupSwitch.Toggled += (_, _) => StartupService.SetEnabled(startupSwitch.IsOn);
            windowsCard.Children.Add(startupSwitch);
            root.Children.Add(Card(windowsCard));

            var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var emulators = new Button { Content = "Emulator Manager" };
            emulators.Click += (_, _) => App.ShowMainWindow("emulators");
            footer.Children.Add(emulators);
            var about = new Button { Content = "About AndroLaunch" };
            about.Click += async (_, _) => await AboutDialog.ShowAsync();
            footer.Children.Add(about);
            root.Children.Add(footer);

            return new ScrollViewer
            {
                Content = new Grid { Padding = new Thickness(28), Children = { root } },
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
        }

        private static TextBlock SectionTitle(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 16,
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
                Padding = new Thickness(16),
                Child = content
            };
        }

        private static TextBox PathBox()
        {
            return new TextBox
            {
                PlaceholderText = "Not set",
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
        }

        private UIElement PathRow(string label, TextBox textBox, string description, bool isFolder)
        {
            var panel = new StackPanel { Spacing = 4 };
            panel.Children.Add(new TextBlock { Text = label, Opacity = 0.8 });
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(textBox, 0);
            row.Children.Add(textBox);
            var browse = new Button { Content = "Browse…" };
            Grid.SetColumn(browse, 1);
            browse.Click += async (_, _) =>
            {
                string? path = isFolder
                    ? await PickFolderAsync(description)
                    : await PickFileAsync(description);
                if (!string.IsNullOrWhiteSpace(path))
                {
                    textBox.Text = path;
                    await SaveAsync();
                }
            };
            row.Children.Add(browse);
            panel.Children.Add(row);
            panel.Children.Add(new TextBlock
            {
                Text = description,
                Opacity = 0.55,
                FontSize = 12
            });
            return panel;
        }

        private async Task PickPathAsync(TextBox box, bool folder, string description)
        {
            string? path = folder ? await PickFolderAsync(description) : await PickFileAsync(description);
            if (!string.IsNullOrWhiteSpace(path))
            {
                box.Text = path;
                await SaveAsync();
            }
        }

        private static async Task<string?> PickFolderAsync(string description)
        {
            var picker = new FolderPicker
            {
                SuggestedStartLocation = PickerLocationId.ComputerFolder
            };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            Windows.Storage.StorageFolder? folder = await picker.PickSingleFolderAsync();
            return folder?.Path;
        }

        private static async Task<string?> PickFileAsync(string description)
        {
            var picker = new FileOpenPicker
            {
                SuggestedStartLocation = PickerLocationId.ComputerFolder
            };
            picker.FileTypeFilter.Add(".exe");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
            return file?.Path;
        }

        private void LoadSettings()
        {
            AppSettings settings = AppSettingsStore.Current;
            toolsPath.Text = settings.CommandLineToolsPath ?? "";
            avdPath.Text = settings.AvdPath ?? AppSettingsStore.DefaultAvdPath;
            imagesPath.Text = settings.ImageDownloadPath ?? AppSettingsStore.DefaultSdkRoot;
            emulatorPath.Text = settings.EmulatorPath ?? "";
            adbPath.Text = settings.AdbPath ?? "";
            scrcpyPath.Text = settings.ScrcpyPath ?? "";
        }

        private async Task SaveAsync()
        {
            AppSettings settings = AppSettingsStore.Current;
            settings.CommandLineToolsPath = NullIfEmpty(toolsPath.Text);
            settings.AvdPath = NullIfEmpty(avdPath.Text);
            settings.ImageDownloadPath = NullIfEmpty(imagesPath.Text);
            settings.EmulatorPath = NullIfEmpty(emulatorPath.Text);
            settings.AdbPath = NullIfEmpty(adbPath.Text);
            settings.ScrcpyPath = NullIfEmpty(scrcpyPath.Text);
            AppSettingsStore.Save();
            AdbHelper.RefreshToolPaths();
            await CheckToolsAsync();
        }

        private static string? NullIfEmpty(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
        }

        private void AutoDetect()
        {
            string? tools = AppSettingsStore.AutoDetectCommandLineToolsPath();
            string? emulator = AppSettingsStore.AutoDetectEmulatorPath();
            if (!string.IsNullOrWhiteSpace(tools))
            {
                toolsPath.Text = tools;
            }

            if (!string.IsNullOrWhiteSpace(emulator))
            {
                emulatorPath.Text = emulator;
            }

            avdPath.Text = AppSettingsStore.DefaultAvdPath;
            imagesPath.Text = AppSettingsStore.SdkRootFromToolsPath(tools);
            _ = SaveAsync();
        }

        private async Task CheckToolsAsync()
        {
            string adbMessage = "";
            bool adbOk = await Task.Run(() => AdbHelper.TestAdb(out adbMessage));
            bool scrcpyOk = await Task.Run(() => AdbHelper.TestScrcpy(out _));
            bool sdkOk = File.Exists(Path.Combine(toolsPath.Text.Trim(), "sdkmanager.bat"));
            bool avdOk = File.Exists(Path.Combine(toolsPath.Text.Trim(), "avdmanager.bat"));
            bool emulatorOk = File.Exists(emulatorPath.Text.Trim());

            statusBar.IsOpen = true;
            statusBar.Severity = adbOk && scrcpyOk && sdkOk && avdOk && emulatorOk
                ? InfoBarSeverity.Success
                : InfoBarSeverity.Warning;
            statusBar.Title = adbOk ? "ADB ready" : "ADB not available";
            statusBar.Message =
                $"{adbMessage}   scrcpy {(scrcpyOk ? "found" : "not found")} · " +
                $"sdkmanager {(sdkOk ? "found" : "not found")} · " +
                $"avdmanager {(avdOk ? "found" : "not found")} · " +
                $"emulator {(emulatorOk ? "found" : "not found")}";
        }
    }
}
