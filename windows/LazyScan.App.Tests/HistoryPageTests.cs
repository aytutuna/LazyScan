using System.IO;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Add to queue and Save on a card of the Scans tab (AppViewModel.History.cs), on the Demo Scanner in a temporary
// profile. The Mac has the same rules in AppState.swift and AppState+HistorySave.swift.
[Collection(WallClockCollection.Name)]
public class HistoryPageTests
{
    [Fact]
    public void ACardKeepsItsPageInAFile()
    {
        Run(session =>
        {
            session.Scan();
            var item = session.Model.History[0];
            Assert.True(File.Exists(item.Entry.PageFile));
            Assert.True(item.CanAdd);
            Assert.True(item.CanSave);
        });
    }

    [Fact]
    public void AddToQueue_AppendsACopyAndKeepsTheCard()
    {
        Run(session =>
        {
            session.Scan();
            int queued = session.Model.ScannedPages.Count;
            int cards = session.Model.History.Count;
            var item = session.Model.History[0];

            session.Wait(session.Model.AddToQueue(item));

            Assert.Equal(queued + 1, session.Model.ScannedPages.Count);
            Assert.Equal(cards, session.Model.History.Count);
            Assert.True(File.Exists(item.Entry.PageFile));
            var added = session.Model.ScannedPages[^1].Page;
            Assert.NotEqual(item.Entry.PageFile, added.FilePath);
            Assert.Equal(item.Entry.Dpi, added.Dpi);
            Assert.Equal(item.Entry.PixelSize, added.FullPixelSize);
            Assert.Equal("Added to the queue", session.Model.StatusMessage);
        });
    }

    [Fact]
    public void Save_WritesThatPageAloneAndLeavesTheQueueAndTheCard()
    {
        Run(session =>
        {
            session.Scan();
            int queued = session.Model.ScannedPages.Count;
            int cards = session.Model.History.Count;
            var item = session.Model.History[0];

            session.Wait(session.Model.SaveHistoryPage(item));

            string saved = Assert.Single(session.Model.LastSavedPaths);
            Assert.True(File.Exists(saved));
            Assert.Equal(queued, session.Model.ScannedPages.Count);
            Assert.Equal(cards, session.Model.History.Count);
            Assert.True(File.Exists(item.Entry.PageFile));
            Assert.True(item.CanSave);
        });
    }

    [Fact]
    public void ACardWhoseFileIsGone_SaysSoAndTurnsBothButtonsOff()
    {
        Run(session =>
        {
            session.Scan();
            int queued = session.Model.ScannedPages.Count;
            var item = session.Model.History[0];
            File.Delete(item.Entry.PageFile!);

            session.Wait(session.Model.AddToQueue(item));

            Assert.Equal(queued, session.Model.ScannedPages.Count);
            Assert.Equal("Could not add the scan. Its full page is no longer available.", session.Model.StatusMessage);
            Assert.False(item.CanAdd);
            Assert.False(item.CanSave);
            Assert.Equal("The full scan is no longer available", item.UnavailableText);
        });
    }

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-history-").FullName;
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
        if (failure is not null) throw new Exception("The history page test failed.", failure);
    }

    private sealed class Session(string profile)
    {
        private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
        public AppViewModel Model { get; private set; } = null!;

        public void Run(Action<Session> test)
        {
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
                Model.StartTask(ScanTask.Document);
                Model.Settings.Source = ScanSource.DocumentFeeder;
                Model.SettingsEdited();
                test(this);
            }
            finally
            {
                Model.Shutdown();
                for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
            }
        }

        public void Scan()
        {
            int before = Model.ScannedPages.Count;
            Wait(Model.PerformScan());
            Wait(() => Model.ScannedPages.Count > before);
            Pump(500);
        }

        public void Wait(Task task)
        {
            Wait(() => task.IsCompleted);
            task.GetAwaiter().GetResult();
        }

        private void Wait(Func<bool> done)
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
