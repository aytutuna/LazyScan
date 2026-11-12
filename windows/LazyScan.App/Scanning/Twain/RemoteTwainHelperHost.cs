using LazyScan.Core;

namespace LazyScan.App.Scanning.Twain;

/// <summary>
/// TWAIN in a helper process of its own (<see cref="TwainHelperProcess"/>) instead of this one, so a
/// driver that faults or hangs ends only the helper. Used by <see cref="TwainScannerBackend"/> for
/// 64-bit drivers when <see cref="TwainHelperOptions.Helper64Enabled"/> is set.
/// </summary>
internal sealed class RemoteTwainHelperHost(TwainHelperOptions options) : ITwainHelperHost, IDisposable
{
    private readonly TwainHelperProcess _helper = new(options);

    /// <summary>The helper's process id while it runs (tests).</summary>
    internal int? ProcessId => _helper.ProcessId;

    public TwainHelperSourceList ListSources()
    {
        // A listing is the moment to try again after a helper that could not start.
        _helper.Retry();
        var reply = _helper.Connect().Request(new TwainHelperListSources(), options.Limits.ListSources);
        return reply switch
        {
            TwainHelperSourceList found => found,
            TwainHelperFailure failure => throw failure.Error.ToException(),
            _ => throw ScanException.SessionFailed(() => Loc.T("the 32-bit TWAIN helper answered with {0}.", reply.Type)),
        };
    }

    public ITwainTransport Open(string name)
    {
        var transport = new RemoteTwainTransport(_helper.Connect, name, options.Limits);
        transport.Open();
        return transport;
    }

    public void Close(ITwainTransport source)
    {
        if (source is RemoteTwainTransport transport) transport.Close();
    }

    public void Dispose() => _helper.Dispose();
}
