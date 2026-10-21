using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch.UI.Renderers
{
    /// <summary>Native Windows 11 menu rendering: accent-neutral selection and a standard check mark.</summary>
    public class MenuRenderer : ToolStripProfessionalRenderer
    {
        public MenuRenderer() : base(new MenuColorTable())
        {
            RoundedEdges = true;
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using var brush = new SolidBrush(ThemeManager.Background);
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            using var pen = new Pen(ThemeManager.Border);
            Rectangle bounds = new(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
            e.Graphics.DrawRectangle(pen, bounds);
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            var item = e.Item;
            if (item is not ToolStripMenuItem)
            {
                return;
            }

            using (var background = new SolidBrush(ThemeManager.Background))
            {
                e.Graphics.FillRectangle(background, item.Bounds);
            }

            if (item.Enabled && item.Selected)
            {
                e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                var rect = new Rectangle(3, 1, item.Width - 7, item.Height - 3);
                using var brush = new SolidBrush(ThemeManager.Selection);
                e.Graphics.FillRoundedRectangle(brush, rect, 4);
            }
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (!e.Item.Enabled)
            {
                e.TextColor = ThemeManager.SecondaryForeground;
            }
            else if (e.Item.Selected)
            {
                e.TextColor = ThemeManager.IsDarkMode ? Color.White : ThemeManager.Foreground;
            }
            else
            {
                e.TextColor = ThemeManager.Foreground;
            }

            base.OnRenderItemText(e);
        }

        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = ThemeManager.SecondaryForeground;
            base.OnRenderArrow(e);
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle r = e.ImageRectangle;
            const int glyphSize = 16;
            var glyphRect = new Rectangle(
                r.Left + (r.Width - glyphSize) / 2,
                r.Top + (r.Height - glyphSize) / 2,
                glyphSize,
                glyphSize);

            Color foreground = e.Item.Selected
                ? (ThemeManager.IsDarkMode ? Color.White : ThemeManager.Foreground)
                : ThemeManager.Foreground;
            Color background = e.Item.Selected ? ThemeManager.Selection : ThemeManager.Background;

            ControlPaint.DrawMenuGlyph(g, glyphRect, MenuGlyph.Checkmark, foreground, background);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            var g = e.Graphics;
            int y = e.Item.Height / 2;
            using var pen = new Pen(ThemeManager.Border);
            g.DrawLine(pen, 8, y, e.Item.Width - 8, y);
        }
    }

    public static class GraphicsExtensions
    {
        public static void FillRoundedRectangle(this Graphics g, Brush brush, Rectangle rect, int radius)
        {
            using var path = GetRoundedRectanglePath(rect, radius);
            g.FillPath(brush, path);
        }

        private static GraphicsPath GetRoundedRectanglePath(Rectangle rect, int radius)
        {
            var path = new GraphicsPath();
            int d = radius * 2;
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public class MenuColorTable : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground => ThemeManager.Background;
        public override Color MenuBorder => ThemeManager.Border;
        public override Color MenuItemSelected => ThemeManager.Selection;
        public override Color MenuItemBorder => Color.Transparent;
        public override Color ImageMarginGradientBegin => ThemeManager.Background;
        public override Color ImageMarginGradientMiddle => ThemeManager.Background;
        public override Color ImageMarginGradientEnd => ThemeManager.Background;
        public override Color CheckBackground => ThemeManager.Background;
        public override Color CheckSelectedBackground => ThemeManager.Selection;
        public override Color CheckPressedBackground => ThemeManager.Selection;
        public override Color SeparatorDark => ThemeManager.Border;
        public override Color SeparatorLight => ThemeManager.Border;
        public override Color GripDark => ThemeManager.Border;
        public override Color GripLight => ThemeManager.Background;
    }
}
