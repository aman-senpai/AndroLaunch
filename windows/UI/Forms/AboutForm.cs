using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using WinFormsMethodInvoker = System.Windows.Forms.MethodInvoker;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Controls;

namespace Androlaunch.UI.Forms
{
    public class AboutForm : ThemedForm
    {
        private readonly PictureBox iconBox;
        private readonly LinkLabel link;

        public AboutForm()
        {
            Text = "About AndroLaunch";
            ClientSize = new Size(420, 300);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;

            Version? version = Assembly.GetExecutingAssembly().GetName().Version;
            string versionText = version is null ? "0.3.9" : version.ToString(3);

            iconBox = new PictureBox
            {
                Size = new Size(72, 72),
                SizeMode = PictureBoxSizeMode.Zoom,
                Image = AppIcons.App256.ToBitmap(),
                BackColor = Color.Transparent,
                Margin = new Padding(0, 0, 14, 0)
            };

            var nameLabel = new Label
            {
                Text = "AndroLaunch",
                AutoSize = true,
                Font = new Font(ThemeManager.TitleFont.FontFamily, 18F, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 8, 0, 0)
            };

            var versionLabel = new Label
            {
                Text = $"Version {versionText}",
                AutoSize = true,
                ForeColor = ThemeManager.SecondaryForeground,
                Margin = new Padding(0, 0, 0, 0)
            };

            var headerText = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0),
                BackColor = Color.Transparent
            };
            headerText.Controls.Add(nameLabel);
            headerText.Controls.Add(versionLabel);

            var header = new TableLayoutPanel
            {
                ColumnCount = 2,
                RowCount = 1,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 0, 0, 12),
                BackColor = Color.Transparent
            };
            header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            header.Controls.Add(iconBox, 0, 0);
            header.Controls.Add(headerText, 1, 0);

            var description = new Label
            {
                Text = "Control Android devices from the Windows desktop with adb and scrcpy: mirror the screen, launch apps, toggle settings, pair wirelessly and run shell commands.",
                AutoSize = true,
                MaximumSize = new Size(370, 0),
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 0, 10)
            };

            link = new LinkLabel
            {
                Text = "github.com/aman-senpai/AndroLaunch",
                AutoSize = true,
                LinkColor = ThemeManager.Accent,
                ActiveLinkColor = ThemeManager.Accent,
                VisitedLinkColor = ThemeManager.Accent,
                LinkBehavior = LinkBehavior.HoverUnderline,
                Margin = new Padding(0, 0, 0, 2)
            };
            link.LinkClicked += (_, _) =>
            {
                try
                {
                    Process.Start(new ProcessStartInfo(link.Text) { UseShellExecute = true });
                }
                catch
                {
                    // No default browser; the URL is still selectable in the label.
                }
            };

            var licenseLabel = new Label
            {
                Text = "MIT License",
                AutoSize = true,
                ForeColor = ThemeManager.SecondaryForeground,
                Margin = new Padding(0, 0, 0, 0)
            };

            var btnOk = new ThemedButton
            {
                Text = "OK",
                Kind = ThemedButton.ButtonKind.Primary,
                DialogResult = DialogResult.OK,
                Anchor = AnchorStyles.Right,
                Margin = new Padding(0)
            };

            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 5,
                Padding = new Padding(20),
                BackColor = ThemeManager.Background
            };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(header, 0, 0);
            root.Controls.Add(description, 0, 1);
            root.Controls.Add(link, 0, 2);
            root.Controls.Add(licenseLabel, 0, 3);
            root.Controls.Add(btnOk, 0, 4);
            Controls.Add(root);

            AcceptButton = btnOk;
            CancelButton = btnOk;

            ThemeManager.ThemeChanged += OnThemeChanged;
            Shown += (_, _) =>
            {
                link.LinkColor = ThemeManager.Accent;
                link.ActiveLinkColor = ThemeManager.Accent;
                link.VisitedLinkColor = ThemeManager.Accent;
            };
        }

        private void OnThemeChanged()
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke((WinFormsMethodInvoker)(() =>
                {
                    ThemeManager.ApplyTheme(this);
                    link.LinkColor = ThemeManager.Accent;
                    link.ActiveLinkColor = ThemeManager.Accent;
                    link.VisitedLinkColor = ThemeManager.Accent;
                }));
            }
            else
            {
                ThemeManager.ApplyTheme(this);
                link.LinkColor = ThemeManager.Accent;
                link.ActiveLinkColor = ThemeManager.Accent;
                link.VisitedLinkColor = ThemeManager.Accent;
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            iconBox.Image?.Dispose();
            iconBox.Image = null;
            base.OnFormClosed(e);
        }
    }
}
