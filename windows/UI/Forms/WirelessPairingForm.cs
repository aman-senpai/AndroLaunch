using System;
using System.Drawing;
using System.Windows.Forms;
using QRCoder;
using Androlaunch.Core;

namespace Androlaunch.UI.Forms
{
    public class WirelessPairingForm : Form
    {
        private PictureBox qrImageBox;
        private Label statusLabel;
        private Label codeLabel;
        private Label titleLabel;
        private Label instructionsLabel;
        private Panel mainPanel;

        public WirelessPairingForm()
        {
            InitializeComponent();
            SetupPairing();
            
            ThemeManager.ThemeChanged += () => {
                if (this.IsHandleCreated) this.BeginInvoke((MethodInvoker)delegate { ApplyTheme(); });
            };
            ApplyTheme();
        }

        private void ApplyTheme()
        {
            ThemeManager.ApplyTheme(this);
            statusLabel.ForeColor = ThemeManager.Accent;
            instructionsLabel.ForeColor = ThemeManager.SecondaryForeground;
            this.Refresh();
        }

        private void InitializeComponent()
        {
            this.Text = "Wireless Pairing";
            this.Size = new Size(400, 550);
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.ShowInTaskbar = true;
            this.Font = new Font("Segoe UI", 10F);

            try
            {
                string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app_icon.ico");
                if (!System.IO.File.Exists(iconPath)) iconPath = "app_icon.ico";
                if (System.IO.File.Exists(iconPath)) this.Icon = new Icon(iconPath);
            }
            catch { }

            mainPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(20) };

            titleLabel = new Label
            {
                Text = "Wireless Pairing",
                Font = new Font("Segoe UI Semibold", 20F),
                Dock = DockStyle.Top,
                TextAlign = ContentAlignment.MiddleCenter,
                Height = 70
            };

            var qrContainer = new Panel
            {
                Size = new Size(260, 260),
                Location = new Point(70, 85),
                BackColor = Color.White,
                Padding = new Padding(10)
            };
            qrContainer.Paint += (s, e) => {
                e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using (var pen = new Pen(Color.FromArgb(200, 200, 200), 1))
                {
                    e.Graphics.DrawRoundedRectangle(pen, new Rectangle(0, 0, qrContainer.Width - 1, qrContainer.Height - 1), 10);
                }
            };

            qrImageBox = new PictureBox
            {
                Dock = DockStyle.Fill,
                SizeMode = PictureBoxSizeMode.Zoom,
                BackColor = Color.White
            };
            qrContainer.Controls.Add(qrImageBox);

            instructionsLabel = new Label
            {
                Text = "Go to Settings > Developer options > Wireless debugging > Pair device with QR code",
                Dock = DockStyle.Bottom,
                TextAlign = ContentAlignment.MiddleCenter,
                Height = 60,
                Font = new Font("Segoe UI", 9F)
            };

            codeLabel = new Label
            {
                Text = "Code: ------",
                Font = new Font("Segoe UI", 14F, FontStyle.Bold),
                Dock = DockStyle.Bottom,
                TextAlign = ContentAlignment.MiddleCenter,
                Height = 40
            };

            statusLabel = new Label
            {
                Text = "Initializing...",
                Dock = DockStyle.Bottom,
                TextAlign = ContentAlignment.MiddleCenter,
                Height = 40
            };

            mainPanel.Controls.Add(qrContainer);
            mainPanel.Controls.Add(titleLabel);
            mainPanel.Controls.Add(statusLabel);
            mainPanel.Controls.Add(codeLabel);
            mainPanel.Controls.Add(instructionsLabel);

            this.Controls.Add(mainPanel);

            this.FormClosing += (s, e) => AdbHelper.StopPairingService();
        }

        private void SetupPairing()
        {
            var (qrString, password) = AdbHelper.StartPairingService();
            codeLabel.Text = $"Pairing Code: {password}";
            GenerateQR(qrString);

            AdbHelper.OnPairingStatusChanged += (status) =>
            {
                if (this.IsHandleCreated)
                {
                    this.BeginInvoke((MethodInvoker)delegate {
                        statusLabel.Text = status;
                    });
                }
            };

            AdbHelper.OnPairingComplete += () =>
            {
                if (this.IsHandleCreated)
                {
                    this.BeginInvoke((MethodInvoker)delegate {
                        // Success micro-animation or sound could go here
                        // For now we restart automatically via the service event
                    });
                }
            };
        }

        private void GenerateQR(string content)
        {
            using (QRCodeGenerator qrGenerator = new QRCodeGenerator())
            using (QRCodeData qrCodeData = qrGenerator.CreateQrCode(content, QRCodeGenerator.ECCLevel.Q))
            using (PngByteQRCode qrCode = new PngByteQRCode(qrCodeData))
            {
                byte[] qrCodeAsPngByteArr = qrCode.GetGraphic(20);
                using (var ms = new System.IO.MemoryStream(qrCodeAsPngByteArr))
                {
                    qrImageBox.Image = Image.FromStream(ms);
                }
            }
        }
    }

    public static class GraphicsExtensionsPairing
    {
        public static void DrawRoundedRectangle(this Graphics g, Pen pen, Rectangle rect, int radius)
        {
            using (var path = GetRoundedRectanglePath(rect, radius))
            {
                g.DrawPath(pen, path);
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
}
