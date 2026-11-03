using System.Globalization;
using System.Runtime.CompilerServices;

namespace LazyScan.Core.Tests;

internal static class TestCulture
{
    // Asserts compare English text and en-US number formats, whatever the machine's language is.
    [ModuleInitializer]
    internal static void Pin()
    {
        var en = CultureInfo.GetCultureInfo("en-US");
        CultureInfo.DefaultThreadCurrentCulture = en;
        CultureInfo.DefaultThreadCurrentUICulture = en;
        CultureInfo.CurrentCulture = en;
        CultureInfo.CurrentUICulture = en;
    }
}
