using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Renderers;

namespace Androlaunch.UI.Controls
{
    /// <summary>
    /// A flat, rounded Windows 11 style button. Derived from Button so keyboard, mnemonic,
    /// default-button and accessibility behaviour stay native.
    /// </summary>
    public sealed class ThemedButton : Button
    {
        public enum ButtonKind
        {
            Standard,
            Primary,
            Danger
        }

        private ButtonKind _kind = ButtonKind.Standard;
        private bool _hovered;
        private bool _pressed;

        public ThemedButton()
        {
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.SupportsTransparentBackColor,
                true);

            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            BackColor = Color.Transparent;
            Font = ThemeManager.UiFont;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(14, 5, 14, 5);
            MinimumSize = new Size(88, 32);
            TabStop = true;
        }

        public ButtonKind Kind
        {
            get => _kind;
            set
            {
                if (_kind != value)
                {
                    _kind = value;
                    Invalidate();
                }
            }
        }

        public override Size GetPreferredSize(Size proposedSize)
        {
            Size textSize = TextRenderer.MeasureText(Text, Font);
            return new Size(
                Math.Max(MinimumSize.Width, textSize.Width + Padding.Horizontal + 4),
                Math.Max(MinimumSize.Height, textSize.Height + Padding.Vertical + 6));
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ThemeManager.ThemeChanged += OnThemeChanged;
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            base.OnHandleDestroyed(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;

            Color fill;
            Color text;
            Color border;

            if (!Enabled)
            {
                fill = ThemeManager.Surface;
                text = ThemeManager.SecondaryForeground;
                border = ThemeManager.Border;
            }
            else if (Kind == ButtonKind.Primary)
            {
                fill = _pressed ? Darken(ThemeManager.Accent, 0.12f)
                    : _hovered ? Lighten(ThemeManager.Accent, 0.10f)
                    : ThemeManager.Accent;
                text = ThemeManager.AccentForeground;
                border = fill;
            }
            else if (Kind == ButtonKind.Danger)
            {
                fill = _pressed ? Darken(ThemeManager.DangerSurface, 0.08f)
                    : _hovered ? Color.FromArgb(
                        Math.Max(0, ThemeManager.DangerSurface.R - 8),
                        Math.Max(0, ThemeManager.DangerSurface.G - 8),
                        Math.Max(0, ThemeManager.DangerSurface.B - 8))
                    : ThemeManager.DangerSurface;
                text = ThemeManager.Danger;
                border = ThemeManager.Danger;
            }
            else
            {
                fill = _pressed ? Darken(ThemeManager.Surface, 0.06f)
                    : _hovered ? ThemeManager.Hover
                    : ThemeManager.Surface;
                text = ThemeManager.Foreground;
                border = ThemeManager.Border;
            }

            graphics.Clear(Parent?.BackColor ?? ThemeManager.Background);

            Rectangle bounds = new(0, 0, Width - 1, Height - 1);
            using (var path = RoundedRect(bounds, 4))
            using (var fillBrush = new SolidBrush(fill))
            {
                graphics.FillPath(fillBrush, path);
            }

            if (Kind != ButtonKind.Primary || !Enabled)
            {
                using var borderPen = new Pen(border);
                using var path = RoundedRect(bounds, 4);
                graphics.DrawPath(borderPen, path);
            }

            const TextFormatFlags flags =
                TextFormatFlags.HorizontalCenter |
                TextFormatFlags.VerticalCenter |
                TextFormatFlags.EndEllipsis;

            Rectangle textBounds = ClientRectangle;
            if (Padding != Padding.Empty)
            {
                textBounds = new Rectangle(
                    Padding.Left,
                    Padding.Top,
                    Math.Max(0, Width - Padding.Horizontal),
                    Math.Max(0, Height - Padding.Vertical));
            }

            TextRenderer.DrawText(graphics, Text, Font, textBounds, text, flags);

            if (Focused && ShowFocusCues)
            {
                ControlPaint.DrawFocusRectangle(
                    graphics,
                    new Rectangle(3, 3, Width - 7, Height - 7),
                    text,
                    fill);
            }
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            _hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            _hovered = false;
            _pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs mevent)
        {
            if (mevent.Button == MouseButtons.Left)
            {
                _pressed = true;
                Invalidate();
            }

            base.OnMouseDown(mevent);
        }

        protected override void OnMouseUp(MouseEventArgs mevent)
        {
            _pressed = false;
            Invalidate();
            base.OnMouseUp(mevent);
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            _hovered = false;
            _pressed = false;
            Invalidate();
            base.OnEnabledChanged(e);
        }

        private void OnThemeChanged()
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)Invalidate);
            }
            else
            {
                Invalidate();
            }
        }

        private static Color Lighten(Color color, float amount)
        {
            return Color.FromArgb(
                color.A,
                Math.Min(255, (int)(color.R + (255 - color.R) * amount)),
                Math.Min(255, (int)(color.G + (255 - color.G) * amount)),
                Math.Min(255, (int)(color.B + (255 - color.B) * amount)));
        }

        private static Color Darken(Color color, float amount)
        {
            return Color.FromArgb(
                color.A,
                Math.Max(0, (int)(color.R * (1 - amount))),
                Math.Max(0, (int)(color.G * (1 - amount))),
                Math.Max(0, (int)(color.B * (1 - amount))));
        }

        private static GraphicsPath RoundedRect(Rectangle bounds, int radius)
        {
            int diameter = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
