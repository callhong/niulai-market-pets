using System.IO;
using System.Media;
using NiuLaiMarketPets.Windows.Core;

namespace NiuLaiMarketPets.Windows;

public sealed class AudioPlayer
{
    private readonly Dictionary<string, SoundPlayer> _players = new(StringComparer.OrdinalIgnoreCase);

    public AudioPlayer()
    {
        foreach (var name in new[] { "niulai", "baola", "muamua-mama-long", "muamua-mama-rescue" })
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Audio", $"{name}.wav");
            if (!File.Exists(path)) continue;
            try
            {
                var player = new SoundPlayer(path);
                player.LoadTimeout = 3000;
                _players[name] = player;
            }
            catch
            {
                // A missing or unsupported optional audio file must not stop the app.
            }
        }
    }

    public bool Play(PetId pet, bool muted)
    {
        if (muted) return false;
        var names = pet switch
        {
            PetId.Niulai => new[] { "niulai" },
            PetId.Baola => new[] { "baola" },
            _ => new[] { "muamua-mama-long", "muamua-mama-rescue" }
        };
        var name = names[Random.Shared.Next(names.Length)];
        if (!_players.TryGetValue(name, out var player)) return false;
        try
        {
            if (!player.IsLoadCompleted) player.Load();
            player.Play();
            return true;
        }
        catch { return false; }
    }
}
