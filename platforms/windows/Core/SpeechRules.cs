namespace NiuLaiMarketPets.Windows.Core;

public sealed record SpeechBubble(
    string Id,
    string Text,
    bool IsBurst,
    DateTimeOffset StartedAt,
    TimeSpan Duration,
    double OriginX,
    double OriginY,
    double DriftX,
    double DriftY,
    double RotationDegrees,
    string FontName,
    double FontSize)
{
    public double ProgressAt(DateTimeOffset at)
    {
        if (Duration <= TimeSpan.Zero) return 1;
        return Math.Clamp((at - StartedAt).TotalSeconds / Duration.TotalSeconds, 0, 1);
    }

    public bool IsVisibleAt(DateTimeOffset at)
    {
        var elapsed = at - StartedAt;
        return elapsed >= TimeSpan.Zero && elapsed < Duration;
    }
}

public static class SpeechRules
{
    private static readonly TimeSpan IdleInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan BurstStep = TimeSpan.FromSeconds(0.42);
    private static readonly TimeSpan IdleVisibleDuration = TimeSpan.FromSeconds(2.2);
    private static readonly TimeSpan BurstBubbleDuration = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan BurstDuration = TimeSpan.FromSeconds(2.84);

    private static readonly IReadOnlyDictionary<PetId, string[]> IdleLines = new Dictionary<PetId, string[]>
    {
        [PetId.Niulai] = ["牛来", "牛来！", "冲呀"],
        [PetId.Baola] = ["豹拉", "起飞", "再冲一段"],
        [PetId.Muamua] = ["妈妈", "呜呜", "妈妈救我"]
    };

    private static readonly IReadOnlyDictionary<PetId, string[]> BurstLines = new Dictionary<PetId, string[]>
    {
        [PetId.Niulai] = ["牛来速归", "牛来！", "冲冲冲"],
        [PetId.Baola] = ["豹拉 All in", "豹拉起飞", "再来一根"],
        [PetId.Muamua] = ["妈妈救我！", "妈——", "妈妈"]
    };

    public static string Idle(PetId pet, DateTimeOffset now)
    {
        var lines = IdleLines[pet];
        var slot = Math.Max(0, (long)Math.Floor(Math.Max(0, (now - DateTimeOffset.UnixEpoch).TotalSeconds) / IdleInterval.TotalSeconds));
        return lines[slot % lines.Length];
    }

    public static string Burst(PetId pet, TimeSpan elapsed)
    {
        var lines = BurstLines[pet];
        var slot = Math.Max(0, (long)Math.Floor(Math.Max(0, elapsed.TotalSeconds) / BurstStep.TotalSeconds));
        return lines[slot % lines.Length];
    }

    public static string Current(PetId pet, DateTimeOffset now, DateTimeOffset? burstStartedAt = null)
    {
        if (burstStartedAt is { } started)
        {
            var elapsed = now - started;
            if (elapsed >= TimeSpan.Zero && elapsed < BurstDuration) return Burst(pet, elapsed);
        }

        return Idle(pet, now);
    }

    public static double FontSize(double scalePercent) => 25 * Math.Clamp(scalePercent, 80, 140) / 100;

    public static IReadOnlyList<SpeechBubble> Bubbles(
        PetId pet,
        DateTimeOffset at,
        DateTimeOffset? burstStartedAt,
        double textScalePercent = 100)
    {
        var textScale = Math.Clamp(textScalePercent, 80, 140) / 100;
        if (burstStartedAt is { } started)
        {
            var burst = MakeBurstBubbles(pet, started, at, textScale);
            if (burst.Count > 0) return burst;
        }

        return MakeIdleBubbles(pet, at, textScale);
    }

    public static IReadOnlyList<SpeechBubble> BurstBubbles(
        PetId pet,
        DateTimeOffset startedAt,
        DateTimeOffset at,
        double textScalePercent = 100) =>
        MakeBurstBubbles(pet, startedAt, at, Math.Clamp(textScalePercent, 80, 140) / 100);

    private static IReadOnlyList<SpeechBubble> MakeIdleBubbles(PetId pet, DateTimeOffset at, double textScale)
    {
        var cycle = (long)Math.Floor((at - DateTimeOffset.UnixEpoch).TotalSeconds / IdleInterval.TotalSeconds);
        var cycleStart = DateTimeOffset.UnixEpoch.AddSeconds(cycle * IdleInterval.TotalSeconds);
        var phrases = IdleLines[pet];
        var index = PositiveModulo(cycle, phrases.Length);
        var bubbles = new List<SpeechBubble>
        {
            MakeBubble(
                $"idle-{pet}-{cycle}-0",
                phrases[index],
                pet,
                cycle,
                cycleStart,
                isBurst: false,
                fontSize: 25 * textScale)
        };

        // A quiet echo every third line follows the Mac client. It is small,
        // offset and independently animated instead of being clipped into one
        // fixed top label.
        if (PositiveModulo(cycle, 3) == 1)
        {
            var echoStart = cycleStart.AddSeconds(0.34);
            if (at >= echoStart)
            {
                bubbles.Add(MakeBubble(
                    $"idle-{pet}-{cycle}-echo",
                    "…",
                    pet,
                    cycle + 7,
                    echoStart,
                    isBurst: false,
                    fontSize: 19 * textScale));
            }
        }

        return bubbles.Where(item => item.IsVisibleAt(at)).ToArray();
    }

    private static IReadOnlyList<SpeechBubble> MakeBurstBubbles(PetId pet, DateTimeOffset startedAt, DateTimeOffset at, double textScale)
    {
        var phrases = BurstLines[pet];
        return phrases.Select((phrase, index) => MakeBubble(
                $"burst-{pet}-{startedAt.ToUnixTimeMilliseconds()}-{index}",
                phrase,
                pet,
                index,
                startedAt.AddSeconds(index * BurstStep.TotalSeconds),
                isBurst: true,
                fontSize: (index == 0 ? 29 : 24) * textScale))
            .Where(item => item.IsVisibleAt(at))
            .ToArray();
    }

    private static SpeechBubble MakeBubble(
        string id,
        string text,
        PetId pet,
        long index,
        DateTimeOffset startedAt,
        bool isBurst,
        double fontSize)
    {
        var styles = isBurst ? BurstStyle((int)index) : IdleStyle(pet, index);
        return new SpeechBubble(
            id,
            text,
            isBurst,
            startedAt,
            isBurst ? BurstBubbleDuration : IdleVisibleDuration,
            styles.OriginX,
            styles.OriginY,
            styles.DriftX,
            styles.DriftY,
            styles.RotationDegrees,
            styles.FontName,
            fontSize);
    }

    private static (double OriginX, double OriginY, double DriftX, double DriftY, double RotationDegrees, string FontName) IdleStyle(PetId pet, long index)
    {
        var fonts = new[] { "KaiTi", "Microsoft YaHei", "SimSun", "Microsoft JhengHei" };
        var slots = new (double X, double Y, double DriftX, double DriftY, double Rotation)[]
        {
            (92, -118, 10, -34, -4),
            (-82, -98, -12, -28, 3),
            (76, -42, 14, -24, 5),
            (-64, -54, -10, -30, -5),
            (108, -76, 6, -38, 2)
        };
        var petOffset = pet switch
        {
            PetId.Baola => 1,
            PetId.Muamua => 2,
            _ => 0
        };
        var slotIndex = PositiveModulo(index + petOffset, slots.Length);
        var slot = slots[slotIndex];
        return (slot.X, slot.Y, slot.DriftX, slot.DriftY, slot.Rotation, fonts[PositiveModulo(index + petOffset, fonts.Length)]);
    }

    private static (double OriginX, double OriginY, double DriftX, double DriftY, double RotationDegrees, string FontName) BurstStyle(int index)
    {
        var fonts = new[] { "KaiTi", "Microsoft YaHei", "SimSun" };
        var slots = new (double X, double Y, double DriftX, double DriftY, double Rotation)[]
        {
            (-112, -104, -12, -30, -4),
            (112, -104, 14, -32, 4),
            (0, -174, 0, -28, 0)
        };
        var slot = slots[PositiveModulo(index, slots.Length)];
        return (slot.X, slot.Y, slot.DriftX, slot.DriftY, slot.Rotation, fonts[PositiveModulo(index, fonts.Length)]);
    }

    private static int PositiveModulo(long value, int divisor)
    {
        var remainder = value % divisor;
        return (int)(remainder >= 0 ? remainder : remainder + divisor);
    }
}
