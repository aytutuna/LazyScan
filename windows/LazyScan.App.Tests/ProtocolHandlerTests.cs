using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class ProtocolHandlerTests
{
    [Fact]
    public void ASchemeNobodyHandlesHasNoHandler() =>
        Assert.False(WindowsFileActions.HasProtocolHandler("lazytest" + Guid.NewGuid().ToString("N")));

    [Fact]
    public void TheShellKnowsWhoHandlesHttp() => Assert.True(WindowsFileActions.HasProtocolHandler("http"));
}
