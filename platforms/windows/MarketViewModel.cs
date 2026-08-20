using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using System.Windows.Threading;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public sealed class MarketViewModel : INotifyPropertyChanged
{
    private readonly ConfigStore _store = new();
    private readonly QuoteService _quotes = new();
    private readonly AudioPlayer _audio = new();
    private readonly ToastNotifier _notifier;
    private readonly DispatcherTimer _refreshTimer;
    private readonly DispatcherTimer _pollingTimer;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private PersistedState _state;
    private MarketStateEngine _engine;
    private NotificationPolicy _notificationPolicy = new();
    private Quote? _quote;
    private MarketTarget _target;
    private PetId _activePet;
    private string? _error;
    private DateTimeOffset? _speechBurstStartedAt;
    private string? _lastSpeechText;
    private bool _firstValidQuote = true;
    private bool _suppressEffectsForTargetChange;

    public event PropertyChangedEventHandler? PropertyChanged;
    public IReadOnlyDictionary<string, MarketSnapshot> Snapshots { get; private set; } = new Dictionary<string, MarketSnapshot>();
    public MarketTarget Target => _target;
    public string TargetDisplayName => DisplayName(_target);
    public IReadOnlyList<MarketTarget> CustomTargets => _state.WatchlistCodes
        .Select(code => MarketTarget.TryCreateTonghuashun(code, out var target) ? target : null)
        .Where(target => target is not null)
        .Select(target => target!)
        .ToArray();
    public Quote? Quote => _quote;
    public PetId ActivePet => _activePet;
    public ControlMode Mode => _state.Mode;
    public bool ShowPet => _state.ShowPet;
    public bool ShowMarketPill => _state.ShowMarketPill;
    public bool IsMuted => _state.IsMuted;
    public bool IndexPollingEnabled => _state.IndexPollingEnabled;
    public bool WatchlistPollingEnabled => _state.WatchlistPollingEnabled;
    public bool LaunchAtStartup => _state.LaunchAtStartup;
    public double? WindowX => _state.WindowX;
    public double? WindowY => _state.WindowY;
    public double PetScalePercent => _state.PetScalePercent;
    public double SpeechTextScalePercent => _state.SpeechTextScalePercent;
    public string SpeechText => SpeechRules.Current(_activePet, DateTimeOffset.UtcNow, _speechBurstStartedAt);
    public double SpeechFontSize => SpeechRules.FontSize(_state.SpeechTextScalePercent);
    public IReadOnlyList<SpeechBubble> SpeechBubbles => SpeechRules.Bubbles(
        _activePet,
        DateTimeOffset.UtcNow,
        _speechBurstStartedAt,
        _state.SpeechTextScalePercent);
    public string Error => _error ?? string.Empty;
    public string QuotePrice => MarketRules.Price(_quote?.LastPrice);
    public string QuotePercent => MarketRules.SignedPercent(_quote?.Percent);
    public string SessionText => CurrentQuoteIsStale ? "数据陈旧" : MarketSessions.For(DateTimeOffset.Now) switch
    {
        MarketSession.Trading => "交易中",
        MarketSession.PreOpen => "集合竞价",
        MarketSession.Lunch => "午休",
        _ => "已收盘"
    };
    public bool CurrentQuoteIsStale => Snapshots.TryGetValue(_target.Id, out var snapshot) ? snapshot.IsStale(DateTimeOffset.UtcNow) : true;
    public System.Windows.Media.Brush MarketBrush => new System.Windows.Media.SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(MarketToneRules.Hex(MarketToneRules.Resolve(_quote?.Percent, CurrentQuoteIsStale)))!);

    public MarketViewModel(ToastNotifier notifier)
    {
        _notifier = notifier;
        _state = _store.Load();
        _state.LaunchAtStartup = StartupManager.IsEnabled();
        _target = MarketTarget.FromId(_state.TargetId);
        if (_target.IsCustomCode && !_state.WatchlistCodes.Contains(_target.Symbol, StringComparer.Ordinal))
        {
            _state.WatchlistCodes.Add(_target.Symbol);
            _state.Normalize();
            _store.Save(_state);
        }
        _activePet = _state.ActivePetId;
        if (_state.Mode == ControlMode.Auto && _state.LastMarketPercent is { } lastPercent && MarketRules.Bucket(lastPercent) is { } persistedPet)
            _activePet = persistedPet;
        _engine = new MarketStateEngine(_activePet, _state.LastMarketPercent is not null);
        if (_state.Mode == ControlMode.Manual && _state.ManualPetId is not null)
        {
            _activePet = _state.ManualPetId.Value;
            _engine.ResetForManual(_activePet);
        }
        // Quote refresh is separate from target rotation: values refresh every
        // 10 seconds while the selected index/watchlist target rotates every 60.
        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(10) };
        _refreshTimer.Tick += async (_, _) => await RefreshAsync();
        _pollingTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _pollingTimer.Tick += async (_, _) =>
        {
            if (IndexPollingEnabled) await AdvanceIndexPollingAsync();
            else if (WatchlistPollingEnabled) await AdvanceWatchlistPollingAsync();
        };
    }

    public async Task StartAsync()
    {
        _refreshTimer.Start();
        _pollingTimer.Start();
        await RefreshAsync();
        RefreshSpeech();
        NotifyChanged();
    }

    public async Task RefreshAsync()
    {
        await _refreshGate.WaitAsync();
        try
        {
            var requested = _target;
            var result = await _quotes.FetchAsync(requested);
            if (requested.Id != _target.Id) return;
            ApplyFetch(requested, result, DateTimeOffset.UtcNow, _suppressEffectsForTargetChange);
            _suppressEffectsForTargetChange = false;
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    public async Task RefreshSnapshotsForMenuAsync()
    {
        var now = DateTimeOffset.UtcNow;
        var menuTargets = MarketTarget.All.Concat(CustomTargets).Append(_target).DistinctBy(item => item.Id);
        var targets = menuTargets.Where(item => !Snapshots.TryGetValue(item.Id, out var snapshot) || snapshot.IsStale(now)).ToArray();
        var results = await Task.WhenAll(targets.Select(async target => (target, result: await _quotes.FetchAsync(target))));
        foreach (var (target, result) in results) ApplyFetch(target, result, DateTimeOffset.UtcNow, target.Id != _target.Id || _suppressEffectsForTargetChange);
        _suppressEffectsForTargetChange = false;
    }

    public async Task SelectTargetAsync(MarketTarget target, bool rotation = false)
    {
        if (!rotation)
        {
            _state.IndexPollingEnabled = false;
            _state.WatchlistPollingEnabled = false;
        }
        EnsureInWatchlist(target);
        if (target.Id == _target.Id)
        {
            Save();
            await RefreshAsync();
            NotifyChanged();
            return;
        }
        _target = target;
        _state.TargetId = target.Id;
        _quote = null;
        _error = null;
        _firstValidQuote = true;
        _suppressEffectsForTargetChange = true;
        _notificationPolicy.Reset();
        _engine = new MarketStateEngine(_activePet);
        Save();
        await RefreshAsync();
        NotifyChanged();
    }

    public async Task AdvancePollingAsync() => await AdvanceIndexPollingAsync();

    public async Task AdvanceIndexPollingAsync() => await SelectTargetAsync(MarketTarget.NextPollingTarget(_target.Id), true);

    public async Task AdvanceWatchlistPollingAsync()
    {
        var targets = CustomTargets;
        if (targets.Count == 0)
        {
            _state.WatchlistPollingEnabled = false;
            Save();
            NotifyChanged();
            return;
        }

        var currentIndex = targets.ToList().FindIndex(target => target.Id == _target.Id);
        var next = currentIndex < 0 ? targets[0] : targets[(currentIndex + 1) % targets.Count];
        await SelectTargetAsync(next, true);
    }

    public void TogglePolling()
    {
        _state.IndexPollingEnabled = !_state.IndexPollingEnabled;
        if (_state.IndexPollingEnabled) _state.WatchlistPollingEnabled = false;
        Save();
        NotifyChanged();
    }

    public void ToggleWatchlistPolling()
    {
        if (CustomTargets.Count == 0)
        {
            _state.WatchlistPollingEnabled = false;
        }
        else
        {
            _state.WatchlistPollingEnabled = !_state.WatchlistPollingEnabled;
            if (_state.WatchlistPollingEnabled) _state.IndexPollingEnabled = false;
        }
        Save();
        NotifyChanged();
    }

    public async Task AddCustomCodeAsync(string code)
    {
        if (!MarketTarget.TryCreateTonghuashun(code, out var target)) throw new ArgumentException("请输入 6 位数字代码。", nameof(code));
        EnsureInWatchlist(target);
        _state.IndexPollingEnabled = false;
        _state.WatchlistPollingEnabled = false;
        await SelectTargetAsync(target);
    }

    public async Task RemoveCustomCodeAsync(string code)
    {
        if (!MarketTarget.TryCreateTonghuashun(code, out var target)) return;
        _state.WatchlistCodes.RemoveAll(item => string.Equals(item, target.Symbol, StringComparison.Ordinal));
        if (_state.WatchlistCodes.Count == 0) _state.WatchlistPollingEnabled = false;
        if (_target.Id == target.Id) await SelectTargetAsync(MarketTarget.Default);
        else
        {
            Save();
            NotifyChanged();
        }
    }
    public void SelectPet(PetId pet) { _state.Mode = ControlMode.Manual; _state.ManualPetId = pet; _activePet = pet; _engine.ResetForManual(pet); _notificationPolicy.Reset(); StartSpeechBurst(); _audio.Play(pet, IsMuted); Save(); NotifyChanged(); }
    public void SelectAuto()
    {
        _state.Mode = ControlMode.Auto;
        if (_quote is not null && !CurrentQuoteIsStale && MarketRules.Bucket(_quote.Percent) is { } next && next != _activePet)
        {
            _activePet = next;
            StartSpeechBurst();
            _audio.Play(next, IsMuted);
        }
        _engine = new MarketStateEngine(_activePet, hasHistory: _quote is not null && !CurrentQuoteIsStale);
        Save(); NotifyChanged();
    }
    public void TogglePetVisibility() { _state.ShowPet = !_state.ShowPet; Save(); NotifyChanged(); }
    public void TogglePill() { _state.ShowMarketPill = !_state.ShowMarketPill; Save(); NotifyChanged(); }
    public void ToggleMute() { _state.IsMuted = !_state.IsMuted; Save(); NotifyChanged(); }
    public void SetPetScale(double value) { _state.PetScalePercent = Math.Clamp(value, 60, 160); Save(); NotifyChanged(); }
    public void SetSpeechScale(double value) { _state.SpeechTextScalePercent = Math.Clamp(value, 80, 140); Save(); NotifyChanged(); }
    public void SetStartup(bool enabled) { StartupManager.SetEnabled(enabled); _state.LaunchAtStartup = enabled; Save(); NotifyChanged(); }
    public void SaveWindowPosition(double x, double y) { _state.WindowX = x; _state.WindowY = y; Save(); }
    public void ClickPet() { StartSpeechBurst(); _audio.Play(_activePet, IsMuted); NotifyChanged(); }
    public void RefreshSpeech()
    {
        var text = SpeechText;
        if (text == _lastSpeechText) return;
        _lastSpeechText = text;
        OnPropertyChanged(nameof(SpeechText));
    }

    public MarketSnapshot Snapshot(MarketTarget target) => Snapshots.TryGetValue(target.Id, out var snapshot) ? snapshot : new MarketSnapshot(target.Id);

    private void ApplyFetch(MarketTarget target, QuoteFetchResult result, DateTimeOffset at, bool targetRotation)
    {
        var oldQuote = _quote;
        var current = Snapshot(target);
        if (result.Quote is { } quote && quote.Symbol == target.Symbol && quote.IsUsable)
        {
            current = current with { Quote = quote, FetchedAt = at, LastError = null };
            _error = current.LastError;
            Snapshots = new Dictionary<string, MarketSnapshot>(Snapshots) { [target.Id] = current };
            if (target.Id == _target.Id)
            {
                _quote = quote;
                if (_state.Mode == ControlMode.Auto && !current.IsStale(at))
                {
                    // Shape follows the latest valid quote even outside market
                    // hours. Only notifications retain the trading-session gate.
                    var canNotify = MarketSessions.For(DateTimeOffset.Now) == MarketSession.Trading;
                    if (_engine.Accept(quote.Percent, at, true, false) is { } next)
                    {
                        var changed = next != _activePet;
                        _activePet = next;
                        if (changed && !targetRotation) { StartSpeechBurst(); _audio.Play(next, IsMuted); }
                        if (changed && canNotify && _notificationPolicy.ShouldNotify(oldQuote?.Percent, quote.Percent, next, _state.Mode, _firstValidQuote, targetRotation, false))
                            _notifier.Show(NotificationPolicy.Title(next), NotificationPolicy.Body(next, target with { Name = quote.Name }, quote));
                    }
                }
                _firstValidQuote = false;
            }
        }
        else
        {
            var staleQuote = current.Quote is { } previous ? previous with { IsStale = true } : null;
            current = current with
            {
                Quote = staleQuote,
                LastError = result.Errors.Count == 0 ? "行情数据与当前指数不匹配" : string.Join(" | ", result.Errors)
            };
            Snapshots = new Dictionary<string, MarketSnapshot>(Snapshots) { [target.Id] = current };
            if (target.Id == _target.Id) _error = current.LastError;
        }
        Save();
        NotifyChanged();
    }

    private void Save()
    {
        _state.TargetId = _target.Id;
        _state.ActivePetId = _activePet;
        _state.LastMarketPercent = _quote?.Percent;
        _state.LastQuoteAt = _quote?.QuoteTimestamp;
        _store.Save(_state);
    }

    private void StartSpeechBurst() => _speechBurstStartedAt = DateTimeOffset.UtcNow;

    public string DisplayName(MarketTarget target)
    {
        if (Snapshots.TryGetValue(target.Id, out var snapshot) && snapshot.Quote?.Name is { Length: > 0 } snapshotName)
            return snapshotName;
        if (target.Id == _target.Id && _quote?.Name is { Length: > 0 } currentName) return currentName;
        return target.Name;
    }

    private void EnsureInWatchlist(MarketTarget target)
    {
        if (!target.IsCustomCode) return;
        if (_state.WatchlistCodes.Contains(target.Symbol, StringComparer.Ordinal)) return;
        _state.WatchlistCodes.Add(target.Symbol);
        _state.Normalize();
    }

    private void NotifyChanged([CallerMemberName] string? propertyName = null)
    {
        OnPropertyChanged(propertyName);
        foreach (var property in new[] { nameof(Target), nameof(TargetDisplayName), nameof(CustomTargets), nameof(Quote), nameof(ActivePet), nameof(Mode), nameof(ShowPet), nameof(ShowMarketPill), nameof(IsMuted), nameof(IndexPollingEnabled), nameof(WatchlistPollingEnabled), nameof(LaunchAtStartup), nameof(WindowX), nameof(WindowY), nameof(PetScalePercent), nameof(SpeechTextScalePercent), nameof(SpeechFontSize), nameof(SpeechText), nameof(SpeechBubbles), nameof(Error), nameof(QuotePrice), nameof(QuotePercent), nameof(SessionText), nameof(CurrentQuoteIsStale), nameof(MarketBrush), nameof(Snapshots) }) OnPropertyChanged(property);
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
