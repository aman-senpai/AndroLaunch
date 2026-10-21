using System;
using System.Drawing;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch.UI
{
    /// <summary>Base form that applies the native dark title bar, rounded corners and icon.</summary>
    public class ThemedForm : Form
    {
        public ThemedForm()
        {
            Icon = AppIcons.App;
            Font = ThemeManager.UiFont;
            AutoScaleMode = AutoScaleMode.Font;
            BackColor = ThemeManager.Background;
            ForeColor = ThemeManager.Foreground;
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ThemeManager.ApplyWindow(this);
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            base.OnDpiChanged(e);
            ThemeManager.ApplyWindow(this);
        }
    }
}
