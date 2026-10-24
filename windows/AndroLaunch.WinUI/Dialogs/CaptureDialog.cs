using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.System;
using WinRT.Interop;

namespace AndroLaunch.WinUI.Dialogs;

public static class CaptureDialog
{
    private static bool showing;

    public static async Task ShowAsync(string serial)
    {
        if (showing) return;
        showing = true;
        try { await ShowCoreAsync(serial); }
        finally { showing = false; }
    }

    private static async Task ShowCoreAsync(string serial)
    {
        var folder = new TextBlock { Text = QuickAccessStore.CaptureDirectory, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var prefix = new TextBox { Header = "Filename prefix", Text = QuickAccessStore.CapturePrefix, MaxLength = 80 };
        var chooseFolder = new Button { Content = "Choose save folder…" };
        var screenshot = new Button { Content = "Take screenshot" };
        var record = new Button { Content = "Start recording" };
        var stop = new Button { Content = "Stop and save recording", IsEnabled = false };
        var cancel = new Button { Content = "Cancel screenshot", Visibility = Visibility.Collapsed };
        var open = new Button { Content = "Open saved capture", IsEnabled = false };
        var copy = new Button { Content = "Copy screenshot", IsEnabled = false };
        var reveal = new Button { Content = "Show in folder", IsEnabled = false };
        var progress = new ProgressRing { Width = 20, Height = 20, IsActive = false, HorizontalAlignment = HorizontalAlignment.Left };
        var message = new InfoBar { IsClosable = false, IsOpen = true, Title = "Ready to capture", Message = "Screenshots save as PNG. Recording opens a scrcpy window; stop here or close that window to finalize the MP4. Protected content may not be captured.", Severity = InfoBarSeverity.Informational };
        var recordingState = new TextBlock { TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetLiveSetting(recordingState, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
        var body = new StackPanel { Spacing = 12, MinWidth = 420, MaxWidth = 600 };
        body.Children.Add(new TextBlock { Text = $"Target device: {serial}", TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        body.Children.Add(new TextBlock { Text = "Save captures to", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        body.Children.Add(folder);
        body.Children.Add(chooseFolder);
        body.Children.Add(prefix);
        body.Children.Add(new TextBlock { Text = "A timestamp and unique suffix are appended automatically. Recording uses your mirroring quality settings and never enables clipboard sharing.", TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        var actions = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, MaximumRowsOrColumns = 2 };
        foreach (var button in new[] { screenshot, record, stop, cancel, open, copy, reveal })
        {
            button.Margin = new Thickness(0, 0, 8, 8);
            actions.Children.Add(button);
        }
        body.Children.Add(actions);
        body.Children.Add(recordingState);
        body.Children.Add(progress);
        body.Children.Add(message);
        var dialog = new ContentDialog
        {
            Title = "Capture screen", Content = new ScrollViewer { Content = body, MaxHeight = 600 }, CloseButtonText = "Done",
            DefaultButton = ContentDialogButton.Close, XamlRoot = App.MainWindowInstance.Content.XamlRoot
        };
        bool busy = false;
        string? savedPath = null;
        CaptureService.RecordingSession? session = null;
        using var screenshotCancellation = new CancellationTokenSource();
        CancellationTokenSource? currentShot = null;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };

        void Update()
        {
            bool recording = session?.IsRunning == true;
            screenshot.IsEnabled = record.IsEnabled = chooseFolder.IsEnabled = prefix.IsEnabled = !busy && !recording;
            stop.IsEnabled = recording && !busy;
            open.IsEnabled = reveal.IsEnabled = !busy && savedPath is not null;
            copy.IsEnabled = !busy && savedPath?.EndsWith(".png", StringComparison.OrdinalIgnoreCase) == true;
            progress.IsActive = busy;
            recordingState.Text = recording ? $"Recording session active • {(DateTimeOffset.Now - session!.StartedAt):mm\\:ss} • {session.Path}" : "";
        }
        void Status(string title, string detail, InfoBarSeverity severity)
        {
            message.Title = title; message.Message = detail; message.Severity = severity; message.IsOpen = true;
        }
        void SavePreferences() => QuickAccessStore.SetCapturePreferences(folder.Text, prefix.Text);
        async Task GuardAsync(Func<Task> action)
        {
            if (busy) return;
            busy = true; Update();
            try { await action(); }
            catch (OperationCanceledException) { Status("Screenshot cancelled", "No incomplete screenshot was saved.", InfoBarSeverity.Informational); }
            catch (Exception ex) { Status("Capture needs attention", ex.Message, InfoBarSeverity.Error); }
            finally { busy = false; Update(); }
        }
        async Task ObserveRecordingAsync(CaptureService.RecordingSession recording)
        {
            try
            {
                await recording.Completion;
                savedPath = recording.Path;
                Status("Recording saved", savedPath, InfoBarSeverity.Success);
            }
            catch (Exception ex) { Status("Recording needs attention", ex.Message, InfoBarSeverity.Error); }
            finally { timer.Stop(); Update(); }
        }
        timer.Tick += (_, _) => Update();
        chooseFolder.Click += async (_, _) => await GuardAsync(async () =>
        {
            var picker = new FolderPicker();
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, App.MainWindowInstance.WindowHandle);
            StorageFolder? selected = await picker.PickSingleFolderAsync();
            if (selected is not null) { folder.Text = selected.Path; SavePreferences(); }
        });
        screenshot.Click += async (_, _) => await GuardAsync(async () =>
        {
            SavePreferences();
            currentShot = CancellationTokenSource.CreateLinkedTokenSource(screenshotCancellation.Token);
            cancel.Visibility = Visibility.Visible;
            Status("Capturing screenshot", "Keep the device connected while the image is saved.", InfoBarSeverity.Informational);
            try
            {
                savedPath = await CaptureService.ScreenshotAsync(serial, currentShot.Token);
                Status("Screenshot saved", savedPath, InfoBarSeverity.Success);
            }
            finally { currentShot.Dispose(); currentShot = null; cancel.Visibility = Visibility.Collapsed; }
        });
        cancel.Click += (_, _) => currentShot?.Cancel();
        record.Click += async (_, _) => await GuardAsync(async () =>
        {
            SavePreferences();
            session = await CaptureService.StartRecordingAsync(serial);
            Status("Recording session started", "Use Stop and save recording, or close the scrcpy recording window. The file is ready only after the recorder exits.", InfoBarSeverity.Informational);
            timer.Start();
            _ = ObserveRecordingAsync(session);
        });
        stop.Click += async (_, _) => await GuardAsync(async () =>
        {
            if (session is not null) await session.StopAsync();
        });
        open.Click += async (_, _) => await GuardAsync(async () =>
        {
            if (savedPath is not null && !await Launcher.LaunchFileAsync(await StorageFile.GetFileFromPathAsync(savedPath)))
                throw new IOException("Windows could not open the capture. Use Show in folder to choose an application.");
        });
        copy.Click += async (_, _) => await GuardAsync(async () =>
        {
            if (savedPath is null) return;
            var data = new DataPackage();
            data.SetBitmap(RandomAccessStreamReference.CreateFromFile(await StorageFile.GetFileFromPathAsync(savedPath)));
            Clipboard.SetContent(data);
            Status("Screenshot copied", "Paste the image into another application.", InfoBarSeverity.Success);
        });
        reveal.Click += async (_, _) => await GuardAsync(async () =>
        {
            if (savedPath is not null && !await Launcher.LaunchFolderAsync(await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(savedPath)!)))
                throw new IOException("Windows could not open the capture folder.");
        });
        dialog.Closing += (_, args) =>
        {
            if (busy || session?.IsRunning == true)
            {
                args.Cancel = true;
                Status("Finish capture before closing", "Cancel the screenshot or stop and save the recording first.", InfoBarSeverity.Warning);
            }
        };
        try { await dialog.ShowAsync(); }
        finally { timer.Stop(); screenshotCancellation.Cancel(); }
    }
}
