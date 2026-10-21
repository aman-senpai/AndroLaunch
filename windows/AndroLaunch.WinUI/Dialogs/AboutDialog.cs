using System;
using System.Reflection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.System;

namespace AndroLaunch.WinUI.Dialogs
{
    public static class AboutDialog
    {
        public static async System.Threading.Tasks.Task ShowAsync()
        {
            Version? version = Assembly.GetExecutingAssembly().GetName().Version;
            string versionText = version is null ? "0.3.9" : version.ToString(3);

            var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
            header.Children.Add(new Image
            {
                Source = new BitmapImage(new Uri("ms-appx:///Assets/app_icon.png")),
                Width = 72,
                Height = 72
            });

            var titlePanel = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
            titlePanel.Children.Add(new TextBlock
            {
                Text = "AndroLaunch",
                FontSize = 24,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            titlePanel.Children.Add(new TextBlock
            {
                Text = $"Version {versionText}",
                Opacity = 0.7
            });
            header.Children.Add(titlePanel);

            var link = new HyperlinkButton
            {
                Content = "github.com/aman-senpai/AndroLaunch",
                Padding = new Thickness(0)
            };
            link.Click += async (_, _) =>
            {
                await Launcher.LaunchUriAsync(new Uri("https://github.com/aman-senpai/AndroLaunch"));
            };

            var content = new StackPanel { Spacing = 14, MaxWidth = 460 };
            content.Children.Add(header);
            content.Children.Add(new TextBlock
            {
                Text = "Control Android devices from the Windows desktop with adb and scrcpy: mirror the screen, launch apps, browse files, manage emulators and run shell commands.",
                TextWrapping = TextWrapping.Wrap
            });
            content.Children.Add(link);
            content.Children.Add(new TextBlock { Text = "MIT License", Opacity = 0.6 });

            var dialog = new ContentDialog
            {
                Title = "About AndroLaunch",
                Content = content,
                CloseButtonText = "Close",
                XamlRoot = App.MainWindowInstance.Content.XamlRoot
            };
            await dialog.ShowAsync();
        }
    }
}
