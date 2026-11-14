using System.IO;
using System.Windows.Threading;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Share and email of files over the limit (AppViewModel.LargeSend.cs), on the Demo Scanner in a temporary profile.
// Windows only: the Mac and the iPhone have the same rules in AppState+LargeSend.swift.
[Collection(WallClockCollection.Name)]
public class LargeSendTests
{
    [Fact]
    public void ASmallFileGoesStraightToTheShareWindow()
    {
        Run(session =>
        {
            string file = session.File(1000);
            session.Model.AskLargeSend = (_, _, _) => throw new Exception("asked");

            Assert.True(session.Model.RunFileAction(FileAction.Share, [file]));

            Assert.Equal([file], session.Actions.Shared);
        });
    }

    [Fact]
    public void ALargeFileIsHeldBackUntilTheUserSaysSendAnyway()
    {
        Run(session =>
        {
            string file = session.File(SaveActions.LargeAttachmentBytes + 1);
            (int Count, long Bytes, bool CanSaveSmaller)? asked = null;
            var choice = LargeSendChoice.Cancel;
            session.Model.AskLargeSend = (count, bytes, canSaveSmaller) =>
            {
                asked = (count, bytes, canSaveSmaller);
                return choice;
            };

            Assert.False(session.Model.RunFileAction(FileAction.Share, [file]));
            Assert.Empty(session.Actions.Shared);
            Assert.Equal((1, SaveActions.LargeAttachmentBytes + 1, false), asked);

            choice = LargeSendChoice.SendAnyway;
            Assert.True(session.Model.RunFileAction(FileAction.Email, [file]));
            Assert.Equal([file], session.Actions.Shared);
        });
    }

    [Fact]
    public void OtherActionsAreNeverHeldBack()
    {
        Run(session =>
        {
            string file = session.File(SaveActions.LargeAttachmentBytes + 1);
            session.Model.AskLargeSend = (_, _, _) => throw new Exception("asked");

            Assert.True(session.Model.RunFileAction(FileAction.Reveal, [file]));
            Assert.True(session.Model.RunFileAction(FileAction.Open, [file]));
        });
    }

    [Fact]
    public void SizesPrintAsWholeMegabytesFromTenUp()
    {
        Assert.Equal("35 MB", AppViewModel.AttachmentSizeText(34_400_000));
        Assert.Equal("20 MB", AppViewModel.AttachmentSizeText(SaveActions.LargeAttachmentBytes));
        Assert.Equal("6.4 MB", AppViewModel.AttachmentSizeText(6_400_000));
    }

    private sealed class FakeActions : IFileActions
    {
        public List<string> Shared { get; } = [];
        public SendProbe SendProbe { get; } = new(CanCompose: false, CanShare: true);
        public void Open(string path) { }
        public void OpenWith(string path) { }
        public void Reveal(IReadOnlyList<string> paths) { }
        public void Share(IReadOnlyList<string> paths, string title) => Shared.AddRange(paths);
        public void ComposeEmail(IReadOnlyList<string> paths) => throw new NotSupportedException();
        public void Copy(ClipboardContent content) { }
        public void CopyText(string text) { }
    }

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-large-").FullName;
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
        if (failure is not null) throw new Exception("Large send failed.", failure);
    }

    private sealed class Session(string profile)
    {
        private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
        public AppViewModel Model { get; private set; } = null!;
        public FakeActions Actions { get; } = new();

        public void Run(Action<Session> test)
        {
            // The known folders expand these variables, so the settings, spool and counter land in the profile.
            string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
            var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(_dispatcher));
            Model = new AppViewModel(fileActions: Actions);
            try
            {
                Model.Settings.DestinationPath = Directory.CreateDirectory(Path.Combine(profile, "Scans")).FullName;
                Model.SettingsEdited();
                Model.Start();
                Wait(() => Model.DeviceGroups.Any(g => g.Primary.IsDemo));
                Model.UserSelectDevice(Model.DeviceGroups.First(g => g.Primary.IsDemo).Primary.Id);
                Wait(() => Model.IsConnected);
                Model.StartTask(ScanTask.Document);
                Model.Settings.Source = ScanSource.Flatbed;
                Model.SettingsEdited();
                test(this);
            }
            finally
            {
                Model.Shutdown();
                for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
            }
        }

        public string File(long bytes)
        {
            string path = Path.Combine(profile, Guid.NewGuid().ToString("N") + ".pdf");
            using var stream = System.IO.File.Create(path);
            stream.SetLength(bytes);
            return path;
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
