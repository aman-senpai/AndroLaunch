using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Linq;
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
            public string Status { get; set; } = "device";

            public bool IsWireless =>
                Serial.Contains(':') ||
                Serial.Contains("_adb-tls-", StringComparison.OrdinalIgnoreCase);

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
                    FileName = _adbPath ?? "adb",
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
                            if (string.IsNullOrWhiteSpace(line))
                                continue;

                            var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                            if (parts.Length < 2) continue;

                            var serial = parts[0];
                            var status = parts[1];
                            var info = new AdbDeviceInfo { Serial = serial, Status = status };

                            // Parse long output: product:XXX model:YYY device:ZZZ transport_id:N
                            foreach (var part in parts)
                            {
                                if (part.StartsWith("model:")) info.Model = part.Substring(6).Replace("_", " ");
                                if (part.StartsWith("product:")) info.Product = part.Substring(8);
                            }

                            info.Name = string.IsNullOrEmpty(info.Model) ? serial : info.Model;

                            // Deduplicate physical devices while remembering which transport is best.
                            var deviceKey = string.IsNullOrEmpty(info.Product) && string.IsNullOrEmpty(info.Model)
                                ? serial
                                : $"{info.Product}|{info.Model}";

                            int GetPriority(AdbDeviceInfo device) {
                                int statusPriority = device.Status == "device" ? 10 : 0;
                                if (device.Serial.Contains("_adb-tls-connect")) return statusPriority + 2; // mDNS
                                if (device.Serial.Contains(".") || device.Serial.Contains(":")) return statusPriority + 1; // IP
                                return statusPriority + 3; // USB / Hardware (likely no dots or underscores)
                            }

                            if (deviceDictionary.TryGetValue(deviceKey, out var existing))
                            {
                                if (GetPriority(info) > GetPriority(existing))
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

        public static string? AdbPath => _adbPath;
        public static string? ScrcpyPath => _scrcpyPath;

        static AdbHelper()
        {
            ResolvePaths();
        }

        public static void RefreshToolPaths()
        {
            ResolvePaths();
        }

        private static void ResolvePaths()
        {
            AppSettings settings = AppSettingsStore.Current;

            _adbPath = !string.IsNullOrWhiteSpace(settings.AdbPath) && System.IO.File.Exists(settings.AdbPath)
                ? settings.AdbPath
                : FindExecutable("adb.exe", new[] {
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Android\Sdk\platform-tools\adb.exe"),
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WinGet\Links\adb.exe"),
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"scoop\shims\adb.exe"),
                    @"C:\ProgramData\chocolatey\bin\adb.exe",
                    @"C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe",
                    @"C:\platform-tools\adb.exe"
                });

            _scrcpyPath = !string.IsNullOrWhiteSpace(settings.ScrcpyPath) && System.IO.File.Exists(settings.ScrcpyPath)
                ? settings.ScrcpyPath
                : FindExecutable("scrcpy.exe", new[] {
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WinGet\Links\scrcpy.exe"),
                    System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"scoop\shims\scrcpy.exe"),
                    @"C:\ProgramData\chocolatey\bin\scrcpy.exe",
                    @"C:\scrcpy\scrcpy.exe"
                });
        }

        public static string? FindExecutable(string fileName, string[] searchPaths)
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

        public static bool IsToolAvailable(string fileName, string[] searchPaths, out string? resolvedPath)
        {
            resolvedPath = null;
            try
            {
                resolvedPath = GetFullPathFromPath(fileName);
            }
            catch
            {
                // Fall through to the explicit paths.
            }

            if (string.IsNullOrWhiteSpace(resolvedPath))
            {
                resolvedPath = searchPaths.FirstOrDefault(System.IO.File.Exists);
            }

            return !string.IsNullOrWhiteSpace(resolvedPath) && System.IO.File.Exists(resolvedPath);
        }

        public static bool TestAdb(out string message)
        {
            RefreshToolPaths();
            try
            {
                string output = RunAdbCommand("version");
                message = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "ADB is available.";
                return true;
            }
            catch (Exception ex)
            {
                message = ex.Message.Trim();
                return false;
            }
        }

        public static bool TestScrcpy(out string? path)
        {
            string[] paths =
            {
                System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WinGet\Links\scrcpy.exe"),
                System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"scoop\shims\scrcpy.exe"),
                @"C:\ProgramData\chocolatey\bin\scrcpy.exe",
                @"C:\scrcpy\scrcpy.exe"
            };
            bool available = IsToolAvailable("scrcpy.exe", paths, out path);
            if (available)
            {
                _scrcpyPath = path;
            }
            return available;
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
            public int MaxSize { get; set; } = 0; // mirroring size; 0 = original
            public int AppResolution { get; set; } = 900; // app-window resolution; 0 = original
            public int MaxFps { get; set; } = 0; // 0 = unlimited
            public int BitRate { get; set; } = 8; // Mbps
            public bool AudioEnabled { get; set; } = true;
            public bool ClipboardEnabled { get; set; } = true;
            public string Orientation { get; set; } = "Auto"; // 0, 90, 180, 270 or Auto
            public bool Borderless { get; set; } = false;
            public bool FlexDisplay { get; set; } = false;

            // Camera specific
            public string CameraFacing { get; set; } = "Auto";
            public int CameraFps { get; set; } = 0;
            public int CameraSize { get; set; } = 0; // 0 = original
            public string CameraAr { get; set; } = "Auto";
        }

        public class AppInfo
        {
            public string Name { get; set; } = "";
            public string PackageName { get; set; } = "";
            public override string ToString() => Name;
        }

        private static Dictionary<string, MirrorConfig> _deviceConfigs = new Dictionary<string, MirrorConfig>();

        public static MirrorConfig GetConfig(string serial)
        {
            if (!_deviceConfigs.TryGetValue(serial, out MirrorConfig? config))
            {
                config = new MirrorConfig();
                _deviceConfigs[serial] = config;
            }

            return config;
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
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to install APK. {ex.Message}", ex);
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
                        Task<string> outputTask = process.StandardOutput.ReadToEndAsync();
                        Task<string> errorTask = process.StandardError.ReadToEndAsync();
                        if (!process.WaitForExit(20000))
                        {
                            try { process.Kill(entireProcessTree: true); } catch { }
                            process.WaitForExit(5000);
                        }

                        var output = outputTask.GetAwaiter().GetResult();
                        var error = errorTask.GetAwaiter().GetResult();
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
        /// <summary>
        /// scrcpy's <c>--new-display</c> creates a virtual display. On Android 12, 12L and 13 the
        /// platform SystemUI (WM Shell <c>LegacySplitScreenController</c>) dereferences a null
        /// <c>DisplayLayout</c> for that display on its next rotation/configuration event, crashes,
        /// and on restart re-shows the lock screen — the phone ends up locked. Android 14 removed
        /// that code path, so only these versions must fall back to mirroring the main display.
        /// An unknown version is treated as unsafe so the device is never locked by mistake.
        /// </summary>
        private static bool VirtualDisplayUnsafe(string serial)
        {
            try
            {
                var sdk = RunAdbCommand($"-s {serial} shell getprop ro.build.version.sdk").Trim();
                if (int.TryParse(sdk, out var level))
                {
                    return level >= 31 && level <= 33;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error reading Android SDK level: {ex.Message}");
            }
            return true;
        }

        public static void LaunchApp(string serial, string packageName)
        {
            try
            {
                // Primary Method: Scrcpy --start-app (Requested by user as per native implementation check)
                // This will open a scrcpy window directly for the app.
                try 
                {
                    // Android 12-13: the virtual display crashes SystemUI and locks the device, so
                    // mirror the main display with the app in the foreground instead.
                    MirrorConfig config = GetConfig(serial);
                    var args = $"-s {serial} --stay-awake --window-title \"AndroLaunch - {packageName}\"";
                    if (!VirtualDisplayUnsafe(serial))
                    {
                        args += " --new-display";
                        if (config.FlexDisplay)
                        {
                            args += " --flex-display";
                        }
                        else if (config.AppResolution > 0)
                        {
                            args += $" -m {config.AppResolution}";
                        }
                    }
                    else if (config.AppResolution > 0)
                    {
                        args += $" -m {config.AppResolution}";
                    }

                    if (!config.AudioEnabled) args += " --no-audio";
                    if (!config.ClipboardEnabled) args += " --no-clipboard-autosync";
                    args += $" --start-app={packageName}";

                    Process.Start(new ProcessStartInfo
                    {
                        FileName = _scrcpyPath,
                        Arguments = args,
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
                throw new InvalidOperationException($"Failed to launch app. {ex.Message}", ex);
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
                var args = $"-s {serial} --window-title \"AndroLaunch - {serial}\"";

                if (!config.FlexDisplay && config.MaxSize > 0) args += $" -m {config.MaxSize}";
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
                throw new InvalidOperationException($"Failed to launch scrcpy. Ensure it is installed. Path used: {_scrcpyPath}. {ex.Message}", ex);
            }
        }

        public static void MirrorCamera(string serial, string? facingOverride = null)
        {
            try 
            {
                var config = GetConfig(serial);
                var facing = facingOverride ?? config.CameraFacing;
                var args = $"-s {serial} --video-source=camera --window-title \"AndroLaunch Camera - {serial}\"";

                if (!string.IsNullOrEmpty(facing) && facing != "Auto") args += $" --camera-facing={facing}";
                if (config.CameraFps > 0) args += $" --max-fps {config.CameraFps}";
                if (config.CameraSize > 0) args += $" -m {config.CameraSize}";
                if (!string.IsNullOrEmpty(config.CameraAr) && config.CameraAr != "Auto") args += $" --camera-ar={config.CameraAr}";
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
                throw new InvalidOperationException($"Failed to launch camera mirroring. {ex.Message}", ex);
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
                throw new InvalidOperationException($"Failed to open shell. {ex.Message}", ex);
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


        public sealed class DeviceInfo
        {
            public string AndroidVersion { get; set; } = "";
            public int ApiLevel { get; set; }
            public string Model { get; set; } = "";
            public string Manufacturer { get; set; } = "";
            public int? BatteryLevel { get; set; }
            public bool IsCharging { get; set; }

            public string Summary
            {
                get
                {
                    var parts = new List<string>();
                    if (!string.IsNullOrWhiteSpace(AndroidVersion))
                    {
                        parts.Add(ApiLevel > 0 ? $"Android {AndroidVersion} (API {ApiLevel})" : $"Android {AndroidVersion}");
                    }
                    if (BatteryLevel is int level)
                    {
                        parts.Add(IsCharging ? $"{level}% charging" : $"{level}%");
                    }
                    return string.Join("  ·  ", parts);
                }
            }
        }

        public static DeviceInfo GetDeviceInfo(string serial)
        {
            var info = new DeviceInfo();
            try
            {
                string properties = RunAdbCommand($"-s {serial} shell getprop");
                var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (string line in properties.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    Match match = Regex.Match(line, @"^\[([^\]]+)\]:\s*\[(.*)\]$");
                    if (match.Success)
                    {
                        values[match.Groups[1].Value] = match.Groups[2].Value;
                    }
                }

                if (values.TryGetValue("ro.build.version.release", out string? release)) info.AndroidVersion = release;
                if (values.TryGetValue("ro.build.version.sdk", out string? sdk) && int.TryParse(sdk, out int api)) info.ApiLevel = api;
                if (values.TryGetValue("ro.product.model", out string? model)) info.Model = model;
                if (values.TryGetValue("ro.product.manufacturer", out string? manufacturer)) info.Manufacturer = manufacturer;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error reading device info: {ex.Message}");
            }

            try
            {
                string battery = RunAdbCommand($"-s {serial} shell dumpsys battery");
                Match levelMatch = Regex.Match(battery, @"level:\s*(\d+)");
                Match statusMatch = Regex.Match(battery, @"status:\s*(\d+)");
                if (levelMatch.Success && int.TryParse(levelMatch.Groups[1].Value, out int level))
                {
                    info.BatteryLevel = level;
                }
                if (statusMatch.Success && int.TryParse(statusMatch.Groups[1].Value, out int status))
                {
                    info.IsCharging = status is 2 or 5;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Error reading battery info: {ex.Message}");
            }

            return info;
        }

        public static void Disconnect(string serial)
        {
            try
            {
                RunAdbCommand($"disconnect {serial}");
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to disconnect {serial}: {ex.Message}");
                throw;
            }
        }

        public static void OpenLogcat(string serial)
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = $"/k title Logcat - {serial} & \"{_adbPath}\" -s {serial} logcat -v time",
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to open logcat. {ex.Message}", ex);
            }
        }

        public static string GetAppVersion(string serial, string packageName)
        {
            string output = RunAdbCommand($"-s {serial} shell dumpsys package {packageName}");
            return string.Join(
                Environment.NewLine,
                output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .Where(line => line.Contains("version", StringComparison.OrdinalIgnoreCase)));
        }

        public static string GetAppPermissions(string serial, string packageName)
        {
            string output = RunAdbCommand($"-s {serial} shell dumpsys package {packageName}");
            return string.Join(
                Environment.NewLine,
                output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    .Where(line => line.Contains("permission", StringComparison.OrdinalIgnoreCase)));
        }

        public static string? GetApkPath(string serial, string packageName)
        {
            string output = RunAdbCommand($"-s {serial} shell pm path {packageName}");
            foreach (string line in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.StartsWith("package:", StringComparison.Ordinal))
                {
                    return line.Substring("package:".Length).Trim();
                }
            }

            return null;
        }

        public static void ExportApk(string serial, string packageName, string destinationPath)
        {
            string? remotePath = GetApkPath(serial, packageName);
            if (string.IsNullOrWhiteSpace(remotePath))
            {
                throw new InvalidOperationException("Could not find the APK path on the device.");
            }

            RunAdbCommand($"-s {serial} pull {Quote(remotePath)} {Quote(destinationPath)}");
        }

        public static List<AndroidFile> ListFiles(string serial, string path)
        {
            string target = string.IsNullOrWhiteSpace(path) ? "/sdcard" : path.TrimEnd('/');
            if (target.Length == 0)
            {
                target = "/";
            }

            string output = RunAdbCommand($"-s {serial} shell ls -la {Quote(target + "/")}");
            return ParseFileList(output, target);
        }

        private static List<AndroidFile> ParseFileList(string output, string parentPath)
        {
            var files = new List<AndroidFile>();

            // Toybox:       -rw-rw---- 1 u0_a123 sdcard_rw 12345 2026-04-12 17:00 name
            // Toolbox:      -rw-rw---- u0_a123 sdcard_rw 12345 Apr 12 17:00 name
            // Simple:       -rw-rw---- 12345 Apr 12 17:00 name
            var patterns = new[]
            {
                new Regex(@"^([dl-][rwxstST-]{9}[+@.]?)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+(.+)$"),
                new Regex(@"^([dl-][rwxstST-]{9}[+@.]?)\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2}\s+\d+\s+[\d:]{4,5})\s+(.+)$"),
                new Regex(@"^([dl-][rwxstST-]{9}[+@.]?)\s+(\d+)\s+([A-Z][a-z]{2}\s+\d+\s+[\d:]{4,5})\s+(.+)$")
            };

            foreach (string rawLine in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string line = rawLine.TrimEnd();
                if (string.IsNullOrWhiteSpace(line) || line.StartsWith("total ", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                foreach (Regex pattern in patterns)
                {
                    Match match = pattern.Match(line);
                    if (!match.Success)
                    {
                        continue;
                    }

                    string permissions = match.Groups[1].Value;
                    string sizeText = match.Groups[2].Value;
                    string date = match.Groups[3].Value;
                    if (match.Groups.Count >= 6)
                    {
                        date += " " + match.Groups[4].Value;
                    }

                    string name = match.Groups[match.Groups.Count - 1].Value.Trim();
                    int arrow = name.IndexOf(" -> ", StringComparison.Ordinal);
                    if (arrow >= 0)
                    {
                        name = name[..arrow];
                    }

                    if (name is "." or ".." or "./" or "../")
                    {
                        break;
                    }

                    bool isDirectory = permissions.StartsWith('d') || permissions.StartsWith('l') || name.EndsWith('/');
                    name = name.TrimEnd('/');
                    if (string.IsNullOrWhiteSpace(name))
                    {
                        break;
                    }

                    long size = long.TryParse(sizeText, out long parsedSize) ? parsedSize : 0;
                    string fullPath = parentPath == "/"
                        ? "/" + name
                        : parentPath + "/" + name;

                    files.Add(new AndroidFile
                    {
                        Name = name,
                        Path = fullPath,
                        Size = size,
                        ModificationDate = date,
                        IsDirectory = isDirectory,
                        Permissions = permissions
                    });
                    break;
                }
            }

            return files
                .OrderByDescending(file => file.IsDirectory)
                .ThenBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        public static void PushFile(string serial, string localPath, string remotePath)
        {
            RunAdbCommand($"-s {serial} push {Quote(localPath)} {Quote(remotePath)}");
        }

        public static void PullFile(string serial, string remotePath, string localPath)
        {
            RunAdbCommand($"-s {serial} pull {Quote(remotePath)} {Quote(localPath)}");
        }

        public static void DeleteFile(string serial, string path)
        {
            RunAdbCommand($"-s {serial} shell rm -rf {Quote(path)}");
        }

        public static void CreateDirectory(string serial, string path)
        {
            RunAdbCommand($"-s {serial} shell mkdir -p {Quote(path)}");
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static string _pairingPassword = "";
        private static volatile bool _isPairingActive;
        private static int _pairingGeneration;
        public static event Action<string>? OnPairingStatusChanged;
        public static event Action? OnPairingComplete;

        public static (string qrString, string password) StartPairingService()
        {
            StopPairingService();
            _isPairingActive = true;
            int generation = ++_pairingGeneration;

            // 1. Generate Password
            var random = new Random();
            _pairingPassword = random.Next(100000, 999999).ToString();

            // 2. Generate QR String
            // Format: WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:<password>;;
            string qrString = $"WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:{_pairingPassword};;";

            // 3. Start Discovery in background
            Task.Run(() => RunPairingDiscovery(generation));

            OnPairingStatusChanged?.Invoke("Waiting for device to scan QR code...");
            return (qrString, _pairingPassword);
        }

        public static void StopPairingService()
        {
            _isPairingActive = false;
            _pairingGeneration++;
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

        private static async Task RunPairingDiscovery(int generation)
        {
            var processedEndpoints = new HashSet<string>();
            var processedConnectHosts = new HashSet<string>();

            while (_isPairingActive && generation == _pairingGeneration)
            {
                try
                {
                    // Search for pairing service
                    var pairingResults = await ZeroconfResolver.ResolveAsync("_adb-tls-pairing._tcp.local.");
                    foreach (var result in pairingResults)
                    {
                        if (!_isPairingActive || generation != _pairingGeneration) return;
                        var endpoint = $"{result.IPAddress}:{result.Services.Values.First().Port}";
                        if (processedEndpoints.Contains(endpoint)) continue;
                        processedEndpoints.Add(endpoint);

                        OnPairingStatusChanged?.Invoke($"Device found. Pairing with {result.IPAddress}...");
                        
                        try
                        {
                            var output = WirelessPair(result.IPAddress, result.Services.Values.First().Port.ToString(), _pairingPassword);
                            if (!_isPairingActive || generation != _pairingGeneration) return;
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
                        if (!_isPairingActive || generation != _pairingGeneration) return;
                        var endpoint = $"{result.IPAddress}:{result.Services.Values.First().Port}";
                        if (processedConnectHosts.Contains(endpoint)) continue;
                        processedConnectHosts.Add(endpoint);

                        try
                        {
                            var output = WirelessConnect(result.IPAddress, result.Services.Values.First().Port.ToString());
                            if (!_isPairingActive || generation != _pairingGeneration) return;
                            if (output.Contains("connected to") || output.Contains("already connected"))
                            {
                                OnPairingStatusChanged?.Invoke($"Connected to {result.IPAddress}!");
                                OnPairingComplete?.Invoke();
                                // Restart pairing for next device like macOS implementation
                                if (generation == _pairingGeneration)
                                {
                                    StartPairingService();
                                }
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
