using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Androlaunch.Core
{
    /// <summary>
    /// Windows 11 flavoured colours, fonts and window chrome. Everything is read from the user's
    /// current personalisation settings so the app follows light/dark mode and the system accent
    /// colour instead of shipping a fixed palette.
    /// </summary>
    public static class ThemeManager
    {
        private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        private const string AccentKey = @"Software\Microsoft\Windows\DWM";
        private static readonly Color DefaultAccent = Color.FromArgb(0, 120, 212);

        public static bool IsDarkMode { get; private set; } = true;
        public static bool IsTaskbarLight { get; private set; }
        public static bool IsHighContrast => SystemInformation.HighContrast;

        public static Color Background => IsHighContrast
            ? SystemColors.Window
            : IsDarkMode ? Color.FromArgb(32, 32, 32) : Color.FromArgb(243, 243, 243);

        public static Color Surface => IsHighContrast
            ? SystemColors.Window
            : IsDarkMode ? Color.FromArgb(43, 43, 43) : Color.FromArgb(255, 255, 255);

        public static Color Foreground => IsHighContrast
            ? SystemColors.WindowText
            : IsDarkMode ? Color.FromArgb(255, 255, 255) : Color.FromArgb(26, 26, 26);

        public static Color SecondaryForeground => IsHighContrast
            ? SystemColors.GrayText
            : IsDarkMode ? Color.FromArgb(170, 170, 170) : Color.FromArgb(96, 96, 96);

        public static Color Border => IsHighContrast
            ? SystemColors.WindowFrame
            : IsDarkMode ? Color.FromArgb(61, 61, 61) : Color.FromArgb(225, 225, 225);

        public static Color Selection => IsHighContrast
            ? SystemColors.Highlight
            : IsDarkMode ? Color.FromArgb(54, 58, 64) : Color.FromArgb(235, 235, 235);

        public static Color Hover => IsHighContrast
            ? SystemColors.Highlight
            : IsDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(232, 232, 232);

        public static Color Accent { get; private set; } = DefaultAccent;

        public static Color AccentForeground
        {
            get
            {
                if (IsHighContrast)
                {
                    return SystemColors.HighlightText;
                }

                // Pick the text colour that keeps contrast comfortable on the user's accent.
                double luminance = (0.299 * Accent.R + 0.587 * Accent.G + 0.114 * Accent.B) / 255.0;
                return luminance > 0.62 ? Color.FromArgb(17, 17, 17) : Color.White;
            }
        }

        public static Color Danger => IsHighContrast
            ? SystemColors.WindowText
            : IsDarkMode ? Color.FromArgb(255, 99, 99) : Color.FromArgb(196, 43, 28);

        public static Color DangerSurface => IsHighContrast
            ? SystemColors.Window
            : IsDarkMode ? Color.FromArgb(70, 40, 40) : Color.FromArgb(253, 237, 235);

        public static Font UiFont { get; }
        public static Font MenuFont { get; }
        public static Font MenuHeaderFont { get; }
        public static Font TitleFont { get; }
        public static Font MonoFont { get; }

        public static event Action? ThemeChanged;

        static ThemeManager()
        {
            string uiFamily = PickFamily("Segoe UI Variable Text", "Segoe UI");
            string displayFamily = PickFamily("Segoe UI Variable Display", "Segoe UI Semibold", "Segoe UI");
            string monoFamily = PickFamily("Cascadia Mono", "Consolas", "Courier New");

            UiFont = new Font(uiFamily, 9F, FontStyle.Regular, GraphicsUnit.Point);
            MenuFont = new Font(uiFamily, 9F, FontStyle.Regular, GraphicsUnit.Point);
            MenuHeaderFont = new Font(uiFamily, 9F, FontStyle.Bold, GraphicsUnit.Point);
            TitleFont = new Font(displayFamily, 20F, FontStyle.Bold, GraphicsUnit.Point);
            MonoFont = new Font(monoFamily, 9.5F, FontStyle.Regular, GraphicsUnit.Point);

            UpdateThemeStatus();
            SystemEvents.UserPreferenceChanged += (_, e) =>
            {
                if (e.Category is UserPreferenceCategory.General
                    or UserPreferenceCategory.VisualStyle
                    or UserPreferenceCategory.Color
                    or UserPreferenceCategory.Window)
                {
                    UpdateThemeStatus();
                }
            };
        }

        public static void UpdateThemeStatus()
        {
            int appsUseLight = ReadDword(PersonalizeKey, "AppsUseLightTheme", 0);
            int systemUsesLight = ReadDword(PersonalizeKey, "SystemUsesLightTheme", appsUseLight);
            IsDarkMode = appsUseLight == 0;
            IsTaskbarLight = systemUsesLight == 1;
            Accent = ReadAccent();
            ThemeChanged?.Invoke();
        }

        /// <summary>Applies the native title-bar theme, rounded corners and colours to a form.</summary>
        public static void ApplyWindow(Form form)
        {
            if (form.IsDisposed || !form.IsHandleCreated)
            {
                return;
            }

            try
            {
                int dark = IsDarkMode && !IsHighContrast ? 1 : 0;
                int result = NativeMethods.DwmSetWindowAttribute(
                    form.Handle, NativeMethods.DwmwaUseImmersiveDarkMode, ref dark, sizeof(int));
                if (result != 0)
                {
                    NativeMethods.DwmSetWindowAttribute(
                        form.Handle, NativeMethods.DwmwaUseImmersiveDarkModeLegacy, ref dark, sizeof(int));
                }

                int corners = NativeMethods.DwmwcpRound;
                NativeMethods.DwmSetWindowAttribute(
                    form.Handle, NativeMethods.DwmwaWindowCornerPreference, ref corners, sizeof(int));
            }
            catch
            {
                // DWM is best-effort: Windows 10 builds without these attributes still render.
            }

            form.BackColor = Background;
            form.ForeColor = Foreground;
            ApplyToControls(form.Controls);
        }

        public static void ApplyTheme(Form form)
        {
            if (form.IsDisposed)
            {
                return;
            }

            ApplyWindow(form);
            form.Refresh();
        }

        private static void ApplyToControls(Control.ControlCollection controls)
        {
            foreach (Control control in controls)
            {
                ApplyToControl(control);
                if (control.HasChildren)
                {
                    ApplyToControls(control.Controls);
                }
            }
        }

        private static void ApplyToControl(Control control)
        {
            if (IsHighContrast)
            {
                control.ForeColor = SystemColors.WindowText;
                if (control is not TextBoxBase)
                {
                    control.BackColor = SystemColors.Window;
                }
                return;
            }

            switch (control)
            {
                case Label:
                    control.ForeColor = Foreground;
                    control.BackColor = TransparentOrParent(control);
                    break;

                case CheckBox:
                case RadioButton:
                    control.ForeColor = Foreground;
                    control.BackColor = TransparentOrParent(control);
                    break;

                case TextBox:
                    control.BackColor = Surface;
                    control.ForeColor = Foreground;
                    HookExplorerTheme(control);
                    break;

                case ListBox:
                    control.BackColor = Surface;
                    control.ForeColor = Foreground;
                    HookExplorerTheme(control);
                    break;

                case ListView:
                    control.BackColor = Surface;
                    control.ForeColor = Foreground;
                    HookExplorerTheme(control);
                    break;

                case DataGridView:
                    HookExplorerTheme(control);
                    break;

                case TrackBar:
                    control.BackColor = TransparentOrParent(control);
                    HookExplorerTheme(control);
                    break;

                case TableLayoutPanel:
                case FlowLayoutPanel:
                case SplitContainer:
                case Panel:
                    if (control.BackColor == SystemColors.Control || control.BackColor == Color.Transparent)
                    {
                        control.BackColor = Background;
                    }
                    break;

                case Button:
                    // Native system buttons decide their own colours. ThemedButton follows the theme itself.
                    break;

                case ToolStrip:
                    control.BackColor = Background;
                    control.ForeColor = Foreground;
                    break;
            }
        }

        private static Color TransparentOrParent(Control control)
        {
            bool supportsTransparent = control is Label or CheckBox or RadioButton;
            return supportsTransparent
                ? Color.Transparent
                : control.Parent?.BackColor ?? Background;
        }

        private static void HookExplorerTheme(Control control)
        {
            control.HandleCreated -= ExplorerThemeHandleCreated;
            control.HandleCreated += ExplorerThemeHandleCreated;

            if (control.IsHandleCreated)
            {
                NativeMethods.ApplyExplorerTheme(control.Handle, IsDarkMode);
            }
        }

        private static void ExplorerThemeHandleCreated(object? sender, EventArgs e)
        {
            if (sender is Control control && control.IsHandleCreated)
            {
                NativeMethods.ApplyExplorerTheme(control.Handle, IsDarkMode);
            }
        }

        private static int ReadDword(string keyPath, string valueName, int fallback)
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(keyPath);
                return key?.GetValue(valueName) is int value ? value : fallback;
            }
            catch
            {
                return fallback;
            }
        }

        private static Color ReadAccent()
        {
            try
            {
                if (NativeMethods.DwmGetColorizationColor(out uint colorization, out _) == 0)
                {
                    Color accent = Color.FromArgb(
                        255,
                        (int)((colorization >> 16) & 0xFF),
                        (int)((colorization >> 8) & 0xFF),
                        (int)(colorization & 0xFF));
                    if (accent.R + accent.G + accent.B > 24)
                    {
                        return accent;
                    }
                }
            }
            catch
            {
                // Fall back to the Windows default blue.
            }

            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(AccentKey);
                if (key?.GetValue("AccentColor") is int accentValue)
                {
                    // AccentColor is stored as ABGR.
                    Color accent = Color.FromArgb(accentValue & 0xFF, (accentValue >> 8) & 0xFF, (accentValue >> 16) & 0xFF);
                    if (accent.R + accent.G + accent.B > 24)
                    {
                        return accent;
                    }
                }
            }
            catch
            {
                // Ignore and use the default.
            }

            return DefaultAccent;
        }

        private static string PickFamily(params string[] candidates)
        {
            HashSet<string> installed = FontFamily.Families
                .Select(font => font.Name)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            foreach (string candidate in candidates)
            {
                if (installed.Contains(candidate))
                {
                    return candidate;
                }
            }

            return SystemFonts.MessageBoxFont?.FontFamily.Name ?? "Segoe UI";
        }
    }
}
