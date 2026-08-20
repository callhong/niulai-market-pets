using System.Threading;
using System.Windows;

namespace NiuLaiMarketPets.Windows;

public partial class App : System.Windows.Application
{
    private Mutex? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        const string mutexName = "NiuLaiMarketPets.Windows.SingleInstance";
        _singleInstance = new Mutex(true, mutexName, out var created);
        if (!created)
        {
            Shutdown();
            return;
        }

        base.OnStartup(e);
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
