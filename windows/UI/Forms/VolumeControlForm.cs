using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch.UI.Forms
{
    public class VolumeControlForm : Form
    {
        private string deviceSerial;
        private TrackBar trackVolume;
        private Label lblVolume;

        public VolumeControlForm(string serial)
        {
            this.deviceSerial = serial;
            this.Text = "Volume Control";
            this.Size = new Size(300, 150);
            this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
            this.StartPosition = FormStartPosition.CenterParent;

            try
            {
                string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app_icon.ico");
                if (!System.IO.File.Exists(iconPath)) iconPath = "app_icon.ico";
                if (System.IO.File.Exists(iconPath)) this.Icon = new Icon(iconPath);
            } catch { }

            lblVolume = new Label { Text = "Adjusting Media Volume", Location = new Point(10, 10), AutoSize = true };
            trackVolume = new TrackBar { Minimum = 0, Maximum = 15, Value = 7, Width = 260, Location = new Point(10, 40) };
            
            trackVolume.Scroll += TrackVolume_Scroll;

            this.Controls.Add(lblVolume);
            this.Controls.Add(trackVolume);
        }

        private void TrackVolume_Scroll(object? sender, EventArgs e)
        {
             AdbHelper.SetVolume(deviceSerial, trackVolume.Value);
        }
    }
}
