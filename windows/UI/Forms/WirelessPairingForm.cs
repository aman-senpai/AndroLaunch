using System;
using System.Drawing;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Controls;
using QRCoder;

namespace Androlaunch.UI.Forms
{
    public class WirelessPairingForm : ThemedForm
    {
        private readonly PictureBox qrImageBox;
        private readonly Label statusLabel;
        private readonly Label codeLabel;
        private readonly Label titleLabel;
        private readonly Label instructionsLabel;
        private readonly Panel qrContainer;
        private readonly ThemedButton btnRestart;

        public WirelessPairingForm()
        {
            Text = "Wireless pairing";
            ClientSize = new Size(420, 620);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;

            titleLabel = new Label
            {
                Text = "Wireless pairing",
                Font = new Font(ThemeManager.TitleFont.FontFamily, 20F, FontStyle.Bold, GraphicsUnit.Point),
                AutoSize = false,
                Height = 44,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = ThemeManager.Foreground
            };

            qrContainer = new Panel
            {
                Size = new Size(300, 300),
                BackColor = Color.White,
                Padding = new Padding(12),
                Anchor = AnchorStyles.None,
                Margin = new Padding(0, 8, 0, 8)
            };
            qrContainer.Paint += (_, e) =>
            {
                using var pen = new Pen(Color.FromArgb(210, 210, 210));
                e.Graphics.DrawRectangle(pen, 0, 0, qrContainer.Width - 1, qrContainer.Height - 1);
            };

            qrImageBox = new PictureBox
            {
                Dock = DockStyle.Fill,
                SizeMode = PictureBoxSizeMode.Zoom,
                BackColor = Color.White
            };
            qrContainer.Controls.Add(qrImageBox);

            codeLabel = new Label
            {
                Text = "Pairing code: ------",
                AutoSize = false,
                Height = 38,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font(ThemeManager.UiFont.FontFamily, 14F, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = ThemeManager.Foreground
            };

            statusLabel = new Label
            {
                Text = "Starting pairing…",
                AutoSize = false,
                Height = 34,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = ThemeManager.Accent
            };

            instructionsLabel = new Label
            {
                Text = "On the phone, open Settings › Developer options › Wireless debugging, then choose “Pair device with QR code”.",
                AutoSize = true,
                MaximumSize = new Size(350, 0),
                TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = ThemeManager.SecondaryForeground,
                Anchor = AnchorStyles.None,
                Margin = new Padding(0, 8, 0, 8)
            };

            btnRestart = new ThemedButton
            {
                Text = "Restart pairing",
                Kind = ThemedButton.ButtonKind.Primary,
                Margin = new Padding(0, 0, 8, 0)
            };
            var btnClose = new ThemedButton { Text = "Close", Margin = new Padding(0) };
            btnRestart.Click += (_, _) => SetupPairing();
            btnClose.Click += (_, _) => Close();

            var buttonPanel = new FlowLayoutPanel
            {
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                WrapContents = false,
                FlowDirection = FlowDirection.LeftToRight,
                Anchor = AnchorStyles.None,
                Margin = new Padding(0, 4, 0, 0)
            };
            buttonPanel.Controls.Add(btnRestart);
            buttonPanel.Controls.Add(btnClose);

            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 6,
                Padding = new Padding(20),
                BackColor = ThemeManager.Background
            };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 308F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(titleLabel, 0, 0);
            root.Controls.Add(qrContainer, 0, 1);
            root.Controls.Add(codeLabel, 0, 2);
            root.Controls.Add(statusLabel, 0, 3);
            root.Controls.Add(instructionsLabel, 0, 4);
            root.Controls.Add(buttonPanel, 0, 5);
            Controls.Add(root);

            AdbHelper.OnPairingStatusChanged += HandlePairingStatus;
            AdbHelper.OnPairingComplete += HandlePairingComplete;

            ThemeManager.ThemeChanged += OnThemeChanged;
            Shown += (_, _) => ApplyThemeColors();
            SetupPairing();
        }

        private void SetupPairing()
        {
            AdbHelper.StopPairingService();
            (string qrString, string password) = AdbHelper.StartPairingService();
            string formatted = password.Length == 6 ? $"{password[..3]} {password[3..]}" : password;
            codeLabel.Text = $"Pairing code: {formatted}";
            GenerateQr(qrString);
        }

        private void HandlePairingStatus(string status)
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)(() => statusLabel.Text = status));
            }
            else
            {
                statusLabel.Text = status;
            }
        }

        private void HandlePairingComplete()
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)(() => statusLabel.Text = "Connected."));
            }
            else
            {
                statusLabel.Text = "Connected.";
            }
        }

        private void GenerateQr(string content)
        {
            using var generator = new QRCodeGenerator();
            using QRCodeData data = generator.CreateQrCode(content, QRCodeGenerator.ECCLevel.Q);
            using var code = new PngByteQRCode(data);
            byte[] bytes = code.GetGraphic(20);

            using var stream = new System.IO.MemoryStream(bytes);
            Image? old = qrImageBox.Image;
            qrImageBox.Image = Image.FromStream(stream);
            old?.Dispose();
        }

        private void OnThemeChanged()
        {
            if (IsDisposed)
            {
                return;
            }

            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)(() =>
                {
                    ThemeManager.ApplyTheme(this);
                    ApplyThemeColors();
                }));
            }
            else
            {
                ThemeManager.ApplyTheme(this);
                ApplyThemeColors();
            }
        }

        private void ApplyThemeColors()
        {
            titleLabel.ForeColor = ThemeManager.Foreground;
            codeLabel.ForeColor = ThemeManager.Foreground;
            statusLabel.ForeColor = ThemeManager.Accent;
            instructionsLabel.ForeColor = ThemeManager.SecondaryForeground;
            qrContainer.BackColor = Color.White;
            qrImageBox.BackColor = Color.White;
            Invalidate(true);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            AdbHelper.OnPairingStatusChanged -= HandlePairingStatus;
            AdbHelper.OnPairingComplete -= HandlePairingComplete;
            AdbHelper.StopPairingService();
            ThemeManager.ThemeChanged -= OnThemeChanged;
            qrImageBox.Image?.Dispose();
            qrImageBox.Image = null;
            base.OnFormClosed(e);
        }
    }
}
