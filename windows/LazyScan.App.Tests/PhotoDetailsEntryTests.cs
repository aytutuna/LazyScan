using LazyScan.App;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public class PhotoDetailsEntryTests
{
    private const int Now = 2026;

    [Theory]
    [InlineData("1985", 1985)]
    [InlineData("1800", 1800)]
    [InlineData("2026", 2026)]
    [InlineData("1799", null)]
    [InlineData("2027", null)]
    [InlineData("198", null)]
    [InlineData("", null)]
    [InlineData("+198", null)]
    public void Year_NeedsFourDigitsFrom1800ToThisYear(string text, int? expected) =>
        Assert.Equal(expected, PhotoDetailsEntry.Year(text, Now));

    [Fact]
    public void YearProblem_IsTypedTextThatIsNoYear_OrAMonthOrDayWithoutOne()
    {
        Assert.False(PhotoDetailsEntry.YearProblem("", 0, 0, Now));
        Assert.True(PhotoDetailsEntry.YearProblem("", 3, 0, Now));
        Assert.True(PhotoDetailsEntry.YearProblem("", 0, 5, Now));
        Assert.True(PhotoDetailsEntry.YearProblem("19999", 3, 31, Now));
        Assert.True(PhotoDetailsEntry.YearProblem("198", 0, 0, Now));
        Assert.False(PhotoDetailsEntry.YearProblem("1985", 3, 31, Now));
    }

    [Fact]
    public void DaysInMonth_FollowsTheMonthAndYear()
    {
        Assert.Equal(31, PhotoDetailsEntry.DaysInMonth(null, 0));
        Assert.Equal(30, PhotoDetailsEntry.DaysInMonth(1985, 4));
        Assert.Equal(28, PhotoDetailsEntry.DaysInMonth(1985, 2));
        Assert.Equal(29, PhotoDetailsEntry.DaysInMonth(1984, 2));
        Assert.Equal(29, PhotoDetailsEntry.DaysInMonth(null, 2));
    }

    [Fact]
    public void Details_LeavesOutADateWithoutAValidYear_AndKeepsTheCaption()
    {
        Assert.Equal(new PhotoDetails(), PhotoDetailsEntry.Details("", 0, 0, "", Now));
        Assert.Equal(new PhotoDetails(Caption: "Lake"), PhotoDetailsEntry.Details("19999", 3, 5, "Lake", Now));
        Assert.Null(PhotoDetailsEntry.Details("", 3, 5, "", Now).ExifDate);
    }

    [Fact]
    public void Details_FillsInMonthAndDayOnlyWhenChosen()
    {
        Assert.Equal("1985:01:01 00:00:00", PhotoDetailsEntry.Details("1985", 0, 12, "", Now).ExifDate);
        Assert.Equal("1985:03:01 00:00:00", PhotoDetailsEntry.Details("1985", 3, 0, "", Now).ExifDate);
        Assert.Equal("1985:03:12 00:00:00", PhotoDetailsEntry.Details("1985", 3, 12, "", Now).ExifDate);
    }
}
