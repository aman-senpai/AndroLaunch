using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using System.Linq;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using Androlaunch.Core;
using Androlaunch.UI.Renderers;

namespace Androlaunch.UI.Forms
{
    public class AppLauncherForm : Form
    {
        private string deviceSerial;
        private ListBox listApps;
        private TextBox txtSearch;
        private List<AdbHelper.AppInfo> allApps = new List<AdbHelper.AppInfo>();
        
        private Color BackColorMain => ThemeManager.Background;
        private Color AccentColor => ThemeManager.Accent;
        private Color TextColor => ThemeManager.Foreground;
        private Color SecondaryTextColor => ThemeManager.SecondaryForeground;
        private Color BorderColor => ThemeManager.Border;

        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        public AppLauncherForm(string serial)
        {
            this.deviceSerial = serial;
            this.FormBorderStyle = FormBorderStyle.None;
            this.BackColor = BackColorMain;
            this.Width = 500;
            this.Height = 550;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.ShowInTaskbar = false;
            this.TopMost = true;

            try
            {
                string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app_icon.ico");
                if (!System.IO.File.Exists(iconPath)) iconPath = "app_icon.ico";
                if (System.IO.File.Exists(iconPath)) this.Icon = new Icon(iconPath);
            }
            catch { }

            // Rounded container and border
            this.Paint += (s, e) => {
                e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using (var path = GetRoundedPath(new Rectangle(0, 0, this.Width, this.Height), 12))
                {
                    this.Region = new Region(path);
                    using (var pen = new Pen(BorderColor, 2))
                    {
                        e.Graphics.DrawPath(pen, path);
                    }
                }
            };

            // Draggable header area
            var dragPanel = new Panel { Dock = DockStyle.Top, Height = 15, Cursor = Cursors.SizeAll };
            dragPanel.MouseDown += (s, e) => {
                if (e.Button == MouseButtons.Left)
                {
                    ReleaseCapture();
                    SendMessage(this.Handle, 0xA1, 0x2, 0);
                }
            };

            // Search Box
            var searchHeader = new Panel { Dock = DockStyle.Top, Height = 65, Padding = new Padding(20, 5, 20, 10) };
            txtSearch = new TextBox {
                Dock = DockStyle.Fill,
                BackColor = BackColorMain,
                ForeColor = TextColor,
                BorderStyle = BorderStyle.None,
                Font = new Font("Segoe UI Semilight", 18f),
                PlaceholderText = "Search apps..."
            };
            txtSearch.KeyDown += (s, e) => {
                if (e.KeyCode == Keys.Down && listApps.Items.Count > 0) {
                    listApps.Focus();
                    if (listApps.SelectedIndex == -1) listApps.SelectedIndex = 0;
                }
                if (e.KeyCode == Keys.Escape) this.Close();
                if (e.KeyCode == Keys.Enter) LaunchSelected();
            };
            searchHeader.Controls.Add(txtSearch);

            var sep = new Panel { Dock = DockStyle.Top, Height = 1, BackColor = BorderColor };

            // Results List
            listApps = new ListBox {
                Dock = DockStyle.Fill,
                BackColor = BackColorMain,
                ForeColor = TextColor,
                BorderStyle = BorderStyle.None,
                Font = new Font("Segoe UI", 11f),
                ItemHeight = 52, // Slightly taller for better spacing
                DrawMode = DrawMode.OwnerDrawFixed,
                IntegralHeight = false
            };
            
            listApps.DrawItem += (s, e) => {
                if (e.Index < 0) return;
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

                bool isSelected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
                var app = (AdbHelper.AppInfo)listApps.Items[e.Index];

                // Background
                using (var brush = new SolidBrush(BackColorMain))
                {
                    g.FillRectangle(brush, e.Bounds);
                }

                if (isSelected)
                {
                    var selectionRect = new Rectangle(e.Bounds.X + 8, e.Bounds.Y + 4, e.Bounds.Width - 16, e.Bounds.Height - 8);
                    using (var brush = new SolidBrush(ThemeManager.Selection))
                    {
                        g.FillRoundedRectangle(brush, selectionRect, 6);
                    }
                }

                // Content Rectangles
                var nameRect = new Rectangle(e.Bounds.X + 24, e.Bounds.Y + 10, e.Bounds.Width - 48, 22);
                var pkgRect = new Rectangle(e.Bounds.X + 24, e.Bounds.Y + 30, e.Bounds.Width - 48, 18);

                // Draw App Name
                using (var brush = new SolidBrush(isSelected && ThemeManager.IsDarkMode ? Color.White : TextColor))
                {
                    g.DrawString(app.Name, new Font("Segoe UI Semibold", 10.5f), brush, nameRect,
                                 new StringFormat { Trimming = StringTrimming.EllipsisCharacter });
                }
                
                // Draw Package ID (only if different and small font)
                if (app.Name != app.PackageName)
                {
                    Color pkgColor = isSelected ? (ThemeManager.IsDarkMode ? Color.FromArgb(200, 255, 255, 255) : ThemeManager.SecondaryForeground) : SecondaryTextColor;
                    using (var brush = new SolidBrush(pkgColor))
                    {
                        g.DrawString(app.PackageName, new Font("Segoe UI", 8.2f), brush, pkgRect,
                                     new StringFormat { Trimming = StringTrimming.EllipsisCharacter });
                    }
                }
            };

            listApps.KeyDown += (s, e) => {
                if (e.KeyCode == Keys.Enter) LaunchSelected();
                if (e.KeyCode == Keys.Escape) this.Close();
                if (e.KeyCode == Keys.Back) txtSearch.Focus();
                if (e.KeyCode == Keys.Delete) UninstallSelected();
            };
            listApps.DoubleClick += (s, e) => LaunchSelected();

            // Button Action Area
            var actionPanel = new Panel { Dock = DockStyle.Bottom, Height = 75, Padding = new Padding(15, 10, 15, 20) };
            
            var btnLaunch = CreateButton("🚀 Launch", AccentColor, Color.White);
            btnLaunch.Width = 145;
            btnLaunch.Location = new Point(15, 15);
            btnLaunch.Click += (s, e) => LaunchSelected();

            var btnClear = CreateButton("🧹 Clear Data", Color.FromArgb(45, 45, 48), Color.White);
            btnClear.Width = 145;
            btnClear.Location = new Point(170, 15);
            btnClear.Click += (s, e) => ClearDataSelected();

            var btnUninstall = CreateButton("🗑️ Uninstall", Color.FromArgb(45, 45, 48), Color.FromArgb(255, 69, 58));
            btnUninstall.Width = 145;
            btnUninstall.Location = new Point(325, 15);
            btnUninstall.Click += (s, e) => UninstallSelected();

            actionPanel.Controls.Add(btnLaunch);
            actionPanel.Controls.Add(btnClear);
            actionPanel.Controls.Add(btnUninstall);

            this.Controls.Add(listApps);
            this.Controls.Add(sep);
            this.Controls.Add(searchHeader);
            this.Controls.Add(dragPanel);
            this.Controls.Add(actionPanel);

            txtSearch.TextChanged += (s, e) => FilterApps();
            this.Load += (s, e) => LoadApps();
            this.Deactivate += (s, e) => this.Close();

            ThemeManager.ThemeChanged += () => {
                if (this.IsHandleCreated) this.BeginInvoke((MethodInvoker)(() => {
                    ThemeManager.ApplyTheme(this);
                    this.Refresh();
                }));
            };
        }

        private Button CreateButton(string text, Color back, Color fore)
        {
            var btn = new Button {
                Text = text,
                BackColor = back,
                ForeColor = fore,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI Semibold", 9.5f),
                Height = 40,
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = Color.Transparent;
            btn.FlatAppearance.MouseDownBackColor = Color.Transparent;

            btn.Paint += (s, e) => {
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                
                // Clear background to parent's color to avoid black corners
                g.Clear(btn.Parent?.BackColor ?? ThemeManager.Background);

                Color actualBack = (back == AccentColor) ? back : (ThemeManager.IsDarkMode ? Color.FromArgb(45, 45, 48) : Color.FromArgb(230, 230, 235));
                using (var brush = new SolidBrush(actualBack))
                {
                    g.FillRoundedRectangle(brush, btn.ClientRectangle, 6);
                }
                TextRenderer.DrawText(g, btn.Text, btn.Font, btn.ClientRectangle, fore, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            };
            return btn;
        }

        private async void LoadApps()
        {
            try 
            {
                allApps = await Task.Run(() => AdbHelper.GetApps(deviceSerial));
                FilterApps();
                this.BeginInvoke((MethodInvoker)(() => txtSearch.Focus()));
            }
            catch { }
        }

        private void FilterApps()
        {
            string query = txtSearch.Text.ToLower();
            var filtered = allApps.Where(a => 
                a.Name.ToLower().Contains(query) || 
                a.PackageName.ToLower().Contains(query)
            ).ToList();

            listApps.BeginUpdate();
            listApps.Items.Clear();
            foreach (var app in filtered) listApps.Items.Add(app);
            if (listApps.Items.Count > 0 && !string.IsNullOrEmpty(query)) listApps.SelectedIndex = 0;
            listApps.EndUpdate();
        }

        private void LaunchSelected()
        {
            if (listApps.SelectedItem is AdbHelper.AppInfo app)
            {
                AdbHelper.LaunchApp(deviceSerial, app.PackageName);
                this.Close();
            }
        }

        private void UninstallSelected()
        {
            if (listApps.SelectedItem is AdbHelper.AppInfo app)
            {
                if (MessageBox.Show($"Uninstall {app.Name}?\n({app.PackageName})", "Confirm", MessageBoxButtons.YesNo) == DialogResult.Yes)
                {
                    AdbHelper.UninstallApp(deviceSerial, app.PackageName);
                    LoadApps();
                }
            }
        }

        private void ClearDataSelected()
        {
            if (listApps.SelectedItem is AdbHelper.AppInfo app)
            {
                if (MessageBox.Show($"Clear all data for {app.Name}?\nThis will reset the app.", "Confirm Clear", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
                {
                    try {
                        AdbHelper.ClearAppData(deviceSerial, app.PackageName);
                        MessageBox.Show("App data cleared.", "Success");
                    } catch (Exception ex) {
                        MessageBox.Show("Failed: " + ex.Message);
                    }
                }
            }
        }
        private System.Drawing.Drawing2D.GraphicsPath GetRoundedPath(Rectangle rect, int radius)
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
}
