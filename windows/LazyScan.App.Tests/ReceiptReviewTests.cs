using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Scan more and Join with previous in the receipts review (AppViewModel.Receipts.cs), on the Demo Scanner in a
// temporary profile. Windows only in its harness; the Mac's twin is in AppStateSeamTests.swift.
[Collection(WallClockCollection.Name)]
public class ReceiptReviewTests
{
    [Fact]
    public void ScanMoreAddsTheNextScansReceiptsAfterTheOnesHeld()
    {
        Run(session =>
        {
            session.Scan();
            var held = session.Model.DetectedPhotos.Select(p => p.Photo.Id).ToList();
            Assert.NotEmpty(held);

            session.ScanMore();

            Assert.True(session.Model.ShowPhotoReview);
            Assert.False(session.Model.IsScanningMore);
            Assert.Equal(held.Count * 2, session.Model.DetectedPhotos.Count);
            Assert.Equal(held, session.Model.DetectedPhotos.Take(held.Count).Select(p => p.Photo.Id));
            Assert.Equal(Enumerable.Range(1, held.Count * 2), session.Model.DetectedPhotos.Select(p => p.Number));
            Assert.Equal(Receipts.ReviewTitle(held.Count * 2), session.Model.ReviewTitle);
        });
    }

    [Fact]
    public void ThreeScansSaveAsOnePdfOfAllTheReceipts()
    {
        Run(session =>
        {
            session.Scan();
            int perScan = session.Model.DetectedPhotos.Count;
            session.ScanMore();
            session.ScanMore();
            Assert.Equal(perScan * 3, session.Model.DetectedPhotos.Count);
            session.Model.Settings.TaskOptions.ReceiptCombine = true;
            session.Model.SettingsEdited();

            session.Wait(session.Model.SaveReviewedPhotos());

            Assert.Null(session.Model.ErrorMessage);
            Assert.Equal(perScan * 3, PageCount(Assert.Single(session.Model.LastSavedPaths)));
        });
    }

    [Fact]
    public void JoinedPiecesAreOneReceiptOfConsecutivePages()
    {
        Run(session =>
        {
            session.Scan();
            session.ScanMore();
            var cards = session.Model.DetectedPhotos;
            int all = cards.Count;
            Assert.True(cards[1].CanJoin);
            Assert.False(cards[0].CanJoin);
            var firstId = cards[0].Photo.Id;

            session.Model.JoinWithPrevious(cards[1]);

            Assert.Equal(all - 1, cards.Count);
            Assert.Equal(firstId, cards[0].Photo.Id);
            Assert.True(cards[0].IsJoined);
            Assert.False(cards[0].CropEnabled);
            Assert.Equal("2 pieces", cards[0].PiecesCaption);
            Assert.Equal(Receipts.ReviewTitle(all - 1), session.Model.ReviewTitle);

            session.Model.RotateReviewPhoto(cards[0]);
            Assert.All(cards[0].Photo.Pieces, piece => Assert.Equal(1, piece.RotationQuarterTurns));

            session.Model.SplitReceipt(cards[0]);
            Assert.Equal(all, cards.Count);
            Assert.All(cards, card => Assert.False(card.IsJoined));

            session.Model.JoinWithPrevious(cards[1]);
            session.Model.Settings.TaskOptions.ReceiptCombine = true;
            session.Model.SettingsEdited();
            session.Wait(session.Model.SaveReviewedPhotos());

            Assert.Null(session.Model.ErrorMessage);
            Assert.Equal(all, PageCount(Assert.Single(session.Model.LastSavedPaths)));
        });
    }

    [Fact]
    public void ACardCannotJoinWhileItOrTheOneBeforeIsLeftOut()
    {
        Run(session =>
        {
            session.Scan();
            session.ScanMore();
            var cards = session.Model.DetectedPhotos;

            cards[0].Included = false;
            session.Model.RefreshJoins();

            Assert.False(cards[1].CanJoin);
            session.Model.JoinWithPrevious(cards[1]);
            Assert.False(cards[1].IsJoined);
            Assert.False(cards[0].IsJoined);
        });
    }

    private static int PageCount(string pdf) => Regex.Matches(File.ReadAllText(pdf, System.Text.Encoding.Latin1), @"/Type\s*/Page(?![a-z])").Count;

    private static void Run(Action<Session> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-receipt-review-").FullName;
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
        if (failure is not null) throw new Exception("The receipts review failed.", failure);
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
                Model.StartTask(ScanTask.Receipt);
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

        public void Scan()
        {
            Wait(Model.PerformScan());
            Wait(() => Model.ShowPhotoReview);
            Pump(500);
        }

        public void ScanMore()
        {
            var scan = Model.ScanMoreReceipts();
            Assert.False(Model.ShowPhotoReview);
            Wait(scan);
            Pump(500);
        }

        public void Wait(Task task)
        {
            Wait(() => task.IsCompleted);
            task.GetAwaiter().GetResult();
        }

        private void Wait(Func<bool> done)
        {
            var end = DateTime.UtcNow.AddSeconds(60);
            while (!done())
            {
                if (DateTime.UtcNow > end) throw new TimeoutException("The view model did not reach the state expected.");
                Pump(50);
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
