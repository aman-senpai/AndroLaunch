using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Controls;

namespace Androlaunch.UI.Forms
{
    public class CommandManagerForm : ThemedForm
    {
        private readonly ListBox listCommands;
        private readonly TextBox txtName;
        private readonly TextBox txtCommand;
        private readonly CheckBox chkBackground;
        private readonly CheckBox chkHost;
        private readonly ThemedButton btnAdd;
        private readonly ThemedButton btnUpdate;
        private readonly ThemedButton btnDelete;
        private readonly ThemedButton btnImport;
        private readonly ThemedButton btnExport;
        private readonly Label lblHint;

        private List<AdbHelper.ShellCommand> commands = new();
        private AdbHelper.ShellCommand? selectedCommand;

        public CommandManagerForm()
        {
            Text = "Manage commands";
            ClientSize = new Size(800, 540);
            MinimumSize = new Size(680, 460);
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;

            var lblList = new Label
            {
                Text = "Saved commands",
                AutoSize = false,
                Height = 24,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = ThemeManager.MenuHeaderFont,
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 0, 8)
            };

            listCommands = new ListBox
            {
                Dock = DockStyle.Fill,
                IntegralHeight = false,
                BorderStyle = BorderStyle.FixedSingle,
                Font = ThemeManager.UiFont,
                Margin = new Padding(0)
            };
            listCommands.SelectedIndexChanged += ListCommands_SelectedIndexChanged;

            var leftPanel = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 2,
                Padding = new Padding(12),
                BackColor = ThemeManager.Background
            };
            leftPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            leftPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            leftPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            leftPanel.Controls.Add(lblList, 0, 0);
            leftPanel.Controls.Add(listCommands, 0, 1);

            var lblName = new Label
            {
                Text = "Name",
                AutoSize = true,
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 0, 4)
            };
            txtName = new TextBox
            {
                Dock = DockStyle.Fill,
                BorderStyle = BorderStyle.FixedSingle,
                Font = ThemeManager.UiFont,
                Margin = new Padding(0, 0, 0, 10)
            };
            txtName.TextChanged += (_, _) => UpdateButtonStates();

            var lblCommand = new Label
            {
                Text = "Command",
                AutoSize = true,
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 0, 4)
            };
            txtCommand = new TextBox
            {
                Dock = DockStyle.Fill,
                Multiline = true,
                AcceptsReturn = true,
                WordWrap = true,
                ScrollBars = ScrollBars.Vertical,
                BorderStyle = BorderStyle.FixedSingle,
                Font = ThemeManager.MonoFont,
                Margin = new Padding(0, 0, 0, 10)
            };
            txtCommand.TextChanged += (_, _) => UpdateButtonStates();

            var checkPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0, 0, 0, 8)
            };
            chkBackground = new CheckBox
            {
                Text = "Run in background",
                AutoSize = true,
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0, 0, 20, 0)
            };
            chkHost = new CheckBox
            {
                Text = "Run on this PC",
                AutoSize = true,
                ForeColor = ThemeManager.Foreground,
                Margin = new Padding(0)
            };
            chkBackground.CheckedChanged += (_, _) => UpdateButtonStates();
            chkHost.CheckedChanged += (_, _) => UpdateButtonStates();
            checkPanel.Controls.Add(chkBackground);
            checkPanel.Controls.Add(chkHost);

            btnAdd = new ThemedButton { Text = "Add new", Margin = new Padding(0, 0, 6, 0) };
            btnUpdate = new ThemedButton { Text = "Save changes", Kind = ThemedButton.ButtonKind.Primary, Margin = new Padding(0, 0, 6, 0) };
            btnDelete = new ThemedButton { Text = "Delete", Kind = ThemedButton.ButtonKind.Danger, Margin = new Padding(0) };
            btnAdd.Click += (_, _) => AddCommand();
            btnUpdate.Click += (_, _) => UpdateCommand();
            btnDelete.Click += (_, _) => DeleteCommand();

            var actionPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.RightToLeft,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0)
            };
            actionPanel.Controls.Add(btnDelete);
            actionPanel.Controls.Add(btnUpdate);
            actionPanel.Controls.Add(btnAdd);

            btnImport = new ThemedButton { Text = "Import…", Margin = new Padding(0, 0, 6, 0) };
            btnExport = new ThemedButton { Text = "Export…", Margin = new Padding(0) };
            btnImport.Click += (_, _) => ImportCommands();
            btnExport.Click += (_, _) => ExportCommands();

            var filePanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0)
            };
            filePanel.Controls.Add(btnImport);
            filePanel.Controls.Add(btnExport);

            var bottomPanel = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                RowCount = 1,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0, 4, 0, 0)
            };
            bottomPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            bottomPanel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            bottomPanel.Controls.Add(filePanel, 0, 0);
            bottomPanel.Controls.Add(actionPanel, 1, 0);

            lblHint = new Label
            {
                Text = "Device commands run through adb shell. “Run on this PC” runs the command on Windows.",
                AutoSize = false,
                Dock = DockStyle.Fill,
                Height = 40,
                ForeColor = ThemeManager.SecondaryForeground,
                Margin = new Padding(0, 10, 0, 0)
            };

            var rightPanel = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 7,
                Padding = new Padding(12),
                BackColor = ThemeManager.Background
            };
            rightPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rightPanel.Controls.Add(lblName, 0, 0);
            rightPanel.Controls.Add(txtName, 0, 1);
            rightPanel.Controls.Add(lblCommand, 0, 2);
            rightPanel.Controls.Add(txtCommand, 0, 3);
            rightPanel.Controls.Add(checkPanel, 0, 4);
            rightPanel.Controls.Add(bottomPanel, 0, 5);
            rightPanel.Controls.Add(lblHint, 0, 6);

            var split = new SplitContainer
            {
                Dock = DockStyle.Fill,
                FixedPanel = FixedPanel.Panel1,
                SplitterWidth = 1,
                Panel1MinSize = 180,
                BackColor = ThemeManager.Border
            };
            split.Panel1.BackColor = ThemeManager.Background;
            split.Panel2.BackColor = ThemeManager.Background;
            split.Panel1.Controls.Add(leftPanel);
            split.Panel2.Controls.Add(rightPanel);
            Controls.Add(split);
            split.SplitterDistance = 250;

            KeyPreview = true;
            KeyDown += CommandManagerForm_KeyDown;
            ThemeManager.ThemeChanged += OnThemeChanged;
            Shown += (_, _) => ApplyThemeColors();

            LoadCommands();
            ApplyThemeColors();
        }

        private void CommandManagerForm_KeyDown(object? sender, KeyEventArgs e)
        {
            if (e.Control && e.KeyCode == Keys.S)
            {
                UpdateCommand();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
            else if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
        }

        private void LoadCommands()
        {
            commands = AdbHelper.GetSavedCommands();
            RefreshList();
        }

        private void RefreshList()
        {
            int previousIndex = listCommands.SelectedIndex;
            listCommands.BeginUpdate();
            try
            {
                listCommands.Items.Clear();
                foreach (AdbHelper.ShellCommand command in commands)
                {
                    listCommands.Items.Add(command.Name);
                }
            }
            finally
            {
                listCommands.EndUpdate();
            }

            if (commands.Count > 0)
            {
                listCommands.SelectedIndex = Math.Clamp(previousIndex, 0, commands.Count - 1);
            }
            else
            {
                ClearEditor();
            }

            UpdateButtonStates();
        }

        private void ListCommands_SelectedIndexChanged(object? sender, EventArgs e)
        {
            if (listCommands.SelectedIndex < 0 || listCommands.SelectedIndex >= commands.Count)
            {
                ClearEditor();
                return;
            }

            selectedCommand = commands[listCommands.SelectedIndex];
            txtName.Text = selectedCommand.Name;
            txtCommand.Text = selectedCommand.Command;
            chkBackground.Checked = selectedCommand.IsBackground;
            chkHost.Checked = selectedCommand.IsHostCommand;
            UpdateButtonStates();
        }

        private void ClearEditor()
        {
            selectedCommand = null;
            txtName.Clear();
            txtCommand.Clear();
            chkBackground.Checked = false;
            chkHost.Checked = false;
            UpdateButtonStates();
        }

        private void AddCommand()
        {
            if (!ValidateEditor())
            {
                return;
            }

            var command = new AdbHelper.ShellCommand
            {
                Name = txtName.Text.Trim(),
                Command = txtCommand.Text.Trim(),
                IsBackground = chkBackground.Checked,
                IsHostCommand = chkHost.Checked
            };

            commands.Add(command);
            AdbHelper.SaveCommands(commands);
            RefreshList();
            listCommands.SelectedIndex = commands.Count - 1;
        }

        private void UpdateCommand()
        {
            if (selectedCommand is null || !ValidateEditor())
            {
                return;
            }

            selectedCommand.Name = txtName.Text.Trim();
            selectedCommand.Command = txtCommand.Text.Trim();
            selectedCommand.IsBackground = chkBackground.Checked;
            selectedCommand.IsHostCommand = chkHost.Checked;

            AdbHelper.SaveCommands(commands);
            int index = listCommands.SelectedIndex;
            RefreshList();
            listCommands.SelectedIndex = index;
        }

        private void DeleteCommand()
        {
            if (selectedCommand is null)
            {
                return;
            }

            DialogResult result = MessageBox.Show(
                this,
                $"Delete “{selectedCommand.Name}”?",
                "Delete command",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (result != DialogResult.Yes)
            {
                return;
            }

            commands.Remove(selectedCommand);
            selectedCommand = null;
            AdbHelper.SaveCommands(commands);
            RefreshList();
        }

        private void ImportCommands()
        {
            using var dialog = new OpenFileDialog
            {
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                Title = "Import commands"
            };

            if (dialog.ShowDialog(this) != DialogResult.OK)
            {
                return;
            }

            try
            {
                string json = System.IO.File.ReadAllText(dialog.FileName);
                List<AdbHelper.ShellCommand>? imported =
                    System.Text.Json.JsonSerializer.Deserialize<List<AdbHelper.ShellCommand>>(json);

                if (imported is null || imported.Count == 0)
                {
                    MessageBox.Show(this, "The file does not contain any commands.", "Import commands", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                commands.AddRange(imported);
                AdbHelper.SaveCommands(commands);
                RefreshList();
                MessageBox.Show(this, $"Imported {imported.Count} command(s).", "Import commands", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Could not import commands", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ExportCommands()
        {
            using var dialog = new SaveFileDialog
            {
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                FileName = "androlaunch_commands.json",
                Title = "Export commands"
            };

            if (dialog.ShowDialog(this) != DialogResult.OK)
            {
                return;
            }

            try
            {
                string json = System.Text.Json.JsonSerializer.Serialize(
                    commands,
                    new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                System.IO.File.WriteAllText(dialog.FileName, json);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Could not export commands", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private bool ValidateEditor()
        {
            if (!string.IsNullOrWhiteSpace(txtName.Text) && !string.IsNullOrWhiteSpace(txtCommand.Text))
            {
                return true;
            }

            MessageBox.Show(
                this,
                "Enter both a name and a command.",
                "AndroLaunch",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);

            return false;
        }

        private void UpdateButtonStates()
        {
            bool editing = selectedCommand is not null;
            bool hasContent = !string.IsNullOrWhiteSpace(txtName.Text) && !string.IsNullOrWhiteSpace(txtCommand.Text);
            btnUpdate.Enabled = editing && hasContent;
            btnDelete.Enabled = editing;
            btnAdd.Enabled = hasContent;
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
            listCommands.BackColor = ThemeManager.Surface;
            listCommands.ForeColor = ThemeManager.Foreground;
            txtName.BackColor = ThemeManager.Surface;
            txtName.ForeColor = ThemeManager.Foreground;
            txtCommand.BackColor = ThemeManager.Surface;
            txtCommand.ForeColor = ThemeManager.Foreground;
            lblHint.ForeColor = ThemeManager.SecondaryForeground;
            Invalidate(true);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            base.OnFormClosed(e);
        }
    }
}
