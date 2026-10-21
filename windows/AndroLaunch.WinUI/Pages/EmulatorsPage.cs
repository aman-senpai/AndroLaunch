using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Dialogs;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AndroLaunch.WinUI.Pages
{
    public sealed class EmulatorsPage : Page
    {
        private readonly TabView tabs = new();
        private readonly ListView avdList = new() { SelectionMode = ListViewSelectionMode.Single };
        private readonly ListView imageList = new() { SelectionMode = ListViewSelectionMode.Single };
        private readonly TextBox imageSearch = new() { PlaceholderText = "Search images", Width = 260 };
        private readonly ComboBox imageFilter = new() { Width = 160 };
        private readonly CheckBox installedOnly = new() { Content = "Installed only" };
        private readonly InfoBar status = new()
        {
            IsClosable = false,
            IsOpen = true,
            Title = "Emulator Manager",
            Severity = InfoBarSeverity.Informational
        };
        private readonly ProgressBar downloadProgress = new() { IsIndeterminate = false, Visibility = Visibility.Collapsed, Width = 260 };
        private readonly TextBlock toolsText = new() { Opacity = 0.7 };
        private readonly Button startButton = new() { Content = "Start", IsEnabled = false };
        private readonly Button stopButton = new() { Content = "Stop", IsEnabled = false };
        private readonly Button launchOptionsButton = new() { Content = "Launch options", IsEnabled = false };
        private readonly Button renameButton = new() { Content = "Rename…", IsEnabled = false };
        private readonly Button deleteAvdButton = new() { Content = "Delete", IsEnabled = false };
        private readonly Button downloadButton = new() { Content = "Download", IsEnabled = false };
        private readonly Button deleteImageButton = new() { Content = "Delete", IsEnabled = false };
        private readonly Button cancelDownloadButton = new() { Content = "Cancel", IsEnabled = false };

        private readonly TextBox toolsPath = new() { PlaceholderText = "cmdline-tools\\latest\\bin" };
        private readonly TextBox avdPath = new() { PlaceholderText = "AVD folder" };
        private readonly TextBox imagesPath = new() { PlaceholderText = "SDK root" };
        private readonly TextBox emulatorPath = new() { PlaceholderText = "emulator.exe" };

        private List<AvdInfo> avds = new();
        private List<SystemImageInfo> images = new();
        private bool busy;
        private CancellationTokenSource? downloadCancellation;

        public EmulatorsPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) => await RefreshAllAsync();
        }

        private UIElement BuildContent()
        {
            var root = new Grid { Padding = new Thickness(28), RowSpacing = 12 };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var header = new StackPanel { Spacing = 2 };
            header.Children.Add(new TextBlock
            {
                Text = "Emulator Manager",
                FontSize = 30,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            header.Children.Add(new TextBlock
            {
                Text = "Create and run Android Virtual Devices, and manage system images.",
                Opacity = 0.7
            });
            header.Children.Add(toolsText);
            Grid.SetRow(header, 0);
            root.Children.Add(header);

            Grid.SetRow(status, 1);
            root.Children.Add(status);

            tabs.IsAddTabButtonVisible = false;
            tabs.TabWidthMode = TabViewWidthMode.Equal;

            var devices = new TabViewItem { Header = "My devices", IsClosable = false, Content = BuildAvdTab() };
            var systemImages = new TabViewItem { Header = "System images", IsClosable = false, Content = BuildImageTab() };
            var settings = new TabViewItem { Header = "Settings", IsClosable = false, Content = BuildSettingsTab() };
            tabs.TabItems.Add(devices);
            tabs.TabItems.Add(systemImages);
            tabs.TabItems.Add(settings);
            Grid.SetRow(tabs, 2);
            root.Children.Add(tabs);
            return root;
        }

        private UIElement BuildAvdTab()
        {
            var panel = new Grid { RowSpacing = 10, Padding = new Thickness(2, 10, 2, 2) };
            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            var refresh = new Button { Content = "Refresh" };
            refresh.Click += async (_, _) => await RefreshAvdsAsync();
            toolbar.Children.Add(refresh);
            var create = new Button
            {
                Content = "Create device",
                Style = (Style)Application.Current.Resources["AccentButtonStyle"]
            };
            create.Click += async (_, _) => await CreateAvdAsync();
            toolbar.Children.Add(create);
            toolbar.Children.Add(startButton);
            toolbar.Children.Add(stopButton);
            toolbar.Children.Add(launchOptionsButton);
            toolbar.Children.Add(renameButton);
            toolbar.Children.Add(deleteAvdButton);
            var folder = new Button { Content = "Show folder" };
            folder.Click += (_, _) => ShowAvdFolder();
            toolbar.Children.Add(folder);
            panel.Children.Add(toolbar);

            avdList.SelectionChanged += (_, _) => UpdateAvdButtons();
            avdList.DoubleTapped += async (_, _) => await ToggleAvdAsync();
            var card = new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8),
                Child = avdList
            };
            Grid.SetRow(card, 1);
            panel.Children.Add(card);

            startButton.Click += async (_, _) => await ToggleAvdAsync();
            stopButton.Click += async (_, _) => await ToggleAvdAsync();
            launchOptionsButton.Click += async (_, _) => await EditFlagsAsync();
            renameButton.Click += async (_, _) => await RenameAvdAsync();
            deleteAvdButton.Click += async (_, _) => await DeleteAvdAsync();
            return panel;
        }

        private UIElement BuildImageTab()
        {
            var panel = new Grid { RowSpacing = 10, Padding = new Thickness(2, 10, 2, 2) };
            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            panel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var filters = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            filters.Children.Add(imageSearch);
            imageFilter.Items.Add("All types");
            imageFilter.Items.Add("Phone/Tablet");
            imageFilter.Items.Add("Wear OS");
            imageFilter.Items.Add("Android TV");
            imageFilter.Items.Add("Automotive");
            imageFilter.SelectedIndex = 0;
            filters.Children.Add(imageFilter);
            filters.Children.Add(installedOnly);
            var refresh = new Button { Content = "Refresh" };
            refresh.Click += async (_, _) => await RefreshImagesAsync();
            filters.Children.Add(refresh);
            panel.Children.Add(filters);

            var toolbar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            toolbar.Children.Add(downloadButton);
            toolbar.Children.Add(deleteImageButton);
            toolbar.Children.Add(cancelDownloadButton);
            toolbar.Children.Add(downloadProgress);
            var create = new Button { Content = "Create AVD", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
            create.Click += async (_, _) => await CreateAvdAsync();
            toolbar.Children.Add(create);
            Grid.SetRow(toolbar, 1);
            panel.Children.Add(toolbar);

            imageList.SelectionChanged += (_, _) => UpdateImageButtons();
            imageSearch.TextChanged += (_, _) => RenderImages();
            imageFilter.SelectionChanged += (_, _) => RenderImages();
            installedOnly.Checked += (_, _) => RenderImages();
            installedOnly.Unchecked += (_, _) => RenderImages();

            var card = new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8),
                Child = imageList
            };
            Grid.SetRow(card, 2);
            panel.Children.Add(card);

            var hint = new TextBlock
            {
                Text = "Images are downloaded with sdkmanager into the configured SDK root.",
                Opacity = 0.55,
                FontSize = 12
            };
            Grid.SetRow(hint, 3);
            panel.Children.Add(hint);

            downloadButton.Click += async (_, _) => await DownloadImageAsync();
            deleteImageButton.Click += async (_, _) => await DeleteImageAsync();
            cancelDownloadButton.Click += (_, _) => downloadCancellation?.Cancel();
            return panel;
        }

        private UIElement BuildSettingsTab()
        {
            var panel = new StackPanel { Spacing = 12, Padding = new Thickness(2, 12, 2, 2) };
            panel.Children.Add(new TextBlock
            {
                Text = "SDK paths",
                FontSize = 16,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            panel.Children.Add(PathRow("Command-line tools", toolsPath, true));
            panel.Children.Add(PathRow("AVD folder", avdPath, true));
            panel.Children.Add(PathRow("System images", imagesPath, true));
            panel.Children.Add(PathRow("Emulator", emulatorPath, false));
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var autoDetect = new Button
            {
                Content = "Auto-detect SDK",
                Style = (Style)Application.Current.Resources["AccentButtonStyle"]
            };
            autoDetect.Click += async (_, _) => await AutoDetectAsync();
            actions.Children.Add(autoDetect);
            var save = new Button { Content = "Save" };
            save.Click += async (_, _) => await SaveSettingsAsync();
            actions.Children.Add(save);
            panel.Children.Add(actions);
            return new ScrollViewer
            {
                Content = panel,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
        }

        private UIElement PathRow(string label, TextBox box, bool folder)
        {
            var panel = new StackPanel { Spacing = 3 };
            panel.Children.Add(new TextBlock { Text = label, Opacity = 0.75, FontSize = 12 });
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(box);
            var browse = new Button { Content = "Browse…" };
            Grid.SetColumn(browse, 1);
            browse.Click += async (_, _) =>
            {
                string? path = folder ? await PickFolderAsync() : await PickFileAsync();
                if (!string.IsNullOrWhiteSpace(path))
                {
                    box.Text = path;
                    await SaveSettingsAsync();
                }
            };
            row.Children.Add(browse);
            panel.Children.Add(row);
            return panel;
        }

        private static async Task<string?> PickFolderAsync()
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            Windows.Storage.StorageFolder? folder = await picker.PickSingleFolderAsync();
            return folder?.Path;
        }

        private static async Task<string?> PickFileAsync()
        {
            var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
            picker.FileTypeFilter.Add(".exe");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            Windows.Storage.StorageFile? file = await picker.PickSingleFileAsync();
            return file?.Path;
        }

        private async Task RefreshAllAsync()
        {
            LoadSettings();
            bool tools = EmulatorService.ToolsAvailable;
            toolsText.Text = tools
                ? $"SDK tools: {EmulatorService.ToolsPath}"
                : "Android SDK command-line tools are not configured yet. Open Settings to choose the cmdline-tools folder.";
            if (!tools)
            {
                SetStatus("SDK tools not configured", toolsText.Text, InfoBarSeverity.Warning);
                return;
            }

            await RefreshAvdsAsync();
            await RefreshImagesAsync();
        }

        private void LoadSettings()
        {
            AppSettings settings = AppSettingsStore.Current;
            toolsPath.Text = settings.CommandLineToolsPath ?? "";
            avdPath.Text = settings.AvdPath ?? AppSettingsStore.DefaultAvdPath;
            imagesPath.Text = settings.ImageDownloadPath ?? AppSettingsStore.DefaultSdkRoot;
            emulatorPath.Text = settings.EmulatorPath ?? "";
        }

        private async Task SaveSettingsAsync()
        {
            AppSettings settings = AppSettingsStore.Current;
            settings.CommandLineToolsPath = NullIfEmpty(toolsPath.Text);
            settings.AvdPath = NullIfEmpty(avdPath.Text);
            settings.ImageDownloadPath = NullIfEmpty(imagesPath.Text);
            settings.EmulatorPath = NullIfEmpty(emulatorPath.Text);
            AppSettingsStore.Save();
            AdbHelper.RefreshToolPaths();
            await RefreshAllAsync();
        }

        private async Task AutoDetectAsync()
        {
            string? tools = AppSettingsStore.AutoDetectCommandLineToolsPath();
            string? emulator = AppSettingsStore.AutoDetectEmulatorPath();
            if (!string.IsNullOrWhiteSpace(tools)) toolsPath.Text = tools;
            if (!string.IsNullOrWhiteSpace(emulator)) emulatorPath.Text = emulator;
            avdPath.Text = AppSettingsStore.DefaultAvdPath;
            imagesPath.Text = AppSettingsStore.SdkRootFromToolsPath(tools);
            await SaveSettingsAsync();
        }

        private async Task RefreshAvdsAsync()
        {
            if (busy)
            {
                return;
            }

            busy = true;
            SetStatus("Loading virtual devices", "Reading AVDs…", InfoBarSeverity.Informational);
            try
            {
                avds = await Task.Run(EmulatorService.ListAvds);
                RenderAvds();
                SetStatus($"{avds.Count} virtual devices", "", InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                SetStatus("Could not list AVDs", ex.Message, InfoBarSeverity.Error);
            }
            finally
            {
                busy = false;
                UpdateAvdButtons();
            }
        }

        private void RenderAvds()
        {
            avdList.Items.Clear();
            foreach (AvdInfo avd in avds)
            {
                var row = new Grid { ColumnSpacing = 12 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
                row.Children.Add(new TextBlock
                {
                    Text = avd.Name,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
                });
                var target = new TextBlock { Text = avd.Target ?? avd.Device ?? "", Opacity = 0.6, FontSize = 12 };
                Grid.SetColumn(target, 1);
                row.Children.Add(target);
                var running = new TextBlock
                {
                    Text = avd.IsRunning ? "Running" : "Stopped",
                    Foreground = avd.IsRunning
                        ? (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"]
                        : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
                };
                Grid.SetColumn(running, 2);
                row.Children.Add(running);
                avdList.Items.Add(new ListViewItem { Tag = avd, Content = row });
            }
        }

        private AvdInfo? SelectedAvd => (avdList.SelectedItem as ListViewItem)?.Tag as AvdInfo;
        private SystemImageInfo? SelectedImage => (imageList.SelectedItem as ListViewItem)?.Tag as SystemImageInfo;

        private void UpdateAvdButtons()
        {
            AvdInfo? avd = SelectedAvd;
            bool running = avd?.IsRunning == true;
            startButton.IsEnabled = avd is not null && !running && !busy;
            stopButton.IsEnabled = running && !busy;
            launchOptionsButton.IsEnabled = avd is not null && !busy;
            renameButton.IsEnabled = avd is not null && !running && !busy;
            deleteAvdButton.IsEnabled = avd is not null && !running && !busy;
        }

        private void UpdateImageButtons()
        {
            SystemImageInfo? image = SelectedImage;
            downloadButton.IsEnabled = image is not null && !image.IsDownloaded && !busy;
            deleteImageButton.IsEnabled = image is not null && image.IsDownloaded && !busy;
        }

        private async Task CreateAvdAsync()
        {
            if (!EmulatorService.ToolsAvailable)
            {
                await Ui.ShowErrorAsync("SDK tools not configured", "Choose the Android SDK command-line tools folder in Settings.");
                return;
            }

            if (images.Count == 0)
            {
                await RefreshImagesAsync();
            }

            try
            {
                List<HardwareProfile> profiles = await Task.Run(EmulatorService.ListHardwareProfiles);
                AvdCreationResult? result = await EmulatorDialogs.CreateAvdAsync(images, profiles);
                if (result is null)
                {
                    return;
                }

                SetStatus("Creating AVD", result.Name, InfoBarSeverity.Informational);
                await Task.Run(() => EmulatorService.CreateAvd(result.Name, result.ImageId, result.DeviceId, result.Options));
                await RefreshAvdsAsync();
                tabs.SelectedIndex = 0;
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not create AVD", ex.Message);
            }
        }

        private async Task ToggleAvdAsync()
        {
            AvdInfo? avd = SelectedAvd;
            if (avd is null || busy)
            {
                return;
            }

            busy = true;
            try
            {
                SetStatus(avd.IsRunning ? "Stopping" : "Starting", avd.Name, InfoBarSeverity.Informational);
                if (avd.IsRunning)
                {
                    await Task.Run(() => EmulatorService.StopAvd(avd));
                }
                else
                {
                    await Task.Run(() => EmulatorService.StartAvd(avd.Name));
                    await Task.Delay(1500);
                }
                busy = false;
                await RefreshAvdsAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Emulator", ex.Message);
            }
            finally
            {
                busy = false;
                UpdateAvdButtons();
            }
        }

        private async Task EditFlagsAsync()
        {
            AvdInfo? avd = SelectedAvd;
            if (avd is null)
            {
                return;
            }

            LaunchFlags? flags = await EmulatorDialogs.EditLaunchFlagsAsync(
                avd.Name,
                AppSettingsStore.GetLaunchFlags(avd.Name));
            if (flags is not null)
            {
                AppSettingsStore.SetLaunchFlags(avd.Name, flags);
            }
        }

        private async Task RenameAvdAsync()
        {
            AvdInfo? avd = SelectedAvd;
            if (avd is null)
            {
                return;
            }

            string? name = await Ui.PromptAsync("Rename AVD", "New name", avd.Name);
            if (string.IsNullOrWhiteSpace(name) || name == avd.Name)
            {
                return;
            }

            try
            {
                await Task.Run(() => EmulatorService.RenameAvd(avd.Name, name));
                await RefreshAvdsAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not rename AVD", ex.Message);
            }
        }

        private async Task DeleteAvdAsync()
        {
            AvdInfo? avd = SelectedAvd;
            if (avd is null)
            {
                return;
            }

            if (!await Ui.ConfirmAsync("Delete AVD", $"Delete {avd.Name}? This cannot be undone.", "Delete"))
            {
                return;
            }

            try
            {
                await Task.Run(() => EmulatorService.DeleteAvd(avd.Name));
                await RefreshAvdsAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not delete AVD", ex.Message);
            }
        }

        private void ShowAvdFolder()
        {
            AvdInfo? avd = SelectedAvd;
            string path = avd?.Path is not null && Directory.Exists(avd.Path)
                ? avd.Path
                : EmulatorService.AvdPath;
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                _ = Ui.ShowErrorAsync("Could not open folder", ex.Message);
            }
        }

        private async Task RefreshImagesAsync()
        {
            if (busy || !EmulatorService.ToolsAvailable)
            {
                return;
            }

            busy = true;
            UpdateImageButtons();
            SetStatus("Loading system images", "Reading the SDK package catalog…", InfoBarSeverity.Informational);
            try
            {
                images = await Task.Run(EmulatorService.ListImages);
                RenderImages();
                SetStatus($"{images.Count} system images", "", InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                SetStatus("Could not list system images", ex.Message, InfoBarSeverity.Error);
            }
            finally
            {
                busy = false;
                UpdateImageButtons();
            }
        }

        private void RenderImages()
        {
            string query = imageSearch.Text.Trim();
            string filter = imageFilter.SelectedItem?.ToString() ?? "All types";
            imageList.Items.Clear();
            foreach (SystemImageInfo image in images)
            {
                if (!string.IsNullOrWhiteSpace(query) &&
                    !image.Id.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                    !image.Description.Contains(query, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (filter != "All types" && image.OsType != filter)
                {
                    continue;
                }
                if (installedOnly.IsChecked == true && !image.IsDownloaded)
                {
                    continue;
                }

                var row = new Grid { ColumnSpacing = 12 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
                row.Children.Add(new TextBlock
                {
                    Text = image.Description.Length > 0 ? image.Description : image.DisplayName,
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                var api = new TextBlock { Text = $"API {image.ApiLevel}", Opacity = 0.65 };
                Grid.SetColumn(api, 1);
                row.Children.Add(api);
                var state = new TextBlock
                {
                    Text = image.IsDownloaded ? "Installed" : "Available",
                    Foreground = image.IsDownloaded
                        ? (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"]
                        : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
                };
                Grid.SetColumn(state, 2);
                row.Children.Add(state);
                imageList.Items.Add(new ListViewItem { Tag = image, Content = row });
            }

            UpdateImageButtons();
        }

        private async Task DownloadImageAsync()
        {
            SystemImageInfo? image = SelectedImage;
            if (image is null || image.IsDownloaded || busy)
            {
                return;
            }

            busy = true;
            downloadCancellation = new CancellationTokenSource();
            cancelDownloadButton.IsEnabled = true;
            downloadProgress.Visibility = Visibility.Visible;
            downloadProgress.Value = 0;
            SetStatus("Downloading", image.DisplayName, InfoBarSeverity.Informational);
            try
            {
                double last = -1;
                await Task.Run(() => EmulatorService.DownloadImage(
                    image.Id,
                    progress =>
                    {
                        if (Math.Abs(progress - last) < 0.01)
                        {
                            return;
                        }
                        last = progress;
                        DispatcherQueue.TryEnqueue(() =>
                        {
                            downloadProgress.Value = Math.Clamp(progress * 100, 0, 100);
                            SetStatus("Downloading", $"{image.DisplayName} — {progress:P0}", InfoBarSeverity.Informational);
                        });
                    },
                    downloadCancellation.Token));
                busy = false;
                await RefreshImagesAsync();
                await RefreshAvdsAsync();
            }
            catch (OperationCanceledException)
            {
                SetStatus("Download cancelled", image.DisplayName, InfoBarSeverity.Warning);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not download image", ex.Message);
            }
            finally
            {
                busy = false;
                downloadCancellation?.Dispose();
                downloadCancellation = null;
                cancelDownloadButton.IsEnabled = false;
                downloadProgress.Visibility = Visibility.Collapsed;
                UpdateImageButtons();
            }
        }

        private async Task DeleteImageAsync()
        {
            SystemImageInfo? image = SelectedImage;
            if (image is null || !image.IsDownloaded || busy)
            {
                return;
            }

            if (!await Ui.ConfirmAsync("Delete system image", $"Delete {image.DisplayName}?", "Delete"))
            {
                return;
            }

            busy = true;
            try
            {
                await Task.Run(() => EmulatorService.DeleteImage(image.Id));
                busy = false;
                await RefreshImagesAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not delete image", ex.Message);
            }
            finally
            {
                busy = false;
                UpdateImageButtons();
            }
        }

        private void SetStatus(string title, string message, InfoBarSeverity severity)
        {
            status.IsOpen = true;
            status.Title = title;
            status.Message = message;
            status.Severity = severity;
        }

        private static string? NullIfEmpty(string value)
        {
            return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
        }
    }
}
