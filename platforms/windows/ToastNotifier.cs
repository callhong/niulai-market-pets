using System.Security;
using System.Windows.Forms;

namespace NiuLaiMarketPets.Windows;

public sealed class ToastNotifier
{
    private readonly NotifyIcon _trayIcon;

    public ToastNotifier(NotifyIcon trayIcon) { _trayIcon = trayIcon; }

    public void Show(string title, string body)
    {
        if (TryShowToast(title, body)) return;
        _trayIcon.BalloonTipTitle = title;
        _trayIcon.BalloonTipText = body;
        _trayIcon.ShowBalloonTip(3500);
    }

    private static bool TryShowToast(string title, string body)
    {
        try
        {
            var safeTitle = SecurityElement.Escape(title) ?? title;
            var safeBody = SecurityElement.Escape(body) ?? body;
            var xmlType = Type.GetType("Windows.Data.Xml.Dom.XmlDocument, Windows, ContentType=WindowsRuntime") ?? throw new PlatformNotSupportedException();
            var toastType = Type.GetType("Windows.UI.Notifications.ToastNotification, Windows, ContentType=WindowsRuntime") ?? throw new PlatformNotSupportedException();
            var managerType = Type.GetType("Windows.UI.Notifications.ToastNotificationManager, Windows, ContentType=WindowsRuntime") ?? throw new PlatformNotSupportedException();
            var xml = Activator.CreateInstance(xmlType) ?? throw new InvalidOperationException();
            xmlType.GetMethod("LoadXml")?.Invoke(xml, [$"<toast><visual><binding template=\"ToastGeneric\"><text>{safeTitle}</text><text>{safeBody}</text></binding></visual></toast>"]);
            var toast = Activator.CreateInstance(toastType, new object?[] { xml }) ?? throw new InvalidOperationException();
            var notifier = managerType.GetMethod("CreateToastNotifier", [typeof(string)])?.Invoke(null, ["NiuLaiMarketPets"]) ?? throw new InvalidOperationException();
            notifier.GetType().GetMethod("Show")?.Invoke(notifier, [toast]);
            return true;
        }
        catch { return false; }
    }
}
