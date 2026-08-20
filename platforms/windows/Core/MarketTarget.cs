namespace NiuLaiMarketPets.Windows.Core;

public enum SourceKind { StandardIndex, TonghuashunPublic }

public sealed record MarketTarget(
    string Id,
    string Symbol,
    string Name,
    string? EastmoneySecId,
    string? TencentSymbol,
    SourceKind SourceKind = SourceKind.StandardIndex)
{
    public static MarketTarget Sse { get; } = new("sse", "000001", "上证指数", "1.000001", "sh000001");
    public static MarketTarget CsiAll { get; } = new("csi-all", "000985", "中证全指", "1.000985", "sh000985");
    public static MarketTarget ThsAll { get; } = new("ths-all", "883421", "同花顺全A（沪深）", null, null, SourceKind.TonghuashunPublic);
    public static MarketTarget MicroCap { get; } = CreateTonghuashun("883418");
    public static MarketTarget Chinext { get; } = new("chinext", "399006", "创业板指", "0.399006", "sz399006");
    public static MarketTarget Star50 { get; } = new("star50", "000688", "科创50", "1.000688", "sh000688");
    public static MarketTarget Cni2000 { get; } = new("cni-2000", "399303", "国证2000", "0.399303", "sz399303");
    public static IReadOnlyList<MarketTarget> All { get; } = [Sse, CsiAll, ThsAll, Chinext, Star50, Cni2000];
    public static MarketTarget Default => ThsAll;

    public static MarketTarget FromId(string id)
    {
        var builtIn = All.FirstOrDefault(item => item.Id == id);
        if (builtIn is not null) return builtIn;

        const string prefix = "ths-code-";
        if (id.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && TryCreateTonghuashun(id[prefix.Length..], out var custom)) return custom;
        return Default;
    }

    public bool IsCustomCode => Id.StartsWith("ths-code-", StringComparison.OrdinalIgnoreCase);

    public static bool TryCreateTonghuashun(string? code, out MarketTarget target)
    {
        code = code?.Trim();
        if (code is null || code.Length != 6 || !code.All(char.IsAsciiDigit))
        {
            target = Default;
            return false;
        }

        target = CreateTonghuashun(code);
        return true;
    }

    private static MarketTarget CreateTonghuashun(string code)
    {
        if (code is "883418" or "883421")
        {
            return new MarketTarget(
                $"ths-code-{code}",
                code,
                code == "883418" ? "微盘股（883418）" : "同花顺全A（883421）",
                null,
                null,
                SourceKind.TonghuashunPublic);
        }

        // 5xxxxx is the Shanghai ETF range; both 5xxxxx and 6xxxxx use
        // Eastmoney market 1 and Tencent's sh prefix.
        var isShanghai = code[0] is '5' or '6';
        var eastmoneyMarket = isShanghai ? "1" : "0";
        var tencentMarket = isShanghai ? "sh" : code[0] is '4' or '8' ? "bj" : "sz";
        return new MarketTarget(
            $"ths-code-{code}",
            code,
            $"代码（{code}）",
            $"{eastmoneyMarket}.{code}",
            $"{tencentMarket}{code}",
            SourceKind.StandardIndex);
    }

    public static MarketTarget NextPollingTarget(string id)
    {
        var index = All.ToList().FindIndex(item => item.Id == id);
        return index < 0 ? All[0] : All[(index + 1) % All.Count];
    }
}
