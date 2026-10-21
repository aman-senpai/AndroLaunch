using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.Graphics;

namespace AndroLaunch.WinUI.Tray
{
    /// <summary>
    /// A one-pixel WinUI window used only as an anchor for the tray MenuFlyout. WinUI flyouts need
    /// a XamlRoot, and this keeps the menu fully native while the main window stays hidden.
    /// </summary>
    public sealed class TrayMenuWindow : Window
    {
        private static TrayMenuWindow? current;
        private readonly Grid anchor;
        private bool closing;

        private TrayMenuWindow()
        {
            ExtendsContentIntoTitleBar = true;
            AppWindow.IsShownInSwitchers = false;
            AppWindow.Resize(new SizeInt32(1, 1));
            if (AppWindow.Presenter is OverlappedPresenter presenter)
            {
                presenter.SetBorderAndTitleBar(false, false);
                presenter.IsResizable = false;
                presenter.IsMaximizable = false;
                presenter.IsMinimizable = false;
                presenter.IsAlwaysOnTop = true;
            }

            IntPtr hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            int exStyle = GetWindowLong(hwnd, GwlExStyle);
            SetWindowLong(hwnd, GwlExStyle, exStyle | WsExToolWindow | WsExLayered | WsExTransparent | WsExNoActivate);
            SetLayeredWindowAttributes(hwnd, 0, 0, LwaAlpha);
            SetWindowRgn(hwnd, CreateRectRgn(0, 0, 0, 0), true);

            anchor = new Grid
            {
                Width = 1,
                Height = 1,
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent)
            };
            Content = anchor;

            if (GetCursorPos(out CursorPoint point))
            {
                AppWindow.Move(new PointInt32(point.X, point.Y));
            }

            Closed += (_, _) => closing = true;
            anchor.Loaded += (_, _) => DispatcherQueue.TryEnqueue(ShowFlyout);
        }

        public static void ShowAtCursor()
        {
            if (current is not null)
            {
                try { current.Close(); } catch { }
                current = null;
            }

            current = new TrayMenuWindow();
            current.Activate();
        }

        private void ShowFlyout()
        {
            if (closing)
            {
                return;
            }

            MenuFlyout flyout = TrayMenuBuilder.Build();
            flyout.Closed += (_, _) =>
            {
                if (current == this)
                {
                    current = null;
                }

                try { Close(); } catch { }
            };
            flyout.ShowAt(anchor, new FlyoutShowOptions
            {
                Position = new Point(0, 0),
                ShowMode = FlyoutShowMode.Standard
            });
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CursorPoint
        {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out CursorPoint point);

        private const int GwlExStyle = -20;
        private const int WsExToolWindow = 0x00000080;
        private const int WsExLayered = 0x00080000;
        private const int WsExTransparent = 0x00000020;
        private const int WsExNoActivate = 0x08000000;
        private const uint LwaAlpha = 0x00000002;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateRectRgn(int x1, int y1, int x2, int y2);

        [DllImport("user32.dll")]
        private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    }
}
