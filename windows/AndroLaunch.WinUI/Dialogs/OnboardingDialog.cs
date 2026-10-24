using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace AndroLaunch.WinUI.Dialogs
{
    public static class OnboardingDialog
    {
        private static bool showing;

        public static async Task ShowAsync()
        {
            if (showing) return;
            showing = true;
            try
            {
                await new SetupSession().ShowAsync();
            }
            finally
            {
                showing = false;
            }
        }

        private sealed class SetupSession
        {
            private readonly DependencyRow adb = new("Android Debug Bridge (adb)", "Required to connect and manage a real Android device.");
            private readonly DependencyRow scrcpy = new("scrcpy 4.0 or newer", "Required for screen mirroring, cameras and app windows.");
            private readonly ComboBox devices = new()
            {
                Header = "Connected devices",
                PlaceholderText = "Refresh after connecting your device",
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
            private readonly TextBlock connection = Guidance("Checking connected devices…");
            private readonly InfoBar feedback = new() { IsOpen = false, IsClosable = false };
            private readonly ProgressRing progress = new() { Width = 20, Height = 20, IsActive = false };
            private readonly Button refresh = new() { Content = "Refresh tools and devices" };
            private readonly Button pair = new() { Content = "Pair wirelessly…" };
            private readonly Button mirror = new() { Content = "Mirror selected device" };
            private readonly ContentDialog dialog;
            private bool busy;
            private bool adbReady;
            private bool compatible;
            private bool hasReadyDevice;
            private bool pairRequested;
            private bool skipRequested;
            private bool winget;

            public SetupSession()
            {
                var content = new StackPanel { Spacing = 14, MaxWidth = 560 };
                content.Children.Add(Guidance("Connect your Android device, then try your first mirror. Only adb and scrcpy are needed; the Android SDK, Android Studio and emulator are optional developer tools."));
                content.Children.Add(adb.Container);
                content.Children.Add(scrcpy.Container);
                content.Children.Add(new TextBlock { Text = "Connect with USB", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                content.Children.Add(Guidance("1. On the phone, open Settings › About phone and tap Build number seven times to enable Developer options. The location varies by manufacturer.\n2. In Developer options, turn on USB debugging. Connect the unlocked phone with a USB data cable.\n3. Accept “Allow USB debugging?” on the phone. Trust this computer only if it is yours, then select Refresh below."));
                content.Children.Add(devices);
                content.Children.Add(connection);
                content.Children.Add(refresh);
                content.Children.Add(pair);
                content.Children.Add(Guidance("Wireless pairing requires Android 11 or newer, Wireless debugging enabled, and the phone and PC on the same network. Close pairing to return here; setup will refresh automatically."));
                content.Children.Add(mirror);
                content.Children.Add(progress);
                content.Children.Add(feedback);
                content.Children.Add(Guidance("Finish setup is available when a device is ready. You can deliberately skip now and reopen this guide from Settings › Setup guide."));
                AutomationProperties.SetName(devices, "Connected Android devices and connection states");
                AutomationProperties.SetName(progress, "Setup operation in progress");
                AutomationProperties.SetLiveSetting(connection, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
                dialog = new ContentDialog
                {
                    Title = "Connect your first device",
                    Content = new ScrollViewer { Content = content, MaxHeight = 560, VerticalScrollBarVisibility = ScrollBarVisibility.Auto },
                    PrimaryButtonText = "Finish setup",
                    IsPrimaryButtonEnabled = false,
                    CloseButtonText = "Skip for now",
                    DefaultButton = ContentDialogButton.Primary,
                    XamlRoot = App.MainWindowInstance.Content.XamlRoot
                };
                devices.SelectionChanged += (_, _) => UpdateActions();
                refresh.Click += async (_, _) => await RefreshAsync();
                mirror.Click += async (_, _) => await MirrorAsync();
                pair.Click += (_, _) => { pairRequested = true; dialog.Hide(); };
                adb.InstallButton.Click += async (_, _) => await InstallAsync("Google.PlatformTools", "https://developer.android.com/tools/releases/platform-tools");
                scrcpy.InstallButton.Click += async (_, _) => await InstallAsync("Genymobile.scrcpy", "https://github.com/Genymobile/scrcpy/releases");
                dialog.PrimaryButtonClick += async (_, args) =>
                {
                    var deferral = args.GetDeferral();
                    try
                    {
                        await RefreshAsync();
                        args.Cancel = !hasReadyDevice;
                    }
                    finally { deferral.Complete(); }
                };
                dialog.CloseButtonClick += (_, args) =>
                {
                    args.Cancel = busy;
                    if (!busy) skipRequested = true;
                };
                dialog.Closing += (_, args) => { if (busy) args.Cancel = true; };
                UpdateActions();
            }

            public async Task ShowAsync()
            {
                winget = await Task.Run(IsWingetAvailable);
                adb.InstallButton.Content = scrcpy.InstallButton.Content = winget ? "Install / update with winget" : "Open download page";
                while (true)
                {
                    await RefreshAsync();
                    ContentDialogResult result = await dialog.ShowAsync();
                    if (pairRequested)
                    {
                        pairRequested = false;
                        // Await full dismissal before opening another ContentDialog on this XamlRoot.
                        await PairingDialog.ShowAsync();
                        continue;
                    }

                    if ((result == ContentDialogResult.Primary && hasReadyDevice) || skipRequested)
                    {
                        AppSettingsStore.Current.HasCompletedOnboarding = true;
                        AppSettingsStore.Save();
                        if (SelectedReadyDevice is { } selected) AppState.SelectedSerial = selected.Serial;
                    }
                    return;
                }
            }

            private AdbHelper.AdbDeviceInfo? SelectedReadyDevice =>
                (devices.SelectedItem as ComboBoxItem)?.Tag is AdbHelper.AdbDeviceInfo device && device.Status == "device" ? device : null;

            private void UpdateActions()
            {
                dialog.IsPrimaryButtonEnabled = !busy && hasReadyDevice;
                refresh.IsEnabled = !busy;
                pair.IsEnabled = !busy && adbReady;
                mirror.IsEnabled = !busy && compatible && SelectedReadyDevice is not null;
                devices.IsEnabled = !busy;
                adb.InstallButton.IsEnabled = scrcpy.InstallButton.IsEnabled = !busy;
                progress.IsActive = busy;
                progress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            }

            private void SetBusy(bool value)
            {
                busy = value;
                UpdateActions();
            }

            private async Task RefreshAsync()
            {
                if (busy) return;
                SetBusy(true);
                try
                {
                    string? previous = (devices.SelectedItem as ComboBoxItem)?.Tag is AdbHelper.AdbDeviceInfo selected ? selected.Serial : null;
                    string adbMessage = "";
                    adbReady = await Task.Run(() => AdbHelper.TestAdb(out adbMessage));
                    adb.SetState(adbReady, adbReady ? adbMessage : $"adb is unavailable: {adbMessage} Install platform-tools, then refresh. If installed manually, set the adb override in Advanced settings.");
                    ToolCompatibility.Status status = await ToolCompatibility.CheckScrcpyAsync();
                    compatible = status.IsCompatible;
                    scrcpy.SetState(compatible, status.Summary);
                    devices.Items.Clear();
                    var connected = adbReady ? await Task.Run(AdbHelper.GetDevices) : new System.Collections.Generic.List<AdbHelper.AdbDeviceInfo>();
                    hasReadyDevice = connected.Any(device => device.Status == "device");
                    foreach (AdbHelper.AdbDeviceInfo device in connected)
                    {
                        string state = device.Status switch
                        {
                            "device" => "Ready",
                            "unauthorized" => "Unauthorized — allow USB debugging on the unlocked phone",
                            "offline" => "Offline — reconnect the cable or wireless connection",
                            _ => device.Status + " — boot Android normally to connect"
                        };
                        var item = new ComboBoxItem
                        {
                            Content = Guidance($"{device.Name} · {device.Serial}\n{state}"),
                            Tag = device
                        };
                        AutomationProperties.SetName(item, $"{device.Name}, {device.Serial}, {state}");
                        devices.Items.Add(item);
                        if (device.Serial == previous) devices.SelectedItem = item;
                    }
                    if (devices.SelectedItem is null)
                        devices.SelectedItem = devices.Items.OfType<ComboBoxItem>().FirstOrDefault(item => ((AdbHelper.AdbDeviceInfo)item.Tag).Status == "device") ?? devices.Items.FirstOrDefault();
                    connection.Text = !adbReady
                        ? "Install or repair adb above, then refresh. No full Android SDK is required."
                        : connected.Count == 0
                            ? "No devices found. Unlock the phone, enable USB debugging and use a data-capable cable. Try another USB port or install your phone manufacturer's Windows USB driver, then refresh."
                            : "Ready devices can be mirrored. Unauthorized: unlock the phone and approve the debugging prompt. Offline: reconnect USB, or use wireless pairing to reconnect, then refresh.";
                }
                catch (Exception ex)
                {
                    hasReadyDevice = false;
                    adbReady = false;
                    compatible = false;
                    devices.Items.Clear();
                    feedback.Message = $"Could not refresh setup: {ex.Message} Reconnect your device and try Refresh.";
                    feedback.Severity = InfoBarSeverity.Error;
                    feedback.IsOpen = true;
                }
                finally { SetBusy(false); }
            }

            private async Task InstallAsync(string packageId, string downloadUrl)
            {
                if (busy) return;
                SetBusy(true);
                try
                {
                    if (winget)
                    {
                        feedback.IsOpen = true;
                        feedback.Severity = InfoBarSeverity.Informational;
                        feedback.Message = "Installing or updating with winget. This may take a few minutes…";
                        bool installed = await Task.Run(() => RunWinget(packageId));
                        feedback.Severity = installed ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
                        feedback.Message = installed
                            ? "winget completed. Tool and device status will refresh now."
                            : "winget did not complete. Install or update from the official download page, then refresh. If an older manual override is set, update or clear it in Advanced settings.";
                        if (!installed) await Windows.System.Launcher.LaunchUriAsync(new Uri(downloadUrl));
                    }
                    else
                    {
                        await Windows.System.Launcher.LaunchUriAsync(new Uri(downloadUrl));
                        feedback.IsOpen = true;
                        feedback.Severity = InfoBarSeverity.Informational;
                        feedback.Message = "Install the downloaded tool, then select Refresh. For a portable download, select its executable in Settings › Advanced tool overrides.";
                    }
                }
                catch (Exception ex)
                {
                    feedback.IsOpen = true;
                    feedback.Severity = InfoBarSeverity.Error;
                    feedback.Message = $"Installation could not start: {ex.Message} Download the tool manually, then refresh.";
                }
                finally { SetBusy(false); }
                await RefreshAsync();
            }

            private async Task MirrorAsync()
            {
                if (busy) return;
                await RefreshAsync();
                AdbHelper.AdbDeviceInfo? device = SelectedReadyDevice;
                if (device is null || !compatible) return;
                SetBusy(true);
                try
                {
                    var start = new ProcessStartInfo(AdbHelper.ScrcpyPath ?? "scrcpy.exe") { UseShellExecute = false, CreateNoWindow = true };
                    start.ArgumentList.Add("--serial");
                    start.ArgumentList.Add(device.Serial);
                    start.ArgumentList.Add("--window-title");
                    start.ArgumentList.Add($"AndroLaunch — {device.Name}");
                    if (!string.IsNullOrWhiteSpace(AdbHelper.AdbPath)) start.Environment["ADB"] = AdbHelper.AdbPath;
                    using Process process = Process.Start(start) ?? throw new InvalidOperationException("scrcpy did not start.");
                    using var startup = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                    bool running = false;
                    try { await process.WaitForExitAsync(startup.Token); }
                    catch (OperationCanceledException) { running = !process.HasExited; }
                    if (!running && process.ExitCode != 0)
                        throw new InvalidOperationException($"scrcpy exited with code {process.ExitCode}. Unlock the phone, reconnect it, and refresh before trying again.");
                    feedback.IsOpen = true;
                    feedback.Severity = running ? InfoBarSeverity.Success : InfoBarSeverity.Informational;
                    feedback.Message = running
                        ? $"scrcpy is running for {device.Name} ({device.Serial}). Check the mirror window; you can now finish setup."
                        : "The mirror window has closed. You can open it again here or from Devices.";
                    AppState.SelectedSerial = device.Serial;
                }
                catch (Exception ex)
                {
                    feedback.IsOpen = true;
                    feedback.Severity = InfoBarSeverity.Error;
                    feedback.Message = $"Could not mirror {device.Name} ({device.Serial}): {ex.Message}";
                }
                finally { SetBusy(false); }
            }
        }

        private static TextBlock Guidance(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap };

        private sealed class DependencyRow
        {
            public StackPanel Container { get; } = new() { Spacing = 4 };
            public Button InstallButton { get; } = new() { Content = "Checking installer…", HorizontalAlignment = HorizontalAlignment.Left };
            private readonly TextBlock state = Guidance("Checking…");

            public DependencyRow(string title, string description)
            {
                Container.Children.Add(new TextBlock { Text = title, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                Container.Children.Add(Guidance(description));
                Container.Children.Add(state);
                Container.Children.Add(InstallButton);
                AutomationProperties.SetName(InstallButton, $"Install or update {title}");
                AutomationProperties.SetLiveSetting(state, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
            }

            public void SetState(bool ready, string message)
            {
                state.Text = message;
                state.Foreground = (Brush)Application.Current.Resources[ready ? "SystemFillColorSuccessBrush" : "SystemFillColorCriticalBrush"];
            }
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
                if (process is null) return false;
                _ = process.StandardOutput.ReadToEndAsync();
                _ = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(5000))
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    return false;
                }
                return process.ExitCode == 0;
            }
            catch { return false; }
        }

        private static bool RunWinget(string packageId)
        {
            try
            {
                using Process? process = Process.Start(new ProcessStartInfo("winget", $"install --id {packageId} -e --silent --accept-package-agreements --accept-source-agreements")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                });
                if (process is null) return false;
                _ = process.StandardOutput.ReadToEndAsync();
                _ = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(600000))
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    return false;
                }
                return process.ExitCode == 0;
            }
            catch { return false; }
        }
    }
}
