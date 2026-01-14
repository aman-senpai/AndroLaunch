using System.Drawing;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch.UI.Renderers
{
    public class MenuRenderer : ToolStripProfessionalRenderer
    {
        public MenuRenderer() : base(new MenuColorTable())
        {
            this.RoundedEdges = true;
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (e.Item.Enabled && e.Item.Selected)
            {
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                
                // Subtle rounded selection
                var rect = new Rectangle(e.Item.ContentRectangle.X + 3, e.Item.ContentRectangle.Y + 1, 
                                         e.Item.ContentRectangle.Width - 6, e.Item.ContentRectangle.Height - 2);
                
                using (var brush = new SolidBrush(ThemeManager.Selection))
                {
                    g.FillRoundedRectangle(brush, rect, 4);
                }
            }
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (ThemeManager.IsDarkMode)
                e.TextColor = e.Item.Selected ? Color.White : ThemeManager.Foreground;
            else
                e.TextColor = ThemeManager.Foreground; // Always dark text in light mode for better legibility on light tints
            base.OnRenderItemText(e);
        }

        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = Color.FromArgb(180, 180, 180);
            base.OnRenderArrow(e);
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

            var r = e.ImageRectangle;
            // Modern Pill Toggle
            int switchWidth = 22;
            int switchHeight = 14;
            var switchRect = new Rectangle(r.Left + (r.Width - switchWidth) / 2, r.Top + (r.Height - switchHeight) / 2, switchWidth, switchHeight);

            bool isChecked = ((ToolStripMenuItem)e.Item).Checked;

            // Background pill with subtle border
            using (var brush = new SolidBrush(isChecked ? ThemeManager.Accent : (ThemeManager.IsDarkMode ? Color.FromArgb(70, 70, 72) : Color.FromArgb(200, 200, 205))))
            {
                g.FillRoundedRectangle(brush, switchRect, switchHeight / 2);
            }

            // The knob
            int knobPadding = 2;
            int knobSize = switchHeight - (knobPadding * 2);
            float knobX = isChecked ? switchRect.Right - knobSize - knobPadding : switchRect.Left + knobPadding;
            var knobRect = new System.Drawing.RectangleF(knobX, switchRect.Top + knobPadding, knobSize, knobSize);

            using (var brush = new SolidBrush(Color.White))
            {
                g.FillEllipse(brush, knobRect);
            }
        }
    }

    public static class GraphicsExtensions
    {
        public static void FillRoundedRectangle(this Graphics g, Brush brush, Rectangle rect, int radius)
        {
            using (var path = GetRoundedRectanglePath(rect, radius))
            {
                g.FillPath(brush, path);
            }
        }

        private static System.Drawing.Drawing2D.GraphicsPath GetRoundedRectanglePath(Rectangle rect, int radius)
        {
            var path = new System.Drawing.Drawing2D.GraphicsPath();
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
        public override Color MenuItemBorder => Color.Transparent; // No border for rounded selection
        public override Color ImageMarginGradientBegin => ThemeManager.Background;
        public override Color ImageMarginGradientMiddle => ThemeManager.Background;
        public override Color ImageMarginGradientEnd => ThemeManager.Background;
        public override Color SeparatorDark => ThemeManager.Border;
        public override Color SeparatorLight => ThemeManager.Border;
    }
}
