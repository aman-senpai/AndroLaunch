using System;
using System.Drawing;
using Microsoft.Win32;
using System.Windows.Forms;

namespace Androlaunch.Core
{
    public static class ThemeManager
    {
        public static bool IsDarkMode { get; private set; } = true;

        public static Color Background => IsDarkMode ? Color.FromArgb(30, 30, 30) : Color.FromArgb(245, 245, 247);
        public static Color Surface => IsDarkMode ? Color.FromArgb(45, 45, 48) : Color.FromArgb(255, 255, 255);
        public static Color Foreground => IsDarkMode ? Color.FromArgb(230, 230, 230) : Color.FromArgb(25, 25, 25);
        public static Color SecondaryForeground => IsDarkMode ? Color.FromArgb(142, 142, 147) : Color.FromArgb(100, 100, 105);
        public static Color Accent => Color.FromArgb(10, 132, 255);
        public static Color Border => IsDarkMode ? Color.FromArgb(60, 60, 62) : Color.FromArgb(220, 220, 225);
        public static Color Selection => IsDarkMode ? Color.FromArgb(60, 60, 64) : Color.FromArgb(230, 240, 255);

        public static event Action ThemeChanged;

        static ThemeManager()
        {
            UpdateThemeStatus();
            SystemEvents.UserPreferenceChanged += (s, e) =>
            {
                if (e.Category == UserPreferenceCategory.General || e.Category == UserPreferenceCategory.VisualStyle)
                {
                    UpdateThemeStatus();
                }
            };
        }

        public static void UpdateThemeStatus()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    if (key != null)
                    {
                        var value = key.GetValue("AppsUseLightTheme");
                        if (value is int i)
                        {
                            IsDarkMode = (i == 0);
                        }
                    }
                }
            }
            catch { IsDarkMode = true; } // Default to dark

            ThemeChanged?.Invoke();
        }

        public static void ApplyTheme(Form form)
        {
            form.BackColor = Background;
            form.ForeColor = Foreground;
            
            // Recursively apply to controls if needed, but mostly we set them in components
            ApplyToControls(form.Controls);
        }

        private static void ApplyToControls(Control.ControlCollection controls)
        {
            foreach (Control control in controls)
            {
                if (control is Label || control is CheckBox || control is RadioButton)
                {
                    control.ForeColor = Foreground;
                }
                else if (control is Button btn && btn.FlatStyle == FlatStyle.Flat)
                {
                    // Buttons often have custom logic, so we might need more specific handling
                    // but general flat buttons follow surface/foreground
                }
                else if (control is TextBox txt)
                {
                    txt.BackColor = Surface;
                    txt.ForeColor = Foreground;
                }
                else if (control is ListBox lb)
                {
                    lb.BackColor = Background;
                    lb.ForeColor = Foreground;
                }
                else if (control is Panel || control is TableLayoutPanel || control is SplitContainer)
                {
                    // If it's a separator-like panel (very small), we might not want to change it
                    // but for now, general background is safer
                    if (control.Height > 2 && control.Width > 2)
                        control.BackColor = Background;
                }

                if (control.HasChildren)
                {
                    ApplyToControls(control.Controls);
                }
            }
        }
    }
}
