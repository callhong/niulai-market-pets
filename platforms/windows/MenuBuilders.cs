using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Forms = System.Windows.Forms;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public static class WpfMenuBuilder
{
    public static ContextMenu Build(MarketViewModel model, MainWindow window)
    {
        var menu = new ContextMenu();
        var shape = new MenuItem { Header = "形态" };
        AddShape(shape, "自动", ControlMode.Auto, null, model);
        foreach (var pet in Enum.GetValues<PetId>()) AddShape(shape, pet.DisplayName(), ControlMode.Manual, pet, model);
        menu.Items.Add(shape);

        var indexMenu = new MenuItem { Header = "指数" };
        foreach (var target in MarketTarget.All)
        {
            indexMenu.Items.Add(IndexItem(target, model));
        }
        indexMenu.Items.Add(new Separator());
        var polling = new MenuItem { Header = "轮询指数（每 60 秒）", IsCheckable = true, IsChecked = model.IndexPollingEnabled };
        polling.Click += (_, _) => model.TogglePolling();
        indexMenu.Items.Add(polling);
        var watchlist = new MenuItem { Header = "自选池" };
        PopulateWatchlistMenu(watchlist, model, window);
        indexMenu.Items.Add(new Separator());
        indexMenu.Items.Add(watchlist);
        menu.Items.Add(indexMenu);

        var pill = new MenuItem { Header = "显示行情标签", IsCheckable = true, IsChecked = model.ShowMarketPill };
        pill.Click += (_, _) => model.TogglePill();
        menu.Items.Add(pill);
        menu.Items.Add(new Separator());
        menu.Items.Add(SizeMenu(model));
        menu.Items.Add(SpeechMenu(model));
        var mute = new MenuItem { Header = "静音", IsCheckable = true, IsChecked = model.IsMuted };
        mute.Click += (_, _) => model.ToggleMute();
        menu.Items.Add(mute);
        var startup = new MenuItem { Header = "开机启动", IsCheckable = true, IsChecked = model.LaunchAtStartup };
        startup.Click += (_, _) => model.SetStartup(!model.LaunchAtStartup);
        menu.Items.Add(startup);
        menu.Items.Add(new Separator());
        var visibility = new MenuItem { Header = model.ShowPet ? "隐藏宠物" : "显示宠物" };
        visibility.Click += (_, _) => window.ToggleVisibility();
        menu.Items.Add(visibility);
        var update = new MenuItem { Header = "检查更新…" };
        update.Click += async (_, _) => await window.CheckForUpdatesAsync();
        menu.Items.Add(update);
        var exit = new MenuItem { Header = "退出" };
        exit.Click += (_, _) => window.ExitApplication();
        menu.Items.Add(exit);

        menu.Opened += async (_, _) =>
        {
            await model.RefreshSnapshotsForMenuAsync();
            RefreshShapeChecks(shape, model);
            foreach (var item in indexMenu.Items.OfType<MenuItem>())
            {
                if (item.Tag is not MarketTarget target) continue;
                item.IsChecked = !model.IndexPollingEnabled && !model.WatchlistPollingEnabled && model.Target.Id == target.Id;
                item.Header = MakeRow(target, model.Snapshot(target));
            }
            polling.IsChecked = model.IndexPollingEnabled;
            PopulateWatchlistMenu(watchlist, model, window);
            pill.IsChecked = model.ShowMarketPill;
            RefreshPresetMenu(menu.Items.OfType<MenuItem>().First(item => item.Tag as string == "pet-size"), "宠物大小", model.PetScalePercent);
            RefreshPresetMenu(menu.Items.OfType<MenuItem>().First(item => item.Tag as string == "speech-size"), "台词字号", model.SpeechTextScalePercent);
            mute.IsChecked = model.IsMuted;
            startup.IsChecked = model.LaunchAtStartup;
            visibility.Header = model.ShowPet ? "隐藏宠物" : "显示宠物";
        };
        return menu;
    }

    private static void RefreshShapeChecks(MenuItem parent, MarketViewModel model)
    {
        foreach (var item in parent.Items.OfType<MenuItem>())
        {
            var title = item.Header as string;
            item.IsChecked = title == "自动"
                ? model.Mode == ControlMode.Auto
                : model.Mode == ControlMode.Manual && model.ActivePet.DisplayName() == title;
        }
    }

    private static void AddShape(MenuItem parent, string title, ControlMode mode, PetId? pet, MarketViewModel model)
    {
        var item = new MenuItem { Header = title, IsCheckable = true, IsChecked = pet is null ? model.Mode == ControlMode.Auto : model.Mode == ControlMode.Manual && model.ActivePet == pet };
        item.Click += (_, _) => { if (mode == ControlMode.Auto) model.SelectAuto(); else model.SelectPet(pet!.Value); };
        parent.Items.Add(item);
    }

    private static Grid MakeRow(MarketTarget target, MarketSnapshot snapshot)
    {
        var grid = new Grid { Width = 286, Margin = new Thickness(4, 1, 4, 1) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var name = new TextBlock { Text = snapshot.Quote?.Name ?? target.Name, MinWidth = 150, TextTrimming = TextTrimming.None };
        var percent = new TextBlock { Text = snapshot.Quote is null ? "--" : MarketRules.SignedPercent(snapshot.Quote.Percent), TextAlignment = TextAlignment.Right, Foreground = Brush(snapshot.Tone(DateTimeOffset.UtcNow)), MinWidth = 70 };
        Grid.SetColumn(percent, 1);
        grid.Children.Add(name);
        grid.Children.Add(percent);
        return grid;
    }

    private static System.Windows.Media.Brush Brush(MarketTone tone) => new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(MarketToneRules.Hex(tone))!);

    private static MenuItem IndexItem(MarketTarget target, MarketViewModel model)
    {
        var item = new MenuItem { IsCheckable = true, IsChecked = !model.IndexPollingEnabled && !model.WatchlistPollingEnabled && model.Target.Id == target.Id, Tag = target };
        item.Header = MakeRow(target, model.Snapshot(target));
        item.Click += async (_, _) => await model.SelectTargetAsync(target);
        return item;
    }

    private static void PopulateWatchlistMenu(MenuItem parent, MarketViewModel model, MainWindow window)
    {
        parent.Items.Clear();

        var add = new MenuItem { Header = "输入股票代码…" };
        add.Click += async (_, _) => await window.SelectTonghuashunCodeAsync();
        parent.Items.Add(add);

        var manage = new MenuItem { Header = "管理自选池…", IsEnabled = model.CustomTargets.Count > 0 };
        manage.Click += async (_, _) => await window.ManageWatchlistAsync();
        parent.Items.Add(manage);

        if (model.CustomTargets.Count == 0) return;

        parent.Items.Add(new Separator());
        var polling = new MenuItem { Header = "轮询自选池（每 60 秒）", IsCheckable = true, IsChecked = model.WatchlistPollingEnabled };
        polling.Click += (_, _) => model.ToggleWatchlistPolling();
        parent.Items.Add(polling);
        parent.Items.Add(new Separator());
        foreach (var target in model.CustomTargets) parent.Items.Add(IndexItem(target, model));
    }

    private static MenuItem SizeMenu(MarketViewModel model)
    {
        var parent = new MenuItem { Header = $"宠物大小（{model.PetScalePercent:0}%）", Tag = "pet-size" };
        foreach (var value in new[] { 60d, 80, 100, 120, 140, 160 })
        {
            var item = new MenuItem { Header = $"{value:0}%", IsCheckable = true, IsChecked = Math.Abs(model.PetScalePercent - value) < 0.1 };
            item.Click += (_, _) => model.SetPetScale(value);
            parent.Items.Add(item);
        }
        return parent;
    }

    private static MenuItem SpeechMenu(MarketViewModel model)
    {
        var parent = new MenuItem { Header = $"台词字号（{model.SpeechTextScalePercent:0}%）", Tag = "speech-size" };
        foreach (var value in new[] { 80d, 100, 120, 140 })
        {
            var item = new MenuItem { Header = $"{value:0}%", IsCheckable = true, IsChecked = Math.Abs(model.SpeechTextScalePercent - value) < 0.1 };
            item.Click += (_, _) => model.SetSpeechScale(value);
            parent.Items.Add(item);
        }
        return parent;
    }

    private static void RefreshPresetMenu(MenuItem parent, string title, double current)
    {
        parent.Header = $"{title}（{current:0}%）";
        foreach (var item in parent.Items.OfType<MenuItem>())
        {
            if (item.Header is string text && double.TryParse(text.TrimEnd('%'), out var value)) item.IsChecked = Math.Abs(current - value) < 0.1;
        }
    }
}

public static class TrayMenuBuilder
{
    public static void Populate(Forms.ContextMenuStrip menu, MarketViewModel model, MainWindow window)
    {
        menu.Items.Clear();
        var shape = new Forms.ToolStripMenuItem("形态");
        AddShape(shape, "自动", model.Mode == ControlMode.Auto, () => model.SelectAuto());
        foreach (var pet in Enum.GetValues<PetId>()) AddShape(shape, pet.DisplayName(), model.Mode == ControlMode.Manual && model.ActivePet == pet, () => model.SelectPet(pet));
        menu.Items.Add(shape);

        var indexes = new Forms.ToolStripMenuItem("指数");
        foreach (var target in MarketTarget.All)
        {
            var row = new MarketTrayMenuItem(target, model.Snapshot(target), !model.IndexPollingEnabled && !model.WatchlistPollingEnabled && model.Target.Id == target.Id, model.DisplayName(target));
            row.Click += async (_, _) => await model.SelectTargetAsync(target);
            indexes.DropDownItems.Add(row);
        }
        indexes.DropDownItems.Add(new Forms.ToolStripSeparator());
        var polling = new Forms.ToolStripMenuItem("轮询指数（每 60 秒）") { CheckOnClick = true, Checked = model.IndexPollingEnabled };
        polling.Click += (_, _) => model.TogglePolling();
        indexes.DropDownItems.Add(polling);
        var watchlist = new Forms.ToolStripMenuItem("自选池");
        PopulateWatchlistMenu(watchlist, model, window);
        indexes.DropDownItems.Add(new Forms.ToolStripSeparator());
        indexes.DropDownItems.Add(watchlist);
        menu.Items.Add(indexes);

        var pill = new Forms.ToolStripMenuItem("显示行情标签") { CheckOnClick = true, Checked = model.ShowMarketPill };
        pill.Click += (_, _) => model.TogglePill();
        menu.Items.Add(pill);
        menu.Items.Add(new Forms.ToolStripSeparator());
        AddPresets(menu, "宠物大小", new[] { 60d, 80, 100, 120, 140, 160 }, model.PetScalePercent, model.SetPetScale);
        AddPresets(menu, "台词字号", new[] { 80d, 100, 120, 140 }, model.SpeechTextScalePercent, model.SetSpeechScale);
        var mute = new Forms.ToolStripMenuItem("静音") { CheckOnClick = true, Checked = model.IsMuted };
        mute.Click += (_, _) => model.ToggleMute();
        menu.Items.Add(mute);
        var startup = new Forms.ToolStripMenuItem("开机启动") { CheckOnClick = true, Checked = model.LaunchAtStartup };
        startup.Click += (_, _) => model.SetStartup(!model.LaunchAtStartup);
        menu.Items.Add(startup);
        menu.Items.Add(new Forms.ToolStripSeparator());
        var visibility = new Forms.ToolStripMenuItem(model.ShowPet ? "隐藏宠物" : "显示宠物");
        visibility.Click += (_, _) => window.ToggleVisibility();
        menu.Items.Add(visibility);
        var update = new Forms.ToolStripMenuItem("检查更新…");
        update.Click += async (_, _) => await window.CheckForUpdatesAsync();
        menu.Items.Add(update);
        var exit = new Forms.ToolStripMenuItem("退出");
        exit.Click += (_, _) => window.ExitApplication();
        menu.Items.Add(exit);
    }

    private static void PopulateWatchlistMenu(Forms.ToolStripMenuItem parent, MarketViewModel model, MainWindow window)
    {
        parent.DropDownItems.Clear();
        var add = new Forms.ToolStripMenuItem("输入股票代码…");
        add.Click += async (_, _) => await window.SelectTonghuashunCodeAsync();
        parent.DropDownItems.Add(add);
        var manage = new Forms.ToolStripMenuItem("管理自选池…") { Enabled = model.CustomTargets.Count > 0 };
        manage.Click += async (_, _) => await window.ManageWatchlistAsync();
        parent.DropDownItems.Add(manage);
        if (model.CustomTargets.Count == 0) return;

        parent.DropDownItems.Add(new Forms.ToolStripSeparator());
        var polling = new Forms.ToolStripMenuItem("轮询自选池（每 60 秒）") { CheckOnClick = true, Checked = model.WatchlistPollingEnabled };
        polling.Click += (_, _) => model.ToggleWatchlistPolling();
        parent.DropDownItems.Add(polling);
        parent.DropDownItems.Add(new Forms.ToolStripSeparator());
        foreach (var target in model.CustomTargets)
        {
            var row = new MarketTrayMenuItem(target, model.Snapshot(target), !model.IndexPollingEnabled && !model.WatchlistPollingEnabled && model.Target.Id == target.Id, model.DisplayName(target));
            row.Click += async (_, _) => await model.SelectTargetAsync(target);
            parent.DropDownItems.Add(row);
        }
    }

    private static void AddShape(Forms.ToolStripMenuItem parent, string title, bool selected, Action action)
    {
        var item = new Forms.ToolStripMenuItem(title) { Checked = selected };
        item.Click += (_, _) => action();
        parent.DropDownItems.Add(item);
    }

    private static void AddPresets(Forms.ContextMenuStrip menu, string title, double[] values, double current, Action<double> setter)
    {
        var parent = new Forms.ToolStripMenuItem($"{title}（{current:0}%）");
        foreach (var value in values)
        {
            var item = new Forms.ToolStripMenuItem($"{value:0}%") { Checked = Math.Abs(current - value) < 0.1 };
            item.Click += (_, _) => setter(value);
            parent.DropDownItems.Add(item);
        }
        menu.Items.Add(parent);
    }
}

public sealed class MarketTrayMenuItem : Forms.ToolStripMenuItem
{
    private readonly MarketTarget _target;
    private MarketSnapshot _snapshot;
    private readonly string _displayName;

    public MarketTrayMenuItem(MarketTarget target, MarketSnapshot snapshot, bool selected, string? displayName = null)
    {
        _target = target;
        _snapshot = snapshot;
        _displayName = string.IsNullOrWhiteSpace(displayName) ? target.Name : displayName;
        Checked = selected;
        AutoSize = false;
        Width = 286;
        Height = 25;
        Text = _displayName;
        DisplayStyle = Forms.ToolStripItemDisplayStyle.None;
    }

    protected override void OnPaint(Forms.PaintEventArgs e)
    {
        var bounds = new System.Drawing.Rectangle(System.Drawing.Point.Empty, Size);
        var selected = Selected;
        var background = selected ? System.Drawing.SystemColors.Highlight : Owner?.BackColor ?? System.Drawing.SystemColors.Menu;
        var foreground = selected ? System.Drawing.SystemColors.HighlightText : System.Drawing.SystemColors.MenuText;
        using var backgroundBrush = new System.Drawing.SolidBrush(background);
        using var textBrush = new System.Drawing.SolidBrush(foreground);
        using var toneBrush = new System.Drawing.SolidBrush(System.Drawing.ColorTranslator.FromHtml(MarketToneRules.Hex(_snapshot.Tone(DateTimeOffset.UtcNow))));
        e.Graphics.FillRectangle(backgroundBrush, bounds);
        var font = Font ?? System.Drawing.SystemFonts.MenuFont;
        var check = Checked ? "✓" : "";
        var percent = _snapshot.Quote is null ? "--" : MarketRules.SignedPercent(_snapshot.Quote.Percent);
        e.Graphics.DrawString(check, font!, textBrush, bounds.Left + 4, bounds.Top + 4);
        e.Graphics.DrawString(_displayName, font!, textBrush, bounds.Left + 26, bounds.Top + 4);
        var width = e.Graphics.MeasureString(percent, font!).Width;
        e.Graphics.DrawString(percent, font!, toneBrush, bounds.Right - width - 8, bounds.Top + 4);
    }
}
