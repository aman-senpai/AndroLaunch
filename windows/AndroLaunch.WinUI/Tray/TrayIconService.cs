using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AndroLaunch.WinUI.Tray
{
    /// <summary>Win32 notification-area icon. The menu itself is a native WinUI MenuFlyout.</summary>
    public sealed class TrayIconService : IDisposable
    {
        private const int WmApp = 0x8000;
        private const int WmTrayCallback = WmApp + 1;
        private const int WmLButtonUp = 0x0202;
        private const int WmRButtonUp = 0x0205;
        private const uint NimAdd = 0;
        private const uint NimModify = 1;
        private const uint NimDelete = 2;
        private const uint NifMessage = 0x00000001;
        private const uint NifIcon = 0x00000002;
        private const uint NifTip = 0x00000004;
        private const int SmCxSmIcon = 49;
        private const string TrayClassName = "AndroLaunchTrayWindow";

        private static readonly Dictionary<IntPtr, TrayIconService> Instances = new();
        private static WndProcDelegate? sharedWndProc;
        private static bool classRegistered;

        private readonly Action onMenuRequested;
        private IntPtr windowHandle;
        private IntPtr iconHandle;
        private uint taskbarCreatedMessage;
        private bool iconAdded;
        private string? loadedAsset;
        private int loadedSize;

        public TrayIconService(Action onMenuRequested)
        {
            this.onMenuRequested = onMenuRequested;
        }

        public void Initialize()
        {
            EnsureWindowClass();
            IntPtr module = GetModuleHandle(null);
            windowHandle = CreateWindowEx(
                0, TrayClassName, "AndroLaunchTray", 0,
                0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, module, IntPtr.Zero);
            if (windowHandle == IntPtr.Zero)
            {
                throw new InvalidOperationException("Could not create the notification-area window.");
            }

            Instances[windowHandle] = this;
            taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
            ReloadIcon();
            if (!iconAdded)
            {
                throw new InvalidOperationException("Windows could not add the AndroLaunch notification-area icon.");
            }
        }

        public void ReloadIcon()
        {
            string asset = IsLightTaskbar() ? "dark" : "light";
            int size = GetSystemMetrics(SmCxSmIcon);
            if (iconHandle != IntPtr.Zero && loadedAsset == asset && loadedSize == size)
            {
                return;
            }

            IntPtr replacement = LoadEmbeddedIcon(asset, size);
            IntPtr previous = iconHandle;
            iconHandle = replacement;
            loadedAsset = asset;
            loadedSize = size;
            if (windowHandle != IntPtr.Zero)
            {
                AddOrUpdateIcon();
            }
            if (previous != IntPtr.Zero) DestroyIcon(previous);
        }

        private static IntPtr LoadEmbeddedIcon(string theme, int size)
        {
            using Stream stream = typeof(TrayIconService).Assembly.GetManifestResourceStream(
                $"AndroLaunch.Tray.{theme}.ico") ??
                throw new InvalidOperationException("The notification-area icon resource is missing.");
            using var reader = new BinaryReader(stream);
            reader.ReadUInt16();
            reader.ReadUInt16();
            int count = reader.ReadUInt16();
            uint offset = 0;
            uint length = 0;
            int best = int.MaxValue;
            for (int i = 0; i < count; i++)
            {
                int width = reader.ReadByte();
                width = width == 0 ? 256 : width;
                stream.Position += 7;
                uint entryLength = reader.ReadUInt32();
                uint entryOffset = reader.ReadUInt32();
                int score = width >= size ? width - size : 1024 + size - width;
                if (score < best)
                {
                    best = score;
                    length = entryLength;
                    offset = entryOffset;
                }
            }
            stream.Position = offset;
            byte[] image = reader.ReadBytes(checked((int)length));
            IntPtr icon = CreateIconFromResourceEx(image, (uint)image.Length, true, 0x00030000, size, size, 0);
            if (icon == IntPtr.Zero)
            {
                throw new InvalidOperationException("Windows could not decode the notification-area icon.");
            }
            return icon;
        }

        private void AddOrUpdateIcon()
        {
            var data = new NotifyIconData
            {
                cbSize = Marshal.SizeOf<NotifyIconData>(),
                hWnd = windowHandle,
                uID = 1,
                uFlags = NifMessage | NifIcon | NifTip,
                uCallbackMessage = WmTrayCallback,
                hIcon = iconHandle,
                szTip = "AndroLaunch - Android device manager",
                szInfo = "",
                szInfoTitle = ""
            };
            if (iconAdded && Shell_NotifyIcon(NimModify, ref data))
            {
                return;
            }
            iconAdded = Shell_NotifyIcon(NimAdd, ref data);
        }

        private static bool IsLightTaskbar()
        {
            try
            {
                using RegistryKey? key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                int value = key?.GetValue("SystemUsesLightTheme") is int intValue ? intValue : 0;
                return value == 1;
            }
            catch
            {
                return false;
            }
        }

        private static void EnsureWindowClass()
        {
            if (classRegistered)
            {
                return;
            }

            sharedWndProc = WindowProc;
            var windowClass = new WindowClassEx
            {
                cbSize = (uint)Marshal.SizeOf<WindowClassEx>(),
                style = 0,
                lpfnWndProc = Marshal.GetFunctionPointerForDelegate(sharedWndProc),
                cbClsExtra = 0,
                cbWndExtra = 0,
                hInstance = GetModuleHandle(null),
                hIcon = IntPtr.Zero,
                hCursor = IntPtr.Zero,
                hbrBackground = IntPtr.Zero,
                lpszMenuName = null,
                lpszClassName = TrayClassName,
                hIconSm = IntPtr.Zero
            };

            if (RegisterClassEx(ref windowClass) == 0)
            {
                throw new InvalidOperationException("Could not register the notification-area window class.");
            }

            classRegistered = true;
        }

        private static IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
        {
            if (Instances.TryGetValue(hwnd, out TrayIconService? service))
            {
                if (message == service.taskbarCreatedMessage)
                {
                    service.iconAdded = false;
                    service.AddOrUpdateIcon();
                    return IntPtr.Zero;
                }

                if (message is 0x001A or 0x031A) // WM_SETTINGCHANGE / WM_THEMECHANGED
                {
                    service.ReloadIcon();
                }
                if (message == WmTrayCallback)
                {
                    int mouseMessage = (int)(lParam.ToInt64() & 0xFFFF);
                    if (mouseMessage is WmLButtonUp or WmRButtonUp)
                    {
                        SetForegroundWindow(hwnd);
                        service.ReloadIcon();
                        service.onMenuRequested();
                    }

                    return IntPtr.Zero;
                }
            }

            return DefWindowProc(hwnd, message, wParam, lParam);
        }

        public void Dispose()
        {
            if (windowHandle != IntPtr.Zero)
            {
                var data = new NotifyIconData
                {
                    cbSize = Marshal.SizeOf<NotifyIconData>(),
                    hWnd = windowHandle,
                    uID = 1,
                    szTip = "",
                    szInfo = "",
                    szInfoTitle = ""
                };
                Shell_NotifyIcon(NimDelete, ref data);
                Instances.Remove(windowHandle);
                DestroyWindow(windowHandle);
                windowHandle = IntPtr.Zero;
            }

            if (iconHandle != IntPtr.Zero)
            {
                DestroyIcon(iconHandle);
                iconHandle = IntPtr.Zero;
            }
        }

        private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NotifyIconData
        {
            public int cbSize;
            public IntPtr hWnd;
            public uint uID;
            public uint uFlags;
            public uint uCallbackMessage;
            public IntPtr hIcon;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szTip;
            public uint dwState;
            public uint dwStateMask;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string szInfo;
            public uint uTimeoutOrVersion;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
            public string szInfoTitle;
            public uint dwInfoFlags;
            public Guid guidItem;
            public IntPtr hBalloonIcon;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WindowClassEx
        {
            public uint cbSize;
            public uint style;
            public IntPtr lpfnWndProc;
            public int cbClsExtra;
            public int cbWndExtra;
            public IntPtr hInstance;
            public IntPtr hIcon;
            public IntPtr hCursor;
            public IntPtr hbrBackground;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string? lpszMenuName;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string lpszClassName;
            public IntPtr hIconSm;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern ushort RegisterClassEx(ref WindowClassEx windowClass);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowEx(
            uint exStyle, string className, string windowName, uint style,
            int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

        [DllImport("user32.dll")]
        private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool DestroyWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern uint RegisterWindowMessage(string message);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr CreateIconFromResourceEx(
            byte[] bits, uint size, [MarshalAs(UnmanagedType.Bool)] bool icon, uint version,
            int width, int height, uint flags);

        [DllImport("user32.dll")]
        private static extern bool DestroyIcon(IntPtr icon);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string? moduleName);
    }
}
