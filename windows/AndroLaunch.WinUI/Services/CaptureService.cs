using System.Diagnostics;
using Androlaunch.Core;

namespace AndroLaunch.WinUI.Services;

internal static class CaptureService
{
    public static RecordingSession? ActiveRecording { get; private set; }
    private static readonly byte[] PngSignature = { 137, 80, 78, 71, 13, 10, 26, 10 };

    private static ProcessStartInfo StartInfo(string executable, params string[] arguments)
    {
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (string argument in arguments) info.ArgumentList.Add(argument);
        if (!string.IsNullOrWhiteSpace(AdbHelper.AdbPath)) info.Environment["ADB"] = AdbHelper.AdbPath;
        return info;
    }

    private static string NewPath(string extension)
    {
        Directory.CreateDirectory(QuickAccessStore.CaptureDirectory);
        return Path.Combine(QuickAccessStore.CaptureDirectory, $"{QuickAccessStore.CapturePrefix}-{DateTime.Now:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.{extension}");
    }

    public static async Task<string> ScreenshotAsync(string serial, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(serial)) throw new ArgumentException("Select a connected device first.", nameof(serial));
        AdbHelper.RefreshToolPaths();
        string destination = NewPath("png");
        string temporary = destination + ".partial";
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            using var process = Process.Start(StartInfo(AdbHelper.AdbPath ?? "adb.exe", "-s", serial, "exec-out", "screencap", "-p"))
                ?? throw new InvalidOperationException("Could not start adb.");
            using var registration = timeout.Token.Register(() => Kill(process));
            Task<string> error = process.StandardError.ReadToEndAsync();
            await using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                await process.StandardOutput.BaseStream.CopyToAsync(file, timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            string detail = await error;
            if (process.ExitCode != 0) throw new IOException($"Screenshot failed. Unlock and reconnect the device, then retry. {detail.Trim()}");
            // adb exec-out must produce a PNG, not a shell error saved with an image extension.
            byte[] signature = new byte[8];
            await using (var file = File.OpenRead(temporary))
            {
                if (await file.ReadAsync(signature, timeout.Token) != 8 || !signature.AsSpan().SequenceEqual(PngSignature))
                    throw new IOException("The device did not return a PNG screenshot. Protected screens may not support capture.");
            }
            File.Move(temporary, destination);
            return destination;
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public static async Task<RecordingSession> StartRecordingAsync(string serial)
    {
        if (ActiveRecording is { IsRunning: true }) throw new InvalidOperationException("Stop the current recording before starting another.");
        var compatibility = await ToolCompatibility.CheckScrcpyAsync();
        if (!compatibility.IsCompatible) throw new InvalidOperationException(compatibility.Summary);
        MirrorPresetStore.Restore(serial);
        string destination = NewPath("mp4");
        var config = AdbHelper.GetConfig(serial);
        var info = StartInfo(AdbHelper.ScrcpyPath ?? "scrcpy.exe", "--serial", serial, "--record", destination,
            "--window-title", "AndroLaunch — Recording (close this window to stop)", "--no-clipboard-autosync");
        if (!config.AudioEnabled) info.ArgumentList.Add("--no-audio");
        if (config.MaxSize > 0) info.ArgumentList.Add($"--max-size={config.MaxSize}");
        if (config.MaxFps > 0) info.ArgumentList.Add($"--max-fps={config.MaxFps}");
        if (config.BitRate > 0) info.ArgumentList.Add($"--video-bit-rate={config.BitRate}M");
        var process = Process.Start(info) ?? throw new InvalidOperationException("Could not start the recorder.");
        var session = new RecordingSession(process, destination);
        ActiveRecording = session;
        // Completion observes early startup errors and natural user closure as well as Stop.
        await Task.WhenAny(session.Completion, Task.Delay(700));
        if (session.Completion.IsCompleted) await session.Completion;
        return session;
    }

    private static void Kill(Process process)
    {
        try { if (!process.HasExited) process.Kill(true); }
        catch (InvalidOperationException) { }
        catch (System.ComponentModel.Win32Exception) { }
    }

    internal sealed class RecordingSession
    {
        private readonly Process process;
        public string Path { get; }
        public DateTimeOffset StartedAt { get; } = DateTimeOffset.Now;
        public Task Completion { get; }
        public bool IsRunning => !Completion.IsCompleted;

        internal RecordingSession(Process process, string path)
        {
            this.process = process;
            Path = path;
            Completion = ObserveAsync();
        }

        private async Task ObserveAsync()
        {
            try
            {
                Task<string> output = process.StandardOutput.ReadToEndAsync();
                Task<string> error = process.StandardError.ReadToEndAsync();
                await process.WaitForExitAsync();
                await output;
                string detail = await error;
                if (process.ExitCode != 0)
                    throw new IOException($"Recording stopped with an error. If a partial file exists, it is retained at {Path}. {detail.Trim()}");
                if (!File.Exists(Path) || new FileInfo(Path).Length == 0)
                    throw new IOException("The recorder exited without saving a video. Check device authorization and try again.");
            }
            finally { process.Dispose(); }
        }

        public async Task StopAsync()
        {
            if (!IsRunning) { await Completion; return; }
            // SDL's window-close event lets scrcpy finish the MP4 container. Never Kill a recorder.
            bool requested = false;
            for (int attempt = 0; attempt < 40 && IsRunning; attempt++)
            {
                try
                {
                    process.Refresh();
                    if (process.CloseMainWindow()) { requested = true; break; }
                }
                catch (InvalidOperationException) { break; }
                await Task.Delay(250);
            }
            if (IsRunning && !requested)
                throw new IOException("The recording window is not ready to close. Close its window manually, then wait for the video to finish saving.");
            try { await Completion.WaitAsync(TimeSpan.FromSeconds(20)); }
            catch (TimeoutException)
            {
                throw new IOException("The recorder is still finishing. Close its recording window and wait; the app will not force-stop it or risk corrupting the video.");
            }
        }
    }
}
