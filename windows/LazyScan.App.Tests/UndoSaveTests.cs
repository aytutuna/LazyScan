using System.IO;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Undo after a save (AppViewModel.UndoSave.cs), on the Demo Scanner in a temporary profile. Windows only: the
// Mac and the iPhone have the same rules in AppState+Undo.swift.
[Collection(WallClockCollection.Name)]
public class UndoSaveTests
{
    [Fact]
    public void Undo_DeletesTheFileAndBringsThePagesBack()
    {
        Run(session =>
        {
            session.Scan();
            int pages = session.Model.ScannedPages.Count;
            var ids = session.Model.ScannedPages.Select(item => item.Page.Id).ToList();
            session.Wait(session.Model.SavePdf());

            string saved = Assert.Single(session.Model.LastSavedPaths);
            Assert.True(File.Exists(saved));
            Assert.Empty(session.Model.ScannedPages);
            Assert.True(session.Model.CanUndoSave);
            Assert.False(session.Model.CanUndoRemove);

            var undo = session.Model.UndoSave();
            session.Wait(undo);

            Assert.False(File.Exists(saved));
            Assert.False(session.Model.CanUndoSave);
            Assert.Equal(ids, session.Model.ScannedPages.Select(item => item.Page.Id));
            Assert.Equal(ids[0], undo.Result);
            Assert.Equal(pages, session.Model.ScannedPages.Count);
            Assert.Equal("Save undone: the pages are in the queue again.", session.Model.StatusMessage);
        });
    }

    [Fact]
    public void Undo_LeavesAFileChangedSinceTheSave()
    {
        Run(session =>
        {
            session.Scan();
            session.Wait(session.Model.SavePdf());
            string saved = Assert.Single(session.Model.LastSavedPaths);
            File.AppendAllText(saved, "more");

            session.Wait(session.Model.UndoSave());

            Assert.True(File.Exists(saved));
            Assert.True(session.Model.CanUndoSave);
            Assert.Empty(session.Model.ScannedPages);
            Assert.Equal(Path.GetFileName(saved) + " was changed after it was saved, so Undo left it as it is.", session.Model.ErrorMessage);
        });
    }

    [Fact]
    public void ANewScanLetsTheHeldSaveGo()
    {
        Run(session =>
        {
            session.Scan();
            session.Wait(session.Model.SavePdf());
            Assert.True(session.Model.CanUndoSave);

            session.Scan();

            Assert.False(session.Model.CanUndoSave);
            Assert.True(File.Exists(Assert.Single(session.Model.LastSavedPaths)));
        });
    }

    [Fact]
    public void Undo_PutsAPdfBackThatPagesWereAddedTo()
    {
        Run(session =>
        {
            session.Scan();
            session.Wait(session.Model.SavePdf());
            string target = Assert.Single(session.Model.LastSavedPaths);
            byte[] before = File.ReadAllBytes(target);

            session.Scan();
            session.Model.SetAppendTarget(target);
            session.Wait(session.Model.AppendToPdf(target));
            Assert.NotEqual(before, File.ReadAllBytes(target));
            Assert.Null(session.Model.AppendTarget);
            Assert.True(session.Model.CanUndoSave);

            session.Wait(session.Model.UndoSave());

            Assert.Equal(before, File.ReadAllBytes(target));
            Assert.Equal(target, session.Model.AppendTarget);
            Assert.NotEmpty(session.Model.ScannedPages);
            Assert.Equal(Path.GetFileName(target) + " is as it was, and the pages are in the queue again.", session.Model.StatusMessage["Save undone: ".Length..]);
        });
    }

    [Fact]
    public void ASavedPasswordProtectedPdfCannotBeUndone()
    {
        Run(session =>
        {
            session.Scan();
            session.Model.Settings.Output.Protect = true;
            session.Model.AskPdfPassword = () => new PdfProtection("secret");
            session.Wait(session.Model.SavePdf());

            Assert.Single(session.Model.LastSavedPaths);
            Assert.False(session.Model.CanUndoSave);
        });
    }

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-undo-").FullName;
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
        if (failure is not null) throw new Exception("Undo after a save failed.", failure);
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
