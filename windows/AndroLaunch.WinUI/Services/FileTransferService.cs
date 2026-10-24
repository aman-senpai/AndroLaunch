using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Androlaunch.Core;

namespace AndroLaunch.WinUI.Services;

public enum TransferState { Queued, Transferring, Completed, Skipped, Failed, Cancelled }
public enum TransferConflictChoice { Overwrite, Skip, Rename }
public sealed record TransferConflict(string Serial, string Destination, bool IsDirectory, bool Upload);
public sealed record TransferConflictDecision(TransferConflictChoice Choice, string? NewName = null);
public sealed record TransferProgress(long? Bytes, long? TotalBytes, double? BytesPerSecond, TimeSpan? Remaining, int? AdbPercent);

public sealed class FileTransferItem
{
    public required string Serial { get; init; }
    public required string Source { get; init; }
    public required string Destination { get; set; }
    public required bool Upload { get; init; }
    public required bool IsDirectory { get; init; }
    public long? TotalBytes { get; set; }
    public TransferState State { get; set; } = TransferState.Queued;
    public string Message { get; set; } = "Waiting";
    public TransferProgress? Progress { get; set; }
}

/// <summary>One adb transfer at a time, staged beside its destination until it succeeds.</summary>
public sealed class FileTransferService
{
    public async Task RunAsync(IReadOnlyList<FileTransferItem> items,
        Func<TransferConflict, Task<TransferConflictDecision>> resolveConflict,
        Action<FileTransferItem> changed, CancellationToken cancellationToken)
    {
        foreach (FileTransferItem item in items)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                item.State = TransferState.Cancelled;
                item.Message = "Not started — queue cancelled";
                changed(item);
                continue;
            }
            await TransferAsync(item, resolveConflict, changed, cancellationToken);
        }
    }

    private async Task TransferAsync(FileTransferItem item,
        Func<TransferConflict, Task<TransferConflictDecision>> resolveConflict,
        Action<FileTransferItem> changed, CancellationToken token)
    {
        string? stage = null;
        string? approvedDestination = null;
        bool committing = false;
        try
        {
            item.State = TransferState.Transferring;
            item.Message = "Checking destination…";
            item.Progress = null;
            changed(item);
            await ValidateSourceAsync(item, token);
            if (!await ResolveDestinationAsync()) return;
            token.ThrowIfCancellationRequested();
            stage = Sibling(item.Destination, ".androlaunch-" + Guid.NewGuid().ToString("N") + ".partial", item.Upload);
            item.Message = "Transferring to a temporary location; existing destination is unchanged.";
            changed(item);
            var clock = Stopwatch.StartNew();
            using var monitorCancellation = CancellationTokenSource.CreateLinkedTokenSource(token);
            Task monitor = MonitorAsync(item, stage, clock, changed, monitorCancellation.Token);
            try
            {
                await RunAdbAsync(item.Serial,
                    new[] { item.Upload ? "push" : "pull", item.Source, stage }, token,
                    line =>
                    {
                        Match match = Regex.Match(line, @"\[\s*(\d+)%\]");
                        if (match.Success && int.TryParse(match.Groups[1].Value, out int percent))
                        {
                            item.Progress = (item.Progress ?? new(null, item.TotalBytes, null, null, null)) with { AdbPercent = percent };
                            changed(item);
                        }
                    });
            }
            finally
            {
                monitorCancellation.Cancel();
                await monitor;
            }
            token.ThrowIfCancellationRequested();
            // Recheck after staging: another queue item or an external writer may have created the name.
            if (!await ResolveDestinationAsync()) return;
            token.ThrowIfCancellationRequested();
            item.Message = "Finishing safely…";
            changed(item);
            committing = true;
            // A rename/rollback must finish even if Cancel is pressed in this short commit section.
            using var commitTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            string? retainedBackup = item.Upload
                ? await CommitRemoteAsync(item.Serial, stage, item.Destination, approvedDestination == item.Destination, commitTimeout.Token)
                : await Task.Run(() => CommitLocal(stage, item.Destination, approvedDestination == item.Destination));
            stage = null;
            item.State = TransferState.Completed;
            item.Message = retainedBackup is null ? "Completed" : $"Completed; previous destination retained at {retainedBackup}";
            item.Progress = new(item.TotalBytes, item.TotalBytes, null, null, 100);
        }
        catch (OperationCanceledException)
        {
            item.State = committing ? TransferState.Failed : token.IsCancellationRequested ? TransferState.Cancelled : TransferState.Failed;
            item.Message = committing
                ? "Finalization was interrupted; inspect the destination and any retained backup before retrying. Earlier completed items are kept."
                : token.IsCancellationRequested
                    ? "Cancelled — this item was not committed; earlier completed items are kept."
                    : "The operation timed out; inspect the destination before retrying.";
        }
        catch (Exception ex)
        {
            item.State = TransferState.Failed;
            item.Message = ex.Message;
        }
        finally
        {
            if (stage is not null)
            {
                try
                {
                    using var cleanupTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                    if (item.Upload)
                        await RunAdbAsync(item.Serial, new[] { "shell", "rm -rf -- " + QuoteRemote(stage) }, cleanupTimeout.Token);
                    else await Task.Run(() => DeleteLocal(stage));
                }
                catch (Exception ex)
                {
                    item.Message += $" Temporary data may remain at {stage}: {ex.Message}";
                }
            }
            changed(item);
        }

        async Task<bool> ResolveDestinationAsync()
        {
            while (await ExistsAsync(item.Serial, item.Destination, item.Upload, token))
            {
                if (approvedDestination == item.Destination) return true;
                token.ThrowIfCancellationRequested();
                TransferConflictDecision decision = await resolveConflict(new(item.Serial, item.Destination, item.IsDirectory, item.Upload));
                token.ThrowIfCancellationRequested();
                if (decision.Choice == TransferConflictChoice.Skip)
                {
                    item.State = TransferState.Skipped;
                    item.Message = "Skipped — destination kept unchanged";
                    return false;
                }
                if (decision.Choice == TransferConflictChoice.Overwrite)
                {
                    approvedDestination = item.Destination;
                    return true;
                }
                if (!ValidName(decision.NewName, item.Upload))
                    throw new IOException("The new name must be a single valid file or folder name.");
                item.Destination = Sibling(item.Destination, decision.NewName!, item.Upload);
                changed(item);
            }
            return true;
        }
    }

    private static async Task ValidateSourceAsync(FileTransferItem item, CancellationToken token)
    {
        string destinationName = item.Upload
            ? item.Destination[(item.Destination.LastIndexOf('/') + 1)..]
            : Path.GetFileName(item.Destination);
        if (!ValidName(destinationName, item.Upload))
            throw new IOException("The destination must have a valid file or folder name; storage roots cannot be replaced.");
        if (item.Upload)
        {
            await Task.Run(() =>
            {
                token.ThrowIfCancellationRequested();
                if ((File.GetAttributes(item.Source) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Linked files/folders are not uploaded. Select an ordinary file or folder instead.");
                if (!item.IsDirectory)
                {
                    item.TotalBytes = new FileInfo(item.Source).Length;
                    return;
                }
                foreach (string entry in Directory.EnumerateFileSystemEntries(item.Source, "*", new EnumerationOptions
                {
                    RecurseSubdirectories = true,
                    AttributesToSkip = 0,
                    IgnoreInaccessible = false
                }))
                {
                    token.ThrowIfCancellationRequested();
                    if ((File.GetAttributes(entry) & FileAttributes.ReparsePoint) != 0)
                        throw new IOException("This folder contains a link. Linked files/folders are not uploaded.");
                }
            }, token);
        }
        else if (item.IsDirectory)
        {
            string links = await RunAdbAsync(item.Serial,
                new[] { "shell", "find " + QuoteRemote(item.Source) + " -type l -print" }, token);
            if (!string.IsNullOrWhiteSpace(links))
                throw new IOException("This folder contains symbolic links. Download ordinary files/folders directly to avoid following links outside the selected tree.");
        }
    }

    public static Task DeleteRemoteAsync(string serial, string path, CancellationToken token) =>
        RunAdbAsync(serial, new[] { "shell", "rm -rf -- " + QuoteRemote(path) }, token);

    public static Task CreateDirectoryAsync(string serial, string path, CancellationToken token) =>
        RunAdbAsync(serial, new[] { "shell", "mkdir -- " + QuoteRemote(path) }, token);

    private static async Task MonitorAsync(FileTransferItem item, string stage, Stopwatch clock,
        Action<FileTransferItem> changed, CancellationToken token)
    {
        long previousBytes = 0;
        double previousSeconds = 0;
        try
        {
            while (true)
            {
                await Task.Delay(700, token);
                long? bytes = null;
                if (!item.Upload)
                {
                    try
                    {
                        if (File.Exists(stage)) bytes = new FileInfo(stage).Length;
                        else if (Directory.Exists(stage))
                            bytes = await Task.Run(() =>
                            {
                                long length = 0;
                                foreach (string path in Directory.EnumerateFiles(stage, "*", SearchOption.AllDirectories))
                                {
                                    token.ThrowIfCancellationRequested();
                                    length += new FileInfo(path).Length;
                                }
                                return length;
                            }, token);
                    }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                }
                else if (!item.IsDirectory)
                {
                    // adb suppresses terminal progress on some versions when redirected. Stat the
                    // fresh staging file, never the previous destination, to measure actual bytes.
                    using var sampleTimeout = CancellationTokenSource.CreateLinkedTokenSource(token);
                    sampleTimeout.CancelAfter(TimeSpan.FromSeconds(3));
                    try
                    {
                        string output = await RunAdbAsync(item.Serial,
                            new[] { "shell", "if [ -f " + QuoteRemote(stage) + " ]; then stat -c %s -- " + QuoteRemote(stage) + "; fi" }, sampleTimeout.Token);
                        if (long.TryParse(output.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out long count)) bytes = count;
                    }
                    catch (Exception) when (!token.IsCancellationRequested) { /* Transfer errors are reported by push/pull. */ }
                }
                if (bytes is not long measured) continue;
                double seconds = clock.Elapsed.TotalSeconds;
                double? rate = seconds > previousSeconds && measured >= previousBytes
                    ? (measured - previousBytes) / (seconds - previousSeconds) : null;
                TimeSpan? remaining = item.TotalBytes is long total && measured <= total && rate is > 0
                    ? TimeSpan.FromSeconds(Math.Min((total - measured) / rate.Value, TimeSpan.MaxValue.TotalSeconds - 1)) : null;
                previousBytes = measured;
                previousSeconds = seconds;
                item.Progress = new(measured, item.TotalBytes, rate, remaining, item.Progress?.AdbPercent);
                changed(item);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
    }

    public static bool ValidName(string? name, bool remote) =>
        !string.IsNullOrWhiteSpace(name) && name is not "." and not ".." &&
        !name.Contains('/') && !name.Contains('\\') && !name.Contains('\0') &&
        (remote || (name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 &&
                    !name.EndsWith('.') && !name.EndsWith(' ') &&
                    !Regex.IsMatch(name, @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)", RegexOptions.IgnoreCase)));

    public static string QuoteRemote(string text) => "'" + text.Replace("'", "'\"'\"'") + "'";

    private static string Sibling(string destination, string name, bool remote) => remote
        ? destination[..(destination.LastIndexOf('/') + 1)] + name
        : Path.Combine(Path.GetDirectoryName(destination)!, name);

    private static async Task<bool> ExistsAsync(string serial, string path, bool remote, CancellationToken token)
    {
        if (!remote) return Path.Exists(path);
        string quoted = QuoteRemote(path);
        string output = await RunAdbAsync(serial,
            new[] { "shell", "if [ -e " + quoted + " ] || [ -L " + quoted + " ]; then printf exists; fi" }, token);
        return output.Trim() == "exists";
    }

    private static string? CommitLocal(string stage, string destination, bool overwrite)
    {
        string? backup = null;
        if (Path.Exists(destination))
        {
            if (!overwrite) throw new IOException("Destination appeared during transfer; retry to choose how to handle the conflict.");
            backup = Sibling(destination, ".androlaunch-" + Guid.NewGuid().ToString("N") + ".backup", false);
            MoveLocal(destination, backup);
        }
        try { MoveLocal(stage, destination); }
        catch (Exception commitError)
        {
            if (backup is not null)
            {
                try { MoveLocal(backup, destination); }
                catch (Exception restoreError)
                {
                    throw new IOException($"Could not finish or restore the original. Original retained at {backup}. {restoreError.Message}", commitError);
                }
            }
            throw;
        }
        if (backup is null) return null;
        try { DeleteLocal(backup); return null; }
        catch (IOException) { return backup; }
        catch (UnauthorizedAccessException) { return backup; }
    }

    private static async Task<string?> CommitRemoteAsync(string serial, string stage, string destination, bool overwrite, CancellationToken token)
    {
        string backup = Sibling(destination, ".androlaunch-" + Guid.NewGuid().ToString("N") + ".backup", true);
        string s = QuoteRemote(stage), d = QuoteRemote(destination), b = QuoteRemote(backup);
        string script = "if [ -e " + d + " ] || [ -L " + d + " ]; then " +
            (overwrite ? "mv -n -T -- " + d + " " + b + " || exit 1; if [ -e " + d + " ] || [ -L " + d + " ]; then exit 1; fi; " : "echo 'Destination appeared during transfer; retry to resolve the conflict.' >&2; exit 1; ") +
            "fi; if mv -n -T -- " + s + " " + d + " && [ ! -e " + s + " ] && [ ! -L " + s + " ]; then " +
            "if [ -e " + b + " ] || [ -L " + b + " ]; then rm -rf -- " + b + " || { printf BACKUP_RETAINED; exit 0; }; fi; " +
            "else echo 'Destination could not be committed without a conflict.' >&2; " +
            "if [ -e " + b + " ] || [ -L " + b + " ]; then mv -n -T -- " + b + " " + d + "; " +
            "if [ -e " + b + " ] || [ -L " + b + " ]; then echo " + QuoteRemote("Original retained at " + backup) + " >&2; fi; fi; exit 1; fi";
        string output = await RunAdbAsync(serial, new[] { "shell", script }, token);
        return output.Contains("BACKUP_RETAINED", StringComparison.Ordinal) ? backup : null;
    }

    private static void MoveLocal(string source, string destination)
    {
        if (Directory.Exists(source)) Directory.Move(source, destination);
        else File.Move(source, destination);
    }

    private static void DeleteLocal(string path)
    {
        if (Directory.Exists(path)) Directory.Delete(path, true);
        else if (File.Exists(path)) File.Delete(path);
    }

    private static async Task<string> RunAdbAsync(string serial, IEnumerable<string> arguments,
        CancellationToken token, Action<string>? outputLine = null)
    {
        token.ThrowIfCancellationRequested();
        var info = new ProcessStartInfo
        {
            FileName = AdbHelper.AdbPath ?? "adb",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        info.ArgumentList.Add("-s");
        info.ArgumentList.Add(serial);
        foreach (string argument in arguments) info.ArgumentList.Add(argument);
        using var process = new Process { StartInfo = info };
        if (!process.Start()) throw new IOException("Could not start adb.");
        using var cancellation = token.Register(() =>
        {
            try { process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
        });
        var output = new StringBuilder();
        var errors = new StringBuilder();
        Task stdout = DrainAsync(process.StandardOutput, output);
        Task stderr = DrainAsync(process.StandardError, errors);
        try
        {
            await process.WaitForExitAsync(CancellationToken.None);
            await Task.WhenAll(stdout, stderr);
        }
        catch (IOException) when (token.IsCancellationRequested)
        {
            throw new OperationCanceledException(token);
        }
        token.ThrowIfCancellationRequested();
        if (process.ExitCode != 0)
            throw new IOException($"adb exited with code {process.ExitCode}: {errors}{output}".Trim());
        return output.ToString();

        async Task DrainAsync(StreamReader reader, StringBuilder buffer)
        {
            while (await reader.ReadLineAsync() is string line)
            {
                if (buffer.Length < 16000) buffer.AppendLine(line);
                outputLine?.Invoke(line);
            }
        }
    }
}
