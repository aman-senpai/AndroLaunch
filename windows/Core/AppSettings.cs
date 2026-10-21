using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Androlaunch.Core
{
    public sealed class PreviousDevice
    {
        public string SerialNumber { get; set; } = "";
        public string Name { get; set; } = "";
        public string? Model { get; set; }
        public string LastKnownHost { get; set; } = "";
        public DateTimeOffset LastConnected { get; set; } = DateTimeOffset.Now;
    }

    public sealed class AppSettings
    {
        public bool HasCompletedOnboarding { get; set; }
        public string? CommandLineToolsPath { get; set; }
        public string? AvdPath { get; set; }
        public string? ImageDownloadPath { get; set; }
        public string? EmulatorPath { get; set; }
        public string? AdbPath { get; set; }
        public string? ScrcpyPath { get; set; }
        public List<PreviousDevice> PreviousDevices { get; set; } = new();
        public Dictionary<string, LaunchFlags> AvdLaunchFlags { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>User settings and Android SDK path discovery for the Windows build.</summary>
    public static class AppSettingsStore
    {
        private static readonly object Gate = new();
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            WriteIndented = true,
            PropertyNameCaseInsensitive = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        private static AppSettings? _current;

        public static string SettingsDirectory => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "AndroLaunch");

        public static string SettingsPath => Path.Combine(SettingsDirectory, "settings.json");

        public static string DefaultSdkRoot => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Android", "Sdk");

        public static string DefaultAvdPath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".android", "avd");

        public static AppSettings Current
        {
            get
            {
                lock (Gate)
                {
                    return _current ??= Load();
                }
            }
        }

        public static void Save()
        {
            lock (Gate)
            {
                try
                {
                    Directory.CreateDirectory(SettingsDirectory);
                    File.WriteAllText(SettingsPath, JsonSerializer.Serialize(Current, JsonOptions));
                }
                catch
                {
                    // Settings are best-effort; the app stays usable without them.
                }
            }
        }

        private static AppSettings Load()
        {
            AppSettings settings;
            try
            {
                settings = File.Exists(SettingsPath)
                    ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), JsonOptions) ?? new AppSettings()
                    : new AppSettings();
            }
            catch
            {
                settings = new AppSettings();
            }

            settings.CommandLineToolsPath ??= AutoDetectCommandLineToolsPath();
            settings.EmulatorPath ??= AutoDetectEmulatorPath();
            settings.AvdPath ??= DefaultAvdPath;
            settings.ImageDownloadPath ??= DefaultSdkRoot;
            settings.PreviousDevices ??= new List<PreviousDevice>();
            settings.AvdLaunchFlags ??= new Dictionary<string, LaunchFlags>(StringComparer.OrdinalIgnoreCase);
            return settings;
        }

        public static string? AutoDetectCommandLineToolsPath()
        {
            var candidates = new List<string>();
            foreach (string? root in EnumerateSdkRoots())
            {
                if (string.IsNullOrWhiteSpace(root))
                {
                    continue;
                }

                string cmdlineTools = Path.Combine(root, "cmdline-tools");
                try
                {
                    if (Directory.Exists(cmdlineTools))
                    {
                        candidates.AddRange(
                            Directory.GetDirectories(cmdlineTools)
                                .OrderByDescending(path => string.Equals(Path.GetFileName(path), "latest", StringComparison.OrdinalIgnoreCase))
                                .ThenByDescending(path => path, StringComparer.OrdinalIgnoreCase)
                                .Select(path => Path.Combine(path, "bin")));
                    }
                }
                catch
                {
                    // Keep looking in the other roots.
                }
            }

            candidates.AddRange(PathDirectories().Select(dir => dir));
            foreach (string candidate in candidates)
            {
                if (!string.IsNullOrWhiteSpace(candidate) &&
                    File.Exists(Path.Combine(candidate, "sdkmanager.bat")) &&
                    File.Exists(Path.Combine(candidate, "avdmanager.bat")))
                {
                    return candidate;
                }
            }

            return null;
        }

        public static string? AutoDetectEmulatorPath()
        {
            foreach (string? root in EnumerateSdkRoots())
            {
                if (string.IsNullOrWhiteSpace(root))
                {
                    continue;
                }

                string path = Path.Combine(root, "emulator", "emulator.exe");
                if (File.Exists(path))
                {
                    return path;
                }
            }

            foreach (string directory in PathDirectories())
            {
                string path = Path.Combine(directory, "emulator.exe");
                if (File.Exists(path))
                {
                    return path;
                }
            }

            return null;
        }

        public static string SdkRootFromToolsPath(string? toolsPath)
        {
            if (string.IsNullOrWhiteSpace(toolsPath))
            {
                return DefaultSdkRoot;
            }

            try
            {
                // <sdk>/cmdline-tools/latest/bin -> <sdk>
                DirectoryInfo? latest = Directory.GetParent(toolsPath.TrimEnd(Path.DirectorySeparatorChar));
                DirectoryInfo? cmdlineTools = latest?.Parent;
                DirectoryInfo? sdkRoot = cmdlineTools?.Parent;
                return sdkRoot?.FullName ?? DefaultSdkRoot;
            }
            catch
            {
                return DefaultSdkRoot;
            }
        }

        public static string AvdPathOrDefault =>
            string.IsNullOrWhiteSpace(Current.AvdPath) ? DefaultAvdPath : Current.AvdPath!;

        public static string ImageDownloadPathOrDefault =>
            string.IsNullOrWhiteSpace(Current.ImageDownloadPath) ? DefaultSdkRoot : Current.ImageDownloadPath!;

        public static bool ToolsAvailable =>
            !string.IsNullOrWhiteSpace(Current.CommandLineToolsPath) &&
            File.Exists(Path.Combine(Current.CommandLineToolsPath!, "sdkmanager.bat")) &&
            File.Exists(Path.Combine(Current.CommandLineToolsPath!, "avdmanager.bat"));

        public static void AddPreviousDevice(string serial, string name, string? model, string host)
        {
            if (string.IsNullOrWhiteSpace(serial))
            {
                return;
            }

            lock (Gate)
            {
                var settings = Current;
                settings.PreviousDevices.RemoveAll(device =>
                    string.Equals(device.SerialNumber, serial, StringComparison.OrdinalIgnoreCase));
                settings.PreviousDevices.Insert(0, new PreviousDevice
                {
                    SerialNumber = serial,
                    Name = string.IsNullOrWhiteSpace(name) ? serial : name,
                    Model = model,
                    LastKnownHost = string.IsNullOrWhiteSpace(host) ? serial : host,
                    LastConnected = DateTimeOffset.Now
                });

                if (settings.PreviousDevices.Count > 12)
                {
                    settings.PreviousDevices.RemoveRange(12, settings.PreviousDevices.Count - 12);
                }
            }

            Save();
        }

        public static void RemovePreviousDevice(string serial)
        {
            lock (Gate)
            {
                Current.PreviousDevices.RemoveAll(device =>
                    string.Equals(device.SerialNumber, serial, StringComparison.OrdinalIgnoreCase));
            }

            Save();
        }

        public static LaunchFlags GetLaunchFlags(string avdName)
        {
            lock (Gate)
            {
                return Current.AvdLaunchFlags.TryGetValue(avdName, out LaunchFlags? flags)
                    ? flags
                    : new LaunchFlags();
            }
        }

        public static void SetLaunchFlags(string avdName, LaunchFlags flags)
        {
            lock (Gate)
            {
                Current.AvdLaunchFlags[avdName] = flags;
            }

            Save();
        }

        private static IEnumerable<string?> EnumerateSdkRoots()
        {
            yield return DefaultSdkRoot;
            yield return Environment.GetEnvironmentVariable("ANDROID_HOME");
            yield return Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
            yield return @"C:\Android\sdk";
            yield return @"C:\Program Files\Android\Android Studio";
        }

        private static IEnumerable<string> PathDirectories()
        {
            string? path = Environment.GetEnvironmentVariable("PATH");
            if (string.IsNullOrEmpty(path))
            {
                yield break;
            }

            foreach (string directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            {
                yield return directory.Trim().Trim('"');
            }
        }
    }
}
