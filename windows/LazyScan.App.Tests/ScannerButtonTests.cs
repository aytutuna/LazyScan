using System.IO;
using System.Windows.Threading;
using LazyScan.App.Scanning;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// A press on the selected scanner's own button starts a scan; a press on another scanner does nothing.
[Collection(WallClockCollection.Name)]
public class ScannerButtonTests
{
    private const string ScanImage = "{A6C5A715-8C6E-11D2-977A-0000F87A926F}";

    [Fact]
    public void OnlyAPressOnTheIdleSelectedScannerStartsAScan()
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-button-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { Run(profile); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        try { Directory.Delete(profile, recursive: true); }
        catch (IOException) { }
        if (failure is not null) throw new Exception("Button press failed.", failure);
    }

    private static void Run(string profile)
    {
        string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
        var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
        Environment.SetEnvironmentVariable("USERPROFILE", profile);
        Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
        Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
        var dispatcher = Dispatcher.CurrentDispatcher;
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(dispatcher));
        Action<string, string>? press = null;
        var wia = new WiaScannerBackend(() => ServiceStatus.Running, () => true, () => [], onEvent =>
        {
            press = onEvent;
            return () => { };
        });
        var scanner = new StandInScanner();
        var model = new AppViewModel(backends: [wia, scanner]);
        bool busy = false;
        model.PropertyChanged += (_, _) => busy |= model.IsBusy;
        try
        {
            model.Start();
            Pump(dispatcher, () => model.IsConnected && press is not null, "The scanner did not connect.");
            Assert.Equal(StandInScanner.Id, model.SelectedDeviceId);

            Press(dispatcher, press!, "{OTHER}");
            Assert.False(busy);

            Press(dispatcher, press!, StandInScanner.WiaId);
            Pump(dispatcher, () => busy, "The press did not start a scan.");
            Pump(dispatcher, () => !model.IsBusy, "The scan did not end.");
        }
        finally
        {
            model.Shutdown();
            for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
        }
    }

    private static void Press(Dispatcher dispatcher, Action<string, string> press, string deviceId)
    {
        press(ScanImage, deviceId);
        dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
    }

    private static void Pump(Dispatcher dispatcher, Func<bool> done, string timeout)
    {
        var end = DateTime.UtcNow.AddSeconds(30);
        while (!done())
        {
            if (DateTime.UtcNow > end) throw new TimeoutException(timeout);
            dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            Thread.Sleep(10);
        }
    }

    // Lists one scanner under a WIA id and scans with the demo scanner's session.
    private sealed class StandInScanner : IScannerBackend
    {
        public const string WiaId = "{STANDIN}";
        public const string Id = "wia:" + WiaId;
        private readonly MockScannerBackend _demo = new();
        public event Action? DevicesChanged;
        public IReadOnlyList<ScannerInfo> Devices { get; private set; } = [];

        public void StartBrowsing()
        {
            _demo.StartBrowsing();
            Devices = [new ScannerInfo(Id, "Stand-in", "USB", Backend: "wia")];
            DevicesChanged?.Invoke();
        }

        public void StopBrowsing() => _demo.StopBrowsing();
        public Task<IScannerSession> OpenSessionAsync(string deviceId) => _demo.OpenSessionAsync("mock:demo");
    }
}
