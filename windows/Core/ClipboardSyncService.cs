using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

namespace Androlaunch.Core
{
    /// <summary>
    /// Clipboard bridge that does not depend on WinForms. Host-to-device uses a Win32 clipboard
    /// poll and an adb broadcast; device-to-host reads scrcpy's "Device clipboard" output.
    /// </summary>
    public static class ClipboardSyncService
    {
        private const uint CfUnicodeText = 13;
        private const uint GmemMoveable = 0x0002;

        private static readonly object Gate = new();
        private static readonly HashSet<string> ActiveDevices = new(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, Process> Processes = new(StringComparer.OrdinalIgnoreCase);
        private static Timer? observer;
        private static string? lastClipboardText;

        public static bool IsActive(string serial)
        {
            lock (Gate)
            {
                return ActiveDevices.Contains(serial);
            }
        }

        public static void Toggle(string serial, bool enable)
        {
            lock (Gate)
            {
                if (enable)
                {
                    if (ActiveDevices.Add(serial))
                    {
                        StartScrcpy(serial);
                        lastClipboardText = GetClipboardText();
                        observer ??= new Timer(_ => PollClipboard(), null, 1000, 1000);
                    }
                }
                else
                {
                    ActiveDevices.Remove(serial);
                    StopScrcpy(serial);
                    if (ActiveDevices.Count == 0)
                    {
                        observer?.Dispose();
                        observer = null;
                        lastClipboardText = null;
                    }
                }
            }
        }

        public static void Dispose()
        {
            lock (Gate)
            {
                foreach (string serial in Processes.Keys.ToList())
                {
                    StopScrcpy(serial);
                }

                observer?.Dispose();
                observer = null;
                ActiveDevices.Clear();
            }
        }

        private static void StartScrcpy(string serial)
        {
            try
            {
                string? scrcpy = AdbHelper.ScrcpyPath;
                if (string.IsNullOrWhiteSpace(scrcpy))
                {
                    return;
                }

                var startInfo = new ProcessStartInfo
                {
                    FileName = scrcpy,
                    Arguments = $"-s {serial} --no-video --no-audio --no-window",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    WorkingDirectory = System.IO.Path.GetDirectoryName(scrcpy) ?? ""
                };

                if (!string.IsNullOrWhiteSpace(AdbHelper.AdbPath))
                {
                    startInfo.Environment["ADB"] = AdbHelper.AdbPath;
                }

                var process = new Process { StartInfo = startInfo };
                process.OutputDataReceived += (_, e) =>
                {
                    if (string.IsNullOrWhiteSpace(e.Data))
                    {
                        return;
                    }

                    Debug.WriteLine($"[scrcpy-{serial}] {e.Data}");
                    const string marker = "Device clipboard: ";
                    int index = e.Data.IndexOf(marker, StringComparison.Ordinal);
                    if (index >= 0)
                    {
                        string text = e.Data[(index + marker.Length)..].Trim();
                        if (text.Length > 0)
                        {
                            lastClipboardText = text;
                            SetClipboardText(text);
                        }
                    }
                };
                process.ErrorDataReceived += (_, e) =>
                {
                    if (!string.IsNullOrWhiteSpace(e.Data))
                    {
                        Debug.WriteLine($"[scrcpy-err-{serial}] {e.Data}");
                    }
                };

                if (process.Start())
                {
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    Processes[serial] = process;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to start clipboard sync: {ex.Message}");
            }
        }

        private static void StopScrcpy(string serial)
        {
            if (!Processes.TryGetValue(serial, out Process? process))
            {
                return;
            }

            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // The process may already have exited.
            }

            process.Dispose();
            Processes.Remove(serial);
        }

        private static void PollClipboard()
        {
            try
            {
                string? text = GetClipboardText();
                if (string.IsNullOrEmpty(text) || text == lastClipboardText || text.Length >= 100000)
                {
                    return;
                }

                lastClipboardText = text;
                string[] serials;
                lock (Gate)
                {
                    serials = ActiveDevices.ToArray();
                }

                foreach (string serial in serials)
                {
                    SendToDevice(serial, text);
                }
            }
            catch
            {
                // Clipboard access can fail while another app owns it.
            }
        }

        private static void SendToDevice(string serial, string text)
        {
            try
            {
                string escaped = text.Replace("'", "'\\''");
                AdbHelper.RunAdbCommand(
                    $"-s {serial} shell am broadcast -a ch.pete.adbclipboard.WRITE -n ch.pete.adbclipboard/.WriteReceiver -e text '{escaped}'");
            }
            catch
            {
                // The device may not have the clipboard helper installed.
            }
        }

        private static string? GetClipboardText()
        {
            if (!OpenClipboard(IntPtr.Zero))
            {
                return null;
            }

            try
            {
                IntPtr handle = GetClipboardData(CfUnicodeText);
                if (handle == IntPtr.Zero)
                {
                    return null;
                }

                IntPtr pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero)
                {
                    return null;
                }

                try
                {
                    return Marshal.PtrToStringUni(pointer);
                }
                finally
                {
                    GlobalUnlock(handle);
                }
            }
            finally
            {
                CloseClipboard();
            }
        }

        private static void SetClipboardText(string text)
        {
            if (!OpenClipboard(IntPtr.Zero))
            {
                return;
            }

            try
            {
                EmptyClipboard();
                IntPtr pointer = Marshal.StringToHGlobalUni(text);
                if (SetClipboardData(CfUnicodeText, pointer) == IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(pointer);
                }
            }
            finally
            {
                CloseClipboard();
            }
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool OpenClipboard(IntPtr newOwner);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EmptyClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetClipboardData(uint format);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetClipboardData(uint format, IntPtr data);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GlobalLock(IntPtr handle);

        [DllImport("kernel32.dll")]
        private static extern bool GlobalUnlock(IntPtr handle);
    }
}
