using System;
using System.Net;
using System.Threading.Tasks;
using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using QRCoder;
using Windows.Storage.Streams;

namespace AndroLaunch.WinUI.Dialogs
{
    public static class PairingDialog
    {
        private static bool showing;

        public static async Task ShowAsync()
        {
            if (showing)
            {
                return;
            }

            showing = true;
            try
            {
                if (!App.MainWindowInstance.AppWindow.IsVisible)
                {
                    App.ShowMainWindow("devices");
                }

                var root = (FrameworkElement)App.MainWindowInstance.Content;
                if (root.XamlRoot is null)
                {
                    var loaded = new TaskCompletionSource<bool>();
                    void OnLoaded(object sender, RoutedEventArgs args) => loaded.TrySetResult(true);
                    root.Loaded += OnLoaded;
                    try { await loaded.Task; }
                    finally { root.Loaded -= OnLoaded; }
                }

                using var session = new PairingSession();
                await session.ShowAsync();
            }
            catch (Exception ex)
            {
                await Ui.ShowErrorAsync("Wireless pairing", ex.Message);
            }
            finally
            {
                showing = false;
            }
        }

        private sealed class PairingSession : IDisposable
        {
            private readonly Image qr = new()
            {
                Width = 260,
                Height = 260,
                Stretch = Stretch.Uniform,
                HorizontalAlignment = HorizontalAlignment.Center
            };
            private readonly TextBlock code = new()
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                FontSize = 20,
                IsTextSelectionEnabled = true
            };
            private readonly InfoBar status = new()
            {
                IsOpen = true,
                IsClosable = false,
                Severity = InfoBarSeverity.Informational,
                Message = "Starting pairing…"
            };
            private readonly TextBox host = new() { Header = "Phone IP address", PlaceholderText = "192.168.1.10" };
            private readonly TextBox pairingPort = new() { Header = "Pairing port", PlaceholderText = "Port shown with the pairing code" };
            private readonly TextBox pairingCode = new() { Header = "Six-digit pairing code", MaxLength = 6 };
            private readonly TextBox connectPort = new() { Header = "Connection port", PlaceholderText = "Port on the Wireless debugging screen" };
            private readonly Button pair = new() { Content = "Pair with code" };
            private readonly Button connect = new() { Content = "Connect" };
            private readonly ContentDialog dialog;
            private volatile bool closed;
            private volatile bool completed;
            private volatile bool qrActive;
            private bool busy;
            private int qrRevision;

            public PairingSession()
            {
                var panel = new StackPanel { Spacing = 12, MinWidth = 360, MaxWidth = 440 };
                panel.Children.Add(new TextBlock
                {
                    Text = "Connect your phone and PC to the same network. On Android 11 or newer, open Settings › Developer options › Wireless debugging › Pair device with QR code.",
                    TextWrapping = TextWrapping.Wrap
                });
                panel.Children.Add(new Border
                {
                    Background = new SolidColorBrush(Microsoft.UI.Colors.White),
                    Padding = new Thickness(12),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Child = qr
                });
                panel.Children.Add(code);
                panel.Children.Add(status);

                var manual = new StackPanel { Spacing = 10 };
                manual.Children.Add(new TextBlock
                {
                    Text = "Choose “Pair device with pairing code” on the phone. After pairing, use the separate connection port from the main Wireless debugging screen.",
                    TextWrapping = TextWrapping.Wrap
                });
                manual.Children.Add(host);
                manual.Children.Add(pairingPort);
                manual.Children.Add(pairingCode);
                manual.Children.Add(pair);
                manual.Children.Add(connectPort);
                manual.Children.Add(connect);
                panel.Children.Add(new Expander
                {
                    Header = "Pair manually or reconnect",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Stretch,
                    Content = manual
                });

                dialog = new ContentDialog
                {
                    Title = "Wireless pairing",
                    XamlRoot = App.MainWindowInstance.Content.XamlRoot,
                    Content = new ScrollViewer
                    {
                        Content = panel,
                        MaxHeight = 560,
                        VerticalScrollBarVisibility = ScrollBarVisibility.Auto
                    },
                    PrimaryButtonText = "Restart QR pairing",
                    CloseButtonText = "Close",
                    DefaultButton = ContentDialogButton.Close
                };
                dialog.Opened += async (_, _) => await RestartAsync();
                dialog.PrimaryButtonClick += async (_, args) =>
                {
                    args.Cancel = true;
                    await RestartAsync();
                };
                dialog.Closed += (_, _) => Dispose();
                pair.Click += async (_, _) => await RunManualAsync(pairing: true);
                connect.Click += async (_, _) => await RunManualAsync(pairing: false);
                AdbHelper.OnPairingStatusChanged += OnStatus;
                AdbHelper.OnPairingComplete += OnComplete;
            }

            public async Task ShowAsync() => await dialog.ShowAsync();

            private void SetStatus(string message, InfoBarSeverity severity = InfoBarSeverity.Informational)
            {
                status.Message = message;
                status.Severity = severity;
            }

            private void OnStatus(string message)
            {
                int revision = qrRevision;
                App.MainWindowInstance.DispatcherQueue.TryEnqueue(() =>
                {
                    if (!closed && !completed && qrActive && revision == qrRevision)
                    {
                        SetStatus(message);
                    }
                });
            }

            private void OnComplete()
            {
                if (closed || !qrActive)
                {
                    return;
                }

                completed = true;
                qrActive = false;
                int revision = qrRevision;
                // Core otherwise replaces the password immediately, invalidating the displayed QR.
                AdbHelper.StopPairingService();
                App.MainWindowInstance.DispatcherQueue.TryEnqueue(() =>
                {
                    if (!closed && completed && revision == qrRevision)
                    {
                        qr.Source = null;
                        code.Text = "Connected";
                        SetStatus("Connected. Close this dialog or restart to pair another device.", InfoBarSeverity.Success);
                    }
                });
            }

            private async Task RestartAsync()
            {
                if (closed || busy)
                {
                    return;
                }

                SetBusy(true);
                completed = false;
                qrActive = true;
                int revision = ++qrRevision;
                try
                {
                    (string content, string password) = AdbHelper.StartPairingService();
                    code.Text = $"Pairing code: {password[..3]} {password[3..]}";
                    using var generator = new QRCodeGenerator();
                    using var data = generator.CreateQrCode(content, QRCodeGenerator.ECCLevel.Q);
                    using var png = new PngByteQRCode(data);
                    using var stream = new InMemoryRandomAccessStream();
                    using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
                    {
                        writer.WriteBytes(png.GetGraphic(12));
                        await writer.StoreAsync();
                        await writer.FlushAsync();
                    }

                    stream.Seek(0);
                    var bitmap = new BitmapImage();
                    await bitmap.SetSourceAsync(stream);
                    if (!closed && !completed && revision == qrRevision)
                    {
                        qr.Source = bitmap;
                    }
                }
                catch (Exception ex)
                {
                    qrActive = false;
                    AdbHelper.StopPairingService();
                    if (!closed)
                    {
                        qr.Source = null;
                        code.Text = "";
                        SetStatus(ex.Message, InfoBarSeverity.Error);
                    }
                }
                finally
                {
                    if (!closed) SetBusy(false);
                }
            }

            private async Task RunManualAsync(bool pairing)
            {
                if (closed || busy)
                {
                    return;
                }

                string address = host.Text.Trim();
                string portText = (pairing ? pairingPort : connectPort).Text.Trim();
                string password = pairingCode.Text.Trim();
                if (!IPAddress.TryParse(address.Trim('[', ']'), out IPAddress? ip) ||
                    !ushort.TryParse(portText, out ushort port) || port == 0 ||
                    (pairing && (password.Length != 6 || !System.Linq.Enumerable.All(password, char.IsAsciiDigit))))
                {
                    SetStatus("Enter the phone’s IP address, a port from 1 to 65535, and (when pairing) the six-digit code.", InfoBarSeverity.Warning);
                    return;
                }

                SetBusy(true);
                completed = false;
                qrActive = false;
                ++qrRevision;
                AdbHelper.StopPairingService();
                qr.Source = null;
                code.Text = "QR pairing paused";
                SetStatus(pairing ? "Pairing…" : "Connecting…");
                try
                {
                    string target = ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 ? $"[{ip}]" : ip.ToString();
                    string output = await Task.Run(() => pairing
                        ? AdbHelper.WirelessPair(target, port.ToString(), password)
                        : AdbHelper.WirelessConnect(target, port.ToString()));
                    if (!closed)
                    {
                        bool success = pairing
                            ? output.Contains("Successfully paired", StringComparison.OrdinalIgnoreCase) ||
                              output.Contains("already paired", StringComparison.OrdinalIgnoreCase)
                            : output.Contains("connected to", StringComparison.OrdinalIgnoreCase);
                        SetStatus(string.IsNullOrWhiteSpace(output) ? "adb returned no result." : output.Trim(),
                            success ? InfoBarSeverity.Success : InfoBarSeverity.Error);
                    }
                }
                catch (Exception ex)
                {
                    if (!closed) SetStatus(ex.Message, InfoBarSeverity.Error);
                }
                finally
                {
                    if (!closed) SetBusy(false);
                }
            }

            private void SetBusy(bool value)
            {
                busy = value;
                dialog.IsPrimaryButtonEnabled = !value;
                pair.IsEnabled = !value;
                connect.IsEnabled = !value;
            }

            public void Dispose()
            {
                if (closed) return;
                closed = true;
                qrActive = false;
                ++qrRevision;
                AdbHelper.OnPairingStatusChanged -= OnStatus;
                AdbHelper.OnPairingComplete -= OnComplete;
                AdbHelper.StopPairingService();
                qr.Source = null;
            }
        }
    }
}
