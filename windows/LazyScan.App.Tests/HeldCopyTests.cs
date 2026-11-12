using System.IO;
using System.Windows.Threading;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// A copy that did not print stays held (AppViewModel.Copy.cs), on the Demo Scanner in a temporary profile
// with a stand-in for the printers. The Mac has the same rules in AppState+Copy.swift.
[Collection(WallClockCollection.Name)]
public class HeldCopyTests
{
    [Fact]
    public void FailedPrint_HoldsThePagesAndPrintAgainUsesTheChosenPrinter()
    {
        Run(printers => printers.FailNext = true, session =>
        {
            session.Wait(session.Model.PerformScan());

            Assert.True(session.Model.HasHeldCopy);
            Assert.Equal("Could not print.", session.Model.StatusMessage);
            Assert.Equal("Could not print on Office: offline", session.Model.HeldCopyFailure);
            Assert.Equal("Could not print on Office: offline The copy is still here.", session.Model.ErrorMessage);
            Assert.True(session.Model.ErrorAboutCopy);

            session.Model.SetCopyPrinter("Photo");
            session.Wait(session.Model.PrintHeldCopy());

            Assert.False(session.Model.HasHeldCopy);
            Assert.Equal(["Office", "Photo"], session.Printers.Printed);
            Assert.StartsWith("Sent", session.Model.StatusMessage);
        });
    }

    [Fact]
    public void CancelledPrint_HoldsThePagesWithNoFailure()
    {
        Run(printers => printers.WaitForCancel = true, session =>
        {
            var scan = session.Model.PerformScan();
            session.Wait(() => session.Printers.Started);
            session.Model.CancelScan();
            session.Wait(scan);

            Assert.True(session.Model.HasHeldCopy);
            Assert.Null(session.Model.HeldCopyFailure);
            Assert.Equal("Cancelled.", session.Model.StatusMessage);
        });
    }

    [Fact]
    public void ATaskChangeLetsTheHeldCopyGo()
    {
        Run(printers => printers.FailNext = true, session =>
        {
            session.Wait(session.Model.PerformScan());
            Assert.True(session.Model.HasHeldCopy);

            session.Model.StartTask(ScanTask.Document);

            Assert.False(session.Model.HasHeldCopy);
        });
    }

    [Fact]
    public void ANewScanReplacesTheHeldCopy()
    {
        Run(printers => printers.FailNext = true, session =>
        {
            session.Wait(session.Model.PerformScan());
            Assert.True(session.Model.HasHeldCopy);

            session.Wait(session.Model.PerformScan());

            Assert.False(session.Model.HasHeldCopy);
            Assert.Equal(["Office", "Office"], session.Printers.Printed);
        });
    }

    private sealed class FakePrinters : IPrintService
    {
        private static readonly PrinterPaper Letter = PrinterPaper.Make(new SizeD(8.5, 11), null);
        public bool FailNext { get; set; }
        public bool WaitForCancel { get; set; }
        public bool Started { get; private set; }
        public List<string> Printed { get; } = [];

        public Task<IReadOnlyList<PrinterInfo>> GetPrintersAsync() =>
            Task.FromResult<IReadOnlyList<PrinterInfo>>([new PrinterInfo("Office", true), new PrinterInfo("Photo", false)]);

        public Task<PrinterSetup?> GetSetupAsync(string? printerName, PaperSize? requestedPaper) =>
            Task.FromResult<PrinterSetup?>(new PrinterSetup(printerName ?? "Office", Letter, null, true));

        public async Task PrintAsync(PrintJob job, CancellationToken token)
        {
            Printed.Add(job.PrinterName);
            if (WaitForCancel)
            {
                Started = true;
                await Task.Delay(Timeout.Infinite, token);
            }
            if (FailNext)
            {
                FailNext = false;
                throw new PrintException($"Could not print on {job.PrinterName}: offline");
            }
        }
    }

    private static void Run(Action<FakePrinters> arrange, Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-heldcopy-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { new Session(profile, arrange).Run(test); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        try { Directory.Delete(profile, recursive: true); }
        catch (IOException) { }
        if (failure is not null) throw new Exception("The held copy test failed.", failure);
    }

    private sealed class Session(string profile, Action<FakePrinters> arrange)
    {
        private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
        public FakePrinters Printers { get; } = new();
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
            arrange(Printers);
            Model = new AppViewModel(printService: Printers);
            try
            {
                Model.Settings.DestinationPath = Directory.CreateDirectory(Path.Combine(profile, "Scans")).FullName;
                Model.SettingsEdited();
                Model.Start();
                Wait(() => Model.DeviceGroups.Any(g => g.Primary.IsDemo));
                Model.UserSelectDevice(Model.DeviceGroups.First(g => g.Primary.IsDemo).Primary.Id);
                Wait(() => Model.IsConnected);
                Wait(Model.RefreshPrintersAsync());
                Assert.True(Model.StartTask(ScanTask.Copy));
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
                Pump(50);
            }
        }

        private void Pump(int milliseconds)
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
