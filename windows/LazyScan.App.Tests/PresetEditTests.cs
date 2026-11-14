using System.IO;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Renaming and updating a preset (AppViewModel.RenamePreset, UpdatePreset), in a temporary profile.
[Collection(WallClockCollection.Name)]
public class PresetEditTests
{
    [Fact]
    public void Rename_KeepsTheIdAndSettingsAndTrimsTheName()
    {
        Run(model =>
        {
            model.SaveCurrentAsPreset("Invoices");
            var saved = model.Presets[0];

            Assert.True(model.RenamePreset(saved.Id, "  Receipts "));

            var renamed = Assert.Single(model.Presets);
            Assert.Equal("Receipts", renamed.Name);
            Assert.Equal(saved.Id, renamed.Id);
            Assert.Same(saved.Settings, renamed.Settings);
        });
    }

    [Fact]
    public void Rename_RefusesABlankNameAndAMissingPreset()
    {
        Run(model =>
        {
            model.SaveCurrentAsPreset("Invoices");

            Assert.False(model.RenamePreset(model.Presets[0].Id, "   "));
            Assert.False(model.RenamePreset(Guid.NewGuid(), "Receipts"));
            Assert.Equal("Invoices", Assert.Single(model.Presets).Name);
        });
    }

    [Fact]
    public void Update_ReplacesTheSettingsAndKeepsTheName()
    {
        Run(model =>
        {
            model.SaveCurrentAsPreset("Invoices");
            var id = model.Presets[0].Id;
            model.Settings.Resolution = 150;
            model.SettingsEdited();

            Assert.True(model.UpdatePreset(id));

            var updated = Assert.Single(model.Presets);
            Assert.Equal("Invoices", updated.Name);
            Assert.Equal(id, updated.Id);
            Assert.Equal(150, updated.Settings.Resolution);
            Assert.Equal("Updated “Invoices” with the current settings.", model.StatusMessage);
            Assert.False(model.UpdatePreset(Guid.NewGuid()));
        });
    }

    private static void Run(Action<AppViewModel> test)
    {
        string profile = Directory.CreateTempSubdirectory("LazyScan-presets-").FullName;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string[] names = ["USERPROFILE", "APPDATA", "LOCALAPPDATA"];
            var before = names.Select(Environment.GetEnvironmentVariable).ToArray();
            Environment.SetEnvironmentVariable("USERPROFILE", profile);
            Environment.SetEnvironmentVariable("APPDATA", Path.Combine(profile, "AppData", "Roaming"));
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(profile, "AppData", "Local"));
            try { test(new AppViewModel()); }
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
        if (failure is not null) throw new Exception("Preset edit failed.", failure);
    }
}
