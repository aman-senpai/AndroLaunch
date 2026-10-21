using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Androlaunch.Core;
using AndroLaunch.WinUI.Dialogs;
using AndroLaunch.WinUI.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AndroLaunch.WinUI.Tray
{
    public static class TrayMenuBuilder
    {
        private static readonly Dictionary<string, AdbHelper.AdbDeviceInfo> connectedWireless =
            new(StringComparer.OrdinalIgnoreCase);

        public static MenuFlyout Build()
        {
            var flyout = new MenuFlyout();
            flyout.Items.Add(new MenuFlyoutItem { Text = "AndroLaunch", IsEnabled = false });
            flyout.Items.Add(Create(flyout, "Open AndroLaunch", () => Navigate("devices")));
            flyout.Items.Add(new MenuFlyoutSeparator());
            var devices = new MenuFlyoutSubItem { Text = "Devices" };
            devices.Items.Add(new MenuFlyoutItem { Text = "Loading devices…", IsEnabled = false });
            flyout.Items.Add(devices);
            flyout.Items.Add(Create(flyout, "Wireless pairing…", async () =>
            {
                await ShowMainWindowAsync();
                await PairingDialog.ShowAsync();
            }));
            flyout.Items.Add(new MenuFlyoutSeparator());
            flyout.Items.Add(Create(flyout, "Emulator manager", () => Navigate("emulators")));
            flyout.Items.Add(Create(flyout, "Settings", () => Navigate("settings")));
            flyout.Items.Add(Create(flyout, "Manage commands…", async () =>
            {
                await ShowMainWindowAsync();
                await CommandManagerDialog.ShowAsync();
            }));

            var startup = new ToggleMenuFlyoutItem { Text = "Run at startup", IsChecked = StartupService.IsEnabled };
            startup.Click += (_, _) =>
            {
                bool enabled = startup.IsChecked;
                AfterClosing(flyout, () =>
                {
                    StartupService.SetEnabled(enabled);
                    if (StartupService.IsEnabled != enabled)
                    {
                        throw new InvalidOperationException("Windows did not save the startup setting. Check access to your user startup registry key.");
                    }
                    return Task.CompletedTask;
                }, "Could not update startup");
            };
            flyout.Items.Add(startup);
            flyout.Items.Add(new MenuFlyoutSeparator());
            flyout.Items.Add(Create(flyout, "Setup guide…", async () =>
            {
                await ShowMainWindowAsync();
                await OnboardingDialog.ShowAsync();
            }));
            flyout.Items.Add(Create(flyout, "About AndroLaunch", async () =>
            {
                await ShowMainWindowAsync();
                await AboutDialog.ShowAsync();
            }));
            flyout.Items.Add(new MenuFlyoutSeparator());
            flyout.Items.Add(Create(flyout, "Exit", () =>
            {
                App.Shutdown();
                return Task.CompletedTask;
            }));

            bool closed = false;
            flyout.Closed += (_, _) => closed = true;
            flyout.Opened += async (_, _) =>
            {
                try
                {
                    List<AdbHelper.AdbDeviceInfo> current = await Task.Run(AdbHelper.GetDevices);
                    List<AdbHelper.ShellCommand> commands = await Task.Run(AdbHelper.GetSavedCommands);
                    if (closed || App.IsShuttingDown) return;
                    RememberWirelessDevices(current);
                    devices.Items.Clear();
                    foreach (AdbHelper.AdbDeviceInfo device in current)
                    {
                        devices.Items.Add(device.Status == "device"
                            ? BuildDeviceMenu(flyout, device, commands)
                            : new MenuFlyoutItem { Text = $"{device.Name} — {device.Status}", IsEnabled = false });
                    }

                    if (current.Count == 0)
                    {
                        devices.Items.Add(new MenuFlyoutItem { Text = "No devices connected", IsEnabled = false });
                    }

                    var serials = new HashSet<string>(current.Select(device => device.Serial), StringComparer.OrdinalIgnoreCase);
                    List<PreviousDevice> previous = AppSettingsStore.Current.PreviousDevices
                        .Where(device => !serials.Contains(device.SerialNumber)).ToList();
                    if (previous.Count > 0)
                    {
                        devices.Items.Add(new MenuFlyoutSeparator());
                        var previousMenu = new MenuFlyoutSubItem { Text = "Previous devices" };
                        foreach (PreviousDevice device in previous)
                        {
                            var menu = new MenuFlyoutSubItem { Text = device.Name };
                            menu.Items.Add(Create(flyout, "Reconnect", async () =>
                            {
                                string result = await Task.Run(() => AdbHelper.RunAdbCommand($"connect {Quote(device.LastKnownHost)}"));
                                await ShowMainWindowAsync();
                                await Ui.ShowTextAsync($"Reconnect — {device.Name}", result);
                            }));
                            menu.Items.Add(Create(flyout, "Forget device", () =>
                            {
                                AppSettingsStore.RemovePreviousDevice(device.SerialNumber);
                                return Task.CompletedTask;
                            }));
                            previousMenu.Items.Add(menu);
                        }
                        devices.Items.Add(previousMenu);
                    }
                    devices.Items.Add(new MenuFlyoutSeparator());
                    devices.Items.Add(Create(flyout, "Manage and refresh devices", () => Navigate("devices")));
                }
                catch (Exception ex)
                {
                    if (!closed)
                    {
                        devices.Items.Clear();
                        devices.Items.Add(Create(flyout, "Device refresh failed — details…", async () =>
                        {
                            await ShowMainWindowAsync();
                            await Ui.ShowErrorAsync("Could not refresh devices", ex.Message);
                        }));
                    }
                }
            };
            return flyout;
        }

        private static void RememberWirelessDevices(List<AdbHelper.AdbDeviceInfo> devices)
        {
            var live = new HashSet<string>(devices.Where(device => device.Status == "device")
                .Select(device => device.Serial), StringComparer.OrdinalIgnoreCase);
            foreach (string serial in connectedWireless.Keys.ToList())
            {
                if (!live.Contains(serial))
                {
                    AdbHelper.AdbDeviceInfo device = connectedWireless[serial];
                    AppSettingsStore.AddPreviousDevice(serial, device.Name, device.Model, serial);
                    connectedWireless.Remove(serial);
                }
            }

            foreach (AdbHelper.AdbDeviceInfo device in devices.Where(device => device.Status == "device" && device.IsWireless))
            {
                connectedWireless[device.Serial] = device;
            }

            if (AppSettingsStore.Current.PreviousDevices.RemoveAll(device => live.Contains(device.SerialNumber)) > 0)
            {
                AppSettingsStore.Save();
            }
        }

        private static MenuFlyoutSubItem BuildDeviceMenu(MenuFlyout flyout, AdbHelper.AdbDeviceInfo device,
            List<AdbHelper.ShellCommand> commands)
        {
            string serial = device.Serial;
            var menu = new MenuFlyoutSubItem { Text = device.Name };
            ToolTipService.SetToolTip(menu, serial);
            menu.Items.Add(Create(flyout, "Mirror screen", () => Task.Run(() => AdbHelper.MirrorScreen(serial))));
            menu.Items.Add(Create(flyout, "Apps and APK installation", () => Navigate("apps", serial)));
            menu.Items.Add(Create(flyout, "Browse files", () => Navigate("files", serial)));
            menu.Items.Add(Create(flyout, "Device controls and configuration", () => Navigate("devices", serial)));

            var tools = new MenuFlyoutSubItem { Text = "Quick actions" };
            tools.Items.Add(Create(flyout, "Mirror camera", () => Task.Run(() => AdbHelper.MirrorCamera(serial))));
            tools.Items.Add(Create(flyout, "Open shell", () => Task.Run(() => AdbHelper.OpenShell(serial))));
            tools.Items.Add(Create(flyout, "Open logcat", () => Task.Run(() => AdbHelper.OpenLogcat(serial))));
            var clipboard = new ToggleMenuFlyoutItem
            {
                Text = "Clipboard sync",
                IsChecked = ClipboardSyncService.IsActive(serial)
            };
            clipboard.Click += (_, _) =>
            {
                bool enabled = clipboard.IsChecked;
                AfterClosing(flyout, () => Task.Run(() => ClipboardSyncService.Toggle(serial, enabled)),
                    "Could not change clipboard sync");
            };
            tools.Items.Add(clipboard);
            tools.Items.Add(Create(flyout, "Reboot…", async () =>
            {
                await ShowMainWindowAsync("devices", serial);
                if (await Ui.ConfirmAsync("Reboot device", $"Reboot {device.Name}?", "Reboot"))
                {
                    await Task.Run(() => AdbHelper.Reboot(serial));
                }
            }));
            menu.Items.Add(tools);
            if (commands.Count > 0)
            {
                var commandsMenu = new MenuFlyoutSubItem { Text = "Saved commands" };
                foreach (AdbHelper.ShellCommand command in commands)
                {
                    var item = Create(flyout, command.Name, () => RunSavedCommandAsync(serial, command));
                    ToolTipService.SetToolTip(item, command.IsHostCommand ? "Runs on this PC" : "Runs on the Android device");
                    commandsMenu.Items.Add(item);
                }
                menu.Items.Add(commandsMenu);
            }
            if (device.IsWireless)
            {
                menu.Items.Add(new MenuFlyoutSeparator());
                menu.Items.Add(Create(flyout, "Disconnect", async () =>
                {
                    await Task.Run(() => AdbHelper.Disconnect(serial));
                    AppSettingsStore.AddPreviousDevice(serial, device.Name, device.Model, serial);
                    connectedWireless.Remove(serial);
                }));
            }
            return menu;
        }

        private static async Task RunSavedCommandAsync(string serial, AdbHelper.ShellCommand command)
        {
            if (!command.IsBackground)
            {
                await Task.Run(() => AdbHelper.RunShellCommand(serial, command));
                return;
            }

            var completion = new TaskCompletionSource<(string Output, bool Success)>(TaskCreationOptions.RunContinuationsAsynchronously);
            AdbHelper.RunShellCommand(serial, command, (resultText, succeeded) => completion.TrySetResult((resultText, succeeded)));
            (string output, bool success) = await completion.Task;
            if (App.IsShuttingDown) return;
            if (!success) throw new InvalidOperationException(output);
            await ShowMainWindowAsync();
            await Ui.ShowTextAsync(command.Name, output);
        }

        private static Task Navigate(string page, string? serial = null)
        {
            App.ShowMainWindow(page, serial);
            return Task.CompletedTask;
        }

        private static async Task ShowMainWindowAsync(string page = "devices", string? serial = null)
        {
            App.ShowMainWindow(page, serial);
            var root = (FrameworkElement)App.MainWindowInstance.Content;
            if (root.XamlRoot is not null) return;
            var loaded = new TaskCompletionSource<bool>();
            void OnLoaded(object sender, RoutedEventArgs args) => loaded.TrySetResult(true);
            root.Loaded += OnLoaded;
            try { await loaded.Task; }
            finally { root.Loaded -= OnLoaded; }
        }

        private static MenuFlyoutItem Create(MenuFlyout flyout, string text, Func<Task> action)
        {
            var item = new MenuFlyoutItem { Text = text };
            item.Click += (_, _) => AfterClosing(flyout, action, text);
            return item;
        }

        private static void AfterClosing(MenuFlyout flyout, Func<Task> action, string title)
        {
            // The flyout owns a transient window. Dispatch only after it closes, and use the
            // main window's queue/root for dialogs instead of the disappearing tray XamlRoot.
            void OnClosed(object? sender, object args)
            {
                flyout.Closed -= OnClosed;
                App.MainWindowInstance.DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, async () =>
                {
                    if (App.IsShuttingDown) return;
                    try
                    {
                        await action();
                    }
                    catch (Exception ex)
                    {
                        if (!App.IsShuttingDown)
                        {
                            await ShowMainWindowAsync();
                            await Ui.ShowErrorAsync(title, ex.Message);
                        }
                    }
                });
            }

            flyout.Closed += OnClosed;
            flyout.Hide();
        }

        private static string Quote(string value) => "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
