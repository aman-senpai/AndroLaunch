using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace Androlaunch.Core
{
    public sealed class AvdInfo
    {
        public string Name { get; set; } = "";
        public string? Device { get; set; }
        public string? Path { get; set; }
        public string? Target { get; set; }
        public bool IsRunning { get; set; }
        public bool IsStarting { get; set; }
        public bool IsStopping { get; set; }
        public string? Serial { get; set; }
    }

    public sealed class SystemImageInfo
    {
        public string Id { get; set; } = "";
        public string Description { get; set; } = "";
        public bool IsDownloaded { get; set; }
        public long? SizeBytes { get; set; }
        public string OsType { get; set; } = "Phone/Tablet";

        public string ApiLevel
        {
            get
            {
                string[] parts = Id.Split(';');
                return parts.Length >= 2 ? parts[1].Replace("android-", "") : "";
            }
        }

        public string Variant
        {
            get
            {
                string[] parts = Id.Split(';');
                return parts.Length >= 3 ? parts[2] : "";
            }
        }

        public string Architecture
        {
            get
            {
                string[] parts = Id.Split(';');
                return parts.Length >= 4 ? parts[3] : "";
            }
        }

        public string DisplayName
        {
            get
            {
                var parts = new List<string>();
                if (!string.IsNullOrWhiteSpace(ApiLevel)) parts.Add($"API {ApiLevel}");
                if (!string.IsNullOrWhiteSpace(Variant)) parts.Add(FormatVariant(Variant));
                if (!string.IsNullOrWhiteSpace(Architecture)) parts.Add(Architecture);
                return parts.Count == 0 ? Description : string.Join(" — ", parts);
            }
        }

        public string FormattedSize
        {
            get
            {
                if (SizeBytes is not long size || size <= 0)
                {
                    return "";
                }

                string[] units = { "B", "KB", "MB", "GB", "TB" };
                double value = size;
                int unit = 0;
                while (value >= 1024 && unit < units.Length - 1)
                {
                    value /= 1024;
                    unit++;
                }

                return $"{value:0.#} {units[unit]}";
            }
        }

        private static string FormatVariant(string variant)
        {
            return variant.ToLowerInvariant() switch
            {
                "google_apis" => "Google APIs",
                "google_apis_playstore" => "Google Play",
                "android-wear" => "Wear OS",
                "android-wear-cn" => "Wear OS (China)",
                "android-tv" => "Android TV",
                "google_apis_atd" => "Automotive",
                "android-automotive" => "Automotive",
                "google_apis_ps_uef" => "Google Play (UEF)",
                "google_atd" => "Google ATD",
                "aosp_atd" => "AOSP ATD",
                "default" => "AOSP",
                _ => variant.StartsWith("aosp_", StringComparison.OrdinalIgnoreCase)
                    ? "AOSP " + variant[5..].Replace('_', ' ')
                    : variant
            };
        }
    }

    public sealed class HardwareProfile
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string? Oem { get; set; }
        public int? Width { get; set; }
        public int? Height { get; set; }
        public int? Density { get; set; }
    }

    public sealed class AvdOptions
    {
        public int RamMB { get; set; } = 2048;
        public int HeapMB { get; set; } = 512;
        public int StorageMB { get; set; } = 4096;
        public int Width { get; set; } = 1080;
        public int Height { get; set; } = 2400;
        public int Density { get; set; } = 420;
        public int SdCardMB { get; set; } = 512;
        public string CameraBack { get; set; } = "emulated";
        public bool Gps { get; set; } = true;
        public bool Keyboard { get; set; } = true;
        public string GpuMode { get; set; } = "auto";
        public bool ColdBoot { get; set; }
        public bool ShowDeviceFrame { get; set; } = true;
    }

    /// <summary>Android SDK emulator and AVD management for the Windows build.</summary>
    public static class EmulatorService
    {
        private static readonly object ProcessGate = new();
        private static readonly Dictionary<string, Process> RunningProcesses = new(StringComparer.OrdinalIgnoreCase);

        public static bool ToolsAvailable => AppSettingsStore.ToolsAvailable;

        public static string ToolsPath => AppSettingsStore.Current.CommandLineToolsPath ?? "";
        public static string AvdPath => AppSettingsStore.AvdPathOrDefault;
        public static string ImagePath => AppSettingsStore.ImageDownloadPathOrDefault;
        public static string SdkRoot => AppSettingsStore.SdkRootFromToolsPath(ToolsPath);
        public static string? EmulatorPath =>
            !string.IsNullOrWhiteSpace(AppSettingsStore.Current.EmulatorPath) &&
            File.Exists(AppSettingsStore.Current.EmulatorPath)
                ? AppSettingsStore.Current.EmulatorPath
                : AppSettingsStore.AutoDetectEmulatorPath();

        public static List<AvdInfo> ListAvds()
        {
            var result = RunTools("avdmanager.bat", "list avd");
            var avds = ParseAvds(result.Output + Environment.NewLine + result.Error);
            var running = GetRunningEmulators();
            foreach (AvdInfo avd in avds)
            {
                if (running.TryGetValue(avd.Name, out string? serial))
                {
                    avd.IsRunning = true;
                    avd.Serial = serial;
                }
            }

            return avds
                .OrderBy(avd => avd.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        public static List<SystemImageInfo> ListImages()
        {
            ProcessResult result = RunTools("sdkmanager.bat", $"--list {Quote("--sdk_root=" + SdkRoot)}");
            return ParseImages(result.Output + Environment.NewLine + result.Error);
        }

        public static List<HardwareProfile> ListHardwareProfiles()
        {
            ProcessResult result = RunTools("avdmanager.bat", "list device");
            return ParseHardwareProfiles(result.Output + Environment.NewLine + result.Error);
        }

        public static void CreateAvd(string name, string imageId, string? deviceId, AvdOptions options)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                throw new ArgumentException("AVD name is required.", nameof(name));
            }

            var args = new StringBuilder();
            args.Append("create avd --name ").Append(Quote(name));
            args.Append(" --package ").Append(Quote(imageId));
            args.Append(" --force");

            if (!string.IsNullOrWhiteSpace(deviceId))
            {
                args.Append(" --device ").Append(Quote(deviceId));
            }

            string avdDirectory = Path.Combine(AvdPath, name.Replace(' ', '_') + ".avd");
            args.Append(" --path ").Append(Quote(avdDirectory));
            if (options.SdCardMB > 0)
            {
                args.Append(" -c ").Append(options.SdCardMB).Append('M');
            }

            ProcessResult result = RunTools("avdmanager.bat", args.ToString(), "no\n", timeoutMs: 120000);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    string.IsNullOrWhiteSpace(result.Error) ? "Failed to create the AVD." : result.Error.Trim());
            }

            UpdateAvdConfig(name, options, avdDirectory);
        }

        public static void DeleteAvd(string name)
        {
            ProcessResult result = RunTools("avdmanager.bat", $"delete avd --name {Quote(name)}", timeoutMs: 60000);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(result.Error) ? "Failed to delete the AVD." : result.Error.Trim());
            }
        }

        public static void RenameAvd(string oldName, string newName)
        {
            ProcessResult result = RunTools(
                "avdmanager.bat",
                $"move avd -n {Quote(oldName)} -r {Quote(newName)}",
                timeoutMs: 60000);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(result.Error) ? "Failed to rename the AVD." : result.Error.Trim());
            }
        }

        public static void StartAvd(string name)
        {
            string? emulator = EmulatorPath;
            if (string.IsNullOrWhiteSpace(emulator) || !File.Exists(emulator))
            {
                throw new InvalidOperationException(
                    "The Android emulator was not found. Set the emulator path in Emulator Manager settings.");
            }

            LaunchFlags flags = AppSettingsStore.GetLaunchFlags(name);
            var startInfo = new ProcessStartInfo
            {
                FileName = emulator,
                Arguments = string.Join(" ", flags.ToArguments(name).Select(QuoteIfNeeded)),
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            };
            ApplySdkEnvironment(startInfo);

            var process = new Process { StartInfo = startInfo };
            process.Start();
            lock (ProcessGate)
            {
                RunningProcesses[name] = process;
            }
        }

        public static void StopAvd(AvdInfo avd)
        {
            if (!string.IsNullOrWhiteSpace(avd.Serial))
            {
                try
                {
                    AdbHelper.RunAdbCommand($"-s {avd.Serial} emu kill");
                }
                catch
                {
                    // Fall through to the tracked process.
                }
            }

            lock (ProcessGate)
            {
                if (RunningProcesses.TryGetValue(avd.Name, out Process? process))
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            process.Kill(entireProcessTree: true);
                        }
                    }
                    catch
                    {
                        // The emulator may already be gone.
                    }

                    RunningProcesses.Remove(avd.Name);
                }
            }
        }

        public static void DownloadImage(string imageId, Action<double>? progress, CancellationToken cancellationToken)
        {
            string sdkManager = Path.Combine(ToolsPath, "sdkmanager.bat");
            var startInfo = BuildCmdStartInfo(
                sdkManager,
                $"--install {Quote(imageId)} {Quote("--sdk_root=" + SdkRoot)}");
            startInfo.RedirectStandardInput = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            var output = new StringBuilder();

            process.OutputDataReceived += (_, e) => HandleLine(e.Data);
            process.ErrorDataReceived += (_, e) => HandleLine(e.Data);

            void HandleLine(string? line)
            {
                if (string.IsNullOrWhiteSpace(line))
                {
                    return;
                }

                lock (output)
                {
                    output.AppendLine(line);
                }

                Match match = Regex.Match(line, @"(\d{1,3})\s*%");
                if (match.Success && int.TryParse(match.Groups[1].Value, out int percent))
                {
                    progress?.Invoke(Math.Clamp(percent / 100.0, 0, 1));
                }
            }

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            Task.Run(async () =>
            {
                try
                {
                    for (int i = 0; i < 1800 && !process.HasExited && !cancellationToken.IsCancellationRequested; i++)
                    {
                        await process.StandardInput.WriteLineAsync("y");
                        await process.StandardInput.FlushAsync();
                        await Task.Delay(500, cancellationToken);
                    }
                }
                catch
                {
                    // The process closed its stdin.
                }
            }, cancellationToken);

            try
            {
                while (!process.WaitForExit(500))
                {
                    if (cancellationToken.IsCancellationRequested)
                    {
                        try { process.Kill(entireProcessTree: true); } catch { }
                        throw new OperationCanceledException(cancellationToken);
                    }
                }
            }
            finally
            {
                try { process.StandardInput.Close(); } catch { }
            }

            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    string.IsNullOrWhiteSpace(output.ToString()) ? "The system image download failed." : output.ToString().Trim());
            }

            progress?.Invoke(1);
        }

        public static void DeleteImage(string imageId)
        {
            ProcessResult result = RunTools(
                "sdkmanager.bat",
                $"--uninstall {Quote(imageId)} {Quote("--sdk_root=" + SdkRoot)}",
                "y\n",
                timeoutMs: 120000);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(result.Error) ? "Failed to delete the system image." : result.Error.Trim());
            }
        }

        private static void UpdateAvdConfig(string name, AvdOptions options, string avdDirectory)
        {
            string configPath = Path.Combine(avdDirectory, "config.ini");
            if (!File.Exists(configPath))
            {
                return;
            }

            var lines = File.ReadAllLines(configPath).ToList();

            void Set(string key, string value)
            {
                int index = lines.FindIndex(line => line.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase));
                if (index >= 0)
                {
                    lines[index] = $"{key}={value}";
                }
                else
                {
                    lines.Add($"{key}={value}");
                }
            }

            Set("hw.ramSize", options.RamMB.ToString());
            Set("vm.heapSize", options.HeapMB.ToString());
            Set("disk.dataPartition.size", $"{options.StorageMB}M");
            Set("hw.lcd.width", options.Width.ToString());
            Set("hw.lcd.height", options.Height.ToString());
            Set("hw.lcd.density", options.Density.ToString());
            Set("hw.gps", options.Gps ? "yes" : "no");
            Set("hw.keyboard", options.Keyboard ? "yes" : "no");
            Set("fastboot.forceCold", options.ColdBoot ? "yes" : "no");
            Set("gpu.mode", options.GpuMode);
            Set("showDeviceFrame", options.ShowDeviceFrame ? "yes" : "no");
            Set("hw.camera.back", options.CameraBack);
            Set("hw.camera.front", options.CameraBack == "none" ? "none" : "emulated");

            File.WriteAllLines(configPath, lines);
        }

        private static Dictionary<string, string> GetRunningEmulators()
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (AdbHelper.AdbDeviceInfo device in AdbHelper.GetDevices())
                {
                    if (!device.Serial.StartsWith("emulator-", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    try
                    {
                        string name = AdbHelper.RunAdbCommand($"-s {device.Serial} emu avd name");
                        string? firstLine = name.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
                        if (!string.IsNullOrWhiteSpace(firstLine) && firstLine != "OK")
                        {
                            result[firstLine.Trim()] = device.Serial;
                        }
                    }
                    catch
                    {
                        // The emulator can disappear between the device list and the query.
                    }
                }
            }
            catch
            {
                // No adb or no emulator is not an error here.
            }

            return result;
        }

        private static List<AvdInfo> ParseAvds(string output)
        {
            var avds = new List<AvdInfo>();
            foreach (string block in output.Split("---------", StringSplitOptions.RemoveEmptyEntries))
            {
                string? name = null;
                string? device = null;
                string? path = null;
                string? target = null;

                foreach (string line in block.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("Name:", StringComparison.OrdinalIgnoreCase))
                        name = trimmed["Name:".Length..].Trim();
                    else if (trimmed.StartsWith("Device:", StringComparison.OrdinalIgnoreCase))
                        device = trimmed["Device:".Length..].Trim();
                    else if (trimmed.StartsWith("Path:", StringComparison.OrdinalIgnoreCase))
                        path = trimmed["Path:".Length..].Trim();
                    else if (trimmed.StartsWith("Target:", StringComparison.OrdinalIgnoreCase))
                        target = trimmed["Target:".Length..].Trim();
                }

                if (!string.IsNullOrWhiteSpace(name))
                {
                    avds.Add(new AvdInfo { Name = name, Device = device, Path = path, Target = target });
                }
            }

            return avds;
        }

        private static List<SystemImageInfo> ParseImages(string output)
        {
            var images = new Dictionary<string, SystemImageInfo>(StringComparer.OrdinalIgnoreCase);
            bool installed = false;

            foreach (string rawLine in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string line = rawLine.Trim();
                if (line.StartsWith("Installed packages:", StringComparison.OrdinalIgnoreCase))
                {
                    installed = true;
                    continue;
                }
                if (line.StartsWith("Available Packages:", StringComparison.OrdinalIgnoreCase))
                {
                    installed = false;
                    continue;
                }
                if (!line.StartsWith("system-images;", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                string[] columns = line.Split('|').Select(column => column.Trim()).ToArray();
                string id = columns[0];
                if (!id.Contains(';'))
                {
                    continue;
                }

                string architecture = id.Split(';').LastOrDefault() ?? "";
                if (!architecture.Equals("x86_64", StringComparison.OrdinalIgnoreCase) &&
                    !architecture.Equals("x86", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (images.TryGetValue(id, out SystemImageInfo? existing))
                {
                    existing.IsDownloaded |= installed;
                    continue;
                }

                var image = new SystemImageInfo
                {
                    Id = id,
                    Description = columns.Length > 2 ? columns[2] : "",
                    IsDownloaded = installed,
                    OsType = OsTypeFromVariant(id.Split(';').ElementAtOrDefault(2) ?? "")
                };

                if (columns.Length > 1)
                {
                    Match sizeMatch = Regex.Match(columns[1], @"([\d.]+)\s*(B|KB|MB|GB|TB)", RegexOptions.IgnoreCase);
                    if (sizeMatch.Success && double.TryParse(sizeMatch.Groups[1].Value, out double size))
                    {
                        double multiplier = sizeMatch.Groups[2].Value.ToUpperInvariant() switch
                        {
                            "KB" => 1024,
                            "MB" => 1024 * 1024,
                            "GB" => 1024 * 1024 * 1024,
                            "TB" => 1024d * 1024 * 1024 * 1024,
                            _ => 1
                        };
                        image.SizeBytes = (long)(size * multiplier);
                    }
                }

                images[id] = image;
            }

            return images.Values
                .OrderByDescending(image => image.IsDownloaded)
                .ThenByDescending(image => int.TryParse(image.ApiLevel, out int api) ? api : 0)
                .ThenBy(image => image.Id, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }

        private static string OsTypeFromVariant(string variant)
        {
            return variant.ToLowerInvariant() switch
            {
                "android-wear" or "android-wear-cn" => "Wear OS",
                "android-tv" => "Android TV",
                "google_apis_atd" or "android-automotive" => "Automotive",
                _ => "Phone/Tablet"
            };
        }

        private static List<HardwareProfile> ParseHardwareProfiles(string output)
        {
            var profiles = new List<HardwareProfile>();
            foreach (string block in output.Split("---------", StringSplitOptions.RemoveEmptyEntries))
            {
                string? id = null;
                string? name = null;
                string? oem = null;
                int? width = null;
                int? height = null;
                int? density = null;

                foreach (string line in block.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string trimmed = line.Trim();
                    Match idMatch = Regex.Match(trimmed, "id: \\d+ or \"([^\"]+)\"");
                    if (idMatch.Success) id = idMatch.Groups[1].Value;
                    else if (trimmed.StartsWith("Name:", StringComparison.OrdinalIgnoreCase)) name = trimmed["Name:".Length..].Trim();
                    else if (trimmed.StartsWith("OEM", StringComparison.OrdinalIgnoreCase)) oem = trimmed.Split(':', 2).LastOrDefault()?.Trim();
                    else
                    {
                        Match resolution = Regex.Match(trimmed, @"Resolution\s*:\s*(\d+)x(\d+)");
                        if (resolution.Success)
                        {
                            width = int.Parse(resolution.Groups[1].Value);
                            height = int.Parse(resolution.Groups[2].Value);
                        }

                        Match densityMatch = Regex.Match(trimmed, @"Density\s*:\s*(\d+)");
                        if (densityMatch.Success)
                        {
                            density = int.Parse(densityMatch.Groups[1].Value);
                        }
                    }
                }

                if (id is not null && name is not null)
                {
                    profiles.Add(new HardwareProfile
                    {
                        Id = id,
                        Name = name,
                        Oem = oem,
                        Width = width,
                        Height = height,
                        Density = density
                    });
                }
            }

            return profiles.OrderBy(profile => profile.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        private static ProcessResult RunTools(string tool, string arguments, string? input = null, int timeoutMs = 60000)
        {
            string executable = Path.Combine(ToolsPath, tool);
            if (!File.Exists(executable))
            {
                return new ProcessResult(-1, "", $"{tool} was not found in {ToolsPath}. Open Emulator Manager settings and choose the SDK command-line tools folder.");
            }

            var startInfo = BuildCmdStartInfo(executable, arguments);
            startInfo.RedirectStandardInput = input is not null;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            using var process = new Process { StartInfo = startInfo };
            process.Start();
            if (input is not null)
            {
                try
                {
                    process.StandardInput.Write(input);
                    process.StandardInput.Close();
                }
                catch
                {
                    // The tool may not need input.
                }
            }

            Task<string> stdout = process.StandardOutput.ReadToEndAsync();
            Task<string> stderr = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(timeoutMs))
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                process.WaitForExit(3000);
            }

            return new ProcessResult(process.ExitCode, stdout.GetAwaiter().GetResult(), stderr.GetAwaiter().GetResult());
        }

        private static ProcessStartInfo BuildCmdStartInfo(string executable, string arguments)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/d /s /c \"\"{executable}\" {arguments}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            ApplySdkEnvironment(startInfo);
            return startInfo;
        }

        private static void ApplySdkEnvironment(ProcessStartInfo startInfo)
        {
            string sdkRoot = SdkRoot;
            startInfo.Environment["ANDROID_SDK_ROOT"] = sdkRoot;
            startInfo.Environment["ANDROID_HOME"] = sdkRoot;
            startInfo.Environment["ANDROID_AVD_HOME"] = AvdPath;

            if (!startInfo.Environment.ContainsKey("JAVA_HOME"))
            {
                string studioJbr = @"C:\Program Files\Android\Android Studio\jbr";
                if (Directory.Exists(studioJbr))
                {
                    startInfo.Environment["JAVA_HOME"] = studioJbr;
                }
            }
        }

        private static string QuoteIfNeeded(string value)
        {
            return value.Contains(' ') ? "\"" + value + "\"" : value;
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private readonly record struct ProcessResult(int ExitCode, string Output, string Error);
    }
}
