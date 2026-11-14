using System.IO;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Scan again after (AppViewModel.StartScanAgain): the countdown and the repeat, on the Demo Scanner in a
// temporary profile.
[Collection(WallClockCollection.Name)]
public class ScanAgainTests
{
    [Fact]
    public void ARepeatingFlatbedScanQueuesPagesUntilStop()
    {
        Run(session =>
        {
            session.Model.Settings.ScanAgainSeconds = 2;
            Assert.True(session.Model.OffersScanAgain);
            session.Wait(session.Model.PerformScan());
            session.Wait(() => session.Model.ScannedPages.Count >= 3);
            Assert.Null(session.Model.ErrorMessage);

            session.Model.CancelScan();

            Assert.Null(session.Model.ScanAgainRemaining);
            session.Wait(() => !session.Model.IsBusy);
            int kept = session.Model.ScannedPages.Count;
            session.Pump(400);
            Assert.Equal(kept, session.Model.ScannedPages.Count);
            Assert.False(session.Model.IsBusy);
        });
    }

    [Fact]
    public void TheCountdownShowsWholeSecondsAndStopClearsIt()
    {
        Run(session =>
        {
            session.Model.Settings.ScanAgainSeconds = 3;
            session.Model.ScanAgainTick = TimeSpan.FromMilliseconds(400);
            session.Wait(session.Model.PerformScan());
            session.Wait(() => session.Model.ScanAgainRemaining == 3 && !session.Model.IsBusy);
            session.Wait(() => session.Model.ScanAgainRemaining == 2);
            int queued = session.Model.ScannedPages.Count;

            session.Model.StopScanAgain();

            Assert.Null(session.Model.ScanAgainRemaining);
            session.Pump(1500);
            Assert.Equal(queued, session.Model.ScannedPages.Count);
            Assert.False(session.Model.IsBusy);
        });
    }

    [Fact]
    public void AClosedDeviceEndsTheCountdown()
    {
        Run(session =>
        {
            session.Model.Settings.ScanAgainSeconds = 3;
            session.Model.ScanAgainTick = TimeSpan.FromMilliseconds(400);
            session.Wait(session.Model.PerformScan());
            session.Wait(() => session.Model.ScanAgainRemaining is not null && !session.Model.IsBusy);
            int queued = session.Model.ScannedPages.Count;

            session.Model.UserSelectDevice(null);

            Assert.Null(session.Model.ScanAgainRemaining);
            session.Pump(1500);
            Assert.Equal(queued, session.Model.ScannedPages.Count);
        });
    }

    [Fact]
    public void OffScansOnce()
    {
        Run(session =>
        {
            session.Wait(session.Model.PerformScan());
            session.Wait(() => !session.Model.IsBusy);
            Assert.Null(session.Model.ScanAgainRemaining);
            session.Pump(400);
            Assert.Single(session.Model.ScannedPages);
        });
    }

    [Fact]
    public void TheFeederDoesNotScanAgain()
    {
        Run(session =>
        {
            session.Model.Settings.Source = ScanSource.DocumentFeeder;
            session.Model.Settings.ScanAgainSeconds = 2;
            Assert.False(session.Model.OffersScanAgain);
            session.Wait(session.Model.PerformScan());
            session.Wait(() => !session.Model.IsBusy);
            int queued = session.Model.ScannedPages.Count;
            Assert.Null(session.Model.ScanAgainRemaining);
            session.Pump(400);
            Assert.Equal(queued, session.Model.ScannedPages.Count);
        });
    }

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-again-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { new Session(profile).Run(test); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        try { Directory.Delete(profile, recursive: true); }
        catch (IOException) { }
        if (failure is not null) throw new Exception("Scan again failed.", failure);
    }

    private sealed class Session(string profile)
    {
        private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
        public AppViewModel Model { get; private set; } = null!;

        public void Run(Action<Session> test)
        {
            // The known folders expand these variables, so the settings, spool and counter land in the profile.
            string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
            var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(_dispatcher));
            Model = new AppViewModel();
            try
            {
                Model.Settings.DestinationPath = Directory.CreateDirectory(Path.Combine(profile, "Scans")).FullName;
                Model.SettingsEdited();
                Model.Start();
                Wait(() => Model.DeviceGroups.Any(g => g.Primary.IsDemo));
                Model.UserSelectDevice(Model.DeviceGroups.First(g => g.Primary.IsDemo).Primary.Id);
                Wait(() => Model.IsConnected);
                Model.ScanAgainTick = TimeSpan.FromMilliseconds(20);
                test(this);
            }
            finally
            {
                Model.Shutdown();
                for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
            }
        }

        public void Wait(Task task)
        {
            Wait(() => task.IsCompleted);
            task.GetAwaiter().GetResult();
        }

        public void Wait(Func<bool> done)
        {
            var end = DateTime.UtcNow.AddSeconds(30);
            while (!done())
            {
                if (DateTime.UtcNow > end) throw new TimeoutException("The view model did not reach the state expected.");
                Pump(20);
            }
        }

        public void Pump(int milliseconds)
        {
            var end = DateTime.UtcNow.AddMilliseconds(milliseconds);
            do
            {
                _dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
                Thread.Sleep(10);
            }
            while (DateTime.UtcNow < end);
        }
    }
}
