using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace NiuLaiMarketPets.Windows;

public sealed record WindowsUpdateRelease(
    string TagName,
    string HtmlUrl,
    string InstallerUrl,
    string ChecksumUrl);

public sealed record WindowsUpdateCheckResult(
    bool Success,
    bool IsNewer,
    string CurrentVersion,
    string LatestVersion,
    WindowsUpdateRelease? Release,
    string Message);

public sealed class UpdateService
{
    private const string LatestReleaseUrl = "https://api.github.com/repos/callhong/niulai-market-pets/releases/latest";
    private const string InstallerName = "NiuLaiMarketPets-windows-x64-setup.exe";
    private const string ChecksumName = InstallerName + ".sha256";
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromSeconds(30) };

    public UpdateService()
    {
        _client.DefaultRequestHeaders.UserAgent.ParseAdd("NiuLaiMarketPets.Windows/1.1.0");
        _client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    public async Task<WindowsUpdateCheckResult> CheckAsync(CancellationToken cancellationToken = default)
    {
        var current = CurrentVersion();
        try
        {
            using var response = await _client.GetAsync(LatestReleaseUrl, cancellationToken);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(stream, cancellationToken: cancellationToken)
                ?? throw new InvalidDataException("发布信息为空");
            var tag = release.TagName?.Trim() ?? string.Empty;
            if (!TryParseVersion(tag, out var latest))
                return new WindowsUpdateCheckResult(false, false, current, tag, null, "发布版本号无法识别。");

            var isNewer = Version.TryParse(current, out var currentVersion) && latest > currentVersion;
            if (!isNewer)
                return new WindowsUpdateCheckResult(true, false, current, latest.ToString(3), null, string.Empty);

            var installer = release.Assets?.FirstOrDefault(asset => string.Equals(asset.Name, InstallerName, StringComparison.OrdinalIgnoreCase));
            var checksum = release.Assets?.FirstOrDefault(asset => string.Equals(asset.Name, ChecksumName, StringComparison.OrdinalIgnoreCase));
            var update = installer?.BrowserDownloadUrl is { Length: > 0 } installerUrl && checksum?.BrowserDownloadUrl is { Length: > 0 } checksumUrl
                ? new WindowsUpdateRelease(tag, release.HtmlUrl ?? "https://github.com/callhong/niulai-market-pets/releases", installerUrl, checksumUrl)
                : null;
            return new WindowsUpdateCheckResult(true, true, current, latest.ToString(3), update, string.Empty);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception)
        {
            return new WindowsUpdateCheckResult(false, false, current, string.Empty, null, "暂时无法连接更新服务，请稍后重试。");
        }
    }

    public async Task<string> DownloadAndVerifyAsync(WindowsUpdateRelease release, CancellationToken cancellationToken = default)
    {
        var folder = Path.Combine(Path.GetTempPath(), "NiuLaiMarketPets", "updates");
        Directory.CreateDirectory(folder);
        var safeTag = Regex.Replace(release.TagName, "[^A-Za-z0-9._-]", "_");
        var installerPath = Path.Combine(folder, $"{safeTag}-{InstallerName}");
        var installerTempPath = installerPath + $".{Environment.ProcessId}.tmp";

        try
        {
            await DownloadAsync(release.InstallerUrl, installerTempPath, cancellationToken);
            var checksumText = await _client.GetStringAsync(release.ChecksumUrl, cancellationToken);
            var expected = Regex.Match(checksumText, "\\b[A-Fa-f0-9]{64}\\b").Value;
            if (string.IsNullOrWhiteSpace(expected)) throw new InvalidDataException("安装包校验值缺失");

            await using var stream = File.OpenRead(installerTempPath);
            var actual = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
            if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("安装包 SHA256 校验不一致");

            File.Move(installerTempPath, installerPath, true);
            return installerPath;
        }
        finally
        {
            if (File.Exists(installerTempPath)) File.Delete(installerTempPath);
        }
    }

    public static void LaunchInstaller(string installerPath)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = installerPath,
            UseShellExecute = true
        });
    }

    private async Task DownloadAsync(string url, string destination, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var destinationStream = File.Create(destination);
        await source.CopyToAsync(destinationStream, cancellationToken);
    }

    private static string CurrentVersion()
    {
        var version = typeof(UpdateService).Assembly.GetName().Version;
        return version is null ? "0.0.0" : version.ToString(3);
    }

    private static bool TryParseVersion(string value, out Version version)
    {
        var normalized = value.Trim().TrimStart('v', 'V');
        return Version.TryParse(normalized, out version!);
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string? TagName { get; set; }

        [JsonPropertyName("html_url")]
        public string? HtmlUrl { get; set; }

        [JsonPropertyName("assets")]
        public List<GitHubAsset>? Assets { get; set; }
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("browser_download_url")]
        public string? BrowserDownloadUrl { get; set; }
    }
}
