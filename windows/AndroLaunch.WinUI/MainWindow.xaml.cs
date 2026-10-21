using System;
using System.IO;
using Androlaunch.Core;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;

namespace AndroLaunch.WinUI
{
    public sealed partial class MainWindow : Window
    {
        private bool allowClose;
        private bool navigating;

        public MainWindow()
        {
            InitializeComponent();
            Title = "AndroLaunch";
            SystemBackdrop = new MicaBackdrop();
            AppWindow.Resize(new SizeInt32(1120, 720));
            AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "app_icon.ico"));
            AppWindow.Closing += AppWindow_Closing;

            RootGrid.Loaded += (_, _) => ShowPage("devices");
        }

        public IntPtr WindowHandle => WindowNative.GetWindowHandle(this);

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

        public void ShowPage(string tag, string? serial = null)
        {
            if (tag == "onboarding")
            {
                _ = ShowOnboardingAsync();
                return;
            }

            navigating = true;
            NavigationViewItem? item = null;
            foreach (object menuItem in Nav.MenuItems)
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
