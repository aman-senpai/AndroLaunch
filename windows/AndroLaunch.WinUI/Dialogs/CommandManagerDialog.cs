using Androlaunch.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace AndroLaunch.WinUI.Dialogs;

public static class CommandManagerDialog
{
    public static async Task ShowAsync()
    {
        var commands = AdbHelper.GetSavedCommands().Select(command => new AdbHelper.ShellCommand
        {
            Id = command.Id, Name = command.Name, Command = command.Command,
            IsBackground = command.IsBackground, IsHostCommand = command.IsHostCommand
        }).ToList();
        var list = new ListView { Width = 190, MinHeight = 280, SelectionMode = ListViewSelectionMode.Single };
        AutomationProperties.SetName(list, "Saved commands");
        var name = new TextBox { Header = "Name" };
        var commandText = new TextBox { Header = "Command", AcceptsReturn = true, MinHeight = 120, TextWrapping = TextWrapping.Wrap };
        var background = new CheckBox { Content = "Run in background and show output" };
        var host = new CheckBox { Content = "Run on this PC instead of the device" };
        var error = new InfoBar { IsClosable = false, Severity = InfoBarSeverity.Error };
        var editor = new StackPanel { Spacing = 10, Width = 330 };
        var editorHost = new ContentControl { Content = editor, IsEnabled = false };
        editor.Children.Add(name);
        editor.Children.Add(commandText);
        editor.Children.Add(background);
        editor.Children.Add(host);
        editor.Children.Add(new TextBlock
        {
            Text = "Device commands run with adb shell. PC commands run locally; adb commands target the selected device. Only save commands you trust.",
            TextWrapping = TextWrapping.Wrap, Opacity = 0.7
        });
        var add = new Button { Content = "New command" };
        var delete = new Button { Content = "Delete", IsEnabled = false };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        buttons.Children.Add(add);
        buttons.Children.Add(delete);
        var body = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        body.Children.Add(list);
        body.Children.Add(editorHost);
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(error);
        panel.Children.Add(body);
        panel.Children.Add(buttons);
        bool loading = false;
        AdbHelper.ShellCommand? Selected() => (list.SelectedItem as ListViewItem)?.Tag as AdbHelper.ShellCommand;
        void AddRow(AdbHelper.ShellCommand command) => list.Items.Add(new ListViewItem { Content = command.Name, Tag = command });
        foreach (var command in commands) AddRow(command);
        list.SelectionChanged += (_, _) =>
        {
            loading = true;
            var selected = Selected();
            editorHost.IsEnabled = delete.IsEnabled = selected is not null;
            name.Text = selected?.Name ?? "";
            commandText.Text = selected?.Command ?? "";
            background.IsChecked = selected?.IsBackground ?? false;
            host.IsChecked = selected?.IsHostCommand ?? false;
            loading = false;
        };
        name.TextChanged += (_, _) =>
        {
            if (!loading && Selected() is { } selected)
            {
                selected.Name = name.Text;
                ((ListViewItem)list.SelectedItem).Content = name.Text;
            }
        };
        commandText.TextChanged += (_, _) => { if (!loading && Selected() is { } selected) selected.Command = commandText.Text; };
        void UpdateOptions()
        {
            if (!loading && Selected() is { } selected)
            {
                selected.IsBackground = background.IsChecked == true;
                selected.IsHostCommand = host.IsChecked == true;
            }
        }
        background.Checked += (_, _) => UpdateOptions();
        background.Unchecked += (_, _) => UpdateOptions();
        host.Checked += (_, _) => UpdateOptions();
        host.Unchecked += (_, _) => UpdateOptions();
        add.Click += (_, _) =>
        {
            var command = new AdbHelper.ShellCommand { Name = "New command" };
            commands.Add(command);
            AddRow(command);
            list.SelectedIndex = list.Items.Count - 1;
            name.Focus(FocusState.Programmatic);
            name.SelectAll();
        };
        delete.Click += (_, _) =>
        {
            if (Selected() is not { } selected) return;
            int index = list.SelectedIndex;
            commands.Remove(selected);
            list.Items.RemoveAt(index);
            if (list.Items.Count > 0) list.SelectedIndex = Math.Min(index, list.Items.Count - 1);
        };
        if (list.Items.Count > 0) list.SelectedIndex = 0;
        var dialog = new ContentDialog
        {
            Title = "Manage commands", Content = panel, PrimaryButtonText = "Save",
            CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close,
            XamlRoot = App.MainWindowInstance.Content.XamlRoot
        };
        dialog.PrimaryButtonClick += (_, args) =>
        {
            if (commands.Any(command => string.IsNullOrWhiteSpace(command.Name) || string.IsNullOrWhiteSpace(command.Command)))
            {
                args.Cancel = true;
                error.Title = "Each command needs a name and command text.";
                error.IsOpen = true;
            }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) AdbHelper.SaveCommands(commands);
    }
}
