using System.Globalization;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class AdjustmentScaleTests
{
    [Fact]
    public void AmountTextUsesTheCulturesSigns()
    {
        var saved = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("sv-SE");
            Assert.Equal("−40", AdjustmentScale.AmountText(-40));
            Assert.Equal("+25", AdjustmentScale.AmountText(25));
            Assert.Equal("0", AdjustmentScale.AmountText(0));
            Assert.Equal("0", AdjustmentScale.AmountText(-0.4));
        }
        finally
        {
            CultureInfo.CurrentCulture = saved;
        }
    }
}
