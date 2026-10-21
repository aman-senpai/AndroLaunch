using System;
using System.Drawing;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Controls;

namespace Androlaunch.UI.Forms
{
    public class VolumeControlForm : ThemedForm
    {
        private readonly string deviceSerial;
        private readonly TrackBar trackVolume;
        private readonly Label lblValue;

        public VolumeControlForm(string serial)
        {
            deviceSerial = serial;

            Text = "Volume";
            ClientSize = new Size(380, 200);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;

            var lblTitle = new Label
            {
                Text = "Media volume",
                AutoSize = true,
                Font = new Font(ThemeManager.UiFont.FontFamily, 11F, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 0, 10)
            };

            trackVolume = new TrackBar
            {
                Minimum = 0,
                Maximum = 15,
                Value = 7,
                TickFrequency = 1,
                SmallChange = 1,
                LargeChange = 3,
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 0, 0, 4)
            };
            trackVolume.Scroll += (_, _) => ApplyVolume();

            lblValue = new Label
            {
                Text = "7 / 15",
                AutoSize = true,
                ForeColor = ThemeManager.SecondaryForeground,
                Margin = new Padding(0, 0, 0, 10)
            };

            var btnClose = new ThemedButton
            {
                Text = "Close",
                Kind = ThemedButton.ButtonKind.Primary,
                Anchor = AnchorStyles.Right,
                Margin = new Padding(0)
            };
            btnClose.Click += (_, _) => Close();

            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 4,
                Padding = new Padding(18),
                BackColor = ThemeManager.Background
            };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(lblTitle, 0, 0);
            root.Controls.Add(trackVolume, 0, 1);
            root.Controls.Add(lblValue, 0, 2);
            root.Controls.Add(btnClose, 0, 3);
            Controls.Add(root);

            ThemeManager.ThemeChanged += OnThemeChanged;
            Shown += (_, _) =>
            {
                lblValue.ForeColor = ThemeManager.SecondaryForeground;
                UpdateValueLabel();
            };
            UpdateValueLabel();
        }

        private void ApplyVolume()
        {
            UpdateValueLabel();
            AdbHelper.SetVolume(deviceSerial, trackVolume.Value);
        }

        private void UpdateValueLabel()
        {
            lblValue.Text = $"{trackVolume.Value} / {trackVolume.Maximum}";
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
                    lblValue.ForeColor = ThemeManager.SecondaryForeground;
                }));
            }
            else
            {
                ThemeManager.ApplyTheme(this);
                lblValue.ForeColor = ThemeManager.SecondaryForeground;
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            base.OnFormClosed(e);
        }
    }
}
