using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation;
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
        private readonly Button refreshButton = new() { Content = "Refresh" };
        private readonly Button uploadFolderButton = new() { Content = "Upload folder…" };
        private readonly Button cancelButton = new() { Content = "Cancel transfers", IsEnabled = false };
        private readonly Button retryButton = new() { Content = "Retry failed", IsEnabled = false };
        private readonly Button revealButton = new() { Content = "Show download folder", IsEnabled = false };
        private readonly StackPanel transferRows = new() { Spacing = 8 };
        private readonly ProgressBar transferProgress = new() { Minimum = 0, Maximum = 100, Visibility = Visibility.Collapsed };
        private readonly List<FileTransferItem> transferQueue = new();
        private readonly Dictionary<FileTransferItem, TextBlock> transferLabels = new();
        private readonly FileTransferService transferService = new();
        private CancellationTokenSource? transferCancellation;
        private Task transferTask = Task.CompletedTask;
        private ContentDialog? conflictDialog;
        private string? downloadFolder;
        private bool commandBusy;
        private bool transferring;
        private bool pageActive;
        private bool refreshAfterCommand;
        private bool preserveTransferSummary;
        private bool IsBusy => loading || commandBusy || transferring;

        private readonly List<string> history = new();
        private List<AndroidFile> files = new();
        private string currentPath = "/sdcard";
        private bool loading;

        public FilesPage()
        {
            Content = BuildContent();
            Loaded += async (_, _) =>
            {
                pageActive = true;
                foreach (FileTransferItem item in transferQueue) UpdateTransferRow(item);
                if (!IsBusy) await LoadDevicesAsync();
            };
            Unloaded += async (_, _) => await StopTransfersAsync();
        }

        public async Task StopTransfersAsync()
        {
            pageActive = false;
            transferCancellation?.Cancel();
            conflictDialog?.Hide();
            await transferTask;
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
            refreshButton.Click += async (_, _) => await RefreshFilesAsync();
            headerRight.Children.Add(refreshButton);
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
            toolbar.Children.Add(HorizontalScroll(shortcuts));
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            actions.Children.Add(uploadButton);
            actions.Children.Add(newFolderButton);
            actions.Children.Add(uploadFolderButton);
            actions.Children.Add(downloadButton);
            actions.Children.Add(deleteButton);
            actions.Children.Add(showHidden);
            toolbar.Children.Add(HorizontalScroll(actions));
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
            fileList.DoubleTapped += async (_, _) => await RunExclusiveAsync(OpenSelectedAsync);
            fileList.AllowDrop = true;
            fileList.DragOver += FileList_DragOver;
            fileList.Drop += FileList_Drop;
            Grid.SetRow(listCard, 4);
            root.Children.Add(listCard);

            var footer = new StackPanel { Spacing = 8 };
            var transferActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            transferActions.Children.Add(cancelButton);
            transferActions.Children.Add(retryButton);
            transferActions.Children.Add(revealButton);
            footer.Children.Add(transferActions);
            footer.Children.Add(transferProgress);
            footer.Children.Add(new ScrollViewer
            {
                Content = transferRows,
                MaxHeight = 180,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            });
            footer.Children.Add(new TextBlock
            {
                Text = "Drag files or folders here to upload. Leaving this page cancels active transfers. Completed items are kept.",
                TextWrapping = TextWrapping.Wrap,
                Opacity = 0.65,
                FontSize = 12
            });
            Grid.SetRow(footer, 5);
            root.Children.Add(footer);

            backButton.Click += (_, _) => GoBack();
            upButton.Click += (_, _) => GoUp();
            showHidden.Toggled += (_, _) => RenderFiles();
            uploadButton.Click += async (_, _) => await RunExclusiveAsync(UploadAsync);
            uploadFolderButton.Click += async (_, _) => await RunExclusiveAsync(UploadFolderAsync);
            newFolderButton.Click += async (_, _) => await RunExclusiveAsync(CreateFolderAsync);
            downloadButton.Click += async (_, _) => await RunExclusiveAsync(DownloadSelectedAsync);
            deleteButton.Click += async (_, _) => await RunExclusiveAsync(DeleteSelectedAsync);
            cancelButton.Click += (_, _) =>
            {
                cancelButton.IsEnabled = false;
                transferCancellation?.Cancel();
                conflictDialog?.Hide();
            };
            retryButton.Click += async (_, _) => await RunExclusiveAsync(RetryFailedAsync);
            revealButton.Click += async (_, _) =>
            {
                try
                {
                    if (downloadFolder is string path && Directory.Exists(path))
                        await Windows.System.Launcher.LaunchFolderAsync(await StorageFolder.GetFolderFromPathAsync(path));
                }
                catch (Exception ex) { await Ui.ShowErrorAsync("Could not show folder", ex.Message); }
            };
            AutomationProperties.SetName(fileList, "Device files; select multiple items to download or delete");
            AutomationProperties.SetName(deviceCombo, "File browser device");
            AutomationProperties.SetName(transferProgress, "Current item transfer progress");
            deviceCombo.SelectionChanged += async (_, _) =>
            {
                if (IsBusy || !pageActive) return;
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
            if (IsBusy || !pageActive || path == currentPath)
            {
                return;
            }

            history.Add(currentPath);
            currentPath = path;
            _ = RefreshFilesAsync();
        }

        private void GoBack()
        {
            if (IsBusy || !pageActive || history.Count == 0)
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
            if (Serial is not string serial || IsBusy || !pageActive)
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
            bool available = !IsBusy && pageActive;
            deviceCombo.IsEnabled = available;
            fileList.IsEnabled = available;
            refreshButton.IsEnabled = available;
            showHidden.IsEnabled = available;
            breadcrumbs.IsHitTestVisible = available;
            int count = fileList.SelectedItems.Count;
            downloadButton.IsEnabled = count > 0 && available;
            deleteButton.IsEnabled = count > 0 && available;
            uploadButton.IsEnabled = available && Serial is not null;
            uploadFolderButton.IsEnabled = available && Serial is not null;
            newFolderButton.IsEnabled = available && Serial is not null;
            backButton.IsEnabled = history.Count > 0 && available;
            upButton.IsEnabled = currentPath is not "/" and not "/sdcard" && available;
            cancelButton.IsEnabled = transferring && transferCancellation?.IsCancellationRequested == false;
            retryButton.IsEnabled = available && transferQueue.Any(item => item.State == TransferState.Failed);
            revealButton.IsEnabled = downloadFolder is not null;
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
                history.Add(currentPath);
                currentPath = file.Path;
                refreshAfterCommand = true;
                return;
            }

            string directory = Path.Combine(Path.GetTempPath(), "AndroLaunch", "files", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            downloadFolder = directory;
            string localPath = Path.Combine(directory, SafeLocalName(file.Name));
            var item = DownloadItem(serial, file, localPath);
            await RunQueueAsync(new[] { item }, true);
            if (item.State == TransferState.Completed && pageActive)
                Process.Start(new ProcessStartInfo(localPath) { UseShellExecute = true });
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
            var items = new List<FileTransferItem>();
            foreach (string path in localPaths.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                bool directory = Directory.Exists(path);
                var item = new FileTransferItem
                {
                    Serial = serial,
                    Source = path,
                    Destination = currentPath.TrimEnd('/') + "/" + Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar)),
                    Upload = true,
                    IsDirectory = directory,
                    TotalBytes = null
                };
                items.Add(item);
            }
            if (items.Count == 0 || !pageActive) return;
            await RunQueueAsync(items, true);
            refreshAfterCommand = true;
        }

        private async Task UploadFolderAsync()
        {
            if (Serial is not string serial) return;
            StorageFolder? folder = await PickFolderAsync();
            if (folder is not null && pageActive) await PushFilesAsync(serial, new[] { folder.Path });
        }

        private static async Task<StorageFolder?> PickFolderAsync()
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.Downloads };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            return await picker.PickSingleFolderAsync();
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

            StorageFolder? folder = await PickFolderAsync();
            if (folder is null || !pageActive) return;
            downloadFolder = folder.Path;
            await RunQueueAsync(selected.Select(file =>
                DownloadItem(serial, file, Path.Combine(folder.Path, SafeLocalName(file.Name)))).ToArray(), true);
        }

        private static FileTransferItem DownloadItem(string serial, AndroidFile file, string destination) => new()
        {
            Serial = serial,
            Source = file.Path,
            Destination = destination,
            Upload = false,
            IsDirectory = file.IsDirectory,
            TotalBytes = file.IsDirectory ? null : file.Size
        };

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
                ? $"Delete “{selected[0].Name}” from {DeviceIdentity(serial)} at {selected[0].Path}? This cannot be undone."
                : $"Delete {selected.Count} items from {DeviceIdentity(serial)} in {currentPath}?\n{string.Join("\n", selected.Select(file => file.Name))}\nThis cannot be undone.";
            if (!await Ui.ConfirmAsync("Delete", message, "Delete"))
            {
                return;
            }
            if (!pageActive) return;

            try
            {
                progress.IsActive = true;
                foreach (AndroidFile file in selected)
                {
                    if (!pageActive) break;
                    await FileTransferService.DeleteRemoteAsync(serial, file.Path, CancellationToken.None);
                }
                refreshAfterCommand = true;
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
            if (!pageActive) return;
            if (!FileTransferService.ValidName(name, true))
            {
                await Ui.ShowErrorAsync("Invalid folder name", "Enter a single folder name, without slashes.");
                return;
            }

            try
            {
                await FileTransferService.CreateDirectoryAsync(serial, currentPath.TrimEnd('/') + "/" + name, CancellationToken.None);
                refreshAfterCommand = true;
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Could not create folder", ex.Message);
            }
        }

        private void FileList_DragOver(object sender, DragEventArgs e)
        {
            if (!IsBusy && pageActive && e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                e.AcceptedOperation = DataPackageOperation.Copy;
            }
        }

        private async void FileList_Drop(object sender, DragEventArgs e)
        {
            if (IsBusy || !pageActive || Serial is not string serial || !e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                return;
            }

            await RunExclusiveAsync(async () =>
            {
                IReadOnlyList<IStorageItem> items = await e.DataView.GetStorageItemsAsync();
                await PushFilesAsync(serial, items.Select(item => item.Path).Where(path => !string.IsNullOrWhiteSpace(path)));
            });
        }

        private async Task RunExclusiveAsync(Func<Task> command)
        {
            if (IsBusy || !pageActive) return;
            commandBusy = true;
            preserveTransferSummary = false;
            UpdateButtons();
            try { await command(); }
            catch (Exception ex)
            {
                if (pageActive) await Ui.ShowErrorAsync("File operation failed", ex.Message);
            }
            finally
            {
                commandBusy = false;
                progress.IsActive = false;
                if (refreshAfterCommand && pageActive)
                {
                    refreshAfterCommand = false;
                    string title = status.Title, message = status.Message;
                    InfoBarSeverity severity = status.Severity;
                    await RefreshFilesAsync();
                    if (preserveTransferSummary) SetStatus(title, message, severity);
                }
                UpdateButtons();
            }
        }

        private async Task RetryFailedAsync()
        {
            FileTransferItem[] failed = transferQueue.Where(item => item.State == TransferState.Failed).ToArray();
            if (failed.Length == 0) return;
            foreach (FileTransferItem item in failed)
            {
                item.State = TransferState.Queued;
                item.Message = "Waiting to retry";
                item.Progress = null;
            }
            await RunQueueAsync(failed, false);
            refreshAfterCommand = failed.Any(item => item.Upload);
        }

        private async Task RunQueueAsync(IReadOnlyList<FileTransferItem> items, bool replaceQueue)
        {
            if (!pageActive) return;
            preserveTransferSummary = true;
            if (replaceQueue)
            {
                transferQueue.Clear();
                transferLabels.Clear();
                transferRows.Children.Clear();
                transferQueue.AddRange(items);
                foreach (FileTransferItem item in items)
                {
                    var label = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
                    transferLabels.Add(item, label);
                    transferRows.Children.Add(label);
                    UpdateTransferRow(item);
                }
            }
            transferring = true;
            using var cancellation = new CancellationTokenSource();
            transferCancellation = cancellation;
            progress.IsActive = true;
            transferProgress.Visibility = Visibility.Visible;
            transferProgress.IsIndeterminate = true;
            UpdateButtons();
            SetStatus("Transferring", $"Device {items.FirstOrDefault()?.Serial}. Cancel stops the current item and remaining queue; completed items are kept.", InfoBarSeverity.Informational);
            try
            {
                // A failed item does not abort the remaining queue.
                transferTask = transferService.RunAsync(items.Where(item => item.State == TransferState.Queued).ToArray(),
                    ResolveConflictAsync, item =>
                    {
                        if (DispatcherQueue.HasThreadAccess) UpdateTransferRow(item);
                        else DispatcherQueue.TryEnqueue(() => UpdateTransferRow(item));
                    }, cancellation.Token);
                await transferTask;
            }
            finally
            {
                transferring = false;
                transferCancellation = null;
                progress.IsActive = false;
                transferProgress.Visibility = Visibility.Collapsed;
                int completed = transferQueue.Count(item => item.State == TransferState.Completed);
                int failed = transferQueue.Count(item => item.State == TransferState.Failed);
                int skipped = transferQueue.Count(item => item.State == TransferState.Skipped);
                int cancelled = transferQueue.Count(item => item.State == TransferState.Cancelled);
                SetStatus(failed > 0 ? "Transfer queue finished with errors" : cancelled > 0 ? "Transfer queue cancelled" : "Transfer queue finished",
                    $"{completed} completed · {failed} failed · {skipped} skipped · {cancelled} cancelled. " +
                    "Completed items are kept. Failed items can be retried; skipped and cancelled items are not retried. " +
                    (downloadFolder is null || !transferQueue.Any(item => !item.Upload) ? "" : $"Download folder: {downloadFolder}"),
                    failed > 0 || cancelled > 0 ? InfoBarSeverity.Warning : InfoBarSeverity.Success);
                UpdateButtons();
            }
        }

        private void UpdateTransferRow(FileTransferItem item)
        {
            if (!pageActive || !transferLabels.TryGetValue(item, out TextBlock? label)) return;
            string detail = item.Message;
            TransferProgress? value = item.Progress;
            if (item.State == TransferState.Transferring && value is not null)
            {
                if (value.Bytes is long bytes)
                {
                    detail = FormatBytes(bytes) + (value.TotalBytes is long total ? $" / {FormatBytes(total)}" : " transferred");
                    if (value.BytesPerSecond is > 0) detail += $" · {FormatBytes(value.BytesPerSecond.Value)}/s";
                    if (value.Remaining is TimeSpan eta) detail += $" · about {Math.Ceiling(eta.TotalSeconds):0}s remaining";
                }
                else if (value.AdbPercent is int percent) detail = $"adb reports {percent}%";
                double? percentValue = value.TotalBytes is > 0 && value.Bytes is long count
                    ? Math.Clamp(100.0 * count / value.TotalBytes.Value, 0, 100)
                    : value.AdbPercent;
                transferProgress.IsIndeterminate = percentValue is null;
                if (percentValue is double number) transferProgress.Value = number;
            }
            else if (item.State == TransferState.Transferring) transferProgress.IsIndeterminate = true;
            label.Text = $"{(item.Upload ? "Upload" : "Download")} · {item.Source}\n→ {item.Destination}\n{item.State}: {detail}";
            AutomationProperties.SetName(label, label.Text);
        }

        private async Task<TransferConflictDecision> ResolveConflictAsync(TransferConflict conflict)
        {
            if (!pageActive || transferCancellation?.IsCancellationRequested != false)
                return new(TransferConflictChoice.Skip);
            var name = new TextBox
            {
                Header = "New name (used only for Rename)",
                Text = conflict.Upload ? conflict.Destination[(conflict.Destination.LastIndexOf('/') + 1)..] : Path.GetFileName(conflict.Destination)
            };
            var error = new TextBlock { TextWrapping = TextWrapping.Wrap };
            var panel = new StackPanel { Spacing = 10, MaxWidth = 480 };
            panel.Children.Add(new TextBlock
            {
                Text = $"A destination already exists on {(conflict.Upload ? DeviceIdentity(conflict.Serial) : "this computer")}:\n{conflict.Destination}\n\n" +
                    "Overwrite replaces the entire existing file or folder after the transfer succeeds. Folder contents are replaced, not merged. This cannot be undone. Skip leaves it unchanged. Rename uses a different name.",
                TextWrapping = TextWrapping.Wrap
            });
            panel.Children.Add(name);
            panel.Children.Add(error);
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Destination conflict",
                Content = panel,
                PrimaryButtonText = "Overwrite",
                SecondaryButtonText = "Rename",
                CloseButtonText = "Skip",
                DefaultButton = ContentDialogButton.Close
            };
            dialog.SecondaryButtonClick += (_, args) =>
            {
                if (!FileTransferService.ValidName(name.Text, conflict.Upload))
                {
                    args.Cancel = true;
                    error.Text = "Enter a valid single file or folder name, without path separators.";
                }
            };
            conflictDialog = dialog;
            try
            {
                ContentDialogResult result = await dialog.ShowAsync();
                return result switch
                {
                    ContentDialogResult.Primary => new(TransferConflictChoice.Overwrite),
                    ContentDialogResult.Secondary => new(TransferConflictChoice.Rename, name.Text),
                    _ => new(TransferConflictChoice.Skip)
                };
            }
            finally { conflictDialog = null; }
        }

        private string DeviceIdentity(string serial)
        {
            string? name = deviceCombo.Items.OfType<ComboBoxItem>()
                .FirstOrDefault(item => item.Tag as string == serial)?.Content?.ToString();
            return string.IsNullOrWhiteSpace(name) || name == serial ? serial : $"{name} ({serial})";
        }

        private static string FormatBytes(double bytes)
        {
            string[] units = { "B", "KiB", "MiB", "GiB", "TiB" };
            int unit = 0;
            while (bytes >= 1024 && unit < units.Length - 1) { bytes /= 1024; unit++; }
            return $"{bytes:0.#} {units[unit]}";
        }

        private static ScrollViewer HorizontalScroll(UIElement content) => new()
        {
            Content = content,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollMode = ScrollMode.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollMode = ScrollMode.Disabled
        };

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

            name = name.Trim().TrimEnd('.');
            if (string.IsNullOrWhiteSpace(name)) return "file";
            return FileTransferService.ValidName(name, false) ? name : "_" + name;
        }
    }
}
