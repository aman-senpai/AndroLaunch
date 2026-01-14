using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using System.Linq;
using Androlaunch.Core;
using Androlaunch.UI.Renderers;

namespace Androlaunch.UI.Forms
{
    public class CommandManagerForm : Form
    {
        private ListBox listCommands;
        private TextBox txtName;
        private TextBox txtCommand;
        private CheckBox chkBackground;
        private CheckBox chkHost;
        private Button btnAdd;
        private Button btnUpdate;
        private Button btnDelete;
        private Button btnImport;
        private Button btnExport;
        
        private List<AdbHelper.ShellCommand> commands;
        private AdbHelper.ShellCommand? selectedCommand;

        public CommandManagerForm()
        {
            InitializeComponent();
            LoadCommands();
            ApplyCurrentTheme();
            ThemeManager.ThemeChanged += () => {
                if (this.IsHandleCreated) this.BeginInvoke((MethodInvoker)delegate { 
                    ThemeManager.ApplyTheme(this);
                    ApplyCurrentTheme(); // This one sets specialized control colors
                });
            };
        }

        private void ApplyCurrentTheme()
        {
            this.BackColor = ThemeManager.Background;
            this.ForeColor = ThemeManager.Foreground;
            listCommands.BackColor = ThemeManager.Background;
            txtName.BackColor = ThemeManager.Surface;
            txtName.ForeColor = ThemeManager.Foreground;
            txtCommand.BackColor = ThemeManager.Surface;
            txtCommand.ForeColor = ThemeManager.Foreground;
            this.Refresh();
        }

        private void InitializeComponent()
        {
            this.Text = "Commands";
            this.Size = new Size(600, 450);
            this.Font = new Font("Segoe UI", 10F);
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.StartPosition = FormStartPosition.CenterScreen;

            try
            {
                string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "app_icon.ico");
                if (!System.IO.File.Exists(iconPath)) iconPath = "app_icon.ico";
                if (System.IO.File.Exists(iconPath)) this.Icon = new Icon(iconPath);
            } catch { }

            TableLayoutPanel mainLayout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(10) };
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60));

            // Left side: List
            Panel leftPanel = new Panel { Dock = DockStyle.Fill };
            listCommands = new ListBox
            {
                Dock = DockStyle.Fill,
                BorderStyle = BorderStyle.None,
                ItemHeight = 45,
                DrawMode = DrawMode.OwnerDrawFixed
            };
            listCommands.DrawItem += (s, e) => {
                if (e.Index < 0) return;
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

                bool isSelected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
                var cmd = commands[e.Index];

                using (var brush = new SolidBrush(ThemeManager.Background))
                {
                    g.FillRectangle(brush, e.Bounds);
                }

                if (isSelected)
                {
                    var selectionRect = new Rectangle(e.Bounds.X + 5, e.Bounds.Y + 3, e.Bounds.Width - 10, e.Bounds.Height - 6);
                    g.FillRoundedRectangle(new SolidBrush(ThemeManager.IsDarkMode ? ThemeManager.Accent : Color.FromArgb(220, 235, 255)), selectionRect, 5);
                }

                string icon = cmd.IsHostCommand ? "💻" : "📱";
                string backgroundIcon = cmd.IsBackground ? " ⚙️" : "";
                using (var brush = new SolidBrush(isSelected && ThemeManager.IsDarkMode ? Color.White : ThemeManager.Foreground))
                {
                    g.DrawString($"{icon}{backgroundIcon} {cmd.Name}", listCommands.Font, brush, 
                                 new Rectangle(e.Bounds.X + 10, e.Bounds.Y, e.Bounds.Width - 20, e.Bounds.Height), 
                                 new StringFormat { LineAlignment = StringAlignment.Center });
                }
            };
            listCommands.SelectedIndexChanged += ListCommands_SelectedIndexChanged;
            leftPanel.Controls.Add(listCommands);

            btnDelete = CreateButton("Delete", Color.FromArgb(255, 59, 48), Color.White);
            btnDelete.Dock = DockStyle.Bottom;
            btnDelete.Click += (s, e) => DeleteCommand();
            leftPanel.Controls.Add(btnDelete);
            
            mainLayout.Controls.Add(leftPanel, 0, 0);

            // Right side: Editor
            Panel rightPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(10, 0, 0, 0) };
            
            Label lblName = new Label { Text = "Name:", Dock = DockStyle.Top, Height = 25 };
            txtName = new TextBox { Dock = DockStyle.Top, BorderStyle = BorderStyle.FixedSingle };
            
            Label lblCommand = new Label { Text = "Command:", Dock = DockStyle.Top, Height = 25, Margin = new Padding(0, 10, 0, 0) };
            txtCommand = new TextBox { Dock = DockStyle.Top, Multiline = true, Height = 80, BorderStyle = BorderStyle.FixedSingle };
            
            chkBackground = new CheckBox { Text = "Run in Background", Dock = DockStyle.Top, Height = 30, FlatStyle = FlatStyle.Flat };
            chkHost = new CheckBox { Text = "Host Command (Runs on PC)", Dock = DockStyle.Top, Height = 30, FlatStyle = FlatStyle.Flat };
            
            txtName.BorderStyle = BorderStyle.FixedSingle;
            txtCommand.BorderStyle = BorderStyle.FixedSingle;

            Panel buttonPanel = new Panel { Dock = DockStyle.Top, Height = 45, Margin = new Padding(0, 20, 0, 0) };
            btnAdd = CreateButton("Add New", ThemeManager.Surface, ThemeManager.Foreground);
            btnAdd.Width = 90;
            btnAdd.Click += (s, e) => AddCommand();
            
            btnUpdate = CreateButton("Save Changes", ThemeManager.Accent, Color.White);
            btnUpdate.Width = 120;
            btnUpdate.Left = 100;
            btnUpdate.Enabled = false;
            btnUpdate.Click += (s, e) => UpdateCommand();
            
            btnUpdate.EnabledChanged += (s, e) => {
                btnUpdate.Refresh(); // Force repaint with new state
            };
            
            buttonPanel.Controls.Add(btnAdd);
            buttonPanel.Controls.Add(btnUpdate);

            Panel footerPanel = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 5, 0, 5) };
            btnImport = CreateButton("Import JSON", Color.FromArgb(45, 45, 48), Color.White);
            btnImport.Width = 110;
            btnImport.Click += (s, e) => ImportCommands();
            
            btnExport = CreateButton("Export JSON", Color.FromArgb(45, 45, 48), Color.White);
            btnExport.Width = 110;
            btnExport.Left = 120;
            btnExport.Click += (s, e) => ExportCommands();
            
            footerPanel.Controls.Add(btnImport);
            footerPanel.Controls.Add(btnExport);

            rightPanel.Controls.Add(buttonPanel);
            rightPanel.Controls.Add(chkHost);
            rightPanel.Controls.Add(chkBackground);
            rightPanel.Controls.Add(txtCommand);
            rightPanel.Controls.Add(lblCommand);
            rightPanel.Controls.Add(txtName);
            rightPanel.Controls.Add(lblName);
            rightPanel.Controls.Add(footerPanel);

            mainLayout.Controls.Add(rightPanel, 1, 0);
            this.Controls.Add(mainLayout);
        }

        private void LoadCommands()
        {
            commands = AdbHelper.GetSavedCommands();
            RefreshList();
        }

        private void RefreshList()
        {
            listCommands.Items.Clear();
            foreach (var cmd in commands)
            {
                listCommands.Items.Add(cmd.Name);
            }
        }

        private void ListCommands_SelectedIndexChanged(object? sender, EventArgs e)
        {
            if (listCommands.SelectedIndex == -1)
            {
                selectedCommand = null;
                btnUpdate.Enabled = false;
                txtName.Clear();
                txtCommand.Clear();
                chkBackground.Checked = false;
                chkHost.Checked = false;
                return;
            }

            selectedCommand = commands[listCommands.SelectedIndex];
            txtName.Text = selectedCommand.Name;
            txtCommand.Text = selectedCommand.Command;
            chkBackground.Checked = selectedCommand.IsBackground;
            chkHost.Checked = selectedCommand.IsHostCommand;
            btnUpdate.Enabled = true;
        }

        private void AddCommand()
        {
            if (string.IsNullOrWhiteSpace(txtName.Text) || string.IsNullOrWhiteSpace(txtCommand.Text))
            {
                MessageBox.Show("Please fill Name and Command.", "Validation Error");
                return;
            }

            var cmd = new AdbHelper.ShellCommand
            {
                Name = txtName.Text.Trim(),
                Command = txtCommand.Text.Trim(),
                IsBackground = chkBackground.Checked,
                IsHostCommand = chkHost.Checked
            };

            commands.Add(cmd);
            AdbHelper.SaveCommands(commands);
            RefreshList();
            listCommands.SelectedIndex = commands.Count - 1;
        }

        private void UpdateCommand()
        {
            if (selectedCommand == null) return;
            if (string.IsNullOrWhiteSpace(txtName.Text) || string.IsNullOrWhiteSpace(txtCommand.Text)) return;

            selectedCommand.Name = txtName.Text.Trim();
            selectedCommand.Command = txtCommand.Text.Trim();
            selectedCommand.IsBackground = chkBackground.Checked;
            selectedCommand.IsHostCommand = chkHost.Checked;

            AdbHelper.SaveCommands(commands);
            int idx = listCommands.SelectedIndex;
            RefreshList();
            listCommands.SelectedIndex = idx;
        }

        private void DeleteCommand()
        {
            if (selectedCommand == null) return;
            if (MessageBox.Show($"Are you sure you want to delete '{selectedCommand.Name}'?", "Confirm Delete", MessageBoxButtons.YesNo) == DialogResult.Yes)
            {
                commands.Remove(selectedCommand);
                AdbHelper.SaveCommands(commands);
                RefreshList();
            }
        }

        private void ImportCommands()
        {
            using (var ofd = new OpenFileDialog { Filter = "JSON Files|*.json" })
            {
                if (ofd.ShowDialog() == DialogResult.OK)
                {
                    try
                    {
                        string json = System.IO.File.ReadAllText(ofd.FileName);
                        var imported = System.Text.Json.JsonSerializer.Deserialize<List<AdbHelper.ShellCommand>>(json);
                        if (imported != null)
                        {
                            commands.AddRange(imported);
                            AdbHelper.SaveCommands(commands);
                            RefreshList();
                            MessageBox.Show($"Imported {imported.Count} commands.");
                        }
                    }
                    catch (Exception ex) { MessageBox.Show("Import failed: " + ex.Message); }
                }
            }
        }

        private void ExportCommands()
        {
            using (var sfd = new SaveFileDialog { Filter = "JSON Files|*.json", FileName = "androlaunch_commands.json" })
            {
                if (sfd.ShowDialog() == DialogResult.OK)
                {
                    try
                    {
                        string json = System.Text.Json.JsonSerializer.Serialize(commands, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                        System.IO.File.WriteAllText(sfd.FileName, json);
                        MessageBox.Show("Exported successful.");
                    }
                    catch (Exception ex) { MessageBox.Show("Export failed: " + ex.Message); }
                }
            }
        }
        private Button CreateButton(string text, Color back, Color fore)
        {
            var btn = new Button
            {
                Text = text,
                BackColor = back,
                ForeColor = fore,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI Semibold", 9.5f),
                Height = 35,
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            btn.FlatAppearance.MouseOverBackColor = Color.Transparent; // We handle hover via drawing or just leave it
            btn.FlatAppearance.MouseDownBackColor = Color.Transparent;
            
            btn.Paint += (s, e) => {
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                
                // Clear background to parent's color to avoid black corners
                g.Clear(btn.Parent?.BackColor ?? ThemeManager.Background);
                
                Color actualBack = back;
                Color actualFore = fore;

                if (!btn.Enabled)
                {
                    actualBack = ThemeManager.IsDarkMode ? Color.FromArgb(60, 60, 62) : Color.FromArgb(230, 230, 235);
                    actualFore = ThemeManager.SecondaryForeground;
                }
                else if (back == ThemeManager.Surface) // For standard "secondary" buttons
                {
                    actualBack = ThemeManager.IsDarkMode ? Color.FromArgb(45, 45, 48) : Color.FromArgb(225, 225, 230);
                    actualFore = ThemeManager.Foreground;
                }
                
                using (var brush = new SolidBrush(actualBack))
                {
                    g.FillRoundedRectangle(brush, btn.ClientRectangle, 6);
                }
                
                TextRenderer.DrawText(g, btn.Text, btn.Font, btn.ClientRectangle, actualFore, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            };
            return btn;
        }
    }
}
