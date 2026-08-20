namespace NiuLaiMarketPets.Windows.Core;

public sealed class MarketStateEngine
{
    public PetId ActivePet { get; private set; }
    public PetId? CandidatePet { get; private set; }
    public DateTimeOffset? CandidateSince { get; private set; }
    public DateTimeOffset? CooldownUntil { get; private set; }
    public bool HasValidSample { get; private set; }
    public TimeSpan DebounceInterval { get; }
    public TimeSpan CooldownInterval { get; }

    public MarketStateEngine(PetId activePet = PetId.Niulai, bool hasHistory = false, TimeSpan? debounce = null, TimeSpan? cooldown = null)
    {
        ActivePet = activePet;
        HasValidSample = hasHistory;
        DebounceInterval = debounce ?? TimeSpan.FromSeconds(20);
        CooldownInterval = cooldown ?? TimeSpan.FromSeconds(120);
    }

    public void ResetForManual(PetId pet)
    {
        ActivePet = pet;
        CandidatePet = null;
        CandidateSince = null;
        CooldownUntil = null;
        HasValidSample = true;
    }

    public void ClearPendingCandidate() { CandidatePet = null; CandidateSince = null; }

    public PetId? Accept(double percent, DateTimeOffset at, bool tradingAllowed, bool isStale)
    {
        if (!tradingAllowed || isStale || !double.IsFinite(percent)) { ClearPendingCandidate(); return null; }
        var proposed = MarketRules.Bucket(percent);
        if (proposed is null) { ClearPendingCandidate(); return null; }
        if (!HasValidSample)
        {
            HasValidSample = true;
            ActivePet = proposed.Value;
            ClearPendingCandidate();
            CooldownUntil = at + CooldownInterval;
            return proposed;
        }
        if (proposed == ActivePet) { ClearPendingCandidate(); return null; }
        if (CooldownUntil is not null && at < CooldownUntil) { ClearPendingCandidate(); return null; }
        if (CandidatePet != proposed) { CandidatePet = proposed; CandidateSince = at; return null; }
        if (CandidateSince is null || at - CandidateSince.Value < DebounceInterval) return null;
        ActivePet = proposed.Value;
        ClearPendingCandidate();
        CooldownUntil = at + CooldownInterval;
        return proposed;
    }
}
