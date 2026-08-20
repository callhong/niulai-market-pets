using System.IO;
using System.Windows.Media.Imaging;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace NiuLaiMarketPets.Windows;

public sealed class PetSpriteAnimator
{
    private readonly Dictionary<string, Image<Rgba32>> _atlases = [];

    public BitmapSource Frame(NiuLaiMarketPets.Windows.Core.PetId pet, int row, int frame)
    {
        var safeRow = Math.Clamp(row, 0, 10);
        var maxFrame = safeRow is 0 ? 6 : safeRow is 3 or 4 or 7 or 8 ? 6 : 8;
        var safeFrame = Math.Clamp(frame, 0, maxFrame - 1);
        var image = GetAtlas(pet).Clone(ctx => ctx.Crop(new SixLabors.ImageSharp.Rectangle(safeFrame * 192, safeRow * 208, 192, 208)));
        using var stream = new MemoryStream();
        image.Save(stream, new PngEncoder());
        stream.Position = 0;
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = stream;
        bitmap.EndInit();
        bitmap.Freeze();
        image.Dispose();
        return bitmap;
    }

    private Image<Rgba32> GetAtlas(NiuLaiMarketPets.Windows.Core.PetId pet)
    {
        var key = pet.ToString();
        if (_atlases.TryGetValue(key, out var cached)) return cached;
        var directory = pet switch
        {
            NiuLaiMarketPets.Windows.Core.PetId.Niulai => "niulai",
            NiuLaiMarketPets.Windows.Core.PetId.Baola => "baola",
            _ => "muamua"
        };
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Pets", directory, "spritesheet.webp");
        var image = SixLabors.ImageSharp.Image.Load<Rgba32>(path);
        _atlases[key] = image;
        return image;
    }
}
