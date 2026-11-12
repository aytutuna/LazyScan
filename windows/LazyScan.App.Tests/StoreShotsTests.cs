using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// The Microsoft Store screenshots: the main window at 1920 x 1080 on the Demo Scanner, drawn without being
// shown. Does nothing unless LAZYSCAN_STORE_SHOTS_DIR names the folder for the images; scripts/make_store_shots.ps1
// sets it. The app's settings, page spool and save folder are moved to a temporary profile for the run, so the
// pictures show no personal path or file. Windows only: no Swift twin (the Mac has MacStoreShotsTests).
[Collection(WallClockCollection.Name)]
public class StoreShotsTests
{
    private const int Width = 1920;
    private const int Height = 1080;

    [Fact]
    public void WriteStoreScreenshots()
    {
        if (Environment.GetEnvironmentVariable("LAZYSCAN_STORE_SHOTS_DIR") is not { Length: > 0 } outDir) return;
        Directory.CreateDirectory(outDir);
        // A save folder with no user name in its path, since the Save to box shows it.
        string saveTo = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDocuments), "Lazy Scan");
        if (Directory.Exists(saveTo)) throw new InvalidOperationException(saveTo + " exists; move it away before running.");
        string profile = Directory.CreateTempSubdirectory("LazyScan-store-shots-").FullName;
        Directory.CreateDirectory(saveTo);
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { new Shoot(profile, saveTo, outDir).Run(); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        foreach (var folder in new[] { profile, saveTo })
        {
            try { Directory.Delete(folder, recursive: true); }
            catch (IOException) { }
        }
        if (failure is not null) throw new Exception("The store screenshots failed.", failure);
    }

    private sealed class Shoot(string profile, string saveTo, string outDir)
    {
        private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
        private MainWindow _window = null!;
        private AppViewModel Model => _window.ViewModel;

        public void Run()
        {
            try { Capture(); }
            finally { if (_window is not null) Model.Shutdown(); }
        }

        private void Capture()
        {
            // The known folders expand these variables, so the settings, spool and counter land in the profile.
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            if (!Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData).StartsWith(profile, StringComparison.OrdinalIgnoreCase) ||
                !Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData).StartsWith(profile, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The profile folders could not be redirected for this process.");
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(_dispatcher));
            var culture = System.Globalization.CultureInfo.GetCultureInfo("en-US");
            System.Globalization.CultureInfo.CurrentUICulture = culture;
            System.Globalization.CultureInfo.DefaultThreadCurrentUICulture = culture;

            var app = new App();
            app.InitializeComponent();
            ThemeService.Apply(AppAppearance.Light);

            _window = new MainWindow();
            Model.Settings.DestinationPath = saveTo;
            Model.SettingsEdited();
            Model.Start();
            _window.Width = Width;
            _window.Height = Height;
            Wait(() => Model.DeviceGroups.Any(g => g.Primary.IsDemo));
            Model.UserSelectDevice(Model.DeviceGroups.First(g => g.Primary.IsDemo).Primary.Id);
            Wait(() => Model.IsConnected);
            Settle();
            Write("start");

            Model.StartTask(ScanTask.Document);
            Model.Settings.Source = ScanSource.DocumentFeeder;
            Model.SettingsEdited();
            Show("ScanTab");
            Wait(Model.PerformScan());
            Wait(() => Model.ScannedPages.Count >= 3);
            Settle();
            Write("queue");

            Wait(Model.SavePdf());

            Model.StartTask(ScanTask.Photos);
            Model.Settings.Source = ScanSource.Flatbed;
            Model.SettingsEdited();
            Show("ScanTab");
            Wait(Model.PerformScan());
            Wait(() => Model.ShowPhotoReview);
            Settle();
            Write("photo-review");

            Wait(Model.SaveReviewedPhotos());
            Show("SavedTab");
            Settle();
            Write("saved");
        }

        private void Show(string tab)
        {
            ((TabItem)_window.FindName(tab)).IsSelected = true;
            Call("PushSettingsToUi");
            Call("RefreshFromViewModel");
        }

        private void Call(string name) =>
            typeof(MainWindow).GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(_window, null);

        private void Wait(Task task)
        {
            Wait(() => task.IsCompleted);
            task.GetAwaiter().GetResult();
        }

        private void Wait(Func<bool> done)
        {
            var end = DateTime.UtcNow.AddSeconds(30);
            while (!done())
            {
                if (DateTime.UtcNow > end) throw new TimeoutException("The window did not reach the state to draw.");
                Pump(50);
            }
        }

        /// <summary>Lets queued work and image loads land, then lays the window out again.</summary>
        private void Settle()
        {
            Pump(1500);
            Call("RefreshFromViewModel");
            Pump(500);
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

        private void Layout()
        {
            _window.Measure(new Size(Width, Height));
            _window.Arrange(new Rect(0, 0, Width, Height));
            _window.UpdateLayout();
        }

        /// <summary>The window drawn at 1920 x 1080 on white, written without an alpha channel.</summary>
        private void Write(string name)
        {
            // The pane folds by the window's width, which is only known once it has been arranged.
            Layout();
            Call("UpdatePane");
            Layout();
            Pump(300);
            var visual = new DrawingVisual();
            using (var context = visual.RenderOpen())
            {
                context.DrawRectangle(Brushes.White, null, new Rect(0, 0, Width, Height));
                context.DrawRectangle(new VisualBrush(_window)
            {
                Stretch = Stretch.None, AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Top,
                ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, Width, Height),
            }, null, new Rect(0, 0, Width, Height));
            }
            var bitmap = new RenderTargetBitmap(Width, Height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            var opaque = new FormatConvertedBitmap(bitmap, PixelFormats.Bgr32, null, 0);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(opaque));
            using var stream = File.Create(Path.Combine(outDir, name + ".png"));
            encoder.Save(stream);
        }
    }
}
