using System;
using System.Runtime.InteropServices;

namespace Androlaunch.Core
{
    internal static class NativeMethods
    {
        public const int DwmwaUseImmersiveDarkMode = 20;
        public const int DwmwaUseImmersiveDarkModeLegacy = 19;
        public const int DwmwaWindowCornerPreference = 33;
        public const int DwmwcpRound = 2;

        [DllImport("dwmapi.dll", PreserveSig = true)]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        [DllImport("dwmapi.dll", PreserveSig = true)]
        public static extern int DwmGetColorizationColor(out uint colorizationColor, [MarshalAs(UnmanagedType.Bool)] out bool opaqueBlend);

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SetWindowTheme(IntPtr hwnd, string? subAppName, string? subIdList);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        public static void ApplyExplorerTheme(IntPtr handle, bool dark)
        {
            if (handle == IntPtr.Zero)
            {
                return;
            }

            try
            {
                SetWindowTheme(handle, dark ? "DarkMode_Explorer" : "Explorer", null);
            }
            catch
            {
                // uxtheme is optional on older Windows builds; the control still works without it.
            }
        }
    }
}
