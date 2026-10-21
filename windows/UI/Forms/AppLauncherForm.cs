using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using Androlaunch.Core;
using Androlaunch.UI.Controls;

namespace Androlaunch.UI.Forms
{
    public class AppLauncherForm : ThemedForm
    {
        private readonly string deviceSerial;
        private readonly TextBox txtSearch;
        private readonly Label lblSearchHint;
        private readonly Panel searchPanel;
        private readonly DataGridView gridApps;
        private readonly Label lblStatus;
        private readonly ThemedButton btnLaunch;
        private readonly ThemedButton btnClear;
        private readonly ThemedButton btnUninstall;
        private readonly ThemedButton btnRefresh;

        private List<AdbHelper.AppInfo> allApps = new();
        private bool _loading;

        public AppLauncherForm(string serial)
        {
            deviceSerial = serial;

            Text = "App manager";
            ClientSize = new Size(780, 560);
            MinimumSize = new Size(620, 420);
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;

            txtSearch = new TextBox
            {
                Dock = DockStyle.Fill,
                BorderStyle = BorderStyle.FixedSingle,
                Font = new Font(ThemeManager.UiFont.FontFamily, 11F, FontStyle.Regular, GraphicsUnit.Point),
                Margin = new Padding(0)
            };
            txtSearch.TextChanged += (_, _) => FilterApps();
            txtSearch.KeyDown += TxtSearch_KeyDown;
            txtSearch.Enter += (_, _) => UpdateSearchHint();
            txtSearch.Leave += (_, _) => UpdateSearchHint();

            lblSearchHint = new Label
            {
                Text = "Search apps",
                AutoSize = false,
                Height = 20,
                Width = 200,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = ThemeManager.SecondaryForeground,
                BackColor = ThemeManager.Surface,
                Cursor = Cursors.IBeam,
                Margin = new Padding(0)
            };
            lblSearchHint.Click += (_, _) => txtSearch.Focus();

            searchPanel = new Panel
            {
                Dock = DockStyle.Fill,
                Height = 32,
                BackColor = ThemeManager.Surface,
                Margin = new Padding(0, 0, 0, 8)
            };
            searchPanel.Controls.Add(txtSearch);
            searchPanel.Controls.Add(lblSearchHint);
            lblSearchHint.BringToFront();
            searchPanel.Resize += (_, _) => PositionSearchHint();

            gridApps = new DataGridView
            {
                Dock = DockStyle.Fill,
                BorderStyle = BorderStyle.FixedSingle,
                BackgroundColor = ThemeManager.Surface,
                GridColor = ThemeManager.Border,
                RowHeadersVisible = false,
                AllowUserToAddRows = false,
                AllowUserToDeleteRows = false,
                AllowUserToResizeRows = false,
                AllowUserToOrderColumns = false,
                ReadOnly = true,
                MultiSelect = false,
                SelectionMode = DataGridViewSelectionMode.FullRowSelect,
                AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
                ColumnHeadersHeight = 32,
                ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.DisableResizing,
                EnableHeadersVisualStyles = false,
                CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal,
                ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None,
                Margin = new Padding(0)
            };
            gridApps.DefaultCellStyle.BackColor = ThemeManager.Surface;
            gridApps.DefaultCellStyle.ForeColor = ThemeManager.Foreground;
            gridApps.DefaultCellStyle.SelectionBackColor = ThemeManager.Accent;
            gridApps.DefaultCellStyle.SelectionForeColor = ThemeManager.AccentForeground;
            gridApps.DefaultCellStyle.Font = ThemeManager.UiFont;
            gridApps.DefaultCellStyle.Padding = new Padding(6, 0, 6, 0);
            gridApps.ColumnHeadersDefaultCellStyle.BackColor = ThemeManager.Surface;
            gridApps.ColumnHeadersDefaultCellStyle.ForeColor = ThemeManager.SecondaryForeground;
            gridApps.ColumnHeadersDefaultCellStyle.SelectionBackColor = ThemeManager.Surface;
            gridApps.ColumnHeadersDefaultCellStyle.SelectionForeColor = ThemeManager.SecondaryForeground;
            gridApps.ColumnHeadersDefaultCellStyle.Font = ThemeManager.MenuHeaderFont;
            gridApps.ColumnHeadersDefaultCellStyle.Padding = new Padding(6, 0, 6, 0);
            gridApps.RowTemplate.Height = 30;
            gridApps.Columns.Add(new DataGridViewTextBoxColumn
            {
                Name = "AppName",
                HeaderText = "App",
                FillWeight = 45,
                SortMode = DataGridViewColumnSortMode.NotSortable
            });
            gridApps.Columns.Add(new DataGridViewTextBoxColumn
            {
                Name = "PackageName",
                HeaderText = "Package",
                FillWeight = 55,
                SortMode = DataGridViewColumnSortMode.NotSortable
            });
            gridApps.SelectionChanged += (_, _) => UpdateButtons();
            gridApps.CellDoubleClick += (_, e) =>
            {
                if (e.RowIndex >= 0)
                {
                    LaunchSelected();
                }
            };
            gridApps.KeyDown += GridApps_KeyDown;

            lblStatus = new Label
            {
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                AutoSize = false,
                ForeColor = ThemeManager.SecondaryForeground,
                Margin = new Padding(0, 0, 8, 0)
            };

            btnLaunch = new ThemedButton { Text = "Launch", Kind = ThemedButton.ButtonKind.Primary };
            btnClear = new ThemedButton { Text = "Clear data" };
            btnUninstall = new ThemedButton { Text = "Uninstall", Kind = ThemedButton.ButtonKind.Danger };
            btnRefresh = new ThemedButton { Text = "Refresh" };

            btnLaunch.Click += (_, _) => LaunchSelected();
            btnClear.Click += (_, _) => ClearSelectedData();
            btnUninstall.Click += (_, _) => UninstallSelected();
            btnRefresh.Click += async (_, _) => await LoadAppsAsync();

            var buttonPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.RightToLeft,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0)
            };
            buttonPanel.Controls.Add(btnLaunch);
            buttonPanel.Controls.Add(btnClear);
            buttonPanel.Controls.Add(btnUninstall);
            buttonPanel.Controls.Add(btnRefresh);

            var footer = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                RowCount = 1,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Margin = new Padding(0, 8, 0, 0)
            };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.Controls.Add(lblStatus, 0, 0);
            footer.Controls.Add(buttonPanel, 1, 0);

            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 3,
                Padding = new Padding(12),
                BackColor = ThemeManager.Background
            };
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.Controls.Add(searchPanel, 0, 0);
            root.Controls.Add(gridApps, 0, 1);
            root.Controls.Add(footer, 0, 2);
            Controls.Add(root);

            AcceptButton = btnLaunch;
            KeyPreview = true;
            KeyDown += AppLauncherForm_KeyDown;
            Shown += async (_, _) =>
            {
                ApplyThemeColors();
                PositionSearchHint();
                txtSearch.Focus();
                UpdateSearchHint();
                await LoadAppsAsync();
            };
            ThemeManager.ThemeChanged += OnThemeChanged;
            ApplyThemeColors();
        }

        private AdbHelper.AppInfo? SelectedApp
        {
            get
            {
                if (gridApps.SelectedRows.Count == 0)
                {
                    return null;
                }

                return gridApps.SelectedRows[0].Tag as AdbHelper.AppInfo;
            }
        }

        private void PositionSearchHint()
        {
            lblSearchHint.Location = new Point(7, Math.Max(0, (searchPanel.Height - lblSearchHint.Height) / 2));
        }

        private async Task LoadAppsAsync()
        {
            if (_loading)
            {
                return;
            }

            _loading = true;
            UpdateButtons();
            lblStatus.Text = $"Loading apps from {deviceSerial}…";

            try
            {
                List<AdbHelper.AppInfo> apps = await Task.Run(() => AdbHelper.GetApps(deviceSerial));
                if (IsDisposed)
                {
                    return;
                }

                allApps = apps;
                _loading = false;
                FilterApps();
            }
            catch (Exception ex)
            {
                _loading = false;
                if (!IsDisposed)
                {
                    lblStatus.Text = "Could not load apps";
                    MessageBox.Show(this, ex.Message, "AndroLaunch", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            finally
            {
                if (!IsDisposed)
                {
                    UpdateButtons();
                }
            }
        }

        private void FilterApps()
        {
            string query = txtSearch.Text.Trim();
            List<AdbHelper.AppInfo> filtered = string.IsNullOrEmpty(query)
                ? allApps
                : allApps.Where(app =>
                    app.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    app.PackageName.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();

            gridApps.SuspendLayout();
            try
            {
                gridApps.Rows.Clear();
                foreach (AdbHelper.AppInfo app in filtered)
                {
                    int index = gridApps.Rows.Add(app.Name, app.PackageName);
                    gridApps.Rows[index].Tag = app;
                }
            }
            finally
            {
                gridApps.ResumeLayout();
            }

            UpdateSearchHint();

            if (gridApps.Rows.Count > 0 && !string.IsNullOrEmpty(query))
            {
                gridApps.ClearSelection();
                gridApps.Rows[0].Selected = true;
                gridApps.CurrentCell = gridApps.Rows[0].Cells[0];
            }

            lblStatus.Text = _loading
                ? $"Loading apps from {deviceSerial}…"
                : allApps.Count == 0
                    ? "No apps found"
                    : filtered.Count == allApps.Count
                        ? $"{allApps.Count} apps"
                        : $"{filtered.Count} of {allApps.Count} apps";

            UpdateButtons();
        }

        private void UpdateSearchHint()
        {
            lblSearchHint.Visible = txtSearch.TextLength == 0 && !txtSearch.Focused;
        }

        private void UpdateButtons()
        {
            bool hasSelection = SelectedApp is not null;
            btnLaunch.Enabled = hasSelection && !_loading;
            btnClear.Enabled = hasSelection && !_loading;
            btnUninstall.Enabled = hasSelection && !_loading;
            btnRefresh.Enabled = !_loading;
        }

        private void LaunchSelected()
        {
            AdbHelper.AppInfo? app = SelectedApp;
            if (app is null)
            {
                return;
            }

            AdbHelper.LaunchApp(deviceSerial, app.PackageName);
            Close();
        }

        private async void ClearSelectedData()
        {
            AdbHelper.AppInfo? app = SelectedApp;
            if (app is null)
            {
                return;
            }

            DialogResult result = MessageBox.Show(
                this,
                $"Clear all data for {app.Name}?\n\nThis resets the app to its initial state.",
                "Clear app data",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (result != DialogResult.Yes)
            {
                return;
            }

            try
            {
                UseWaitCursor = true;
                await Task.Run(() => AdbHelper.ClearAppData(deviceSerial, app.PackageName));
                MessageBox.Show(this, "App data cleared.", "AndroLaunch", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Could not clear app data", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        private async void UninstallSelected()
        {
            AdbHelper.AppInfo? app = SelectedApp;
            if (app is null)
            {
                return;
            }

            DialogResult result = MessageBox.Show(
                this,
                $"Uninstall {app.Name}?\n\n{app.PackageName}",
                "Uninstall app",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (result != DialogResult.Yes)
            {
                return;
            }

            try
            {
                UseWaitCursor = true;
                await Task.Run(() => AdbHelper.UninstallApp(deviceSerial, app.PackageName));
                await LoadAppsAsync();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Could not uninstall app", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                UseWaitCursor = false;
            }
        }

        private void TxtSearch_KeyDown(object? sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Down && gridApps.Rows.Count > 0)
            {
                gridApps.Focus();
                if (gridApps.SelectedRows.Count == 0)
                {
                    gridApps.Rows[0].Selected = true;
                    gridApps.CurrentCell = gridApps.Rows[0].Cells[0];
                }
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Enter)
            {
                LaunchSelected();
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
        }

        private void GridApps_KeyDown(object? sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                LaunchSelected();
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Back)
            {
                txtSearch.Focus();
                txtSearch.SelectionStart = txtSearch.TextLength;
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Delete)
            {
                UninstallSelected();
                e.Handled = true;
            }
        }

        private void AppLauncherForm_KeyDown(object? sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
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
            txtSearch.BackColor = ThemeManager.Surface;
            txtSearch.ForeColor = ThemeManager.Foreground;
            lblSearchHint.BackColor = ThemeManager.Surface;
            lblSearchHint.ForeColor = ThemeManager.SecondaryForeground;
            searchPanel.BackColor = ThemeManager.Surface;

            gridApps.BackgroundColor = ThemeManager.Surface;
            gridApps.GridColor = ThemeManager.Border;
            gridApps.DefaultCellStyle.BackColor = ThemeManager.Surface;
            gridApps.DefaultCellStyle.ForeColor = ThemeManager.Foreground;
            gridApps.DefaultCellStyle.SelectionBackColor = ThemeManager.Accent;
            gridApps.DefaultCellStyle.SelectionForeColor = ThemeManager.AccentForeground;
            gridApps.ColumnHeadersDefaultCellStyle.BackColor = ThemeManager.Surface;
            gridApps.ColumnHeadersDefaultCellStyle.ForeColor = ThemeManager.SecondaryForeground;
            gridApps.ColumnHeadersDefaultCellStyle.SelectionBackColor = ThemeManager.Surface;
            gridApps.ColumnHeadersDefaultCellStyle.SelectionForeColor = ThemeManager.SecondaryForeground;
            lblStatus.ForeColor = ThemeManager.SecondaryForeground;
            Invalidate(true);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            ThemeManager.ThemeChanged -= OnThemeChanged;
            base.OnFormClosed(e);
        }
    }
}
