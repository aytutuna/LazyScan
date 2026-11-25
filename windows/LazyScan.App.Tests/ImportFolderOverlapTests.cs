using System.IO;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// The import folder may not be the save folder, hold it or lie inside it: what the app saves there would come
// back in as a new page, again and again.
public sealed class ImportFolderOverlapTests
{
    private static void Run(Action<AppViewModel, string> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-import-folder-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
            var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            try { test(new AppViewModel(), profile); }
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
        if (failure is not null) throw new Exception("Import folder check failed.", failure);
    }

    [Fact]
    public void ThePickerRefusesTheSaveFolderTheOneAroundItAndOnesInsideIt()
    {
        Run((model, profile) =>
        {
            string saves = Path.Combine(profile, "Scans", "Saved");
            model.Settings.DestinationPath = saves;

            Assert.NotNull(model.ImportFolderRefusal(saves));
            Assert.NotNull(model.ImportFolderRefusal(saves + @"\"));
            Assert.NotNull(model.ImportFolderRefusal(saves.ToUpperInvariant()));
            Assert.NotNull(model.ImportFolderRefusal(Path.Combine(saves, "Print")));
            Assert.NotNull(model.ImportFolderRefusal(Path.Combine(profile, "Scans")));
            Assert.NotNull(model.ImportFolderRefusal(Path.Combine(profile, "Scans", "Saved", "..", "Saved")));
            Assert.Contains("Pick another folder", model.ImportFolderRefusal(saves)!);

            Assert.Null(model.ImportFolderRefusal(Path.Combine(profile, "Inbox")));
            Assert.Null(model.ImportFolderRefusal(Path.Combine(profile, "Scans", "Saved2")));
        });
    }

    [Fact]
    public void AFolderThatBecomesTheSaveFolderLaterIsNotWatchedAndSaysWhy()
    {
        Run((model, profile) =>
        {
            string inbox = Path.Combine(profile, "Inbox");
            Directory.CreateDirectory(inbox);
            model.SetImportFolder(inbox);
            Assert.False(model.ImportFolderHasProblem);

            model.Settings.DestinationPath = Path.Combine(inbox, "Saved");

            Assert.True(model.ImportFolderHasProblem);
            Assert.Contains("imported again", model.ImportFolderStatus);
        });
    }
}
