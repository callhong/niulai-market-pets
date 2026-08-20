using System.Globalization;

namespace NiuLaiMarketPets.Windows.Core;

public enum PetId { Niulai, Baola, Muamua }
public enum ControlMode { Auto, Manual }
public enum MarketTone { Positive, Negative, Neutral, Unavailable }

public static class PetNames
{
    public static string DisplayName(this PetId pet) => pet switch
    {
        PetId.Baola => "豹拉",
        PetId.Muamua => "牛妈",
        _ => "牛来"
    };
}

public sealed record Quote(
    string Symbol,
    string Name,
    double LastPrice,
    double PreviousClose,
    DateTimeOffset QuoteTimestamp,
    string Provider,
    bool IsStale = false)
{
    public double Percent => PreviousClose > 0 && double.IsFinite(LastPrice) && double.IsFinite(PreviousClose)
        ? (LastPrice - PreviousClose) / PreviousClose * 100
        : double.NaN;

    public bool IsUsable => PreviousClose > 0
        && double.IsFinite(LastPrice)
        && double.IsFinite(PreviousClose)
        && double.IsFinite(Percent);
}

public sealed record MarketSnapshot(
    string TargetId,
    Quote? Quote = null,
    DateTimeOffset? FetchedAt = null,
    string? LastError = null)
{
    public bool IsStale(DateTimeOffset now, TimeSpan? maxAge = null)
    {
        if (Quote is null || Quote.IsStale || !double.IsFinite(Quote.Percent) || FetchedAt is null) return true;
        if (now - FetchedAt.Value > (maxAge ?? TimeSpan.FromSeconds(60))) return true;
        return now - Quote.QuoteTimestamp > TimeSpan.FromMinutes(5);
    }

    public MarketTone Tone(DateTimeOffset now) => MarketToneRules.Resolve(Quote?.Percent, IsStale(now));
}

public static class MarketToneRules
{
    public static MarketTone Resolve(double? percent, bool stale = false)
    {
        if (percent is null || !double.IsFinite(percent.Value) || stale) return MarketTone.Unavailable;
        if (percent > 0) return MarketTone.Positive;
        if (percent < 0) return MarketTone.Negative;
        return MarketTone.Neutral;
    }

    public static string Hex(MarketTone tone) => tone switch
    {
        MarketTone.Positive => "#E24B4B",
        MarketTone.Negative => "#2F9A62",
        _ => "#8A8F98"
    };
}

public static class MarketRules
{
    public static PetId? Bucket(double percent)
    {
        if (!double.IsFinite(percent)) return null;
        if (percent < 0) return PetId.Muamua;
        return percent <= 1 ? PetId.Niulai : PetId.Baola;
    }

    public static string SignedPercent(double? percent)
    {
        if (percent is null || !double.IsFinite(percent.Value)) return "--";
        var rounded = Math.Round(percent.Value * 100, MidpointRounding.AwayFromZero) / 100;
        return rounded == 0
            ? "+0.00%"
            : rounded.ToString("+0.00;-0.00", CultureInfo.InvariantCulture) + "%";
    }

    public static string Price(double? price) => price is null || !double.IsFinite(price.Value)
        ? "--"
        : price.Value.ToString("0.00", CultureInfo.InvariantCulture);
}

public enum MarketSession { PreOpen, Trading, Lunch, Closed, Stale, Offline }

public static class MarketSessions
{
    public static MarketSession For(DateTimeOffset date)
    {
        var local = TimeZoneInfo.ConvertTimeBySystemTimeZoneId(date, "China Standard Time");
        var minutes = local.Hour * 60 + local.Minute;
        return minutes switch
        {
            >= 555 and < 565 => MarketSession.PreOpen,
            >= 565 and < 690 or >= 780 and < 900 => MarketSession.Trading,
            >= 690 and < 780 => MarketSession.Lunch,
            _ => MarketSession.Closed
        };
    }
}
