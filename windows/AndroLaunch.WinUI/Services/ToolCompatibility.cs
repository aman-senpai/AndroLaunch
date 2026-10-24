using System;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Androlaunch.Core;

namespace AndroLaunch.WinUI.Services
{
    public static class ToolCompatibility
    {
        public sealed record Status(bool IsCompatible, string Summary, string? ExecutablePath = null);

        public static async Task<Status> CheckScrcpyAsync()
        {
            try
            {
                // ResolvePaths respects the user's explicit override; TestScrcpy does not.
                AdbHelper.RefreshToolPaths();
                string path = AdbHelper.ScrcpyPath ?? "scrcpy.exe";
                using var process = new Process
                {
                    StartInfo = new ProcessStartInfo(path, "--version")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true
                    }
                };
                if (!process.Start())
                {
                    return new(false, "Could not start scrcpy. Install scrcpy 4.0 or newer, or correct its override in Advanced settings.");
                }

                Task<string> stdout = process.StandardOutput.ReadToEndAsync();
                Task<string> stderr = process.StandardError.ReadToEndAsync();
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
                try
                {
                    await process.WaitForExitAsync(timeout.Token);
                }
                catch (OperationCanceledException)
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    return new(false, "scrcpy version check timed out. Check the executable in Advanced settings, then refresh.", path);
                }

                string output = (await stdout) + "\n" + (await stderr);
                Match match = Regex.Match(output, @"\bscrcpy\s+v?(\d+\.\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);
                if (process.ExitCode != 0 || !match.Success || !Version.TryParse(match.Groups[1].Value, out Version? version))
                {
                    return new(false, "scrcpy was found, but its version could not be verified. Install scrcpy 4.0 or newer, or correct its override in Advanced settings.", path);
                }

                return version >= new Version(4, 0)
                    ? new(true, $"scrcpy {version} — compatible (4.0 or newer required).", path)
                    : new(false, $"scrcpy {version} is unsupported. Update to scrcpy 4.0 or newer, then refresh. If an override is set, update it in Advanced settings.", path);
            }
            catch (Exception ex)
            {
                return new(false, $"scrcpy is unavailable: {ex.Message} Install scrcpy 4.0 or newer, or correct its override in Advanced settings.");
            }
        }
    }
}
