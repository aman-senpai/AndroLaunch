using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Androlaunch.Core;

namespace AndroLaunch.WinUI.Services
{
    public static class MirrorPresetStore
    {
        public sealed class DevicePreferences
        {
            public string Preset { get; set; } = "Balanced";
            public AdbHelper.MirrorConfig Configuration { get; set; } = new();
        }

        public static readonly string[] Names = { "Balanced", "Best quality", "Low bandwidth", "Presentation", "Custom" };
        public static readonly string[] Descriptions =
        {
            "1600 px · 60 fps · 8 Mbps. Smooth everyday control with moderate bandwidth.",
            "Original size · up to 120 fps · 20 Mbps. Sharpest picture; uses more bandwidth and device power.",
            "800 px · 30 fps · 2 Mbps. Easier on Wi-Fi; smaller text and less fluid motion.",
            "1920 px · 30 fps · 8 Mbps · borderless. Clear slides and demos; less suited to fast motion.",
            "Your advanced settings. Saved for this device, including camera and session options."
        };

        private static readonly string FilePath = Path.Combine(AppSettingsStore.SettingsDirectory, "mirror-presets.json");
        private static readonly object Gate = new();
        private static Dictionary<string, DevicePreferences>? preferences;

        public static void Restore(string serial) => Load(serial, AdbHelper.GetConfig(serial));

        public static string Load(string serial, AdbHelper.MirrorConfig target)
        {
            lock (Gate)
            {
                EnsureLoaded();
                if (preferences!.TryGetValue(serial, out var stored))
                {
                    Copy(stored.Configuration, target);
                    return Array.IndexOf(Names, stored.Preset) >= 0 ? stored.Preset : "Custom";
                }
                Apply("Balanced", target);
                return "Balanced";
            }
        }

        public static void Apply(string preset, AdbHelper.MirrorConfig target)
        {
            switch (preset)
            {
                case "Balanced":
                    target.MaxSize = 1600; target.MaxFps = 60; target.BitRate = 8; target.Borderless = false;
                    break;
                case "Best quality":
                    target.MaxSize = 0; target.MaxFps = 120; target.BitRate = 20; target.Borderless = false;
                    break;
                case "Low bandwidth":
                    target.MaxSize = 800; target.MaxFps = 30; target.BitRate = 2; target.Borderless = false;
                    break;
                case "Presentation":
                    target.MaxSize = 1920; target.MaxFps = 30; target.BitRate = 8; target.Borderless = true;
                    break;
                default:
                    return;
            }
            target.FlexDisplay = false;
        }

        public static void Save(string serial, string preset, AdbHelper.MirrorConfig configuration)
        {
            lock (Gate)
            {
                EnsureLoaded();
                var snapshot = new AdbHelper.MirrorConfig();
                Copy(configuration, snapshot);
                var next = new Dictionary<string, DevicePreferences>(preferences!, StringComparer.Ordinal);
                next[serial] = new DevicePreferences { Preset = preset, Configuration = snapshot };
                Directory.CreateDirectory(AppSettingsStore.SettingsDirectory);
                string temporaryPath = FilePath + ".tmp";
                File.WriteAllText(temporaryPath, JsonSerializer.Serialize(next, new JsonSerializerOptions { WriteIndented = true }));
                File.Move(temporaryPath, FilePath, overwrite: true);
                preferences = next;
            }
        }

        private static void EnsureLoaded()
        {
            if (preferences is not null) return;
            preferences = File.Exists(FilePath)
                ? JsonSerializer.Deserialize<Dictionary<string, DevicePreferences>>(File.ReadAllText(FilePath))
                    ?? throw new InvalidDataException("The saved mirror preferences are empty or invalid.")
                : new Dictionary<string, DevicePreferences>(StringComparer.Ordinal);
        }

        private static void Copy(AdbHelper.MirrorConfig source, AdbHelper.MirrorConfig target)
        {
            target.MaxSize = source.MaxSize;
            target.AppResolution = source.AppResolution;
            target.MaxFps = source.MaxFps;
            target.BitRate = source.BitRate;
            target.AudioEnabled = source.AudioEnabled;
            target.ClipboardEnabled = source.ClipboardEnabled;
            target.Orientation = source.Orientation;
            target.Borderless = source.Borderless;
            target.FlexDisplay = source.FlexDisplay;
            target.CameraFacing = source.CameraFacing;
            target.CameraFps = source.CameraFps;
            target.CameraSize = source.CameraSize;
            target.CameraAr = source.CameraAr;
        }
    }
}
