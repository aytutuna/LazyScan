using LazyScan.Core;

namespace LazyScan.App.Scanning.Twain;

/// <summary>TWAIN in this process: NTwain against the Data Source Manager of its bitness, through <see cref="NTwainSessionHost"/>.</summary>
internal sealed class NTwainHelperHost : ITwainHelperHost
{
    private readonly NTwainSessionHost _session = new();

    public TwainHelperSourceList ListSources()
    {
        var availability = _session.EnsureSession();
        return new TwainHelperSourceList(availability,
                                         availability == TwainAvailability.Available ? _session.Sources() : []);
    }

    public ITwainTransport Open(string name) => _session.Open(name);

    public void Close(ITwainTransport source)
    {
        if (source is NTwainDriver driver) driver.Close();
    }
}
