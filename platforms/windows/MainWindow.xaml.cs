using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using WpfControls = System.Windows.Controls;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public partial class MainWindow : Window
{
    public MarketViewModel Model { get; }
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly ToastNotifier _notifier;
    private readonly PetSpriteAnimator _sprites = new();
    private readonly DispatcherTimer _animationTimer;
    private bool _allowClose;
    private bool _loaded;
    private bool _updateInProgress;
    private readonly UpdateService _updates = new();

    public MainWindow()
    {
        InitializeComponent();
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "BrandMark.ico");
        _trayIcon = new Forms.NotifyIcon { Icon = File.Exists(iconPath) ? new Icon(iconPath) : SystemIcons.Application, Visible = true, Text = "牛来行情宠物" };
        _notifier = new ToastNotifier(_trayIcon);
        Model = new MarketViewModel(_notifier);
        DataContext = Model;
        _trayIcon.ContextMenuStrip = new Forms.ContextMenuStrip();
        _trayIcon.ContextMenuStrip.Opening += (_, _) => TrayMenuBuilder.Populate(_trayIcon.ContextMenuStrip, Model, this);
        _animationTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
        _animationTimer.Tick += (_, _) => UpdateVisual();
        Model.PropertyChanged += ModelOnPropertyChanged;
        Loaded += OnLoaded;
        Closing += OnClosing;
        LocationChanged += (_, _) => { if (_loaded) Model.SaveWindowPosition(Left, Top); };
        ContextMenu = WpfMenuBuilder.Build(Model, this);
        PetImage.ContextMenu = ContextMenu;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (Model.WindowX is not null && Model.WindowY is not null)
        {
            Left = Model.WindowX.Value;
            Top = Model.WindowY.Value;
        }
        else
        {
            Left = SystemParameters.WorkArea.Right - Width - 24;
            Top = SystemParameters.WorkArea.Bottom - Height - 24;
        }
        _loaded = true;
        _animationTimer.Start();
        await Model.StartAsync();
        UpdateVisual();
    }

    private void ModelOnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MarketViewModel.ShowPet) or nameof(MarketViewModel.ShowMarketPill) or nameof(MarketViewModel.PetScalePercent))
        {
            PetImage.Visibility = Model.ShowPet ? Visibility.Visible : Visibility.Hidden;
            MarketPill.Visibility = Model.ShowMarketPill ? Visibility.Visible : Visibility.Hidden;
            var scale = Model.PetScalePercent / 100;
            PetImage.Width = 252 * scale;
            PetImage.Height = 273 * scale;
        }
        UpdateVisual();
    }

    private void UpdateVisual()
    {
        Model.RefreshSpeech();
        var now = DateTimeOffset.UtcNow;
        var seconds = (now - DateTimeOffset.UnixEpoch).TotalSeconds / 1.35;
        var row = 0;
        var frame = 0;
        switch (Model.ActivePet)
        {
            case PetId.Niulai:
                var phase = seconds % 3.1;
                if (phase < 1.15) { row = 1; frame = ((int)(phase / 1.15 * 8)) % 8; }
                else if (phase < 2.25) { row = 5; frame = ((int)((phase - 1.15) / 1.1 * 8)) % 8; }
                break;
            case PetId.Baola:
                row = 4; frame = Math.Min(4, (int)((seconds % 1.28) / 1.28 * 5)); break;
            case PetId.Muamua:
                row = 5; frame = ((int)((seconds % 1.85) / 1.85 * 8)) % 8; break;
        }
        try { PetImage.Source = _sprites.Frame(Model.ActivePet, row, frame); } catch { }
        UpdateMarketGlow();
        UpdateSpeechBubbles();
        PetImage.Visibility = Model.ShowPet ? Visibility.Visible : Visibility.Hidden;
        MarketPill.Visibility = Model.ShowMarketPill ? Visibility.Visible : Visibility.Hidden;
    }

    private void UpdateMarketGlow()
    {
        var color = Model.MarketBrush is SolidColorBrush brush ? brush.Color : Colors.Transparent;
        var tone = MarketToneRules.Resolve(Model.Quote?.Percent, Model.CurrentQuoteIsStale);
        var unavailable = tone == MarketTone.Unavailable;
        var pulse = 0.9 + 0.1 * (0.5 + 0.5 * Math.Sin(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000d * Math.PI * 2 / 2.8));
        var centerAlpha = (byte)Math.Clamp((unavailable ? 30 : 112) * pulse, 0, 255);
        var middleAlpha = (byte)Math.Clamp(centerAlpha * 0.64, 0, 255);

        // Match the README reference: a soft color wash behind the head,
        // never a visible circle crossing the pet. A radial brush keeps the
        // effect reliable on transparent WPF windows; the small blur only
        // smooths the gradient and cannot create a hard outline.
        var glow = new RadialGradientBrush
        {
            Center = new System.Windows.Point(0.5, 0.45),
            GradientOrigin = new System.Windows.Point(0.5, 0.45),
            RadiusX = 0.5,
            RadiusY = 0.5
        };
        glow.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(centerAlpha, color.R, color.G, color.B), 0));
        glow.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(middleAlpha, color.R, color.G, color.B), 0.42));
        glow.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb((byte)Math.Clamp(centerAlpha * 0.2, 0, 255), color.R, color.G, color.B), 0.76));
        glow.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(0, color.R, color.G, color.B), 1));
        MarketGlow.Fill = glow;
        MarketGlow.Stroke = System.Windows.Media.Brushes.Transparent;
        MarketGlow.StrokeThickness = 0;
        MarketGlow.Effect = new System.Windows.Media.Effects.BlurEffect
        {
            Radius = unavailable ? 3 : 5,
            RenderingBias = System.Windows.Media.Effects.RenderingBias.Quality
        };
        PetImage.Effect = null;
    }

    private void UpdateSpeechBubbles()
    {
        SpeechLayer.Children.Clear();
        var now = DateTimeOffset.UtcNow;
        foreach (var bubble in Model.SpeechBubbles)
        {
            var progress = bubble.ProgressAt(now);
            var fadeIn = Math.Clamp(progress / 0.12, 0, 1);
            var fadeOut = progress <= 0.68 ? 1 : Math.Clamp((1 - progress) / 0.32, 0, 1);
            var drift = progress;
            var scale = 1 + (bubble.IsBurst ? Math.Sin(progress * Math.PI) * 0.08 : 0);

            var text = new WpfControls.TextBlock
            {
                Text = bubble.Text,
                MaxWidth = 318,
                FontFamily = new System.Windows.Media.FontFamily(bubble.FontName),
                FontSize = bubble.FontSize,
                FontWeight = bubble.IsBurst ? FontWeights.SemiBold : FontWeights.Medium,
                Foreground = new SolidColorBrush(System.Windows.Media.Color.FromArgb(255, 108, 69, 20)),
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
                TextTrimming = TextTrimming.None
            };
            var border = new WpfControls.Border
            {
                Child = text,
                Padding = bubble.IsBurst ? new Thickness(10, 5, 10, 5) : new Thickness(8, 4, 8, 4),
                MaxWidth = 334,
                CornerRadius = new CornerRadius(bubble.IsBurst ? 16 : 13),
                Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(bubble.IsBurst ? (byte)236 : (byte)226, 255, 247, 232)),
                BorderBrush = new SolidColorBrush(System.Windows.Media.Color.FromArgb(bubble.IsBurst ? (byte)190 : (byte)116, 214, 166, 72)),
                BorderThickness = new Thickness(1),
                Opacity = fadeIn * fadeOut
            };
            border.Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                Color = System.Windows.Media.Colors.Black,
                BlurRadius = bubble.IsBurst ? 8 : 5,
                ShadowDepth = 1,
                Direction = 270,
                Opacity = bubble.IsBurst ? 0.18 : 0.1
            };
            border.RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
            var transforms = new TransformGroup();
            transforms.Children.Add(new ScaleTransform(scale, scale));
            transforms.Children.Add(new RotateTransform(bubble.RotationDegrees * (1 - progress * 0.35)));
            border.RenderTransform = transforms;

            border.Measure(new System.Windows.Size(334, 200));
            border.Arrange(new System.Windows.Rect(new System.Windows.Point(0, 0), border.DesiredSize));
            var left = ActualWidth / 2 + bubble.OriginX + bubble.DriftX * drift - border.DesiredSize.Width / 2;
            var top = ActualHeight / 2 + bubble.OriginY + bubble.DriftY * drift - border.DesiredSize.Height / 2;
            // Keep long Chinese lines fully inside the transparent window;
            // they may move to the nearest edge, but are never clipped.
            var maxLeft = Math.Max(6, ActualWidth - border.DesiredSize.Width - 6);
            var maxTop = Math.Max(6, ActualHeight - border.DesiredSize.Height - 6);
            left = Math.Clamp(left, 6, maxLeft);
            top = Math.Clamp(top, 6, maxTop);
            WpfControls.Canvas.SetLeft(border, left);
            WpfControls.Canvas.SetTop(border, top);
            SpeechLayer.Children.Add(border);
        }
    }

    private void PetImage_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            Model.ClickPet();
            try { DragMove(); } catch (InvalidOperationException) { }
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_allowClose) return;
        e.Cancel = true;
        Hide();
    }

    public void ToggleVisibility()
    {
        if (IsVisible) Hide(); else Show();
        Model.TogglePetVisibility();
    }

    public async Task SelectTonghuashunCodeAsync()
    {
        var code = PromptStockCode();
        if (code is null) return;
        if (!MarketTarget.TryCreateTonghuashun(code, out _))
        {
            System.Windows.MessageBox.Show(this, "请输入 6 位数字的股票或 ETF 代码。", "代码格式不正确", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        try
        {
            await Model.AddCustomCodeAsync(code);
        }
        catch (ArgumentException error)
        {
            System.Windows.MessageBox.Show(this, error.Message, "代码格式不正确", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch
        {
            System.Windows.MessageBox.Show(this, "读取该代码失败，已保留当前行情。请稍后重试。", "行情暂不可用", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    public async Task ManageWatchlistAsync()
    {
        var dialog = new Window
        {
            Title = "管理自选池",
            Width = 390,
            Height = 330,
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.ToolWindow,
            ShowInTaskbar = false,
            Topmost = true,
            WindowStartupLocation = IsVisible ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
            Owner = IsVisible ? this : null
        };
        var list = new WpfControls.ListBox { Margin = new Thickness(0, 8, 0, 12), MinHeight = 150 };
        var remove = new WpfControls.Button { Content = "移除选中代码", Width = 110, IsEnabled = false, Margin = new Thickness(0, 0, 8, 0) };
        var close = new WpfControls.Button { Content = "关闭", Width = 76, IsCancel = true };
        var buttons = new WpfControls.StackPanel { Orientation = WpfControls.Orientation.Horizontal, HorizontalAlignment = System.Windows.HorizontalAlignment.Right };
        buttons.Children.Add(remove);
        buttons.Children.Add(close);
        var panel = new WpfControls.StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new WpfControls.TextBlock { Text = "自选池（股票和 ETF）", FontSize = 15, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new WpfControls.TextBlock { Text = "添加后会保存到本机，可单独选择或轮询整个自选池。", Foreground = System.Windows.Media.Brushes.DimGray, Margin = new Thickness(0, 4, 0, 0) });
        panel.Children.Add(list);
        panel.Children.Add(buttons);
        dialog.Content = panel;

        void RefreshList()
        {
            list.Items.Clear();
            foreach (var target in Model.CustomTargets)
                list.Items.Add(new WatchlistEntry(Model.DisplayName(target), target.Symbol));
            remove.IsEnabled = list.SelectedItem is WatchlistEntry;
        }

        list.SelectionChanged += (_, _) => remove.IsEnabled = list.SelectedItem is WatchlistEntry;
        remove.Click += async (_, _) =>
        {
            if (list.SelectedItem is not WatchlistEntry entry) return;
            remove.IsEnabled = false;
            await Model.RemoveCustomCodeAsync(entry.Code);
            RefreshList();
        };
        dialog.Loaded += (_, _) => RefreshList();
        dialog.ShowDialog();
        await Task.CompletedTask;
    }

    public async Task CheckForUpdatesAsync()
    {
        if (_updateInProgress) return;
        _updateInProgress = true;
        try
        {
            var result = await _updates.CheckAsync();
            if (!result.Success)
            {
                System.Windows.MessageBox.Show(this, result.Message, "检查更新", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (!result.IsNewer)
            {
                System.Windows.MessageBox.Show(this, $"当前已是最新版本（{result.CurrentVersion}）。", "检查更新", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            if (result.Release is null)
            {
                System.Windows.MessageBox.Show(this, $"发现新版本 {result.LatestVersion}，但该版本暂未提供 Windows 安装包。", "检查更新", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var answer = System.Windows.MessageBox.Show(
                this,
                $"发现 Windows 新版本 {result.LatestVersion}。\n\n点击“是”下载并启动安装器，应用会在安装前自动退出。",
                "发现新版本",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);
            if (answer != MessageBoxResult.Yes) return;

            var installerPath = await _updates.DownloadAndVerifyAsync(result.Release);
            UpdateService.LaunchInstaller(installerPath);
            ExitApplication();
        }
        catch (OperationCanceledException)
        {
            System.Windows.MessageBox.Show(this, "检查更新已取消。", "检查更新", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception)
        {
            System.Windows.MessageBox.Show(this, "更新下载或校验失败，请稍后重试，或从发布页手动下载安装包。", "检查更新失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            _updateInProgress = false;
        }
    }

    private string? PromptStockCode()
    {
        var dialog = new Window
        {
            Title = "输入股票代码",
            Width = 360,
            Height = 190,
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.ToolWindow,
            ShowInTaskbar = false,
            Topmost = true,
            WindowStartupLocation = IsVisible ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
            Owner = IsVisible ? this : null
        };
        var codeBox = new WpfControls.TextBox { Text = string.Empty, MaxLength = 6, FontSize = 16, Margin = new Thickness(0, 8, 0, 12) };
        var hint = new WpfControls.TextBlock { Text = "支持股票和 ETF，例如 688365、510300；输入后会保存到自选池。", Foreground = System.Windows.Media.Brushes.DimGray, TextWrapping = TextWrapping.Wrap };
        var ok = new WpfControls.Button { Content = "确定", Width = 76, IsDefault = true, Margin = new Thickness(0, 0, 8, 0) };
        var cancel = new WpfControls.Button { Content = "取消", Width = 76, IsCancel = true };
        var buttons = new WpfControls.StackPanel { Orientation = WpfControls.Orientation.Horizontal, HorizontalAlignment = System.Windows.HorizontalAlignment.Right };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        var panel = new WpfControls.StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new WpfControls.TextBlock { Text = "股票或 ETF 代码", FontSize = 14, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(hint);
        panel.Children.Add(codeBox);
        panel.Children.Add(buttons);
        dialog.Content = panel;
        ok.Click += (_, _) => dialog.DialogResult = true;
        dialog.Loaded += (_, _) => { codeBox.Focus(); codeBox.SelectAll(); };
        return dialog.ShowDialog() == true ? codeBox.Text.Trim() : null;
    }

    private sealed record WatchlistEntry(string Name, string Code)
    {
        public override string ToString() => $"{Name}（{Code}）";
    }

    public void ExitApplication()
    {
        _allowClose = true;
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        System.Windows.Application.Current.Shutdown();
    }
}
