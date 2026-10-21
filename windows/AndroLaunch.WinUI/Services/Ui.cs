using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;

namespace AndroLaunch.WinUI
{
    public static class Ui
    {
        public static async Task ShowErrorAsync(string title, string message)
        {
            await ShowDialogAsync(new ContentDialog
            {
                Title = title,
                Content = new TextBlock
                {
                    Text = message,
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 520
                },
                CloseButtonText = "OK"
            });
        }

        public static async Task ShowTextAsync(string title, string text)
        {
            var output = new TextBox
            {
                Text = string.IsNullOrWhiteSpace(text) ? "(no output)" : text,
                IsReadOnly = true,
                AcceptsReturn = true,
                TextWrapping = TextWrapping.NoWrap,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                MinHeight = 360,
                MinWidth = 660
            };

            var dialog = new ContentDialog
            {
                Title = title,
                Content = new ScrollViewer
                {
                    Content = output,
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                    VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    MaxHeight = 420
                },
                PrimaryButtonText = "Copy",
                CloseButtonText = "Close",
                DefaultButton = ContentDialogButton.Close
            };

            ContentDialogResult result = await ShowDialogAsync(dialog);
            if (result == ContentDialogResult.Primary)
            {
                var package = new DataPackage();
                package.SetText(output.Text);
                Clipboard.SetContent(package);
            }
        }

        public static async Task<string?> PromptAsync(string title, string label, string initialValue = "")
        {
            var input = new TextBox { Text = initialValue, SelectionStart = initialValue.Length };
            var panel = new StackPanel { Spacing = 8 };
            panel.Children.Add(new TextBlock { Text = label });
            panel.Children.Add(input);

            var dialog = new ContentDialog
            {
                Title = title,
                Content = panel,
                PrimaryButtonText = "OK",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary
            };

            ContentDialogResult result = await ShowDialogAsync(dialog);
            return result == ContentDialogResult.Primary ? input.Text.Trim() : null;
        }

        public static async Task<bool> ConfirmAsync(string title, string message, string primary = "Yes")
        {
            var dialog = new ContentDialog
            {
                Title = title,
                Content = new TextBlock
                {
                    Text = message,
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 460
                },
                PrimaryButtonText = primary,
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close
            };
            return await ShowDialogAsync(dialog) == ContentDialogResult.Primary;
        }

        private static async Task<ContentDialogResult> ShowDialogAsync(ContentDialog dialog)
        {
            MainWindow window = App.MainWindowInstance;
            if (!window.AppWindow.IsVisible)
            {
                App.ShowMainWindow();
            }

            dialog.XamlRoot = window.Content.XamlRoot;
            try
            {
                return await dialog.ShowAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine(ex);
                return ContentDialogResult.None;
            }
        }
    }
}
