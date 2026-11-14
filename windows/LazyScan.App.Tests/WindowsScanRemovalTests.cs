using System.IO;
using System.Windows.Threading;
using LazyScan.App.Scanning;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// WIA Automation is asked to look again when a Windows Scan entry appears and when it goes.
[Collection(WallClockCollection.Name)]
public class WindowsScanRemovalTests
{
    [Fact]
    public void ARemovedWindowsScanEntryHasWiaLookAgain()
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-removal-").FullName;
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
        if (failure is not null) throw new Exception("Removal refresh failed.", failure);
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
        var polled = new FakePolled();
        var windowsScan = new FakeBackend();
        windowsScan.Devices = [new ScannerInfo("winrt:a", "Scanner A", "USB", Backend: WindowsScanConnection.Backend)];
        var model = new AppViewModel(backends: [polled, windowsScan]);
        try
        {
            model.Start();
            Assert.Equal(1, polled.Refreshes);

            windowsScan.Devices = [];
            windowsScan.RaiseChanged();
            var end = DateTime.UtcNow.AddSeconds(30);
            while (polled.Refreshes < 2)
            {
                if (DateTime.UtcNow > end) throw new TimeoutException("The list was not refreshed.");
                dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                Thread.Sleep(10);
            }
            Assert.Equal(2, polled.Refreshes);
        }
        finally
        {
            model.Shutdown();
            for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
        }
    }

    private class FakeBackend : IScannerBackend
    {
        public event Action? DevicesChanged;
        public IReadOnlyList<ScannerInfo> Devices { get; set; } = [];
        public void RaiseChanged() => DevicesChanged?.Invoke();
        public void StartBrowsing() { }
        public void StopBrowsing() { }
        public Task<IScannerSession> OpenSessionAsync(string deviceId) => throw new NotSupportedException();
    }

    private sealed class FakePolled : FakeBackend, IPolledScannerBackend
    {
        public event Action? EnumerationFinished { add { } remove { } }
        public long EnumerationsStarted { get; private set; }
        public long EnumerationsFinished { get; private set; }
        public int Refreshes { get; private set; }
        public void RefreshDevices()
        {
            Refreshes++;
            EnumerationsStarted++;
        }
    }
}
