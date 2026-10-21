using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace AndroLaunch.WinUI.Dialogs
{
    public static class OnboardingDialog
    {
        public static async Task ShowAsync()
        {
            var statusPanel = new StackPanel { Spacing = 10 };
            var adbStatus = StatusRow("Android Debug Bridge (adb)", "Talks to Android devices. Required for device control and app management.");
            var scrcpyStatus = StatusRow("scrcpy", "Mirrors the screen and camera. Required for mirroring and app windows.");
            statusPanel.Children.Add(adbStatus.Container);
            statusPanel.Children.Add(scrcpyStatus.Container);

            var content = new StackPanel { Spacing = 14, MinWidth = 480, MaxWidth = 620 };
            content.Children.Add(new TextBlock
            {
                Text = "AndroLaunch uses two external tools. You can install them now with winget, or skip and configure them later in Settings.",
                TextWrapping = TextWrapping.Wrap
            });
            content.Children.Add(statusPanel);
            content.Children.Add(new TextBlock
            {
                Text = "Android 11 and newer can also pair wirelessly from the tray menu after adb is installed.",
                TextWrapping = TextWrapping.Wrap,
                Opacity = 0.7
            });

            var dialog = new ContentDialog
            {
                Title = "Welcome to AndroLaunch",
                Content = new ScrollViewer { Content = content, MaxHeight = 520 },
                PrimaryButtonText = "Start using AndroLaunch",
                SecondaryButtonText = "Skip for now",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = App.MainWindowInstance.Content.XamlRoot
            };

            async Task RefreshAsync()
            {
                AdbHelper.RefreshToolPaths();
                bool adb = await Task.Run(() => AdbHelper.TestAdb(out _));
                bool scrcpy = AdbHelper.TestScrcpy(out string? path);
                adbStatus.SetState(adb, "Installed and ready", "Not found");
                scrcpyStatus.SetState(scrcpy, path ?? "Installed", "Not found");
            }

            async Task InstallAsync(DependencyRow row, string wingetId)
            {
                row.SetBusy("Installing with winget…");
                bool ok = await Task.Run(() => RunWinget(wingetId));
                await RefreshAsync();
                if (!ok)
                {
                    row.SetState(false, "Install did not complete", "Open the download page or install with Scoop/Chocolatey");
                }
            }

            await RefreshAsync();
            bool winget = await Task.Run(IsWingetAvailable);
            adbStatus.InstallButton.IsEnabled = winget;
            scrcpyStatus.InstallButton.IsEnabled = winget;
            if (winget)
            {
                adbStatus.InstallButton.Click += async (_, _) => await InstallAsync(adbStatus, "Google.PlatformTools");
                scrcpyStatus.InstallButton.Click += async (_, _) => await InstallAsync(scrcpyStatus, "Genymobile.scrcpy");
            }
            else
            {
                adbStatus.InstallButton.Content = "Open download page";
                scrcpyStatus.InstallButton.Content = "Open download page";
                adbStatus.InstallButton.IsEnabled = true;
                scrcpyStatus.InstallButton.IsEnabled = true;
                adbStatus.InstallButton.Click += async (_, _) =>
                    await Windows.System.Launcher.LaunchUriAsync(new Uri("https://developer.android.com/tools/releases/platform-tools"));
                scrcpyStatus.InstallButton.Click += async (_, _) =>
                    await Windows.System.Launcher.LaunchUriAsync(new Uri("https://github.com/Genymobile/scrcpy/releases"));
            }

            ContentDialogResult result = await dialog.ShowAsync();
            if (result is ContentDialogResult.Primary or ContentDialogResult.Secondary)
            {
                AppSettings settings = AppSettingsStore.Current;
                settings.HasCompletedOnboarding = true;
                settings.CommandLineToolsPath ??= AppSettingsStore.AutoDetectCommandLineToolsPath();
                settings.EmulatorPath ??= AppSettingsStore.AutoDetectEmulatorPath();
                AppSettingsStore.Save();
                AdbHelper.RefreshToolPaths();
            }
        }

        private sealed class DependencyRow
        {
            public StackPanel Container { get; } = new() { Spacing = 4 };
            public Button InstallButton { get; }
            private readonly TextBlock stateText;

            public DependencyRow(string title, string description)
            {
                Container.Children.Add(new TextBlock
                {
                    Text = title,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
                });
                Container.Children.Add(new TextBlock
                {
                    Text = description,
                    TextWrapping = TextWrapping.Wrap,
                    Opacity = 0.7
                });
                stateText = new TextBlock { Text = "Checking…", Opacity = 0.8 };
                Container.Children.Add(stateText);
                InstallButton = new Button
                {
                    Content = "Install with winget",
                    HorizontalAlignment = HorizontalAlignment.Left
                };
                Container.Children.Add(InstallButton);
            }

            public void SetState(bool installed, string success, string failure)
            {
                stateText.Text = installed ? success : failure;
                stateText.Foreground = installed
                    ? (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"]
                    : (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
            }

            public void SetBusy(string text)
            {
                stateText.Text = text;
                stateText.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            }
        }

        private static DependencyRow StatusRow(string title, string description)
        {
            return new DependencyRow(title, description);
        }

        private static bool IsWingetAvailable()
        {
            try
            {
                using Process? process = Process.Start(new ProcessStartInfo("winget", "--version")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                });
                if (process is null)
                {
                    return false;
                }

                process.WaitForExit(5000);
                return process.HasExited && process.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }

        private static bool RunWinget(string packageId)
        {
            try
            {
                using Process? process = Process.Start(new ProcessStartInfo(
                    "winget",
                    $"install --id {packageId} -e --silent --accept-package-agreements --accept-source-agreements")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                });
                if (process is null)
                {
                    return false;
                }

                _ = process.StandardOutput.ReadToEndAsync();
                _ = process.StandardError.ReadToEndAsync();
                process.WaitForExit(600000);
                if (!process.HasExited)
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    return false;
                }

                return process.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }
    }
}
