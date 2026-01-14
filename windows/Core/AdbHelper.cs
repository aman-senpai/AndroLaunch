using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows.Forms;
using System.Threading.Tasks;
using Zeroconf;
using QRCoder;

namespace Androlaunch.Core
{
    public class AdbHelper
    {
        public class AdbDeviceInfo
        {
            public string Serial { get; set; } = "";
            public string Model { get; set; } = "";
            public string Product { get; set; } = "";
            public string Name { get; set; } = ""; // Display name

            public override string ToString() => string.IsNullOrEmpty(Name) ? Serial : Name;
        }

        public class ShellCommand
        {
            public Guid Id { get; set; } = Guid.NewGuid();
            public string Name { get; set; } = "";
            public string Command { get; set; } = "";
            public bool IsBackground { get; set; } = false;
            public bool IsHostCommand { get; set; } = false;
        }

        public static List<AdbDeviceInfo> GetDevices()
        {
            var deviceDictionary = new Dictionary<string, AdbDeviceInfo>();
            try
            {
                var processInfo = new ProcessStartInfo
                {
                    FileName = "adb",
                    Arguments = "devices -l",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = Process.Start(processInfo))
                {
                    if (process != null)
                    {
                        var output = process.StandardOutput.ReadToEnd();
                        process.WaitForExit();

                        var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                        foreach (var line in lines.Skip(1))
                        {
                            if (string.IsNullOrWhiteSpace(line) || line.Contains("offline") || line.Contains("unauthorized"))
                                continue;

                            var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                            if (parts.Length < 1) continue;

                            var serial = parts[0];
                            var info = new AdbDeviceInfo { Serial = serial };

                            // Parse long output: product:XXX model:YYY device:ZZZ transport_id:N
                            foreach (var part in parts)
                            {
                                if (part.StartsWith("model:")) info.Model = part.Substring(6).Replace("_", " ");
                                if (part.StartsWith("product:")) info.Product = part.Substring(8);
                            }

                            info.Name = string.IsNullOrEmpty(info.Model) ? serial : info.Model;

                            // Deduplication logic:
                            // Use a key that represents the physical device. 
                            var deviceKey = $"{info.Product}|{info.Model}";
                            
                            int GetPriority(string s) {
                                if (s.Contains("_adb-tls-connect")) return 2; // mDNS
                                if (s.Contains(".") || s.Contains(":")) return 1; // IP
                                return 3; // USB / Hardware (likely no dots or underscores)
                            }

                            if (deviceDictionary.TryGetValue(deviceKey, out var existing))
                            {
                                if (GetPriority(serial) > GetPriority(existing.Serial))
                                {
                                    deviceDictionary[deviceKey] = info;
                                }
                            }
                            else
                            {
                                deviceDictionary[deviceKey] = info;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error getting devices: {ex.Message}");
            }
            return deviceDictionary.Values.ToList();
        }

        private static string? _adbPath;
        private static string? _scrcpyPath;

        static AdbHelper()
        {
            ResolvePaths();
        }

        private static void ResolvePaths()
        {
            _adbPath = FindExecutable("adb.exe", new[] {
                System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Android\Sdk\platform-tools\adb.exe"),
                @"C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe",
                @"C:\platform-tools\adb.exe"
            });

            _scrcpyPath = FindExecutable("scrcpy.exe", new[] {
                @"C:\ProgramData\chocolatey\bin\scrcpy.exe",
                @"C:\scrcpy\scrcpy.exe"
            });
        }

        private static string FindExecutable(string fileName, string[] searchPaths)
        {
            // 1. Check if accessible in PATH (by trying to get full path)
            try
            {
                var val = GetFullPathFromPath(fileName);
                if (!string.IsNullOrEmpty(val)) return val;
            }
            catch {}

            // 2. Check explicitly defined common paths
            foreach (var path in searchPaths)
            {
                if (System.IO.File.Exists(path)) return path;
            }

            // 3. Fallback to just the filename (relies on system PATH)
            return fileName;
        }

        public class DeviceState
        {
            public bool Wifi { get; set; }
            public bool Bluetooth { get; set; }
            public bool MobileData { get; set; }
            public bool DarkMode { get; set; }
            public bool AirplaneMode { get; set; }
            public bool Location { get; set; }
            public bool DoNotDisturb { get; set; }
            public bool AutoRotate { get; set; }
            public bool AdaptiveBrightness { get; set; }
        }

        public class MirrorConfig
        {
            public int MaxSize { get; set; } = 0; // 0 = original
            public int MaxFps { get; set; } = 0; // 0 = unlimited
            public int BitRate { get; set; } = 8; // Mbps
            public bool AudioEnabled { get; set; } = true;
            public bool ClipboardEnabled { get; set; } = true;
            public string Orientation { get; set; } = "Auto"; // 0, 90, 180, 270 or Auto
            public bool Borderless { get; set; } = false;

            // Camera specific
            public string CameraFacing { get; set; } = "front";
            public int CameraFps { get; set; } = 0;
            public string CameraSize { get; set; } = "1280x720";
            public string CameraAr { get; set; } = "";
        }

        public class AppInfo
        {
            public string Name { get; set; } = "";
            public string PackageName { get; set; } = "";
            public override string ToString() => Name;
        }

        private static Dictionary<string, MirrorConfig> _deviceConfigs = new Dictionary<string, MirrorConfig>();
        private static Dictionary<string, Process> _clipboardProcesses = new Dictionary<string, Process>();
        private static HashSet<string> _clipboardSyncDevices = new HashSet<string>();
        private static string? _lastClipboardText = null;
        private static System.Windows.Forms.Timer? _clipboardTimer = null;

        public static MirrorConfig GetConfig(string serial)
        {
            if (!_deviceConfigs.ContainsKey(serial))
                _deviceConfigs[serial] = new MirrorConfig();
            return _deviceConfigs[serial];
        }

        public static bool IsClipboardSyncActive(string serial) => _clipboardSyncDevices.Contains(serial);

        public static void ToggleClipboardSync(string serial, bool enable)
        {
            if (enable)
            {
                if (!_clipboardSyncDevices.Contains(serial))
                {
                    _clipboardSyncDevices.Add(serial);
                    StartClipboardSyncProcess(serial);
                    StartClipboardObserver();
                }
            }
            else
            {
                _clipboardSyncDevices.Remove(serial);
                StopClipboardSyncProcess(serial);
                if (_clipboardSyncDevices.Count == 0) StopClipboardObserver();
            }
        }

        private static void StartClipboardSyncProcess(string serial)
        {
            try 
            {
                var psi = new ProcessStartInfo {
                    FileName = _scrcpyPath,
                    Arguments = $"-s {serial} --no-video --no-audio --no-window",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    WorkingDirectory = string.IsNullOrEmpty(_scrcpyPath) ? null : System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(_scrcpyPath))
                };

                if (!string.IsNullOrEmpty(_adbPath)) psi.Environment["ADB"] = _adbPath;

                var process = new Process { StartInfo = psi };
                process.OutputDataReceived += (sender, e) => {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        Debug.WriteLine($"[scrcpy-{serial}] {e.Data}");
                        // Scrcpy prints the device clipboard content when it changes
                        // Looking for: "Device clipboard: ..." or similar depending on version
                        // In recent versions it might just sync, but in background we can catch it.
                        if (e.Data.Contains("Device clipboard: "))
                        {
                            var text = e.Data.Replace("Device clipboard: ", "").Trim();
                            if (!string.IsNullOrEmpty(text))
                            {
                                // We must use a thread compatible with OLE (STA) for Clipboard
                                System.Threading.Thread thread = new System.Threading.Thread(() => {
                                    try { 
                                        _lastClipboardText = text; // Prevent feedback loop
                                        Clipboard.SetText(text); 
                                    } catch { }
                                });
                                thread.SetApartmentState(System.Threading.ApartmentState.STA);
                                thread.Start();
                            }
                        }
                    }
                };
                process.ErrorDataReceived += (sender, e) => {
                    if (!string.IsNullOrEmpty(e.Data)) Debug.WriteLine($"[scrcpy-err-{serial}] {e.Data}");
                };

                if (process.Start())
                {
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    _clipboardProcesses[serial] = process;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to start clipboard sync process: {ex.Message}");
            }
        }

        private static void StopClipboardSyncProcess(string serial)
        {
            if (_clipboardProcesses.TryGetValue(serial, out var p))
            {
                try 
                { 
                    if (!p.HasExited) p.Kill(true); 
                } 
                catch { }
                _clipboardProcesses.Remove(serial);
            }
        }

        private static void StartClipboardObserver()
        {
            if (_clipboardTimer != null) return;
            _clipboardTimer = new System.Windows.Forms.Timer();
            _clipboardTimer.Interval = 1000;
            _clipboardTimer.Tick += (s, e) => {
                try 
                {
                    if (Clipboard.ContainsText())
                    {
                        var text = Clipboard.GetText();
                        if (text != _lastClipboardText && text.Length < 100000)
                        {
                            _lastClipboardText = text;
                            foreach (var serial in _clipboardSyncDevices.ToList())
                            {
                                SendClipboardToDevice(serial, text);
                            }
                        }
                    }
                }
                catch { }
            };
            _clipboardTimer.Start();
        }

        private static void StopClipboardObserver()
        {
            _clipboardTimer?.Stop();
            _clipboardTimer = null;
            _lastClipboardText = null;
        }

        private static void SendClipboardToDevice(string serial, string text)
        {
            try 
            {
                var escaped = text.Replace("'", "'\\''");
                RunAdbCommand($"-s {serial} shell am broadcast -a ch.pete.adbclipboard.WRITE -n ch.pete.adbclipboard/.WriteReceiver -e text '{escaped}'");
            }
            catch { }
        }

        public static DeviceState GetDeviceState(string serial)
        {
            var state = new DeviceState();
            try
            {
                // We use a more direct and robust way to get settings
                // Some devices return extra text with 'cmd settings', so 'settings get' is safer.
                // Zen mode values: 0=Off, 1=Priority, 2=Total Silence, 3=Alarms
                var cmd = "shell \"settings get global wifi_on; " +
                          "settings get global bluetooth_on; " +
                          "settings get global mobile_data; " +
                          "cmd uimode night; " +
                          "settings get global airplane_mode_on; " +
                          "settings get secure location_mode; " +
                          "settings get global zen_mode; " +
                          "settings get system accelerometer_rotation; " +
                          "settings get system screen_brightness_mode\"";
                
                var output = RunAdbCommand($"-s {serial} {cmd}");
                var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

                if (lines.Length >= 9)
                {
                    state.Wifi = lines[0].Trim() == "1";
                    state.Bluetooth = lines[1].Trim() == "1";
                    state.MobileData = lines[2].Trim() == "1";
                    state.DarkMode = lines[3].ToLower().Contains("yes");
                    state.AirplaneMode = lines[4].Trim() == "1";
                    state.Location = lines[5].Trim() != "0" && !lines[5].Contains("null");
                    
                    var zenVal = lines[6].Trim();
                    state.DoNotDisturb = (zenVal != "0" && zenVal != "null");
                    
                    state.AutoRotate = lines[7].Trim() == "1";
                    state.AdaptiveBrightness = lines[8].Trim() == "1";
                }
            }
            catch (Exception ex) 
            { 
                Debug.WriteLine($"Error getting device state for {serial}: {ex.Message}");
            }
            return state;
        }

        private static string? GetFullPathFromPath(string fileName)
        {
            if (System.IO.File.Exists(fileName))
                return System.IO.Path.GetFullPath(fileName);

            var values = Environment.GetEnvironmentVariable("PATH");
            if (values == null) return null;

            foreach (var path in values.Split(System.IO.Path.PathSeparator))
            {
                var fullPath = System.IO.Path.Combine(path, fileName);
                if (System.IO.File.Exists(fullPath))
                    return fullPath;
            }
            return null;
        }
        public static void InstallApk(string serial, string apkPath)
        {
            try
            {
                RunAdbCommand($"-s {serial} install -r \"{apkPath}\"");
                MessageBox.Show("APK Installation Started/Completed.", "Info", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to install APK.\nError: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public static List<AppInfo> GetApps(string serial)
        {
            var apps = new List<AppInfo>();
            try
            {
                // Swift implementation uses: --serial <id> --list-apps
                // Output format is typically: * App Name package.name
                var psi = new ProcessStartInfo
                {
                    FileName = _scrcpyPath,
                    Arguments = $"-s {serial} --list-apps",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                if (!string.IsNullOrEmpty(_adbPath)) psi.Environment["ADB"] = _adbPath;

                using (var process = Process.Start(psi))
                {
                    if (process != null)
                    {
                        var output = process.StandardOutput.ReadToEnd();
                        var error = process.StandardError.ReadToEnd();
                        var combined = output + "\n" + error;

                        var lines = combined.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                        var regex = new System.Text.RegularExpressions.Regex(@"^\s*[\*\-]\s+(.+?)\s+(\S+)$");

                        foreach (var line in lines)
                        {
                            var match = regex.Match(line);
                            if (match.Success)
                            {
                                apps.Add(new AppInfo {
                                    Name = match.Groups[1].Value.Trim(),
                                    PackageName = match.Groups[2].Value.Trim()
                                });
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error listing apps via scrcpy: {ex.Message}");
                // Fallback to basic package list if scrcpy fails
                foreach (var pkg in GetInstalledPackages(serial))
                {
                    apps.Add(new AppInfo { Name = pkg, PackageName = pkg });
                }
            }
            return apps.OrderBy(a => a.Name).ToList();
        }

        public static List<string> GetInstalledPackages(string serial)
        {
            var packages = new List<string>();
            try
            {
                // -3 lists only third-party apps
                var output = RunAdbCommand($"-s {serial} shell pm list packages -3");
                var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in lines)
                {
                    if (line.StartsWith("package:"))
                    {
                        packages.Add(line.Substring(8)); // remove "package:" prefix
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error listing packages: {ex.Message}");
            }
            packages.Sort();
            return packages;
        }
        public static void LaunchApp(string serial, string packageName)
        {
            try
            {
                // Primary Method: Scrcpy --start-app (Requested by user as per native implementation check)
                // This will open a scrcpy window directly for the app.
                try 
                {
                    // Swift implementation uses:
                    // --serial <id> --stay-awake --window-title <name> --new-display -m <res> --start-app <pkg>
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = _scrcpyPath,
                        Arguments = $"-s {serial} --stay-awake --new-display --start-app={packageName}",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    });
                    
                    // If scrcpy launched, we are done. 
                    // However, we can't easily track if it failed inside the process without waiting.
                    // But generally if scrcpy is present, it will try.
                    return; 
                }
                catch (Exception)
                {
                    // Fallback if scrcpy launch fails execution
                }

                // Fallback / Legacy Method: Native ADB Launch
                // Attempt to find the main launcher activity
                // "cmd package resolve-activity --brief <pkg> | tail -n 1" often yields "package/activity"
                // but we need to specific intent args to be sure.
                var activity = string.Empty;
                try 
                {
                    // This command searches for the main launcher activity
                    var cmdOutput = RunAdbCommand($"-s {serial} shell \"cmd package resolve-activity -c android.intent.category.LAUNCHER -a android.intent.action.MAIN --brief {packageName} | tail -n 1\"");
                    
                    if (!string.IsNullOrWhiteSpace(cmdOutput) && cmdOutput.Contains("/"))
                    {
                        activity = cmdOutput.Trim();
                    }
                }
                catch 
                {
                    // Ignore, fallback to monkey
                }

                if (!string.IsNullOrEmpty(activity) && !activity.Contains("No activity found"))
                {
                    RunAdbCommand($"-s {serial} shell am start -n {activity}");
                }
                else
                {
                    // Fallback to monkey if activity resolution failed
                    RunAdbCommand($"-s {serial} shell monkey -p {packageName} -c android.intent.category.LAUNCHER 1");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to launch app.\nError: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public static string WirelessConnect(string ip, string port)
        {
            return RunAdbCommand($"connect {ip}:{port}");
        }

        public static string WirelessPair(string ip, string port, string code)
        {
             // adb pair is available in newer platform-tools (30.0.0+)
             return RunAdbCommand($"pair {ip}:{port} {code}");
        }

        public static void EnableTcpIp(string serial, string port = "5555")
        {
            RunAdbCommand($"-s {serial} tcpip {port}");
        }
        
        public static void MirrorScreen(string serial)
        {
            try 
            {
                var config = GetConfig(serial);
                var args = $"-s {serial}";
                
                if (config.MaxSize > 0) args += $" -m {config.MaxSize}";
                if (config.MaxFps > 0) args += $" --max-fps {config.MaxFps}";
                if (config.BitRate > 0) args += $" --video-bit-rate {config.BitRate}M";
                if (config.Orientation != "Auto") args += $" --lock-video-orientation {config.Orientation}";
                if (config.Borderless) args += " --window-borderless";
                if (!config.AudioEnabled) args += " --no-audio";
                if (!config.ClipboardEnabled) args += " --no-clipboard-autosync";

                Process.Start(new ProcessStartInfo
                {
                    FileName = _scrcpyPath,
                    Arguments = args,
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to launch scrcpy. Ensure it is installed.\nPath used: {_scrcpyPath}\nError: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public static void MirrorCamera(string serial, string? facingOverride = null)
        {
            try 
            {
                var config = GetConfig(serial);
                var facing = facingOverride ?? config.CameraFacing;
                var args = $"-s {serial} --video-source=camera --camera-facing={facing}";
                
                if (config.CameraFps > 0) args += $" --camera-fps {config.CameraFps}";
                if (!string.IsNullOrEmpty(config.CameraSize)) args += $" --camera-size={config.CameraSize}";
                if (!string.IsNullOrEmpty(config.CameraAr)) args += $" --camera-ar={config.CameraAr}";
                if (!config.AudioEnabled) args += " --no-audio";

                Process.Start(new ProcessStartInfo
                {
                    FileName = _scrcpyPath,
                    Arguments = args,
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to launch camera mirroring.\nError: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public static void SetVolume(string serial, int value)
        {
            try 
            {
                // Try media_session first
                RunAdbCommand($"-s {serial} shell cmd media_session volume --stream 3 --set {value}");
            }
            catch 
            {
                try 
                {
                    // Fallback to media volume
                    RunAdbCommand($"-s {serial} shell media volume --set {value}");
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Failed to set volume: {ex.Message}");
                }
            }
        }

        public static void OpenShell(string serial)
        {
             try 
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = $"/k \"{_adbPath}\" -s {serial} shell",
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to open shell.\nError: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public static void ToggleWifi(string serial, bool enable)
        {
            var state = enable ? "enable" : "disable";
            RunAdbCommand($"-s {serial} shell svc wifi {state}");
        }

        public static void ToggleMobileData(string serial, bool enable)
        {
            // Swift impl: settings put global mobile_data 1/0
            var value = enable ? "1" : "0";
            RunAdbCommand($"-s {serial} shell settings put global mobile_data {value}");
        }

        public static void ToggleBluetooth(string serial, bool enable)
        {
            // Swift impl: svc bluetooth enable/disable
            var state = enable ? "enable" : "disable";
            RunAdbCommand($"-s {serial} shell svc bluetooth {state}");
        }

        public static void ToggleDarkMode(string serial, bool enable)
        {
            var mode = enable ? "yes" : "no";
            RunAdbCommand($"-s {serial} shell cmd uimode night {mode}");
        }

        public static void ToggleAirplaneMode(string serial, bool enable)
        {
            var value = enable ? "1" : "0";
            RunAdbCommand($"-s {serial} shell settings put global airplane_mode_on {value}");
            // Broadcast intent to make it take effect
            RunAdbCommand($"-s {serial} shell am broadcast -a android.intent.action.AIRPLANE_MODE");
        }

        public static void ToggleLocation(string serial, bool enable)
        {
            // 3 = High Accuracy, 0 = Off
            var value = enable ? "3" : "0";
            RunAdbCommand($"-s {serial} shell settings put secure location_mode {value}");
        }

        public static void ToggleDoNotDisturb(string serial, bool enable)
        {
             // zen_mode: 0 = Off, 1 = On (DND) - actually usually 1/2/3 depends on DND mode (priority/alarms/silence)
             // Swift impl: value = enable ? "1" : "0"
             var value = enable ? "1" : "0";
             RunAdbCommand($"-s {serial} shell cmd settings put global zen_mode {value}");
        }

        public static void ToggleAutoRotate(string serial, bool enable)
        {
            // Swift impl: accelerometer_rotation 1 = enabled, 0 = disabled
            var value = enable ? "1" : "0";
            RunAdbCommand($"-s {serial} shell settings put system accelerometer_rotation {value}");
        }

        public static void ToggleAdaptiveBrightness(string serial, bool enable)
        {
            var value = enable ? "1" : "0";
            RunAdbCommand($"-s {serial} shell settings put system screen_brightness_mode {value}");
        }

        public static void SetRingerMode(string serial, string mode)
        {
            // mode: normal, vibrate, silent
            RunAdbCommand($"-s {serial} shell cmd media_session set_volume_mode {mode}");
        }

        public static void ClearAppData(string serial, string packageName)
        {
            RunAdbCommand($"-s {serial} shell pm clear {packageName}");
        }
        
        public static void Reboot(string serial, string mode = "")
        {
            // mode can be "recovery", "bootloader", or empty for normal
            RunAdbCommand($"-s {serial} reboot {mode}");
        }

        public static void SetBrightness(string serial, int value)
        {
            // value 0-255
            RunAdbCommand($"-s {serial} shell settings put system screen_brightness {value}");
        }

        public static void UninstallApp(string serial, string packageName)
        {
            RunAdbCommand($"-s {serial} uninstall {packageName}");
        }

        public static string RunAdbCommand(string arguments)
        {
            var processInfo = new ProcessStartInfo
            {
                FileName = _adbPath,
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var process = Process.Start(processInfo))
            {
                if (process == null) return string.Empty;
                
                var output = process.StandardOutput.ReadToEnd();
                var error = process.StandardError.ReadToEnd();
                process.WaitForExit();

                if (process.ExitCode != 0)
                {
                    // Only throw if there is an actual failure exit code
                    // Append output to error because adb sometimes puts error info in stdout or vice-versa
                    throw new Exception($"{error}\n{output}");
                }
                return output;
            }
        }

        private static string _pairingPassword = "";
        private static bool _isPairingActive = false;
        public static event Action<string>? OnPairingStatusChanged;
        public static event Action? OnPairingComplete;

        public static (string qrString, string password) StartPairingService()
        {
            StopPairingService();
            _isPairingActive = true;

            // 1. Generate Password
            var random = new Random();
            _pairingPassword = random.Next(100000, 999999).ToString();

            // 2. Generate QR String
            // Format: WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:<password>;;
            string qrString = $"WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:{_pairingPassword};;";

            // 3. Start Discovery in background
            Task.Run(() => RunPairingDiscovery());

            OnPairingStatusChanged?.Invoke("Waiting for device to scan QR code...");
            return (qrString, _pairingPassword);
        }

        public static void StopPairingService()
        {
            _isPairingActive = false;
            OnPairingStatusChanged?.Invoke("Pairing stopped.");
        }

        // --- Shell Command Management ---
        private static string CommandsFilePath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "commands.json");

        public static List<ShellCommand> GetSavedCommands()
        {
            try
            {
                if (!System.IO.File.Exists(CommandsFilePath)) return new List<ShellCommand>();
                string json = System.IO.File.ReadAllText(CommandsFilePath);
                return System.Text.Json.JsonSerializer.Deserialize<List<ShellCommand>>(json) ?? new List<ShellCommand>();
            }
            catch { return new List<ShellCommand>(); }
        }

        public static void SaveCommands(List<ShellCommand> commands)
        {
            try
            {
                string json = System.Text.Json.JsonSerializer.Serialize(commands, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                System.IO.File.WriteAllText(CommandsFilePath, json);
            }
            catch { }
        }

        public static void RunShellCommand(string serial, ShellCommand cmd, Action<string, bool>? onComplete = null)
        {
            if (cmd.IsBackground)
            {
                Task.Run(() =>
                {
                    try
                    {
                        string finalCmd;
                        if (cmd.IsHostCommand)
                        {
                            // Mirror macOS logic: inject serial into host commands if they use 'adb'
                            string targetedAdb = $"\"{_adbPath}\" -s {serial}";
                            finalCmd = cmd.Command.Replace("adb ", targetedAdb + " ");
                            if (cmd.Command == "adb") finalCmd = targetedAdb;
                        }
                        else
                        {
                            // Device shell
                            finalCmd = $"-s {serial} shell \"{cmd.Command}\"";
                        }

                        // Use our existing RunAdbCommand if it's not a raw shell command (Wait, RunAdbCommand prepends _adbPath)
                        string output;
                        if (cmd.IsHostCommand)
                        {
                             // Raw process for host command since it might not start with adb
                             output = RunRawCommand(finalCmd);
                        }
                        else
                        {
                             output = RunAdbCommand(finalCmd);
                        }
                        
                        onComplete?.Invoke(output, true);
                    }
                    catch (Exception ex)
                    {
                        onComplete?.Invoke(ex.Message, false);
                    }
                });
            }
            else
            {
                // Foreground: Open in new CMD window
                try
                {
                    string finalCmd;
                    string title = $"Androlaunch - {cmd.Name}";
                    
                    if (cmd.IsHostCommand)
                    {
                        string targetedAdb = $"\"{_adbPath}\" -s {serial}";
                        finalCmd = cmd.Command.Replace("adb ", targetedAdb + " ");
                        if (cmd.Command == "adb") finalCmd = targetedAdb;
                    }
                    else
                    {
                        finalCmd = $"\"{_adbPath}\" -s {serial} shell \"{cmd.Command}\"";
                    }

                    // For foreground, we want the window to stay open
                    string fullArguments = $"/k \"title {title} & echo Running: {finalCmd} & echo -------------------- & {finalCmd} & echo. & echo -------------------- & echo Command finished. & pause & exit\"";
                    
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "cmd.exe",
                        Arguments = fullArguments,
                        UseShellExecute = true
                    });
                }
                catch { }
            }
        }

        private static string RunRawCommand(string fullCommandWithArgs)
        {
            // Split into file and args
            string fileName;
            string args;
            
            if (fullCommandWithArgs.StartsWith("\"")) {
                int nextQuote = fullCommandWithArgs.IndexOf("\"", 1);
                fileName = fullCommandWithArgs.Substring(1, nextQuote - 1);
                args = fullCommandWithArgs.Substring(nextQuote + 1).Trim();
            } else {
                int firstSpace = fullCommandWithArgs.IndexOf(" ");
                if (firstSpace == -1) {
                    fileName = fullCommandWithArgs;
                    args = "";
                } else {
                    fileName = fullCommandWithArgs.Substring(0, firstSpace);
                    args = fullCommandWithArgs.Substring(firstSpace + 1);
                }
            }

            var processInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var process = Process.Start(processInfo))
            {
                if (process == null) return string.Empty;
                var output = process.StandardOutput.ReadToEnd();
                var error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                return string.IsNullOrEmpty(output) ? error : output;
            }
        }

        private static async Task RunPairingDiscovery()
        {
            var processedEndpoints = new HashSet<string>();
            var processedConnectHosts = new HashSet<string>();

            while (_isPairingActive)
            {
                try
                {
                    // Search for pairing service
                    var pairingResults = await ZeroconfResolver.ResolveAsync("_adb-tls-pairing._tcp.local.");
                    foreach (var result in pairingResults)
                    {
                        var endpoint = $"{result.IPAddress}:{result.Services.Values.First().Port}";
                        if (processedEndpoints.Contains(endpoint)) continue;
                        processedEndpoints.Add(endpoint);

                        OnPairingStatusChanged?.Invoke($"Device found. Pairing with {result.IPAddress}...");
                        
                        try
                        {
                            var output = WirelessPair(result.IPAddress, result.Services.Values.First().Port.ToString(), _pairingPassword);
                            if (output.Contains("Successfully paired to") || output.Contains("already paired"))
                            {
                                OnPairingStatusChanged?.Invoke($"Paired with {result.IPAddress}. Connecting...");
                                // Now look for connect service
                                break; // Exit pairing loop to focus on connection
                            }
                        }
                        catch (Exception ex)
                        {
                            Debug.WriteLine($"Pairing failed: {ex.Message}");
                            processedEndpoints.Remove(endpoint);
                        }
                    }

                    // Search for connect service
                    var connectResults = await ZeroconfResolver.ResolveAsync("_adb-tls-connect._tcp.local.");
                    foreach (var result in connectResults)
                    {
                        var endpoint = $"{result.IPAddress}:{result.Services.Values.First().Port}";
                        if (processedConnectHosts.Contains(endpoint)) continue;
                        processedConnectHosts.Add(endpoint);

                        try
                        {
                            var output = WirelessConnect(result.IPAddress, result.Services.Values.First().Port.ToString());
                            if (output.Contains("connected to") || output.Contains("already connected"))
                            {
                                OnPairingStatusChanged?.Invoke($"Connected to {result.IPAddress}!");
                                OnPairingComplete?.Invoke();
                                // Restart pairing for next device like macOS implementation
                                StartPairingService();
                                return;
                            }
                        }
                        catch (Exception ex)
                        {
                            Debug.WriteLine($"Connect failed: {ex.Message}");
                            processedConnectHosts.Remove(endpoint);
                        }
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Discovery error: {ex.Message}");
                }

                await Task.Delay(2000);
            }
        }
    }
}
