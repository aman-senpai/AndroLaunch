using System;
using System.Drawing;
using System.Windows.Forms;
using System.Reflection;
using System.Linq;
using Microsoft.Win32;
using Androlaunch.UI.Renderers;

namespace Androlaunch.Core
{
    public class TrayApplicationContext : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private ContextMenuStrip contextMenu;

        private System.Windows.Forms.Timer refreshTimer;
        private string? currentActiveDevice;
        private bool _shouldKeepMenuOpen = false;

        public TrayApplicationContext()
        {
            contextMenu = new ContextMenuStrip();
            contextMenu.Renderer = new MenuRenderer();
            contextMenu.BackColor = ThemeManager.Background;
            contextMenu.ForeColor = ThemeManager.Foreground;
            contextMenu.Font = new Font("Segoe UI", 10F, FontStyle.Regular);

            ThemeManager.ThemeChanged += () => {
                contextMenu.BackColor = ThemeManager.Background;
                contextMenu.ForeColor = ThemeManager.Foreground;
            };
            contextMenu.ShowImageMargin = false;
            contextMenu.Closing += ContextMenu_Closing;

            Icon? trayIconImage = null;
            try
            {
                string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app_icon.ico");
                if (System.IO.File.Exists(iconPath))
                {
                    trayIconImage = new Icon(iconPath);
                }
                else
                {
                    // Fallback to searching in root if not in Resources during dev/build
                    iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app_icon.ico");
                    if (System.IO.File.Exists(iconPath)) trayIconImage = new Icon(iconPath);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Could not load icon: {ex.Message}");
            }

            trayIcon = new NotifyIcon()
            {
                Icon = trayIconImage ?? SystemIcons.Application,
                ContextMenuStrip = contextMenu,
                Visible = true,
                Text = "Androlaunch"
            };
            
            trayIcon.MouseClick += (s, e) => {
                if (e.Button == MouseButtons.Left)
                {
                    MethodInfo mi = typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);
                    mi?.Invoke(trayIcon, null);
                }
            };

            refreshTimer = new System.Windows.Forms.Timer();
            refreshTimer.Interval = 3000; // Refresh every 3 seconds while menu is open
            refreshTimer.Tick += (s, e) => SyncOpenMenu();

            // Initial population
            RefreshDeviceList();

            contextMenu.Opening += (sender, e) => {
                RefreshDeviceList();
                refreshTimer.Start();
            };
            contextMenu.Closed += (sender, e) => refreshTimer.Stop();
        }

        private void SyncOpenMenu()
        {
            if (!contextMenu.Visible) return;
            
            // Background check for each device
            foreach (ToolStripItem item in contextMenu.Items)
            {
                if (item is ToolStripMenuItem deviceMenu && deviceMenu.Tag is string serial)
                {
                    System.Threading.Tasks.Task.Run(() => {
                        var state = AdbHelper.GetDeviceState(serial);
                        contextMenu.BeginInvoke((System.Windows.Forms.MethodInvoker)delegate {
                            UpdateStateInMenu(deviceMenu, state, serial);
                        });
                    });
                }
            }
        }

        private void UpdateStateInMenu(ToolStripMenuItem deviceMenu, AdbHelper.DeviceState state, string serial)
        {
            var quickSettings = deviceMenu.DropDownItems.OfType<ToolStripMenuItem>().FirstOrDefault(i => i.Text == "⚡ Quick Settings");
            if (quickSettings != null)
            {
                UpdateToggle(quickSettings, "Wi-Fi", state.Wifi);
                UpdateToggle(quickSettings, "Bluetooth", state.Bluetooth);
                UpdateToggle(quickSettings, "Mobile Data", state.MobileData);
                UpdateToggle(quickSettings, "Dark Mode", state.DarkMode);
                UpdateToggle(quickSettings, "Airplane Mode", state.AirplaneMode);
                UpdateToggle(quickSettings, "Location", state.Location);
                UpdateToggle(quickSettings, "Do Not Disturb", state.DoNotDisturb);
                UpdateToggle(quickSettings, "Auto-Rotate", state.AutoRotate);
                UpdateToggle(quickSettings, "Adaptive Brightness", state.AdaptiveBrightness);
                UpdateToggle(quickSettings, "Clipboard Sync", AdbHelper.IsClipboardSyncActive(serial));
            }
        }

        private void UpdateToggle(ToolStripMenuItem parent, string text, bool isChecked)
        {
            // Use EndsWith to ignore the emojis at the start of the item text
            var item = parent.DropDownItems.OfType<ToolStripMenuItem>().FirstOrDefault(i => i.Text?.EndsWith(text) == true);
            if (item != null && item.Checked != isChecked)
            {
                item.Checked = isChecked;
            }
        }

        private void InitializeSubMenu(ToolStripDropDown dropDown, bool showMargin = false)
        {
            dropDown.BackColor = contextMenu.BackColor;
            dropDown.ForeColor = contextMenu.ForeColor;
            dropDown.Renderer = contextMenu.Renderer;
            
            if (dropDown is ContextMenuStrip cms) cms.ShowImageMargin = showMargin;
            // For ToolStripDropDown, we need to set it via reflection or Cast
            var prop = dropDown.GetType().GetProperty("ShowImageMargin", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            prop?.SetValue(dropDown, showMargin);

            // Important: All sub-menus must link to the same closing logic
            dropDown.Closing += ContextMenu_Closing;
        }

        private void RefreshDeviceList()
        {
            // Suspend layout to prevent flickering if possible, though ContextMenuStrip doesn't support SuspendLayout well for Items.
            contextMenu.Items.Clear();
            
            // Header
            var titleItem = new ToolStripMenuItem("🚀 Androlaunch");
            titleItem.Enabled = false;
            titleItem.Font = new Font(titleItem.Font, FontStyle.Bold);
            contextMenu.Items.Add(titleItem);
            contextMenu.Items.Add(new ToolStripSeparator());

            var devices = AdbHelper.GetDevices();
            
            if (devices.Count == 0)
            {
                var noDeviceItem = new ToolStripMenuItem("⚠️ No devices connected");
                noDeviceItem.Enabled = false;
                contextMenu.Items.Add(noDeviceItem);
            }
            else
            {
                foreach (var device in devices)
                {
                    var serial = device.Serial;
                    var deviceMenu = new ToolStripMenuItem("📱 " + device.Name);
                    deviceMenu.Tag = serial; // Store serial for sync
                    InitializeSubMenu(deviceMenu.DropDown);

                    // Fetch state for this device
                    var state = AdbHelper.GetDeviceState(serial);
                    
                    // --- Core Features ---
                    var mirrorItem = new ToolStripMenuItem("📺 Mirror Screen (scrcpy)", null, (s, e) => AdbHelper.MirrorScreen(serial));
                    var mirrorCameraItem = new ToolStripMenuItem("📷 Mirror Camera");
                    InitializeSubMenu(mirrorCameraItem.DropDown);
                    mirrorCameraItem.DropDownItems.Add(new ToolStripMenuItem("🤳 Front Camera", null, (s, e) => AdbHelper.MirrorCamera(serial, "front")));
                    mirrorCameraItem.DropDownItems.Add(new ToolStripMenuItem("📸 Back Camera", null, (s, e) => AdbHelper.MirrorCamera(serial, "back")));
                    
                    var commandsMenu = new ToolStripMenuItem("💻 Commands");
                    InitializeSubMenu(commandsMenu.DropDown);

                    var savedCommands = AdbHelper.GetSavedCommands();
                    if (savedCommands.Count == 0)
                    {
                        var noneItem = new ToolStripMenuItem("No saved commands");
                        noneItem.Enabled = false;
                        commandsMenu.DropDownItems.Add(noneItem);
                    }
                    else
                    {
                        foreach (var cmd in savedCommands)
                        {
                            string icon = cmd.IsBackground ? "⚙️" : "🐚";
                            var cmdItem = new ToolStripMenuItem($"{icon} {cmd.Name}", null, (s, e) => {
                                AdbHelper.RunShellCommand(serial, cmd, (output, success) => {
                                    if (cmd.IsBackground)
                                    {
                                        trayIcon.ShowBalloonTip(3000, 
                                            success ? $"Command: {cmd.Name}" : "Command Failed", 
                                            output, 
                                            success ? ToolTipIcon.Info : ToolTipIcon.Error);
                                    }
                                });
                            });
                            commandsMenu.DropDownItems.Add(cmdItem);
                        }
                    }

                    
                    // --- Quick Settings ---
                    var quickSettingsItem = new ToolStripMenuItem("⚡ Quick Settings");
                    InitializeSubMenu(quickSettingsItem.DropDown, true);
                    
                    AddToggleItem(quickSettingsItem, "📶 Wi-Fi", state.Wifi, (val) => AdbHelper.ToggleWifi(serial, val));
                    AddToggleItem(quickSettingsItem, "ᛒ Bluetooth", state.Bluetooth, (val) => AdbHelper.ToggleBluetooth(serial, val));
                    AddToggleItem(quickSettingsItem, "📊 Mobile Data", state.MobileData, (val) => AdbHelper.ToggleMobileData(serial, val));
                    quickSettingsItem.DropDownItems.Add(new ToolStripSeparator());
                    
                    AddToggleItem(quickSettingsItem, "🌙 Dark Mode", state.DarkMode, (val) => AdbHelper.ToggleDarkMode(serial, val));
                    AddToggleItem(quickSettingsItem, "✈️ Airplane Mode", state.AirplaneMode, (val) => AdbHelper.ToggleAirplaneMode(serial, val));
                    AddToggleItem(quickSettingsItem, "📍 Location", state.Location, (val) => AdbHelper.ToggleLocation(serial, val));
                    AddToggleItem(quickSettingsItem, "⛔ Do Not Disturb", state.DoNotDisturb, (val) => AdbHelper.ToggleDoNotDisturb(serial, val));
                    AddToggleItem(quickSettingsItem, "🔄 Auto-Rotate", state.AutoRotate, (val) => AdbHelper.ToggleAutoRotate(serial, val));
                    AddToggleItem(quickSettingsItem, "💡 Adaptive Brightness", state.AdaptiveBrightness, (val) => AdbHelper.ToggleAdaptiveBrightness(serial, val));
                    AddToggleItem(quickSettingsItem, "📋 Clipboard Sync", AdbHelper.IsClipboardSyncActive(serial), (val) => AdbHelper.ToggleClipboardSync(serial, val));
                    
                    // --- Device Control ---
                    var controlItem = new ToolStripMenuItem("🔧 Device Control");
                    InitializeSubMenu(controlItem.DropDown);

                    controlItem.DropDownItems.Add(new ToolStripMenuItem("🔄 Reboot System", null, (s, e) => { if(ConfirmAction("Reboot device now?")) AdbHelper.Reboot(serial); }));
                    controlItem.DropDownItems.Add(new ToolStripMenuItem("👢 Reboot Bootloader", null, (s, e) => { if(ConfirmAction("Reboot to Bootloader?")) AdbHelper.Reboot(serial, "bootloader"); }));
                    controlItem.DropDownItems.Add(new ToolStripMenuItem("🛠️ Reboot Recovery", null, (s, e) => { if(ConfirmAction("Reboot to Recovery?")) AdbHelper.Reboot(serial, "recovery"); }));
                    controlItem.DropDownItems.Add(new ToolStripSeparator());
                    controlItem.DropDownItems.Add(new ToolStripMenuItem("🛑 Power Off", null, (s, e) => { if(ConfirmAction("Power off device now?")) AdbHelper.RunAdbCommand($"-s {serial} shell reboot -p"); }));

                    // --- Configuration ---
                    var configMenu = new ToolStripMenuItem("⚙️ Configuration");
                    InitializeSubMenu(configMenu.DropDown);

                    var mConfig = AdbHelper.GetConfig(serial);

                    // Mirroring Section
                    var mirrorSettings = new ToolStripMenuItem("🖼️ Mirroring Settings");
                    InitializeSubMenu(mirrorSettings.DropDown, true);

                    var resMenu = new ToolStripMenuItem("📏 App Resolution");
                    InitializeSubMenu(resMenu.DropDown, true);
                    AddSelectableGroup<int>(resMenu, new (string, int)[] { 
                        ("Original", 0), ("360p", 360), ("540p", 540), ("720p", 720), ("900p", 900), ("1080p", 1080) 
                    }, mConfig.MaxSize, (val) => mConfig.MaxSize = val);
                    mirrorSettings.DropDownItems.Add(resMenu);

                    var fpsMenu = new ToolStripMenuItem("🚀 Max FPS");
                    InitializeSubMenu(fpsMenu.DropDown, true);
                    AddSelectableGroup<int>(fpsMenu, new (string, int)[] { 
                        ("Unlimited", 0), ("30 FPS", 30), ("60 FPS", 60), ("90 FPS", 90), ("120 FPS", 120) 
                    }, mConfig.MaxFps, (val) => mConfig.MaxFps = val);
                    mirrorSettings.DropDownItems.Add(fpsMenu);

                    var bitMenu = new ToolStripMenuItem("📉 Bit Rate");
                    InitializeSubMenu(bitMenu.DropDown, true);
                    AddSelectableGroup<int>(bitMenu, new (string, int)[] { 
                        ("2 Mbps", 2), ("4 Mbps", 4), ("8 Mbps", 8), ("16 Mbps", 16), ("20 Mbps", 20) 
                    }, mConfig.BitRate, (val) => mConfig.BitRate = val);
                    mirrorSettings.DropDownItems.Add(bitMenu);

                    mirrorSettings.DropDownItems.Add(new ToolStripSeparator());
                    AddToggleItem(mirrorSettings, "🔊 Audio Forwarding", mConfig.AudioEnabled, (val) => mConfig.AudioEnabled = val);
                    AddToggleItem(mirrorSettings, "📋 Clipboard Auto-Sync", mConfig.ClipboardEnabled, (val) => mConfig.ClipboardEnabled = val);
                    AddToggleItem(mirrorSettings, "🔲 Borderless Window", mConfig.Borderless, (val) => mConfig.Borderless = val);

                    var orientMenu = new ToolStripMenuItem("🔄 Orientation");
                    InitializeSubMenu(orientMenu.DropDown, true);
                    AddSelectableGroup<string>(orientMenu, new (string, string)[] { 
                        ("Device", "Auto"), ("Portrait", "0"), ("90° Left", "90"), ("180°", "180"), ("90° Right", "270") 
                    }, mConfig.Orientation, (val) => mConfig.Orientation = val);
                    mirrorSettings.DropDownItems.Add(orientMenu);

                    var camSettings = new ToolStripMenuItem("🎥 Camera Settings");
                    InitializeSubMenu(camSettings.DropDown);

                    var facingMenu = new ToolStripMenuItem("🤳 Camera Facing");
                    InitializeSubMenu(facingMenu.DropDown, true);
                    AddSelectableGroup<string>(facingMenu, new (string, string)[] { 
                        ("Front", "front"), ("Back", "back"), ("External", "external") 
                    }, mConfig.CameraFacing, (val) => mConfig.CameraFacing = val);
                    camSettings.DropDownItems.Add(facingMenu);

                    var camFpsMenu = new ToolStripMenuItem("🚀 Camera FPS");
                    InitializeSubMenu(camFpsMenu.DropDown, true);
                    AddSelectableGroup<int>(camFpsMenu, new (string, int)[] { 
                        ("Default", 0), ("30 FPS", 30), ("60 FPS", 60) 
                    }, mConfig.CameraFps, (val) => mConfig.CameraFps = val);
                    camSettings.DropDownItems.Add(camFpsMenu);

                    var camSizeMenu = new ToolStripMenuItem("📐 Camera Size");
                    InitializeSubMenu(camSizeMenu.DropDown, true);
                    AddSelectableGroup<string>(camSizeMenu, new (string, string)[] { 
                        ("Original", ""), ("1080p", "1920x1080"), ("720p", "1280x720"), ("480p", "854x480") 
                    }, mConfig.CameraSize, (val) => mConfig.CameraSize = val);
                    camSettings.DropDownItems.Add(camSizeMenu);

                    var camARMenu = new ToolStripMenuItem("🖼️ Camera Aspect Ratio");
                    InitializeSubMenu(camARMenu.DropDown, true);
                    AddSelectableGroup<string>(camARMenu, new (string, string)[] { 
                        ("Auto", ""), ("4:3", "4:3"), ("16:9", "16:9"), ("1:1", "1:1") 
                    }, mConfig.CameraAr, (val) => mConfig.CameraAr = val);
                    camSettings.DropDownItems.Add(camARMenu);

                    configMenu.DropDownItems.Add(mirrorSettings);
                    configMenu.DropDownItems.Add(camSettings);


                    // --- Apps ---
                    var launchAppItem = new ToolStripMenuItem("📱 App Manager...", null, (s, e) => {
                        new Androlaunch.UI.Forms.AppLauncherForm(serial).Show();
                    });

                    var installApkItem = new ToolStripMenuItem("📥 Install APK...", null, (s, e) => {
                        using (var openFileDialog = new OpenFileDialog())
                        {
                            openFileDialog.Filter = "APK Files (*.apk)|*.apk|All files (*.*)|*.*";
                            if (openFileDialog.ShowDialog() == DialogResult.OK)
                            {
                                AdbHelper.InstallApk(serial, openFileDialog.FileName);
                            }
                        }
                    });


                    deviceMenu.DropDownItems.Add(mirrorItem);
                    deviceMenu.DropDownItems.Add(mirrorCameraItem);
                    deviceMenu.DropDownItems.Add(new ToolStripMenuItem("🐚 Open Shell", null, (s, e) => AdbHelper.OpenShell(serial)));
                    deviceMenu.DropDownItems.Add(commandsMenu);
                    deviceMenu.DropDownItems.Add(new ToolStripSeparator());
                    deviceMenu.DropDownItems.Add(quickSettingsItem);
                    deviceMenu.DropDownItems.Add(controlItem);
                    deviceMenu.DropDownItems.Add(configMenu);
                    deviceMenu.DropDownItems.Add(new ToolStripSeparator());
                    deviceMenu.DropDownItems.Add(launchAppItem);
                    deviceMenu.DropDownItems.Add(installApkItem);

                    contextMenu.Items.Add(deviceMenu);
                }
            }

            contextMenu.Items.Add(new ToolStripSeparator());
            
            // System Actions
            bool isStartupEnabled = IsRunAtStartupEnabled();
            var startupItem = new ToolStripMenuItem("🚀 Run at Startup");
            startupItem.CheckOnClick = true;
            startupItem.Checked = isStartupEnabled;
            startupItem.MouseDown += (s, e) => _shouldKeepMenuOpen = true;
            startupItem.Click += (s, e) => SetRunAtStartup(startupItem.Checked);
            contextMenu.Items.Add(startupItem);

            contextMenu.Items.Add(new ToolStripMenuItem("⚙️ Commands", null, (s, e) => new Androlaunch.UI.Forms.CommandManagerForm().Show()));
            contextMenu.Items.Add(new ToolStripMenuItem("🔗 Wireless Pairing", null, (s, e) => new Androlaunch.UI.Forms.WirelessPairingForm().Show()));
            contextMenu.Items.Add(new ToolStripMenuItem("🔄 Refresh Devices", null, (s, e) => RefreshDeviceList()));
            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add(new ToolStripMenuItem("❌ Exit", null, Exit));
        }

        private bool ConfirmAction(string message)
        {
            return MessageBox.Show(message, "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
        }

        private void ContextMenu_Closing(object? sender, ToolStripDropDownClosingEventArgs e)
        {
            if (_shouldKeepMenuOpen && e.CloseReason == ToolStripDropDownCloseReason.ItemClicked)
            {
                e.Cancel = true;
                _shouldKeepMenuOpen = false;
            }
        }

        private void AddSelectableGroup<T>(ToolStripMenuItem parent, (string text, T value)[] options, T currentValue, Action<T> onSelected)
        {
            foreach (var opt in options)
            {
                var item = new ToolStripMenuItem(opt.text);
                item.MouseDown += (s, e) => _shouldKeepMenuOpen = true;
                item.Click += (s, e) => {
                    foreach (ToolStripMenuItem sibling in parent.DropDownItems) sibling.Checked = false;
                    item.Checked = true;
                    onSelected(opt.value);
                };
                if (Equals(opt.value, currentValue)) item.Checked = true;
                parent.DropDownItems.Add(item);
            }
        }

        private void AddToggleItem(ToolStripMenuItem parent, string text, bool isChecked, Action<bool> onToggle)
        {
            var item = new ToolStripMenuItem(text);
            item.CheckOnClick = true;
            item.Checked = isChecked;
            item.MouseDown += (s, e) => _shouldKeepMenuOpen = true;
            item.Click += (s, e) => {
                onToggle(item.Checked);
                // Refresh state after a short delay to ensure device updated
                System.Threading.Tasks.Task.Delay(1000).ContinueWith(_ => {
                    SyncOpenMenu();
                });
            };
            parent.DropDownItems.Add(item);
        }

        private void Exit(object? sender, EventArgs e)
        {
            trayIcon.Visible = false; // Hide icon immediately
            Application.Exit();
        }

        private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppName = "Androlaunch";

        private bool IsRunAtStartupEnabled()
        {
            try
            {
                using (RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunRegistryKey))
                {
                    if (key == null) return false;
                    string? value = key.GetValue(AppName) as string;
                    if (string.IsNullOrEmpty(value)) return false;
                    
                    // Verify the path matches current executable in case user moved it
                    string currentPath = Application.ExecutablePath;
                    return value.Trim('"').Equals(currentPath, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error checking startup registry: {ex.Message}");
                return false;
            }
        }

        private void SetRunAtStartup(bool enable)
        {
            try
            {
                using (RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true))
                {
                    if (key == null) return;
                    if (enable)
                    {
                        key.SetValue(AppName, $"\"{Application.ExecutablePath}\"");
                    }
                    else
                    {
                        key.DeleteValue(AppName, false);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to update startup settings: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
