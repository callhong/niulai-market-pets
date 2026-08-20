using System.Text;
using System.Text.RegularExpressions;

namespace NiuLaiMarketPets.Windows.Core;

public static class QuoteTextDecoder
{
    private static readonly Regex CharsetPattern = new(
        @"(?:^|;)\s*charset\s*=\s*(?:""(?<value>[^""]+)""|(?<value>[^;\s]+))",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    static QuoteTextDecoder()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    public static string? ExtractCharset(string? contentType)
    {
        if (string.IsNullOrWhiteSpace(contentType)) return null;
        var match = CharsetPattern.Match(contentType);
        return match.Success ? match.Groups["value"].Value.Trim() : null;
    }

    public static string Decode(ReadOnlySpan<byte> payload, string? contentType)
    {
        var charset = ExtractCharset(contentType);
        if (!string.IsNullOrWhiteSpace(charset))
        {
            try { return Encoding.GetEncoding(charset).GetString(payload); }
            catch (ArgumentException) { }
        }

        return Encoding.UTF8.GetString(payload);
    }
}
