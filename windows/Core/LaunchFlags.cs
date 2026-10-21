using System;
using System.Collections.Generic;
using System.Text;

namespace Androlaunch.Core
{
    /// <summary>Launch options for an Android Virtual Device, mirroring the macOS LaunchFlags model.</summary>
    public sealed class LaunchFlags
    {
        // Core
        public bool NoAudio { get; set; }
        public bool NoWindow { get; set; }
        public bool Verbose { get; set; }
        public bool NoSkin { get; set; }
        public bool QtHideWindow { get; set; }

        // Boot
        public bool WipeData { get; set; }
        public bool ReadOnly { get; set; }
        public bool NoBootAnim { get; set; }
        public bool NoJni { get; set; }

        // Snapshot
        public bool NoSnapshotSave { get; set; }
        public bool NoSnapshotLoad { get; set; }
        public string Snapshot { get; set; } = "";

        // GPU
        public string GpuMode { get; set; } = "auto";

        // Network
        public string NetSpeed { get; set; } = "full";
        public string NetDelay { get; set; } = "none";
        public string HttpProxy { get; set; } = "";
        public string DnsServer { get; set; } = "";

        // Performance
        public string MemoryMB { get; set; } = "";
        public string Cores { get; set; } = "";
        public string Port { get; set; } = "";

        // Camera
        public string CameraBack { get; set; } = "";
        public string CameraFront { get; set; } = "";

        // Audio
        public bool AudioInput { get; set; }
        public bool AudioOutput { get; set; }

        // Extra
        public string Tcpdump { get; set; } = "";
        public string Timezone { get; set; } = "";

        public LaunchFlags Clone() => (LaunchFlags)MemberwiseClone();

        public List<string> ToArguments(string avdName)
        {
            var args = new List<string> { "-avd", avdName };
            if (!string.IsNullOrWhiteSpace(avdName))
            {
                args.AddRange(new[] { "-prop", $"ro.product.model={avdName.Replace(' ', '_')}" });
            }

            if (NoAudio) args.Add("-no-audio");
            if (NoWindow) args.Add("-no-window");
            if (Verbose) args.Add("-verbose");
            if (NoSkin) args.Add("-no-skin");
            if (QtHideWindow) args.Add("-qt-hide-window");

            if (WipeData) args.Add("-wipe-data");
            if (ReadOnly) args.Add("-read-only");
            if (NoBootAnim) args.Add("-no-boot-anim");
            if (NoJni) args.Add("-nojni");

            if (NoSnapshotSave) args.Add("-no-snapshot-save");
            if (NoSnapshotLoad) args.Add("-no-snapshot-load");
            if (!string.IsNullOrWhiteSpace(Snapshot)) args.AddRange(new[] { "-snapshot", Snapshot });

            if (!string.IsNullOrWhiteSpace(GpuMode) && GpuMode != "none")
            {
                args.AddRange(new[] { "-gpu", GpuMode });
            }

            if (!string.IsNullOrWhiteSpace(NetSpeed) && NetSpeed != "full")
            {
                args.AddRange(new[] { "-netspeed", NetSpeed });
            }
            if (!string.IsNullOrWhiteSpace(NetDelay) && NetDelay != "none")
            {
                args.AddRange(new[] { "-netdelay", NetDelay });
            }
            if (!string.IsNullOrWhiteSpace(HttpProxy)) args.AddRange(new[] { "-http-proxy", HttpProxy });
            if (!string.IsNullOrWhiteSpace(DnsServer)) args.AddRange(new[] { "-dns-server", DnsServer });

            if (!string.IsNullOrWhiteSpace(MemoryMB)) args.AddRange(new[] { "-memory", MemoryMB });
            if (!string.IsNullOrWhiteSpace(Cores)) args.AddRange(new[] { "-cores", Cores });
            if (!string.IsNullOrWhiteSpace(Port)) args.AddRange(new[] { "-port", Port });

            if (!string.IsNullOrWhiteSpace(CameraBack)) args.AddRange(new[] { "-camera-back", CameraBack });
            if (!string.IsNullOrWhiteSpace(CameraFront)) args.AddRange(new[] { "-camera-front", CameraFront });

            if (!NoAudio)
            {
                if (AudioInput) args.AddRange(new[] { "-prop", "hw.audioInput=yes" });
                if (AudioOutput) args.AddRange(new[] { "-prop", "hw.audioOutput=yes" });
            }

            if (!string.IsNullOrWhiteSpace(Tcpdump)) args.AddRange(new[] { "-tcpdump", Tcpdump });
            if (!string.IsNullOrWhiteSpace(Timezone)) args.AddRange(new[] { "-timezone", Timezone });

            return args;
        }

        public string ToCommandLine(string avdName)
        {
            var builder = new StringBuilder("emulator.exe");
            foreach (string argument in ToArguments(avdName))
            {
                builder.Append(' ');
                builder.Append(argument.Contains(' ') ? $"\"{argument}\"" : argument);
            }

            return builder.ToString();
        }
    }
}
