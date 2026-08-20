namespace NiuLaiMarketPets.Windows.Core;

public sealed class PersistedState
{
    public int SchemaVersion { get; set; } = 2;
    public string TargetId { get; set; } = MarketTarget.Default.Id;
    public ControlMode Mode { get; set; } = ControlMode.Auto;
    public PetId? ManualPetId { get; set; }
    public PetId ActivePetId { get; set; } = PetId.Niulai;
    public double? LastMarketPercent { get; set; }
    public DateTimeOffset? LastQuoteAt { get; set; }
    public bool ShowPet { get; set; } = true;
    public bool ShowMarketPill { get; set; } = true;
    public double PetScalePercent { get; set; } = 100;
    public double SpeechTextScalePercent { get; set; } = 100;
    public bool IndexPollingEnabled { get; set; }
    public List<string> WatchlistCodes { get; set; } = [];
    public bool WatchlistPollingEnabled { get; set; }
    public bool IsMuted { get; set; }
    public double? WindowX { get; set; }
    public double? WindowY { get; set; }
    public bool LaunchAtStartup { get; set; }

    public void Normalize()
    {
        SchemaVersion = Math.Max(1, SchemaVersion);
        TargetId = string.IsNullOrWhiteSpace(TargetId) ? MarketTarget.Default.Id : TargetId;
        LastMarketPercent = FiniteOrNull(LastMarketPercent);
        PetScalePercent = FiniteOrDefault(PetScalePercent, 100);
        SpeechTextScalePercent = FiniteOrDefault(SpeechTextScalePercent, 100);
        WatchlistCodes = (WatchlistCodes ?? [])
            .Select(code => code?.Trim() ?? string.Empty)
            .Where(code => code.Length == 6 && code.All(char.IsAsciiDigit))
            .Distinct(StringComparer.Ordinal)
            .Take(100)
            .ToList();
        if (WatchlistCodes.Count == 0) WatchlistPollingEnabled = false;
        WindowX = FiniteOrNull(WindowX);
        WindowY = FiniteOrNull(WindowY);
    }

    public PersistedState Clone() => new()
    {
        SchemaVersion = SchemaVersion,
        TargetId = TargetId,
        Mode = Mode,
        ManualPetId = ManualPetId,
        ActivePetId = ActivePetId,
        LastMarketPercent = LastMarketPercent,
        LastQuoteAt = LastQuoteAt,
        ShowPet = ShowPet,
        ShowMarketPill = ShowMarketPill,
        PetScalePercent = PetScalePercent,
        SpeechTextScalePercent = SpeechTextScalePercent,
        IndexPollingEnabled = IndexPollingEnabled,
        WatchlistCodes = [.. WatchlistCodes],
        WatchlistPollingEnabled = WatchlistPollingEnabled,
        IsMuted = IsMuted,
        WindowX = WindowX,
        WindowY = WindowY,
        LaunchAtStartup = LaunchAtStartup
    };

    private static double? FiniteOrNull(double? value) => value is { } number && double.IsFinite(number) ? number : null;

    private static double FiniteOrDefault(double value, double fallback) => double.IsFinite(value) ? value : fallback;
}
