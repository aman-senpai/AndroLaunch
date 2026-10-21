using System;
using Microsoft.Win32;

namespace AndroLaunch.WinUI.Services
{
    public static class StartupService
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppName = "AndroLaunch";

        public static bool IsEnabled
        {
            get
            {
                try
                {
                    using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKey);
                    string? value = key?.GetValue(AppName) as string;
                    return !string.IsNullOrWhiteSpace(value) &&
                           value.Trim('"').Equals(ExecutablePath, StringComparison.OrdinalIgnoreCase);
                }
                catch
                {
                    return false;
                }
            }
        }

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
                if (key is null)
                {
                    return;
                }

                if (enabled)
                {
                    key.SetValue(AppName, $"\"{ExecutablePath}\"");
                }
                else
                {
                    key.DeleteValue(AppName, throwOnMissingValue: false);
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Could not update startup: {ex.Message}");
            }
        }

        private static string ExecutablePath =>
            Environment.ProcessPath ?? System.Reflection.Assembly.GetExecutingAssembly().Location;
    }
}
