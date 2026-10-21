using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            using var singleInstance = new Mutex(initiallyOwned: true, @"Local\AndroLaunch.Tray", out bool createdNew);
            if (!createdNew)
            {
                return;
            }

            ApplicationConfiguration.Initialize();
            Application.SetDefaultFont(ThemeManager.UiFont);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (_, e) => ShowFatalError(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
                LogException(e.ExceptionObject as Exception ?? new InvalidOperationException("Unknown error"));

            try
            {
                Application.Run(new TrayApplicationContext());
            }
            catch (Exception ex)
            {
                ShowFatalError(ex);
            }
        }

        private static void ShowFatalError(Exception exception)
        {
            LogException(exception);
            MessageBox.Show(
                $"AndroLaunch hit an unexpected error.\n\n{exception.Message}\n\nDetails were written to %LOCALAPPDATA%\\AndroLaunch\\errors.log.",
                "AndroLaunch",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }

        private static void LogException(Exception exception)
        {
            try
            {
                string folder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "AndroLaunch");
                Directory.CreateDirectory(folder);
                File.AppendAllText(
                    Path.Combine(folder, "errors.log"),
                    $"[{DateTimeOffset.Now:O}] {exception}{Environment.NewLine}{Environment.NewLine}");
            }
            catch
            {
                // Never let logging mask the original failure.
            }
        }
    }
}
