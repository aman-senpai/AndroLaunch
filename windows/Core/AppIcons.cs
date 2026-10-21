using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

namespace Androlaunch.Core
{
    /// <summary>
    /// Loads the icons that are embedded in the executable. Keeping them embedded is what makes
    /// the tray icon work from the single-file build: the published exe is the only file that is
    /// shipped, so there is no Resources directory to read at runtime.
    /// </summary>
    internal static class AppIcons
    {
        private const string AppIconResource = "app_icon.ico";
        private const string TrayLightResource = "tray_icon_light.ico";
        private const string TrayDarkResource = "tray_icon_dark.ico";

        private static readonly Lazy<Icon> AppSmall = new(() => Load(AppIconResource, 32));
        private static readonly Lazy<Icon> AppLarge = new(() => Load(AppIconResource, 256));
        private static readonly Lazy<Icon> TrayLight = new(() => Load(TrayLightResource, TraySize));
        private static readonly Lazy<Icon> TrayDark = new(() => Load(TrayDarkResource, TraySize));

        private static int TraySize => Math.Max(16, SystemInformation.SmallIconSize.Width);

        public static Icon App => AppSmall.Value;
        public static Icon App256 => AppLarge.Value;

        /// <summary>
        /// White glyph for a dark taskbar, near-black glyph for a light taskbar. The source art is
        /// the macOS menu-bar template icon, so it is a flat monochrome mark rather than the app
        /// icon.
        /// </summary>
        public static Icon Tray(bool lightTaskbar) => lightTaskbar ? TrayDark.Value : TrayLight.Value;

        private static Icon Load(string resourceSuffix, int size)
        {
            Assembly assembly = typeof(AppIcons).Assembly;
            string? name = assembly.GetManifestResourceNames()
                .FirstOrDefault(n => n.EndsWith(resourceSuffix, StringComparison.OrdinalIgnoreCase));

            if (name is null)
            {
                return (Icon)SystemIcons.Application.Clone();
            }

            try
            {
                using Stream? stream = assembly.GetManifestResourceStream(name);
                if (stream is null)
                {
                    return (Icon)SystemIcons.Application.Clone();
                }

                // Icon keeps a reference to the stream on some runtimes, so hand it a copy.
                using var memory = new MemoryStream();
                stream.CopyTo(memory);
                memory.Position = 0;

                try
                {
                    return new Icon(memory, size, size);
                }
                catch
                {
                    memory.Position = 0;
                    return new Icon(memory);
                }
            }
            catch
            {
                return (Icon)SystemIcons.Application.Clone();
            }
        }
    }
}
