using System.IO;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Cutting the queued spreads again after the reading order or rotation changed (AppViewModel.Book.cs), on the
// Demo Scanner in a temporary profile.
[Collection(WallClockCollection.Name)]
public class BookReorderTests
{
    [Fact]
    public void Apply_CutsTheQueuedSpreadsAgainAndUndoBringsThemBack()
    {
        Run(session =>
        {
            session.Scan();
            session.Scan();
            var before = session.Model.ScannedPages.Select(item => item.Page).ToList();
            Assert.Equal(4, before.Count);
            Assert.Null(session.Model.BookReorderOffer);

            session.Model.SetBookRightToLeft(true);
            Assert.Equal(new BookReorderOffer(2, BookReorderChange.Order), session.Model.BookReorderOffer);

            session.Wait(session.Model.ApplyBookReorder());

            var after = session.Model.ScannedPages.Select(item => item.Page).ToList();
            Assert.Equal(4, after.Count);
            Assert.Empty(after.Select(page => page.Id).Intersect(before.Select(page => page.Id)));
            Assert.Equal(before.Select(page => page.Spread!.SpreadId), after.Select(page => page.Spread!.SpreadId));
            Assert.Equal(before.Select(page => page.Spread!.Part).Chunk(2).SelectMany(pair => pair.Reverse()),
                         after.Select(page => page.Spread!.Part));
            Assert.Null(session.Model.BookReorderOffer);
            Assert.Equal("Reordered 2 spreads", session.Model.StatusMessage);
            Assert.True(session.Model.CanUndoRemove);

            session.Model.UndoRemoval();

            Assert.Equal(before.Select(page => page.Id), session.Model.ScannedPages.Select(item => item.Page.Id));
            Assert.All(before, page => Assert.True(File.Exists(page.FilePath)));
            Assert.True(session.Model.Settings.TaskOptions.BookRightToLeft);
        });
    }

    [Fact]
    public void JoiningAReorderedSpreadEndsTheUndo()
    {
        Run(session =>
        {
            session.Scan();
            session.Scan();
            session.Model.SetBookRightToLeft(true);
            session.Wait(session.Model.ApplyBookReorder());
            Assert.True(session.Model.CanUndoRemove);

            session.Wait(session.Model.JoinSpread(session.Model.ScannedPages[0].Page.Id));

            Assert.False(session.Model.CanUndoRemove);
            Assert.Equal(3, session.Model.ScannedPages.Count);
        });
    }

    [Fact]
    public void TheOfferGoesWhenTheOptionIsSetBack()
    {
        Run(session =>
        {
            session.Scan();
            session.Model.SetBookRotation(1);
            Assert.Equal(BookReorderChange.Rotation, session.Model.BookReorderOffer?.Changed);
            session.Model.SetBookRightToLeft(true);
            Assert.Equal(BookReorderChange.Both, session.Model.BookReorderOffer?.Changed);
            session.Model.SetBookRotation(0);
            session.Model.SetBookRightToLeft(false);
            Assert.Null(session.Model.BookReorderOffer);
        });
    }

    [Fact]
    public void NoOfferWithoutSpreadsInTheQueue()
    {
        Run(session =>
        {
            session.Model.SetBookRightToLeft(true);
            Assert.Null(session.Model.BookReorderOffer);
        });
    }

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-book-").FullName;
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
        if (failure is not null) throw new Exception("Book reorder failed.", failure);
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
                Model.StartTask(ScanTask.Book);
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
