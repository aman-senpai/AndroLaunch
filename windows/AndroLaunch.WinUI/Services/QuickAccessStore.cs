using System.Text.Json;
using Androlaunch.Core;

namespace AndroLaunch.WinUI.Services;

internal static class QuickAccessStore
{
    private sealed class Preferences
    {
        public string CaptureDirectory { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "AndroLaunch");
        public string CapturePrefix { get; set; } = "AndroLaunch";
        public HashSet<string> Favorites { get; set; } = new(StringComparer.Ordinal);
        public List<string> RecentActions { get; set; } = new();
    }

    private static readonly string StorePath = Path.Combine(AppSettingsStore.SettingsDirectory, "quick-access.json");
    private static readonly Preferences Current = Load();
    public static string CaptureDirectory => Current.CaptureDirectory;
    public static string CapturePrefix => Current.CapturePrefix;
    public static bool IsFavorite(string id) => Current.Favorites.Contains(id);
    public static IEnumerable<string> KnownAppPackages(string serial)
    {
        string prefix = $"app:{serial}:";
        return Current.Favorites.Concat(Current.RecentActions).Where(id => id.StartsWith(prefix, StringComparison.Ordinal))
            .Select(id => id[prefix.Length..]).Distinct(StringComparer.Ordinal).ToArray();
    }
    public static int RecentIndex(string id) => Current.RecentActions.IndexOf(id);

    private static Preferences Load()
    {
        try
        {
            var value = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(StorePath));
            if (value is null) return new();
            value.Favorites ??= new(StringComparer.Ordinal);
            value.RecentActions ??= new();
            if (string.IsNullOrWhiteSpace(value.CaptureDirectory)) value.CaptureDirectory = new Preferences().CaptureDirectory;
            if (string.IsNullOrWhiteSpace(value.CapturePrefix)) value.CapturePrefix = "AndroLaunch";
            return value;
        }
        catch (IOException) { return new(); }
        catch (UnauthorizedAccessException) { return new(); }
        catch (JsonException) { return new(); }
    }

    public static void SetCapturePreferences(string directory, string prefix)
    {
        directory = Path.GetFullPath(directory);
        prefix = prefix.Trim();
        if (prefix.Length == 0 || prefix.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || prefix.EndsWith('.') || prefix.Length > 80)
            throw new ArgumentException("Use a file prefix of 1–80 characters without filename punctuation or a trailing period.");
        Current.CaptureDirectory = directory;
        Current.CapturePrefix = prefix;
        Save();
    }

    public static void ToggleFavorite(string id)
    {
        if (!Current.Favorites.Remove(id)) Current.Favorites.Add(id);
        Save();
    }

    public static void RecordAction(string id)
    {
        Current.RecentActions.Remove(id);
        Current.RecentActions.Insert(0, id);
        if (Current.RecentActions.Count > 20) Current.RecentActions.RemoveRange(20, Current.RecentActions.Count - 20);
        Save();
    }

    private static void Save()
    {
        Directory.CreateDirectory(AppSettingsStore.SettingsDirectory);
        string temporary = StorePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, StorePath, true);
    }
}
