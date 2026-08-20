using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public sealed class ConfigStore
{
    public string RootPath { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NiuLaiMarketPets");
    public string ConfigPath => Path.Combine(RootPath, "config.json");
    private readonly JsonSerializerOptions _options = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public PersistedState Load()
    {
        try
        {
            if (!File.Exists(ConfigPath)) return new PersistedState();
            var state = JsonSerializer.Deserialize<PersistedState>(File.ReadAllText(ConfigPath), _options) ?? new PersistedState();
            state.Normalize();
            return state;
        }
        catch
        {
            return new PersistedState();
        }
    }

    public void Save(PersistedState state)
    {
        state.Normalize();
        Directory.CreateDirectory(RootPath);
        var temp = Path.Combine(RootPath, $"config.{Environment.ProcessId}.tmp");
        File.WriteAllText(temp, JsonSerializer.Serialize(state, _options));
        File.Move(temp, ConfigPath, true);
    }
}
