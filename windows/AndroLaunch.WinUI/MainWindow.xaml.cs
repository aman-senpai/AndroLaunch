using System;
using System.IO;
using Androlaunch.Core;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Input;
using AndroLaunch.WinUI.Services;
using Windows.System;
using Windows.Graphics;
using WinRT.Interop;

namespace AndroLaunch.WinUI
{
    public sealed partial class MainWindow : Window
    {
        private bool allowClose;
        private bool navigating;
        private int navigationVersion;

        public MainWindow()
        {
            InitializeComponent();
            Title = "AndroLaunch";
            SystemBackdrop = new MicaBackdrop();
            AppWindow.TitleBar.PreferredTheme = TitleBarTheme.UseDefaultAppMode;
            AppWindow.Resize(new SizeInt32(1120, 720));
            AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app_icon.ico"));
            AppWindow.Closing += AppWindow_Closing;

            RootGrid.Loaded += (_, _) =>
            {
                if (ContentFrame.Content is null) ShowPage("devices");
            };
            AddShortcut(VirtualKey.K, VirtualKeyModifiers.Control, () => Dialogs.CommandPaletteDialog.ShowAsync());
            AddShortcut(VirtualKey.Number1, VirtualKeyModifiers.Control, () => NavigateAsync("devices"));
            AddShortcut(VirtualKey.Number2, VirtualKeyModifiers.Control, () => NavigateAsync("apps"));
            AddShortcut(VirtualKey.Number3, VirtualKeyModifiers.Control, () => NavigateAsync("files"));
            AddShortcut(VirtualKey.M, VirtualKeyModifiers.Control, MirrorSelectedAsync);
            AddShortcut(VirtualKey.S, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, CaptureSelectedAsync);
        }

        public IntPtr WindowHandle => WindowNative.GetWindowHandle(this);
        internal object? CurrentPage => ContentFrame.Content;

        public void AllowClose()
        {
            allowClose = true;
        }

        private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
        {
            if (allowClose)
            {
                return;
            }

            args.Cancel = true;
            sender.Hide();
        }

        public async void ShowPage(string tag, string? serial = null)
        {
            if (tag == "onboarding")
            {
                _ = ShowOnboardingAsync();
                return;
            }
            int version = ++navigationVersion;
            if (ContentFrame.Content is Pages.FilesPage files)
            {
                try { await files.StopTransfersAsync(); }
                catch (Exception ex)
                {
                    await Ui.ShowErrorAsync("File transfers could not finish stopping", ex.Message);
                    return;
                }
            }
            if (version != navigationVersion || App.IsShuttingDown) return;

            navigating = true;
            NavigationViewItem? item = null;
            foreach (object menuItem in Nav.MenuItems.Concat(Nav.FooterMenuItems))
            {
                if (menuItem is NavigationViewItem navItem &&
                    string.Equals(navItem.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
                {
                    item = navItem;
                    break;
                }
            }

            if (item is not null)
            {
                Nav.SelectedItem = item;
            }
            navigating = false;

            if (!string.IsNullOrWhiteSpace(serial))
            {
                AppState.SelectedSerial = serial;
            }

            ContentFrame.Content = tag switch
            {
                "apps" => new Pages.AppsPage(),
                "files" => new Pages.FilesPage(),
                "emulators" => new Pages.EmulatorsPage(),
                "settings" => new Pages.SettingsPage(),
                _ => new Pages.DevicesPage()
            };
        }

        private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (navigating)
            {
                return;
            }

            if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
            {
                ShowPage(tag);
            }
        }

        private Task NavigateAsync(string page)
        {
            ShowPage(page);
            return Task.CompletedTask;
        }

        private void AddShortcut(VirtualKey key, VirtualKeyModifiers modifiers, Func<Task> action)
        {
            var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
            accelerator.Invoked += async (_, args) =>
            {
                args.Handled = true;
                if (RootGrid.XamlRoot is not null && VisualTreeHelper.GetOpenPopupsForXamlRoot(RootGrid.XamlRoot).Any()) return;
                try { await action(); }
                catch (Exception ex) { await Ui.ShowErrorAsync("Action could not complete", ex.Message); }
            };
            RootGrid.KeyboardAccelerators.Add(accelerator);
        }

        private async void QuickActions_Click(object sender, RoutedEventArgs e)
        {
            try { await Dialogs.CommandPaletteDialog.ShowAsync(); }
            catch (Exception ex) { await Ui.ShowErrorAsync("Quick actions unavailable", ex.Message); }
        }

        private async Task<string> RequireSelectedDeviceAsync()
        {
            string? serial = AppState.SelectedSerial;
            var devices = await Task.Run(AdbHelper.GetDevices);
            var device = devices.FirstOrDefault(device => device.Serial == serial && device.Status == "device");
            if (device is null) throw new InvalidOperationException("Select an authorized device on the Devices page first. Unlock your phone and approve USB debugging if prompted.");
            return device.Serial;
        }

        private async Task MirrorSelectedAsync()
        {
            string serial = await RequireSelectedDeviceAsync();
            var compatibility = await ToolCompatibility.CheckScrcpyAsync();
            if (!compatibility.IsCompatible) throw new InvalidOperationException(compatibility.Summary);
            MirrorPresetStore.Restore(serial);
            await Task.Run(() => AdbHelper.MirrorScreen(serial));
        }

        private async Task CaptureSelectedAsync() => await Dialogs.CaptureDialog.ShowAsync(await RequireSelectedDeviceAsync());

        public async System.Threading.Tasks.Task ShowMessageAsync(string title, string message)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = Content.XamlRoot,
                Title = title,
                Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
                CloseButtonText = "OK"
            };
            await dialog.ShowAsync();
        }

        public async System.Threading.Tasks.Task ShowOnboardingAsync()
        {
            if (RootGrid.XamlRoot is null)
            {
                var loaded = new System.Threading.Tasks.TaskCompletionSource<bool>();
                void OnLoaded(object sender, RoutedEventArgs args) => loaded.TrySetResult(true);
                RootGrid.Loaded += OnLoaded;
                try { await loaded.Task; }
                finally { RootGrid.Loaded -= OnLoaded; }
            }
            await Dialogs.OnboardingDialog.ShowAsync();
        }
    }
}
