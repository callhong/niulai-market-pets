using System.Text.Json;
using System.Text;
using NiuLaiMarketPets.Windows.Core;
using Xunit;

namespace NiuLaiMarketPets.Windows.Tests;

public sealed class MarketModelTests
{
    [Fact]
    public void DefinesSixStableMarketTargetsAndCyclesPollingAcrossAllOfThem()
    {
        Assert.Equal(6, MarketTarget.All.Count);
        Assert.Equal(6, MarketTarget.All.Select(target => target.Id).Distinct().Count());
        Assert.Equal(MarketTarget.Sse, MarketTarget.FromId(MarketTarget.Sse.Id));

        var current = MarketTarget.All[0];
        for (var i = 0; i < MarketTarget.All.Count; i++) current = MarketTarget.NextPollingTarget(current.Id);
        Assert.Equal(MarketTarget.All[0], current);
    }

    [Fact]
    public void SupportsTheTonghuashunMicroCapCodeWithoutChangingTheSixIndexPollingSet()
    {
        Assert.Equal("883418", MarketTarget.MicroCap.Symbol);
        Assert.Equal("微盘股（883418）", MarketTarget.MicroCap.Name);
        Assert.Equal(MarketTarget.MicroCap, MarketTarget.FromId(MarketTarget.MicroCap.Id));
        Assert.True(MarketTarget.TryCreateTonghuashun(" 883418 ", out var custom));
        Assert.Equal(MarketTarget.MicroCap, custom);
        Assert.False(MarketTarget.TryCreateTonghuashun("88341", out _));
        Assert.Equal(6, MarketTarget.All.Count);
    }

    [Fact]
    public void RoutesIndividualStockCodesToQuoteProvidersInsteadOfTheTonghuashunIndustryPage()
    {
        Assert.True(MarketTarget.TryCreateTonghuashun(" 688365 ", out var stock));
        Assert.Equal("ths-code-688365", stock.Id);
        Assert.Equal("1.688365", stock.EastmoneySecId);
        Assert.Equal("sh688365", stock.TencentSymbol);
        Assert.Equal(SourceKind.StandardIndex, stock.SourceKind);
        Assert.Equal(SourceKind.TonghuashunPublic, MarketTarget.MicroCap.SourceKind);
        Assert.Null(MarketTarget.MicroCap.EastmoneySecId);
    }

    [Fact]
    public void RoutesShanghaiEtfCodesToShanghaiQuoteEndpoints()
    {
        Assert.True(MarketTarget.TryCreateTonghuashun("510300", out var etf));
        Assert.Equal("1.510300", etf.EastmoneySecId);
        Assert.Equal("sh510300", etf.TencentSymbol);
        Assert.True(etf.IsCustomCode);
    }

    [Fact]
    public void ThresholdsAndRawTonesMatchSharedFixture()
    {
        using var document = JsonDocument.Parse(File.ReadAllText("market-model-cases.json"));
        foreach (var item in document.RootElement.GetProperty("thresholds").EnumerateArray())
        {
            var percent = item.GetProperty("percent").GetDouble();
            var expectedPet = item.GetProperty("pet").GetString();
            var expectedTone = item.GetProperty("tone").GetString();
            var actualPet = MarketRules.Bucket(percent)?.ToString().ToLowerInvariant();
            var actualTone = MarketToneRules.Resolve(percent).ToString().ToLowerInvariant();
            Assert.Equal(expectedPet, actualPet);
            Assert.Equal(expectedTone, actualTone);
            var formatted = MarketRules.SignedPercent(percent);
            Assert.Equal(item.GetProperty("formatted").GetString(), formatted);
            Assert.DoesNotContain("-0.00%", formatted);
        }
    }

    [Fact]
    public void PositiveNegativeZeroAndUnavailableTonesUseExpectedColors()
    {
        Assert.Equal(MarketTone.Positive, MarketToneRules.Resolve(0.01));
        Assert.Equal(MarketTone.Negative, MarketToneRules.Resolve(-0.01));
        Assert.Equal(MarketTone.Neutral, MarketToneRules.Resolve(0));
        Assert.Equal(MarketTone.Unavailable, MarketToneRules.Resolve(double.NaN));
        Assert.Equal(MarketTone.Unavailable, MarketToneRules.Resolve(0.5, stale: true));
    }

    [Fact]
    public void InvalidQuoteAndPersistedNumbersDegradeWithoutJsonCrash()
    {
        var invalidQuote = new Quote("883418", "同花顺（883418）", 0, 0, DateTimeOffset.UtcNow, "fixture");
        Assert.False(invalidQuote.IsUsable);
        Assert.Equal(double.NaN, invalidQuote.Percent);

        var state = new PersistedState
        {
            LastMarketPercent = double.NaN,
            PetScalePercent = double.PositiveInfinity,
            SpeechTextScalePercent = double.NegativeInfinity,
            WindowX = double.PositiveInfinity,
            WindowY = double.NaN
        };
        state.Normalize();

        Assert.Null(state.LastMarketPercent);
        Assert.Equal(100, state.PetScalePercent);
        Assert.Equal(100, state.SpeechTextScalePercent);
        Assert.Null(state.WindowX);
        Assert.Null(state.WindowY);
        var json = JsonSerializer.Serialize(state);
        Assert.DoesNotContain("NaN", json, StringComparison.Ordinal);
        Assert.DoesNotContain("Infinity", json, StringComparison.Ordinal);
    }

    [Fact]
    public void NotificationBoundariesAndDeduplicationMatchMacRules()
    {
        using var document = JsonDocument.Parse(File.ReadAllText("market-model-cases.json"));
        var policy = new NotificationPolicy();
        foreach (var item in document.RootElement.GetProperty("notificationTransitions").EnumerateArray())
        {
            var previous = item.GetProperty("previous").GetDouble();
            var current = item.GetProperty("current").GetDouble();
            var pet = MarketRules.Bucket(current)!.Value;
            Assert.Equal(item.GetProperty("notify").GetBoolean(), policy.ShouldNotify(previous, current, pet, ControlMode.Auto, false, false, false));
        }

        var duplicate = new NotificationPolicy();
        Assert.True(duplicate.ShouldNotify(-0.1, 0.1, PetId.Niulai, ControlMode.Auto, false, false, false));
        Assert.False(duplicate.ShouldNotify(-0.2, 0.2, PetId.Niulai, ControlMode.Auto, false, false, false));
    }

    [Fact]
    public void EngineUsesTwentySecondDebounceAndOneTwentySecondCooldown()
    {
        var engine = new MarketStateEngine(hasHistory: true);
        var start = DateTimeOffset.UnixEpoch.AddSeconds(1000);
        Assert.Null(engine.Accept(1.01, start, true, false));
        Assert.Null(engine.Accept(1.01, start.AddSeconds(19), true, false));
        Assert.Equal(PetId.Baola, engine.Accept(1.01, start.AddSeconds(20), true, false));
        Assert.Null(engine.Accept(-0.1, start.AddSeconds(21), true, false));
        Assert.Null(engine.Accept(-0.1, start.AddSeconds(141), true, false));
        Assert.Equal(PetId.Muamua, engine.Accept(-0.1, start.AddSeconds(161), true, false));
    }

    [Fact]
    public void ValidPositiveQuoteMapsAwayFromMuamuaOutsideTradingHours()
    {
        var engine = new MarketStateEngine(PetId.Muamua);

        Assert.Equal(PetId.Niulai, engine.Accept(0.41, DateTimeOffset.UnixEpoch, true, false));
    }

    [Fact]
    public void StaleSnapshotKeepsLastValueButUsesUnavailableTone()
    {
        var now = DateTimeOffset.UnixEpoch.AddSeconds(10_000);
        var quote = new Quote(MarketTarget.Sse.Symbol, MarketTarget.Sse.Name, 3012, 3000, now, "fixture");
        var snapshot = new MarketSnapshot(MarketTarget.Sse.Id, quote, now);
        Assert.False(snapshot.IsStale(now.AddSeconds(59)));
        Assert.True(snapshot.IsStale(now.AddSeconds(61)));
        Assert.Equal(MarketTone.Unavailable, snapshot.Tone(now.AddSeconds(61)));
        Assert.Equal(MarketTarget.Sse.Name, snapshot.Quote!.Name);
    }

    [Fact]
    public void PersistedStateContainsPillAndStartupFields()
    {
        var state = new PersistedState { ShowMarketPill = false, LaunchAtStartup = true, WindowX = 42, WindowY = 84 };
        var json = JsonSerializer.Serialize(state);
        var restored = JsonSerializer.Deserialize<PersistedState>(json)!;
        Assert.Equal(2, restored.SchemaVersion);
        Assert.False(restored.ShowMarketPill);
        Assert.True(restored.LaunchAtStartup);
        Assert.Equal(42, restored.WindowX);
        Assert.Equal(84, restored.WindowY);
    }

    [Fact]
    public void PersistedStateKeepsAValidatedWatchlistWithoutBumpingSchemaVersion()
    {
        var state = new PersistedState
        {
            WatchlistCodes = ["688365", "510300", "688365", "bad", " 159915 "],
            WatchlistPollingEnabled = true
        };
        state.Normalize();
        var json = JsonSerializer.Serialize(state);
        var restored = JsonSerializer.Deserialize<PersistedState>(json)!;

        Assert.Equal(2, restored.SchemaVersion);
        Assert.Equal(["688365", "510300", "159915"], restored.WatchlistCodes);
        Assert.True(restored.WatchlistPollingEnabled);
    }

    [Fact]
    public void NotificationUsesTheSelectedIndexName()
    {
        var quote = new Quote(MarketTarget.CsiAll.Symbol, MarketTarget.CsiAll.Name, 4012, 4000, DateTimeOffset.UtcNow, "fixture");
        var body = NotificationPolicy.Body(PetId.Baola, MarketTarget.CsiAll, quote);
        Assert.Contains(MarketTarget.CsiAll.Name, body);
        Assert.DoesNotContain(MarketTarget.Sse.Name, body);
    }

    [Fact]
    public void DecodesTonghuashunGbkPayloadFromRawContentType()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var payload = Encoding.GetEncoding(936).GetBytes("<h3>同花顺全A（沪深）</h3>");

        Assert.Equal("gbk", QuoteTextDecoder.ExtractCharset("text/html; charset=gbk"));
        Assert.Contains("同花顺全A（沪深）", QuoteTextDecoder.Decode(payload, "text/html; charset=gbk"));
    }

    [Fact]
    public void SpeechRulesProvideChineseIdleBurstAndScaledText()
    {
        Assert.Contains("牛来", SpeechRules.Idle(PetId.Niulai, DateTimeOffset.UnixEpoch));
        Assert.Equal("牛来速归", SpeechRules.Burst(PetId.Niulai, TimeSpan.Zero));
        Assert.Equal("妈妈", SpeechRules.Current(PetId.Muamua, DateTimeOffset.UnixEpoch));
        Assert.Equal(20, SpeechRules.FontSize(80));
        Assert.Equal(35, SpeechRules.FontSize(140));
    }

    [Fact]
    public void SpeechBubblesUseMultiplePositionsRotationAndLiveTextScale()
    {
        var idle = SpeechRules.Bubbles(PetId.Niulai, DateTimeOffset.UnixEpoch.AddSeconds(6), null, 140);
        Assert.True(idle.Count >= 1);
        Assert.Contains(idle, bubble => bubble.FontSize == 35);

        var startedAt = DateTimeOffset.UnixEpoch.AddSeconds(100);
        var burst = SpeechRules.Bubbles(PetId.Niulai, startedAt.AddSeconds(0.6), startedAt, 80);
        Assert.True(burst.Count >= 2);
        Assert.True(burst.Select(bubble => bubble.OriginX).Distinct().Count() >= 2);
        Assert.Contains(burst, bubble => bubble.RotationDegrees != 0);
        Assert.All(burst, bubble => Assert.InRange(bubble.FontSize, 19.19, 23.21));
    }
}
