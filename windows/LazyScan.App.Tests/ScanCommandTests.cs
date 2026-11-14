using System.IO;
using System.Windows.Threading;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// scan --preset NAME --output PATH (ScanCommand): parsing, and a run on the Demo Scanner in a temporary profile.
[Collection(WallClockCollection.Name)]
public class ScanCommandTests
{
    [Fact]
    public void ScanTakesAPresetAndAnOutput()
    {
        Assert.True(ScanCommand.IsScan(["scan", "--preset", "Nightly", "--output", "a.pdf"]));
        Assert.False(ScanCommand.IsScan(["Receipt.lsdoc"]));
        var command = ScanCommand.Parse(["scan", "--output", "C:\\Scans\\a.pdf", "--preset", "Nightly"]);
        Assert.Equal("Nightly", command?.Preset);
        Assert.Equal("C:\\Scans\\a.pdf", command?.Output);
    }

    [Theory]
    [InlineData("scan")]
    [InlineData("scan", "--preset", "Nightly")]
    [InlineData("scan", "--output", "a.pdf")]
    [InlineData("scan", "--preset", "Nightly", "--output")]
    [InlineData("scan", "--preset", "", "--output", "a.pdf")]
    [InlineData("scan", "--preset", "Nightly", "--output", "a.pdf", "--all")]
    public void AnythingElseIsRefused(params string[] args) => Assert.Null(ScanCommand.Parse(args));

    [Fact]
    public void ARunWritesTheFileAndLeavesTheUsersSettings()
    {
        Run((profile, model) =>
        {
            model.Presets.Add(new Preset("Nightly", new ScanSettings()));
            string output = Path.Combine(profile, "Out", "night.pdf");
            var (code, error) = Scan(model, "Nightly", output);

            Assert.Equal(ScanCommand.Done, code);
            Assert.Equal("", error);
            Assert.StartsWith("%PDF", File.ReadAllText(output, System.Text.Encoding.Latin1).Substring(0, 5));
            Assert.Equal(["night.pdf"], Directory.GetFiles(Path.Combine(profile, "Out")).Select(Path.GetFileName));
            Assert.Empty(Directory.GetFiles(profile, "settings.json", SearchOption.AllDirectories));
        });
    }

    [Fact]
    public void ANameIsMatchedWithoutCaseAndAnExtensionIsAddedWhenLeftOut()
    {
        Run((profile, model) =>
        {
            model.Presets.Add(new Preset("Nightly", new ScanSettings()));
            var (code, _) = Scan(model, "nightly", Path.Combine(profile, "Out", "night"));

            Assert.Equal(ScanCommand.Done, code);
            Assert.True(File.Exists(Path.Combine(profile, "Out", "night.pdf")));
        });
    }

    [Fact]
    public void AnUnknownPresetFailsBeforeAnythingScans()
    {
        Run((profile, model) =>
        {
            var (code, error) = Scan(model, "Missing", Path.Combine(profile, "Out", "a.pdf"));

            Assert.Equal(ScanCommand.Failed, code);
            Assert.Contains("Missing", error);
            Assert.False(Directory.Exists(Path.Combine(profile, "Out")));
        });
    }

    [Fact]
    public void TheDemoScannerIsNotAScanner()
    {
        Run((profile, model) =>
        {
            model.Presets.Add(new Preset("Nightly", new ScanSettings()));
            var (code, error) = Scan(model, "Nightly", Path.Combine(profile, "Out", "a.pdf"), allowDemo: false);

            Assert.Equal(ScanCommand.Failed, code);
            Assert.NotEqual("", error);
            Assert.False(File.Exists(Path.Combine(profile, "Out", "a.pdf")));
        });
    }

    [Fact]
    public void APresetThatNeedsTheWindowFails()
    {
        Run((profile, model) =>
        {
            model.Presets.Add(new Preset("Photos", new ScanSettings { Intent = ScanIntent.Photo }));
            var (code, error) = Scan(model, "Photos", Path.Combine(profile, "Out", "a.pdf"));

            Assert.Equal(ScanCommand.Failed, code);
            Assert.Contains("Photos", error);
            Assert.False(File.Exists(Path.Combine(profile, "Out", "a.pdf")));
        });
    }

    private static (int Code, string Error) Scan(AppViewModel model, string preset, string output, bool allowDemo = true)
    {
        var dispatcher = Dispatcher.CurrentDispatcher;
        var error = new StringWriter();
        var command = ScanCommand.Parse(["scan", "--preset", preset, "--output", output])!;
        command.AllowsDemo = allowDemo;
        var run = command.RunAsync(model, error);
        var end = DateTime.UtcNow.AddSeconds(90);
        while (!run.IsCompleted)
        {
            if (DateTime.UtcNow > end) throw new TimeoutException("The command did not end.");
            dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            Thread.Sleep(10);
        }
        return (run.GetAwaiter().GetResult(), error.ToString().Trim());
    }

    private static void Run(Action<string, AppViewModel> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-command-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
            var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher));
            try { test(profile, new AppViewModel()); }
            catch (Exception e) { failure = e; }
            finally
            {
                for (int i = 0; i < names.Length; i++) Environment.SetEnvironmentVariable(names[i], before[i]);
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        try { Directory.Delete(profile, recursive: true); }
        catch (IOException) { }
        if (failure is not null) throw new Exception("Scan command failed.", failure);
    }
}
