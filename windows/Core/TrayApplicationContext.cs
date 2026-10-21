using System;
using System.Drawing;
using System.Linq;
using System.Reflection;
using WinFormsMethodInvoker = System.Windows.Forms.MethodInvoker;
using System.Threading.Tasks;
using System.Windows.Forms;
using Androlaunch.UI.Forms;
using Androlaunch.UI.Renderers;
using Microsoft.Win32;

namespace Androlaunch.Core
{
    public class TrayApplicationContext : ApplicationContext
    {
        private readonly NotifyIcon trayIcon;
        private readonly ContextMenuStrip contextMenu;
        private readonly System.Windows.Forms.Timer refreshTimer;
        private readonly MethodInfo? showContextMenuMethod;

        private bool _shouldKeepMenuOpen;
        private bool _isSyncing;

        public TrayApplicationContext()
        {
            refreshTimer = new System.Windows.Forms.Timer { Interval = 3000 };
            refreshTimer.Tick += (_, _) => SyncOpenMenu();

            contextMenu = new ContextMenuStrip
            {
                Renderer = new MenuRenderer(),
                BackColor = ThemeManager.Background,
                ForeColor = ThemeManager.Foreground,
                Font = ThemeManager.MenuFont,
                ShowImageMargin = false,
                ShowCheckMargin = true,
                Padding = new Padding(2)
            };
            contextMenu.Closing += ContextMenu_Closing;
            contextMenu.Opening += (_, _) => RefreshDeviceList();
            contextMenu.Opened += (_, _) => refreshTimer.Start();
            contextMenu.Closed += (_, _) => refreshTimer.Stop();

            showContextMenuMethod = typeof(NotifyIcon).GetMethod(
                "ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);

            trayIcon = new NotifyIcon
            {
                Icon = AppIcons.Tray(ThemeManager.IsTaskbarLight),
                ContextMenuStrip = contextMenu,
                Visible = true,
                Text = "AndroLaunch - Android device manager"
            };
            trayIcon.MouseClick += TrayIcon_MouseClick;

            ThemeManager.ThemeChanged += OnThemeChanged;
            MigrateStartupEntry();

            RefreshDeviceList();
        }

        private void TrayIcon_MouseClick(object? sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left)
            {
                return;
            }

            if (showContextMenuMethod is not null)
            {
                try
                {
                    showContextMenuMethod.Invoke(trayIcon, null);
                    return;
                }
                catch
                {
                    // The private member is an implementation detail; fall back to a normal popup.
                }
            }

            contextMenu.Show(Cursor.Position);
        }

        private void OnThemeChanged()
        {
            if (contextMenu.IsDisposed)
            {
                return;
            }

            void Apply()
            {
                contextMenu.BackColor = ThemeManager.Background;
                contextMenu.ForeColor = ThemeManager.Foreground;
                contextMenu.Font = ThemeManager.MenuFont;
                trayIcon.Icon = AppIcons.Tray(ThemeManager.IsTaskbarLight);
            }

            try
            {
                if (contextMenu.IsHandleCreated && contextMenu.InvokeRequired)
                {
                    contextMenu.BeginInvoke((WinFormsMethodInvoker)Apply);
                }
                else
                {
                    Apply();
                }
            }
            catch
            {
                // The theme event can arrive while the app is exiting.
            }
        }

        private void SyncOpenMenu()
        {
            if (_isSyncing || !contextMenu.Visible)
            {
                return;
            }

            _isSyncing = true;
            try
            {
                foreach (ToolStripItem item in contextMenu.Items)
                {
                    if (item is not ToolStripMenuItem deviceMenu || deviceMenu.Tag is not string serial)
                    {
                        continue;
                    }

                    _ = Task.Run(() =>
                    {
                        AdbHelper.DeviceState state = AdbHelper.GetDeviceState(serial);
                        try
                        {
                            if (contextMenu.IsHandleCreated && !contextMenu.IsDisposed)
                            {
                                contextMenu.BeginInvoke((WinFormsMethodInvoker)delegate
                                {
                                    UpdateStateInMenu(deviceMenu, state);
                                });
                            }
                        }
                        catch
                        {
                            // The menu may have been disposed between the check and the invoke.
                        }
                    });
                }
            }
            finally
            {
                _isSyncing = false;
            }
        }

        private void UpdateStateInMenu(ToolStripMenuItem deviceMenu, AdbHelper.DeviceState state)
        {
            ToolStripMenuItem? quickSettings = deviceMenu.DropDownItems
                .OfType<ToolStripMenuItem>()
                .FirstOrDefault(i => i.Text == "Quick settings");

            if (quickSettings is null)
            {
                return;
            }

            UpdateToggle(quickSettings, "Wi-Fi", state.Wifi);
            UpdateToggle(quickSettings, "Bluetooth", state.Bluetooth);
            UpdateToggle(quickSettings, "Mobile data", state.MobileData);
            UpdateToggle(quickSettings, "Dark mode", state.DarkMode);
            UpdateToggle(quickSettings, "Airplane mode", state.AirplaneMode);
            UpdateToggle(quickSettings, "Location", state.Location);
            UpdateToggle(quickSettings, "Do not disturb", state.DoNotDisturb);
            UpdateToggle(quickSettings, "Auto-rotate", state.AutoRotate);
            UpdateToggle(quickSettings, "Adaptive brightness", state.AdaptiveBrightness);

            if (deviceMenu.Tag is string serial)
            {
                UpdateToggle(quickSettings, "Clipboard sync", AdbHelper.IsClipboardSyncActive(serial));
            }
        }

        private static void UpdateToggle(ToolStripMenuItem parent, string text, bool isChecked)
        {
            ToolStripMenuItem? item = parent.DropDownItems
                .OfType<ToolStripMenuItem>()
                .FirstOrDefault(i => i.Text == text);

            if (item is not null && item.Checked != isChecked)
            {
                item.Checked = isChecked;
            }
        }

        private void InitializeSubMenu(ToolStripDropDown dropDown, bool showCheckMargin = false)
        {
            dropDown.BackColor = contextMenu.BackColor;
            dropDown.ForeColor = contextMenu.ForeColor;
            dropDown.Renderer = contextMenu.Renderer;

            if (dropDown is ToolStripDropDownMenu menu)
            {
                menu.ShowImageMargin = false;
                menu.ShowCheckMargin = showCheckMargin;
            }

            dropDown.Closing += ContextMenu_Closing;
        }

        private void RefreshDeviceList()
        {
            ToolStripItem[] previousItems = contextMenu.Items.Cast<ToolStripItem>().ToArray();
            contextMenu.Items.Clear();
            foreach (ToolStripItem item in previousItems)
            {
                item.Dispose();
            }

            var titleItem = new ToolStripMenuItem("AndroLaunch")
            {
                Enabled = false,
                Font = ThemeManager.MenuHeaderFont
            };
            contextMenu.Items.Add(titleItem);
            contextMenu.Items.Add(new ToolStripSeparator());

            var devices = AdbHelper.GetDevices();

            if (devices.Count == 0)
            {
                contextMenu.Items.Add(new ToolStripMenuItem("No devices connected") { Enabled = false });
                contextMenu.Items.Add(new ToolStripMenuItem("Check that adb is installed and USB debugging is enabled")
                {
                    Enabled = false
                });
            }
            else
            {
                foreach (AdbHelper.AdbDeviceInfo device in devices)
                {
                    contextMenu.Items.Add(BuildDeviceMenu(device));
                }
            }

            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add(BuildStartupItem());
            contextMenu.Items.Add(new ToolStripMenuItem("Manage commands…", null, (_, _) => new CommandManagerForm().Show()));
            contextMenu.Items.Add(new ToolStripMenuItem("Wireless pairing…", null, (_, _) => new WirelessPairingForm().Show()));
            contextMenu.Items.Add(new ToolStripMenuItem("Refresh devices", null, (_, _) => RefreshDeviceList()));
            contextMenu.Items.Add(new ToolStripMenuItem("About AndroLaunch", null, (_, _) => new AboutForm().ShowDialog()));
            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add(new ToolStripMenuItem("Exit", null, Exit));
        }

        private ToolStripMenuItem BuildDeviceMenu(AdbHelper.AdbDeviceInfo device)
        {
            string serial = device.Serial;
            var deviceMenu = new ToolStripMenuItem(device.Name)
            {
                Tag = serial,
                ToolTipText = serial
            };
            InitializeSubMenu(deviceMenu.DropDown);

            var state = AdbHelper.GetDeviceState(serial);

            var mirrorItem = new ToolStripMenuItem("Mirror screen", null, (_, _) => AdbHelper.MirrorScreen(serial));
            var mirrorCameraItem = new ToolStripMenuItem("Mirror camera");
            InitializeSubMenu(mirrorCameraItem.DropDown);
            mirrorCameraItem.DropDownItems.Add(new ToolStripMenuItem("Front camera", null, (_, _) => AdbHelper.MirrorCamera(serial, "front")));
            mirrorCameraItem.DropDownItems.Add(new ToolStripMenuItem("Back camera", null, (_, _) => AdbHelper.MirrorCamera(serial, "back")));

            var commandsMenu = BuildCommandsMenu(serial);

            var quickSettingsItem = new ToolStripMenuItem("Quick settings");
            InitializeSubMenu(quickSettingsItem.DropDown, true);
            AddToggleItem(quickSettingsItem, "Wi-Fi", state.Wifi, value => AdbHelper.ToggleWifi(serial, value));
            AddToggleItem(quickSettingsItem, "Bluetooth", state.Bluetooth, value => AdbHelper.ToggleBluetooth(serial, value));
            AddToggleItem(quickSettingsItem, "Mobile data", state.MobileData, value => AdbHelper.ToggleMobileData(serial, value));
            quickSettingsItem.DropDownItems.Add(new ToolStripSeparator());
            AddToggleItem(quickSettingsItem, "Dark mode", state.DarkMode, value => AdbHelper.ToggleDarkMode(serial, value));
            AddToggleItem(quickSettingsItem, "Airplane mode", state.AirplaneMode, value => AdbHelper.ToggleAirplaneMode(serial, value));
            AddToggleItem(quickSettingsItem, "Location", state.Location, value => AdbHelper.ToggleLocation(serial, value));
            AddToggleItem(quickSettingsItem, "Do not disturb", state.DoNotDisturb, value => AdbHelper.ToggleDoNotDisturb(serial, value));
            AddToggleItem(quickSettingsItem, "Auto-rotate", state.AutoRotate, value => AdbHelper.ToggleAutoRotate(serial, value));
            AddToggleItem(quickSettingsItem, "Adaptive brightness", state.AdaptiveBrightness, value => AdbHelper.ToggleAdaptiveBrightness(serial, value));
            AddToggleItem(quickSettingsItem, "Clipboard sync", AdbHelper.IsClipboardSyncActive(serial), value => AdbHelper.ToggleClipboardSync(serial, value));

            var controlItem = new ToolStripMenuItem("Device control");
            InitializeSubMenu(controlItem.DropDown);
            controlItem.DropDownItems.Add(new ToolStripMenuItem("Reboot system", null, (_, _) =>
            {
                if (ConfirmAction("Reboot the device now?"))
                {
                    AdbHelper.Reboot(serial);
                }
            }));
            controlItem.DropDownItems.Add(new ToolStripMenuItem("Reboot to bootloader", null, (_, _) =>
            {
                if (ConfirmAction("Reboot to the bootloader?"))
                {
                    AdbHelper.Reboot(serial, "bootloader");
                }
            }));
            controlItem.DropDownItems.Add(new ToolStripMenuItem("Reboot to recovery", null, (_, _) =>
            {
                if (ConfirmAction("Reboot to recovery?"))
                {
                    AdbHelper.Reboot(serial, "recovery");
                }
            }));
            controlItem.DropDownItems.Add(new ToolStripSeparator());
            controlItem.DropDownItems.Add(new ToolStripMenuItem("Volume…", null, (_, _) => new VolumeControlForm(serial).Show()));
            controlItem.DropDownItems.Add(new ToolStripSeparator());
            controlItem.DropDownItems.Add(new ToolStripMenuItem("Power off", null, (_, _) =>
            {
                if (ConfirmAction("Power off the device now?"))
                {
                    AdbHelper.RunAdbCommand($"-s {serial} shell reboot -p");
                }
            }));

            var configMenu = BuildConfigurationMenu(serial);

            var appManagerItem = new ToolStripMenuItem("App manager…", null, (_, _) => new AppLauncherForm(serial).Show());
            var installApkItem = new ToolStripMenuItem("Install APK…", null, (_, _) => InstallApk(serial));

            deviceMenu.DropDownItems.Add(mirrorItem);
            deviceMenu.DropDownItems.Add(mirrorCameraItem);
            deviceMenu.DropDownItems.Add(new ToolStripMenuItem("Open shell", null, (_, _) => AdbHelper.OpenShell(serial)));
            deviceMenu.DropDownItems.Add(commandsMenu);
            deviceMenu.DropDownItems.Add(new ToolStripSeparator());
            deviceMenu.DropDownItems.Add(quickSettingsItem);
            deviceMenu.DropDownItems.Add(controlItem);
            deviceMenu.DropDownItems.Add(configMenu);
            deviceMenu.DropDownItems.Add(new ToolStripSeparator());
            deviceMenu.DropDownItems.Add(appManagerItem);
            deviceMenu.DropDownItems.Add(installApkItem);

            return deviceMenu;
        }

        private ToolStripMenuItem BuildCommandsMenu(string serial)
        {
            var commandsMenu = new ToolStripMenuItem("Commands");
            InitializeSubMenu(commandsMenu.DropDown);

            var savedCommands = AdbHelper.GetSavedCommands();
            if (savedCommands.Count == 0)
            {
                commandsMenu.DropDownItems.Add(new ToolStripMenuItem("No saved commands") { Enabled = false });
                return commandsMenu;
            }

            foreach (AdbHelper.ShellCommand command in savedCommands)
            {
                var commandItem = new ToolStripMenuItem(command.Name, null, (_, _) =>
                {
                    AdbHelper.RunShellCommand(serial, command, (output, success) =>
                    {
                        if (!command.IsBackground)
                        {
                            return;
                        }

                        void ShowBalloon()
                        {
                            trayIcon.ShowBalloonTip(
                                3000,
                                success ? command.Name : "Command failed",
                                Truncate(output, 240),
                                success ? ToolTipIcon.Info : ToolTipIcon.Error);
                        }

                        try
                        {
                            if (contextMenu.IsHandleCreated && !contextMenu.IsDisposed)
                            {
                                contextMenu.BeginInvoke((WinFormsMethodInvoker)ShowBalloon);
                            }
                        }
                        catch
                        {
                            // Nothing to show if the app is shutting down.
                        }
                    });
                });

                if (command.IsHostCommand)
                {
                    commandItem.ToolTipText = "Runs on this PC";
                }
                else if (command.IsBackground)
                {
                    commandItem.ToolTipText = "Runs in the background";
                }

                commandsMenu.DropDownItems.Add(commandItem);
            }

            return commandsMenu;
        }

        private ToolStripMenuItem BuildConfigurationMenu(string serial)
        {
            var configMenu = new ToolStripMenuItem("Configuration");
            InitializeSubMenu(configMenu.DropDown);

            var config = AdbHelper.GetConfig(serial);

            var mirrorSettings = new ToolStripMenuItem("Mirroring");
            InitializeSubMenu(mirrorSettings.DropDown, true);

            var resolutionMenu = new ToolStripMenuItem("App resolution");
            InitializeSubMenu(resolutionMenu.DropDown, true);
            AddSelectableGroup(resolutionMenu, new (string, int)[]
            {
                ("Original", 0), ("360p", 360), ("540p", 540), ("720p", 720), ("900p", 900), ("1080p", 1080)
            }, config.MaxSize, value => config.MaxSize = value);
            mirrorSettings.DropDownItems.Add(resolutionMenu);

            var fpsMenu = new ToolStripMenuItem("Maximum frame rate");
            InitializeSubMenu(fpsMenu.DropDown, true);
            AddSelectableGroup(fpsMenu, new (string, int)[]
            {
                ("Unlimited", 0), ("30 fps", 30), ("60 fps", 60), ("90 fps", 90), ("120 fps", 120)
            }, config.MaxFps, value => config.MaxFps = value);
            mirrorSettings.DropDownItems.Add(fpsMenu);

            var bitRateMenu = new ToolStripMenuItem("Bit rate");
            InitializeSubMenu(bitRateMenu.DropDown, true);
            AddSelectableGroup(bitRateMenu, new (string, int)[]
            {
                ("2 Mbps", 2), ("4 Mbps", 4), ("8 Mbps", 8), ("16 Mbps", 16), ("20 Mbps", 20)
            }, config.BitRate, value => config.BitRate = value);
            mirrorSettings.DropDownItems.Add(bitRateMenu);

            mirrorSettings.DropDownItems.Add(new ToolStripSeparator());
            AddToggleItem(mirrorSettings, "Audio forwarding", config.AudioEnabled, value => config.AudioEnabled = value);
            AddToggleItem(mirrorSettings, "Clipboard auto-sync", config.ClipboardEnabled, value => config.ClipboardEnabled = value);
            AddToggleItem(mirrorSettings, "Borderless window", config.Borderless, value => config.Borderless = value);

            var orientationMenu = new ToolStripMenuItem("Orientation");
            InitializeSubMenu(orientationMenu.DropDown, true);
            AddSelectableGroup(orientationMenu, new (string, string)[]
            {
                ("Device", "Auto"), ("Portrait", "0"), ("90° left", "90"), ("180°", "180"), ("90° right", "270")
            }, config.Orientation, value => config.Orientation = value);
            mirrorSettings.DropDownItems.Add(orientationMenu);

            var cameraSettings = new ToolStripMenuItem("Camera");
            InitializeSubMenu(cameraSettings.DropDown);

            var facingMenu = new ToolStripMenuItem("Camera facing");
            InitializeSubMenu(facingMenu.DropDown, true);
            AddSelectableGroup(facingMenu, new (string, string)[]
            {
                ("Front", "front"), ("Back", "back"), ("External", "external")
            }, config.CameraFacing, value => config.CameraFacing = value);
            cameraSettings.DropDownItems.Add(facingMenu);

            var cameraFpsMenu = new ToolStripMenuItem("Camera frame rate");
            InitializeSubMenu(cameraFpsMenu.DropDown, true);
            AddSelectableGroup(cameraFpsMenu, new (string, int)[]
            {
                ("Default", 0), ("30 fps", 30), ("60 fps", 60)
            }, config.CameraFps, value => config.CameraFps = value);
            cameraSettings.DropDownItems.Add(cameraFpsMenu);

            var cameraSizeMenu = new ToolStripMenuItem("Camera size");
            InitializeSubMenu(cameraSizeMenu.DropDown, true);
            AddSelectableGroup(cameraSizeMenu, new (string, string)[]
            {
                ("Original", ""), ("1080p", "1920x1080"), ("720p", "1280x720"), ("480p", "854x480")
            }, config.CameraSize, value => config.CameraSize = value);
            cameraSettings.DropDownItems.Add(cameraSizeMenu);

            var cameraAspectMenu = new ToolStripMenuItem("Camera aspect ratio");
            InitializeSubMenu(cameraAspectMenu.DropDown, true);
            AddSelectableGroup(cameraAspectMenu, new (string, string)[]
            {
                ("Auto", ""), ("4:3", "4:3"), ("16:9", "16:9"), ("1:1", "1:1")
            }, config.CameraAr, value => config.CameraAr = value);
            cameraSettings.DropDownItems.Add(cameraAspectMenu);

            configMenu.DropDownItems.Add(mirrorSettings);
            configMenu.DropDownItems.Add(cameraSettings);

            return configMenu;
        }

        private ToolStripMenuItem BuildStartupItem()
        {
            var startupItem = new ToolStripMenuItem("Run at startup")
            {
                CheckOnClick = true,
                Checked = IsRunAtStartupEnabled()
            };
            startupItem.MouseDown += (_, _) => _shouldKeepMenuOpen = true;
            startupItem.Click += (_, _) => SetRunAtStartup(startupItem.Checked);
            return startupItem;
        }

        private void InstallApk(string serial)
        {
            using var dialog = new OpenFileDialog
            {
                Filter = "Android packages (*.apk)|*.apk|All files (*.*)|*.*",
                Title = "Install APK",
                CheckFileExists = true
            };

            if (dialog.ShowDialog() == DialogResult.OK)
            {
                AdbHelper.InstallApk(serial, dialog.FileName);
            }
        }

        private static string Truncate(string text, int maxLength)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return "(no output)";
            }

            text = text.Trim();
            return text.Length <= maxLength ? text : text[..maxLength] + "…";
        }

        private static bool ConfirmAction(string message)
        {
            return MessageBox.Show(
                message,
                "AndroLaunch",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2) == DialogResult.Yes;
        }

        private void ContextMenu_Closing(object? sender, ToolStripDropDownClosingEventArgs e)
        {
            if (_shouldKeepMenuOpen && e.CloseReason == ToolStripDropDownCloseReason.ItemClicked)
            {
                e.Cancel = true;
                _shouldKeepMenuOpen = false;
            }
        }

        private void AddSelectableGroup<T>(
            ToolStripMenuItem parent,
            (string Text, T Value)[] options,
            T currentValue,
            Action<T> onSelected)
        {
            foreach ((string text, T value) in options)
            {
                var item = new ToolStripMenuItem(text);
                item.MouseDown += (_, _) => _shouldKeepMenuOpen = true;
                item.Click += (_, _) =>
                {
                    foreach (ToolStripMenuItem sibling in parent.DropDownItems.OfType<ToolStripMenuItem>())
                    {
                        sibling.Checked = false;
                    }

                    item.Checked = true;
                    onSelected(value);
                };

                if (Equals(value, currentValue))
                {
                    item.Checked = true;
                }

                parent.DropDownItems.Add(item);
            }
        }

        private void AddToggleItem(ToolStripMenuItem parent, string text, bool isChecked, Action<bool> onToggle)
        {
            var item = new ToolStripMenuItem(text)
            {
                CheckOnClick = true,
                Checked = isChecked
            };
            item.MouseDown += (_, _) => _shouldKeepMenuOpen = true;
            item.Click += (_, _) =>
            {
                onToggle(item.Checked);

                _ = Task.Delay(700).ContinueWith(_ =>
                {
                    try
                    {
                        if (contextMenu.IsHandleCreated && !contextMenu.IsDisposed)
                        {
                            contextMenu.BeginInvoke((WinFormsMethodInvoker)SyncOpenMenu);
                        }
                    }
                    catch
                    {
                        // The menu may have been disposed while the device was updating.
                    }
                });
            };
            parent.DropDownItems.Add(item);
        }

        private void Exit(object? sender, EventArgs e)
        {
            trayIcon.Visible = false;
            Application.Exit();
        }

        protected override void ExitThreadCore()
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            refreshTimer.Stop();
            refreshTimer.Dispose();
            trayIcon.Visible = false;
            trayIcon.Dispose();
            contextMenu.Dispose();
            base.ExitThreadCore();
        }

        private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppName = "AndroLaunch";
        private const string LegacyAppName = "Androlaunch";

        private static string StartupPath => Environment.ProcessPath ?? Application.ExecutablePath;

        private bool IsRunAtStartupEnabled()
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunRegistryKey);
                if (key is null)
                {
                    return false;
                }

                string? value = key.GetValue(AppName) as string ?? key.GetValue(LegacyAppName) as string;
                if (string.IsNullOrEmpty(value))
                {
                    return false;
                }

                return value.Trim('"').Equals(StartupPath, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        private void SetRunAtStartup(bool enable)
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, writable: true);
                if (key is null)
                {
                    return;
                }

                if (enable)
                {
                    key.SetValue(AppName, $"\"{StartupPath}\"");
                    key.DeleteValue(LegacyAppName, throwOnMissingValue: false);
                }
                else
                {
                    key.DeleteValue(AppName, throwOnMissingValue: false);
                    key.DeleteValue(LegacyAppName, throwOnMissingValue: false);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    $"Could not update the startup setting.\n\n{ex.Message}",
                    "AndroLaunch",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private void MigrateStartupEntry()
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, writable: true);
                if (key is null || key.GetValue(AppName) is not null)
                {
                    return;
                }

                if (key.GetValue(LegacyAppName) is string legacy &&
                    legacy.Trim('"').Equals(StartupPath, StringComparison.OrdinalIgnoreCase))
                {
                    key.SetValue(AppName, $"\"{StartupPath}\"");
                    key.DeleteValue(LegacyAppName, throwOnMissingValue: false);
                }
            }
            catch
            {
                // A locked registry is not a reason to fail startup.
            }
        }
    }
}
