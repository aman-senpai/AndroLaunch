using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AndroLaunch.WinUI.Pages
{
    public sealed class FilesPage : Page
    {
        private readonly ListView fileList = new() { SelectionMode = ListViewSelectionMode.Multiple };
        private readonly ComboBox deviceCombo = new() { MinWidth = 250 };
        private readonly InfoBar status = new()
        {
            IsClosable = false,
            IsOpen = true,
            Title = "Files",
            Severity = InfoBarSeverity.Informational
        };
        private readonly StackPanel breadcrumbs = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 2,
            VerticalAlignment = VerticalAlignment.Center
        };
        private readonly ToggleSwitch showHidden = new()
        {
            Header = "Hidden",
            OnContent = "Shown",
            OffContent = "Hidden",
            Margin = new Thickness(0)
        };
        private readonly Button uploadButton = new() { Content = "Upload…" };
        private readonly Button newFolderButton = new() { Content = "New folder" };
        private readonly Button downloadButton = new() { Content = "Download…", IsEnabled = false };
        private readonly Button deleteButton = new() { Content = "Delete", IsEnabled = false };
        private readonly Button backButton = new() { Content = "Back", IsEnabled = false };
        private readonly Button upButton = new() { Content = "Up" };
        private readonly ProgressRing progress = new() { Width = 20, Height = 20, IsActive = false };

        private readonly List<string> history = new();
        private List<AndroidFile> files = new();
        private string currentPath = "/sdcard";
        private bool loading;

        public FilesPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) => await LoadDevicesAsync();
        }

        private UIElement BuildContent()
        {
            var root = new Grid { Padding = new Thickness(28), RowSpacing = 12 };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var titles = new StackPanel { Spacing = 2 };
            titles.Children.Add(new TextBlock
            {
                Text = "Files",
                FontSize = 30,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            titles.Children.Add(new TextBlock
            {
                Text = "Browse, upload and download files on the device.",
                Opacity = 0.7
            });
            header.Children.Add(titles);
            var headerRight = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            headerRight.Children.Add(deviceCombo);
            headerRight.Children.Add(progress);
            var refresh = new Button { Content = "Refresh" };
            refresh.Click += async (_, _) => await RefreshFilesAsync();
            headerRight.Children.Add(refresh);
            Grid.SetColumn(headerRight, 1);
            header.Children.Add(headerRight);
            Grid.SetRow(header, 0);
            root.Children.Add(header);

            Grid.SetRow(status, 1);
            root.Children.Add(status);

            var toolbar = new StackPanel { Spacing = 8 };
            var shortcuts = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            shortcuts.Children.Add(backButton);
            shortcuts.Children.Add(upButton);
            shortcuts.Children.Add(new FolderShortcut("Internal storage", "/sdcard", Navigate));
            shortcuts.Children.Add(new FolderShortcut("Downloads", "/sdcard/Download", Navigate));
            shortcuts.Children.Add(new FolderShortcut("DCIM", "/sdcard/DCIM", Navigate));
            shortcuts.Children.Add(new FolderShortcut("Pictures", "/sdcard/Pictures", Navigate));
            shortcuts.Children.Add(new FolderShortcut("Root", "/", Navigate));
            toolbar.Children.Add(shortcuts);
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            actions.Children.Add(uploadButton);
            actions.Children.Add(newFolderButton);
            actions.Children.Add(downloadButton);
            actions.Children.Add(deleteButton);
            actions.Children.Add(showHidden);
            toolbar.Children.Add(actions);
            Grid.SetRow(toolbar, 2);
            root.Children.Add(toolbar);

            var breadcrumbScroll = new ScrollViewer
            {
                Content = breadcrumbs,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                HorizontalScrollMode = ScrollMode.Auto
            };
            Grid.SetRow(breadcrumbScroll, 3);
            root.Children.Add(breadcrumbScroll);

            var listCard = new Border
            {
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8),
                Child = fileList,
                AllowDrop = true
            };
            fileList.SelectionChanged += (_, _) => UpdateButtons();
            fileList.DoubleTapped += async (_, _) => await OpenSelectedAsync();
            fileList.AllowDrop = true;
            fileList.DragOver += FileList_DragOver;
            fileList.Drop += FileList_Drop;
            Grid.SetRow(listCard, 4);
            root.Children.Add(listCard);

            var footer = new TextBlock
            {
                Text = "Tip: drag files into this window to upload them.",
                Opacity = 0.55,
                FontSize = 12
            };
            Grid.SetRow(footer, 5);
            root.Children.Add(footer);

            backButton.Click += (_, _) => GoBack();
            upButton.Click += (_, _) => GoUp();
            showHidden.Toggled += (_, _) => RenderFiles();
            uploadButton.Click += async (_, _) => await UploadAsync();
            newFolderButton.Click += async (_, _) => await CreateFolderAsync();
            downloadButton.Click += async (_, _) => await DownloadSelectedAsync();
            deleteButton.Click += async (_, _) => await DeleteSelectedAsync();
            deviceCombo.SelectionChanged += async (_, _) =>
            {
                if (deviceCombo.SelectedItem is ComboBoxItem item && item.Tag is string serial)
                {
                    AppState.SelectedSerial = serial;
                    currentPath = "/sdcard";
                    history.Clear();
                    await RefreshFilesAsync();
                }
            };
            return root;
        }

        private sealed class FolderShortcut : Button
        {
            public FolderShortcut(string label, string path, Action<string> navigate)
            {
                Content = label;
                Click += (_, _) => navigate(path);
            }
        }

        private void Navigate(string path)
        {
            if (loading || path == currentPath)
            {
                return;
            }

            history.Add(currentPath);
            currentPath = path;
            _ = RefreshFilesAsync();
        }

        private void GoBack()
        {
            if (loading || history.Count == 0)
            {
                return;
            }

            currentPath = history[^1];
            history.RemoveAt(history.Count - 1);
            _ = RefreshFilesAsync();
        }

        private void GoUp()
        {
            if (currentPath is "/" or "/sdcard")
            {
                return;
            }

            int index = currentPath.LastIndexOf('/');
            Navigate(index <= 0 ? "/" : currentPath[..index]);
        }

        private async Task LoadDevicesAsync()
        {
            try
            {
                List<AdbHelper.AdbDeviceInfo> devices = await Task.Run(AdbHelper.GetDevices);
                deviceCombo.Items.Clear();
                foreach (AdbHelper.AdbDeviceInfo device in devices.Where(device => device.Status == "device"))
                {
                    deviceCombo.Items.Add(new ComboBoxItem { Content = device.Name, Tag = device.Serial });
                }

                if (deviceCombo.Items.Count == 0)
                {
                    SetStatus("No devices connected", "Enable USB debugging or pair wirelessly.", InfoBarSeverity.Warning);
                    return;
                }

                int index = 0;
                for (int i = 0; i < deviceCombo.Items.Count; i++)
                {
                    if ((deviceCombo.Items[i] as ComboBoxItem)?.Tag as string == AppState.SelectedSerial)
                    {
                        index = i;
                        break;
                    }
                }
                deviceCombo.SelectedIndex = index;
                await RefreshFilesAsync();
            }
            catch (Exception ex)
            {
                SetStatus("Could not list devices", ex.Message, InfoBarSeverity.Error);
            }
        }

        private string? Serial => (deviceCombo.SelectedItem as ComboBoxItem)?.Tag as string;

        private async Task RefreshFilesAsync()
        {
            if (Serial is not string serial || loading)
            {
                return;
            }

            loading = true;
            UpdateButtons();
            progress.IsActive = true;
            SetStatus("Loading", currentPath, InfoBarSeverity.Informational);
            try
            {
                files = await Task.Run(() => AdbHelper.ListFiles(serial, currentPath));
                RenderFiles();
                SetStatus($"{files.Count} items", currentPath, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                SetStatus("Could not read folder", ex.Message, InfoBarSeverity.Error);
            }
            finally
            {
                loading = false;
                progress.IsActive = false;
                UpdateButtons();
            }
        }

        private void RenderFiles()
        {
            List<AndroidFile> display = showHidden.IsOn
                ? files
                : files.Where(file => !file.Name.StartsWith(".", StringComparison.Ordinal)).ToList();

            fileList.Items.Clear();
            foreach (AndroidFile file in display)
            {
                var row = new Grid { ColumnSpacing = 10 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });

                var namePanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                namePanel.Children.Add(new FontIcon
                {
                    Glyph = file.IsDirectory ? "\uE8B7" : "\uE7C3",
                    FontSize = 16,
                    Opacity = 0.85
                });
                namePanel.Children.Add(new TextBlock
                {
                    Text = file.Name,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    VerticalAlignment = VerticalAlignment.Center
                });
                row.Children.Add(namePanel);

                var size = new TextBlock { Text = file.FormattedSize, Opacity = 0.65, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(size, 1);
                row.Children.Add(size);
                var modified = new TextBlock { Text = file.ModificationDate ?? "—", Opacity = 0.55, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(modified, 2);
                row.Children.Add(modified);
                var kind = new TextBlock { Text = file.Kind, Opacity = 0.55, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumn(kind, 3);
                row.Children.Add(kind);

                fileList.Items.Add(new ListViewItem { Tag = file, Content = row });
            }

            RenderBreadcrumbs();
            backButton.IsEnabled = history.Count > 0;
            upButton.IsEnabled = currentPath is not "/" and not "/sdcard";
            UpdateButtons();
        }

        private void RenderBreadcrumbs()
        {
            breadcrumbs.Children.Clear();
            bool underSdcard = currentPath == "/sdcard" || currentPath.StartsWith("/sdcard/", StringComparison.Ordinal);
            var segments = new List<(string Label, string Path)>();
            if (underSdcard)
            {
                segments.Add(("Internal storage", "/sdcard"));
                string remainder = currentPath.Length > "/sdcard".Length ? currentPath["/sdcard".Length..] : "";
                string built = "/sdcard";
                foreach (string part in remainder.Split('/', StringSplitOptions.RemoveEmptyEntries))
                {
                    built += "/" + part;
                    segments.Add((part, built));
                }
            }
            else
            {
                segments.Add(("Device root", "/"));
                string built = "";
                foreach (string part in currentPath.Split('/', StringSplitOptions.RemoveEmptyEntries))
                {
                    built += "/" + part;
                    segments.Add((part, built));
                }
            }

            for (int i = 0; i < segments.Count; i++)
            {
                if (i > 0)
                {
                    breadcrumbs.Children.Add(new TextBlock
                    {
                        Text = "›",
                        Opacity = 0.45,
                        VerticalAlignment = VerticalAlignment.Center
                    });
                }

                var link = new HyperlinkButton
                {
                    Content = segments[i].Label,
                    Padding = new Thickness(4, 2, 4, 2)
                };
                string path = segments[i].Path;
                link.Click += (_, _) => Navigate(path);
                breadcrumbs.Children.Add(link);
            }
        }

        private void UpdateButtons()
        {
            deviceCombo.IsEnabled = !loading;
            fileList.IsEnabled = !loading;
            int count = fileList.SelectedItems.Count;
            downloadButton.IsEnabled = count > 0 && !loading;
            deleteButton.IsEnabled = count > 0 && !loading;
            uploadButton.IsEnabled = !loading && Serial is not null;
            newFolderButton.IsEnabled = !loading && Serial is not null;
            backButton.IsEnabled = history.Count > 0 && !loading;
            upButton.IsEnabled = currentPath is not "/" and not "/sdcard" && !loading;
        }

        private List<AndroidFile> SelectedFiles =>
            fileList.SelectedItems.Cast<ListViewItem>()
                .Select(item => item.Tag as AndroidFile)
                .Where(file => file is not null)
                .Cast<AndroidFile>()
                .ToList();

        private async Task OpenSelectedAsync()
        {
            List<AndroidFile> selected = SelectedFiles;
            if (selected.Count != 1 || Serial is not string serial)
            {
                return;
            }

            AndroidFile file = selected[0];
            if (file.IsDirectory)
            {
                Navigate(file.Path);
                return;
            }

            try
            {
                progress.IsActive = true;
                string directory = Path.Combine(Path.GetTempPath(), "AndroLaunch", "files");
                Directory.CreateDirectory(directory);
                string localPath = Path.Combine(directory, SafeLocalName(file.Name));
                await Task.Run(() => AdbHelper.PullFile(serial, file.Path, localPath));
                Process.Start(new ProcessStartInfo(localPath) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not open file", ex.Message);
            }
            finally
            {
                progress.IsActive = false;
            }
        }

        private async Task UploadAsync()
        {
            if (Serial is not string serial)
            {
                return;
            }

            var picker = new FileOpenPicker
            {
                SuggestedStartLocation = PickerLocationId.Downloads,
                ViewMode = PickerViewMode.List
            };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            IReadOnlyList<StorageFile> selected = await picker.PickMultipleFilesAsync();
            if (selected.Count == 0)
            {
                return;
            }

            await PushFilesAsync(serial, selected.Select(file => file.Path).Where(path => !string.IsNullOrWhiteSpace(path)));
        }

        private async Task PushFilesAsync(string serial, IEnumerable<string> localPaths)
        {
            string[] paths = localPaths.ToArray();
            if (paths.Length == 0)
            {
                return;
            }

            try
            {
                progress.IsActive = true;
                SetStatus("Uploading", $"{paths.Length} file(s)", InfoBarSeverity.Informational);
                foreach (string localPath in paths)
                {
                    string remotePath = currentPath.TrimEnd('/') + "/" + Path.GetFileName(localPath);
                    await Task.Run(() => AdbHelper.PushFile(serial, localPath, remotePath));
                }
                await RefreshFilesAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not upload files", ex.Message);
            }
            finally
            {
                progress.IsActive = false;
            }
        }

        private async Task DownloadSelectedAsync()
        {
            if (Serial is not string serial)
            {
                return;
            }

            List<AndroidFile> selected = SelectedFiles;
            if (selected.Count == 0)
            {
                return;
            }

            var picker = new FolderPicker
            {
                SuggestedStartLocation = PickerLocationId.Downloads
            };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            StorageFolder? folder = await picker.PickSingleFolderAsync();
            if (folder is null)
            {
                return;
            }

            try
            {
                progress.IsActive = true;
                SetStatus("Downloading", $"{selected.Count} item(s)", InfoBarSeverity.Informational);
                foreach (AndroidFile file in selected)
                {
                    string localPath = Path.Combine(folder.Path, SafeLocalName(file.Name));
                    await Task.Run(() => AdbHelper.PullFile(serial, file.Path, localPath));
                }
                SetStatus("Downloaded", folder.Path, InfoBarSeverity.Success);
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not download files", ex.Message);
            }
            finally
            {
                progress.IsActive = false;
            }
        }

        private async Task DeleteSelectedAsync()
        {
            if (Serial is not string serial)
            {
                return;
            }

            List<AndroidFile> selected = SelectedFiles;
            if (selected.Count == 0)
            {
                return;
            }

            string message = selected.Count == 1
                ? $"Delete “{selected[0].Name}”? This cannot be undone."
                : $"Delete {selected.Count} items? This cannot be undone.";
            if (!await Ui.ConfirmAsync("Delete", message, "Delete"))
            {
                return;
            }

            try
            {
                progress.IsActive = true;
                foreach (AndroidFile file in selected)
                {
                    await Task.Run(() => AdbHelper.DeleteFile(serial, file.Path));
                }
                await RefreshFilesAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not delete files", ex.Message);
            }
            finally
            {
                progress.IsActive = false;
            }
        }

        private async Task CreateFolderAsync()
        {
            if (Serial is not string serial)
            {
                return;
            }

            string? name = await Ui.PromptAsync("New folder", "Folder name", "New folder");
            if (string.IsNullOrWhiteSpace(name))
            {
                return;
            }

            try
            {
                await Task.Run(() => AdbHelper.CreateDirectory(serial, currentPath.TrimEnd('/') + "/" + name));
                await RefreshFilesAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not create folder", ex.Message);
            }
        }

        private void FileList_DragOver(object sender, DragEventArgs e)
        {
            if (e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                e.AcceptedOperation = DataPackageOperation.Copy;
            }
        }

        private async void FileList_Drop(object sender, DragEventArgs e)
        {
            if (Serial is not string serial || !e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                return;
            }

            IReadOnlyList<IStorageItem> items = await e.DataView.GetStorageItemsAsync();
            await PushFilesAsync(serial, items.OfType<StorageFile>().Select(file => file.Path));
        }

        private void SetStatus(string title, string message, InfoBarSeverity severity)
        {
            status.IsOpen = true;
            status.Title = title;
            status.Message = message;
            status.Severity = severity;
        }

        private static string SafeLocalName(string name)
        {
            foreach (char invalid in Path.GetInvalidFileNameChars())
            {
                name = name.Replace(invalid, '_');
            }

            name = name.Trim();
            return string.IsNullOrWhiteSpace(name) ? "file" : name;
        }
    }
}
