namespace NiuLaiMarketPets.Windows.Core;

public sealed class NotificationPolicy
{
    private string? _lastTransition;

    public void Reset() => _lastTransition = null;

    public bool ShouldNotify(double? previousPercent, double currentPercent, PetId switchedTo, ControlMode mode, bool initialSample, bool targetRotation, bool stale)
    {
        if (mode != ControlMode.Auto || initialSample || targetRotation || stale || !double.IsFinite(currentPercent) || previousPercent is null || !double.IsFinite(previousPercent.Value)) return false;
        var previous = MarketRules.Bucket(previousPercent.Value);
        var current = MarketRules.Bucket(currentPercent);
        if (previous is null || current is null || previous == current || current != switchedTo) return false;
        var transition = $"{previous}->{current}";
        if (transition == _lastTransition) return false;
        _lastTransition = transition;
        return true;
    }

    public static string Title(PetId pet) => pet switch
    {
        PetId.Muamua => "妈妈——",
        PetId.Baola => "豹拉！",
        _ => "牛来了"
    };

    public static string Body(PetId pet, MarketTarget target, Quote? quote) =>
        $"{pet.DisplayName()} · {target.Name} · {MarketRules.Price(quote?.LastPrice)} · {MarketRules.SignedPercent(quote?.Percent)}";
}
