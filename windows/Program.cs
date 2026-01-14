using System;
using System.Windows.Forms;
using Androlaunch.Core;

namespace Androlaunch
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            
            // Run the application using our custom TrayApplicationContext
            Application.Run(new TrayApplicationContext());
        }
    }
}