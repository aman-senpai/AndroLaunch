using System;
using System.Runtime.InteropServices;
using System.Threading;
using Androlaunch.Core;
using AndroLaunch.WinUI.Tray;
using Microsoft.UI.Xaml;

namespace AndroLaunch.WinUI
{
    public partial class App : Application
    {
        public static App Instance { get; private set; } = null!;
        public static MainWindow MainWindowInstance { get; private set; } = null!;
        public static TrayIconService? TrayIcon { get; private set; }
        public static bool IsShuttingDown { get; private set; }

        private Mutex? instanceMutex;
        public App()
        {
            InitializeComponent();
            Instance = this;
            UnhandledException += (_, e) =>
            {
                e.Handled = true;
                ShowError("Unexpected error", e.Exception.Message);
            };
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            instanceMutex = new Mutex(true, @"Local\AndroLaunch.WinUI", out bool firstInstance);
            if (!firstInstance)
            {
                IntPtr existing = FindWindow("WinUIDesktopWin32WindowClass", "AndroLaunch");
                if (existing != IntPtr.Zero)
                {
                    ShowWindow(existing, 9);
                    SetForegroundWindow(existing);
                }
                instanceMutex.Dispose();
                instanceMutex = null;
                Exit();
                return;
            }
            AdbHelper.RefreshToolPaths();
            MainWindowInstance = new MainWindow();
            MainWindowInstance.AppWindow.Hide();

            TrayIcon = new TrayIconService(ShowTrayMenu);
            TrayIcon.Initialize();

            if (!AppSettingsStore.Current.HasCompletedOnboarding)
            {
                ShowMainWindow("devices");
                _ = MainWindowInstance.ShowOnboardingAsync();
            }
        }

        private static void ShowTrayMenu()
        {
            TrayMenuWindow.ShowAtCursor();
        }

        public static void ShowMainWindow(string page = "devices", string? serial = null)
        {
            MainWindowInstance.ShowPage(page, serial);
            MainWindowInstance.Activate();
            MainWindowInstance.AppWindow.Show();
        }

        public static void ShowError(string title, string message)
        {
            try
            {
                _ = MainWindowInstance.ShowMessageAsync(title, message);
            }
            catch
            {
                // The tray runs even if the window cannot be shown.
            }
        }

        public static void Shutdown()
        {
            if (IsShuttingDown)
            {
                return;
            }

            IsShuttingDown = true;
            ClipboardSyncService.Dispose();
            TrayIcon?.Dispose();
            TrayIcon = null;
            MainWindowInstance.AllowClose();
            MainWindowInstance.Close();
            Instance.instanceMutex?.Dispose();
            Instance.Exit();
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string windowName);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr window, int command);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);
    }
}
