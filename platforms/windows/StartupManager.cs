using Microsoft.Win32;

namespace NiuLaiMarketPets.Windows;

public static class StartupManager
{
    private const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "NiuLaiMarketPets";

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunPath, false);
        return key?.GetValue(ValueName) is string;
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunPath);
        if (enabled) key?.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
        else key?.DeleteValue(ValueName, false);
    }
}
