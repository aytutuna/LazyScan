using System.IO;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// <c>scan --preset NAME --output PATH</c>: scans with a saved preset and writes the file with no window,
/// for a script or a scheduled task. Exits 0 when the file is written, 1 when the scan or the save fails
/// and 2 when the arguments are wrong. It runs beside a window that is already open, without handing
/// anything to it, and leaves the user's own settings as they were.
/// </summary>
public sealed class ScanCommand
{
    public const int Done = 0;
    public const int Failed = 1;
    public const int BadArguments = 2;

    private static readonly TimeSpan ConnectLimit = TimeSpan.FromSeconds(60);

    public string Preset { get; }
    public string Output { get; }

    internal bool AllowsDemo { get; set; }

    private ScanCommand(string preset, string output)
    {
        Preset = preset;
        Output = output;
    }

    public static bool IsScan(IReadOnlyList<string> args) =>
        args.Count > 0 && args[0].Equals("scan", StringComparison.OrdinalIgnoreCase);

    public static string Usage => Loc.T("Usage: scan --preset NAME --output PATH");

    /// <summary>The command for <paramref name="args"/>, which start with <c>scan</c>; null when an option is missing, unknown or empty.</summary>
    public static ScanCommand? Parse(IReadOnlyList<string> args)
    {
        string? preset = null, output = null;
        for (int i = 1; i < args.Count; i += 2)
        {
            if (i + 1 >= args.Count || args[i + 1].Length == 0) return null;
            if (args[i].Equals("--preset", StringComparison.OrdinalIgnoreCase)) preset = args[i + 1];
            else if (args[i].Equals("--output", StringComparison.OrdinalIgnoreCase)) output = args[i + 1];
            else return null;
        }
        return preset is null || output is null ? null : new ScanCommand(preset, output);
    }

    /// <summary>Scans on the connected scanner and moves the one file saved to <see cref="Output"/>; a reason is written to <paramref name="error"/> on failure.</summary>
    public async Task<int> RunAsync(AppViewModel model, TextWriter error)
    {
        model.SavesSettings = false;
        try
        {
            var preset = model.Presets.FirstOrDefault(p => string.Equals(p.Name, Preset, StringComparison.OrdinalIgnoreCase));
            if (preset is null) return Fail(error, Loc.T("There is no preset “{0}”.", Preset));
            string target = Path.GetFullPath(Output);
            model.Start();
            if (!await Connected(model) || (model.DemoSelected && !AllowsDemo))
            {
                return Fail(error, model.ErrorMessage ?? Loc.T("No scanner found"));
            }
            model.ApplyPreset(preset);
            var settings = model.Settings;
            // Only a document that collects its pages or saves each scan has nobody to ask.
            if (TaskCatalog.FlowOf(settings) != TaskFlowKind.DocumentQueue)
            {
                return Fail(error, Loc.T("The preset “{0}” needs the window to finish a scan, so it cannot run from the command line.", preset.Name));
            }
            settings.DestinationPath = Path.GetDirectoryName(target)!;
            settings.Output.AfterSave = AfterSaveAction.None;
            settings.ScanAgainSeconds = 0;
            model.ErrorMessage = null;
            int saves = model.SavedRevision;
            await model.PerformScan();
            if (model.ErrorMessage is null && model.ScannedPages.Count > 0) await model.SavePdf();
            if (model.ErrorMessage is not null) return Fail(error, model.ErrorMessage);
            if (model.SavedRevision == saves) return Fail(error, Loc.T("Nothing was saved."));
            var saved = model.LastSavedPaths;
            if (saved.Count != 1)
            {
                return Fail(error, Loc.T("The preset “{0}” saved {1} files, and --output names one.", preset.Name, saved.Count));
            }
            Move(saved[0], target);
            return Done;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return Fail(error, e.Message);
        }
        finally
        {
            await model.CloseSessionAsync();
            model.Shutdown();
        }
    }

    /// <summary>Waits for the search to end and the scanner it settled on to open; false when none does.</summary>
    private static async Task<bool> Connected(AppViewModel model)
    {
        var end = DateTime.UtcNow + ConnectLimit;
        while (DateTime.UtcNow < end)
        {
            if (model.IsConnected && model.DiscoverySettled) return true;
            if (model.DiscoverySettled && !model.IsConnecting) return false;
            await Task.Delay(100);
        }
        return false;
    }

    private static void Move(string file, string target)
    {
        if (Path.GetExtension(target).Length == 0) target += Path.GetExtension(file);
        if (!string.Equals(file, target, StringComparison.OrdinalIgnoreCase)) File.Move(file, target, overwrite: true);
    }

    private static int Fail(TextWriter error, string message)
    {
        error.WriteLine(message);
        return Failed;
    }
}
