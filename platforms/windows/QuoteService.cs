using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public sealed record QuoteFetchResult(Quote? Quote, IReadOnlyList<string> Errors);

public sealed class QuoteService
{
    private readonly HttpClient _client = CreateClient();

    private static HttpClient CreateClient()
    {
        var handler = new HttpClientHandler();
        var proxyText = Environment.GetEnvironmentVariable("HTTPS_PROXY")
            ?? Environment.GetEnvironmentVariable("HTTP_PROXY");
        if (Uri.TryCreate(proxyText, UriKind.Absolute, out var proxyUri) &&
            proxyUri.Scheme is "http" or "https")
        {
            handler.Proxy = new WebProxy(proxyUri);
            handler.UseProxy = true;
        }

        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("NiuLaiMarketPets/1.0");
        return client;
    }

    public async Task<QuoteFetchResult> FetchAsync(MarketTarget target, CancellationToken cancellationToken = default)
    {
        var errors = new List<string>();
        try { return new QuoteFetchResult(await FetchPrimaryAsync(target, cancellationToken), errors); }
        catch (Exception error) { errors.Add($"主行情源：{DescribeError(error)}"); }
        try { return new QuoteFetchResult(await FetchBackupAsync(target, cancellationToken), errors); }
        catch (Exception error) { errors.Add($"备用行情源：{DescribeError(error)}"); }
        return new QuoteFetchResult(null, errors);
    }

    private async Task<Quote> FetchPrimaryAsync(MarketTarget target, CancellationToken cancellationToken)
    {
        if (target.SourceKind == SourceKind.TonghuashunPublic)
        {
            using var tongResponse = await _client.GetAsync($"https://q.10jqka.com.cn/thshy/detail/code/{target.Symbol}/", cancellationToken);
            tongResponse.EnsureSuccessStatusCode();
            var contentType = tongResponse.Content.Headers.TryGetValues("Content-Type", out var values) ? values.FirstOrDefault() : null;
            var html = QuoteTextDecoder.Decode(await tongResponse.Content.ReadAsByteArrayAsync(cancellationToken), contentType);
            var last = MatchNumber(html, "board-xj[^>]*>(?<value>[0-9.]+)");
            var previous = MatchNumber(html, "昨收</dt>\\s*<dd>(?<value>[0-9.]+)");
            if (last is null || previous is null || !double.IsFinite(last.Value) || !double.IsFinite(previous.Value) || previous <= 0)
                throw new InvalidDataException("同花顺行情格式异常");
            return new Quote(target.Symbol, target.Name, last.Value, previous.Value, DateTimeOffset.UtcNow, "tonghuashun-public");
        }

        var url = $"https://push2.eastmoney.com/api/qt/stock/get?secid={target.EastmoneySecId}&fields=f43,f58,f60,f86";
        using var response = await _client.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(cancellationToken));
        var data = document.RootElement.GetProperty("data");
        var lastRaw = Number(data.GetProperty("f43"));
        var previousRaw = Number(data.GetProperty("f60"));
        if (!double.IsFinite(lastRaw) || !double.IsFinite(previousRaw) || lastRaw <= 0 || previousRaw <= 0)
            throw new InvalidDataException("东方财富行情格式异常");
        var name = StringValue(data, "f58") ?? target.Name;
        var timestamp = data.TryGetProperty("f86", out var rawTimestamp) && rawTimestamp.ValueKind == JsonValueKind.Number
            ? DateTimeOffset.FromUnixTimeSeconds(rawTimestamp.GetInt64())
            : DateTimeOffset.UtcNow;
        return new Quote(target.Symbol, name, lastRaw / 100, previousRaw / 100, timestamp, "eastmoney");
    }

    private async Task<Quote> FetchBackupAsync(MarketTarget target, CancellationToken cancellationToken)
    {
        if (target.SourceKind == SourceKind.TonghuashunPublic || target.TencentSymbol is null) throw new NotSupportedException("该指数暂无备用行情源");
        using var response = await _client.GetAsync($"https://qt.gtimg.cn/q={target.TencentSymbol}", cancellationToken);
        response.EnsureSuccessStatusCode();
        var contentType = response.Content.Headers.TryGetValues("Content-Type", out var values) ? values.FirstOrDefault() : null;
        var text = QuoteTextDecoder.Decode(await response.Content.ReadAsByteArrayAsync(cancellationToken), contentType);
        var fields = text.Split('~');
        if (fields.Length < 5 || !double.TryParse(fields[3], NumberStyles.Float, CultureInfo.InvariantCulture, out var last) || !double.TryParse(fields[4], NumberStyles.Float, CultureInfo.InvariantCulture, out var previous) || !double.IsFinite(last) || !double.IsFinite(previous) || previous <= 0)
            throw new InvalidDataException("腾讯行情格式异常");
        var name = fields.Length > 1 && !string.IsNullOrWhiteSpace(fields[1]) ? fields[1].Trim() : target.Name;
        return new Quote(target.Symbol, name, last, previous, DateTimeOffset.UtcNow, "tencent");
    }

    private static string DescribeError(Exception error) => error switch
    {
        OperationCanceledException => "请求超时",
        HttpRequestException => "网络连接失败",
        InvalidDataException => "返回数据格式异常",
        NotSupportedException => "该指数暂无备用行情源",
        _ => "行情源暂不可用"
    };

    private static double Number(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number => value.GetDouble(),
        JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) => parsed,
        _ => double.NaN
    };

    private static string? StringValue(JsonElement data, string property)
    {
        if (!data.TryGetProperty(property, out var value)) return null;
        var text = value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.GetRawText(),
            _ => null
        };
        return string.IsNullOrWhiteSpace(text) ? null : text.Trim();
    }

    private static double? MatchNumber(string text, string pattern)
    {
        var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline);
        return match.Success && double.TryParse(match.Groups["value"].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : null;
    }
}
