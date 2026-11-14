using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Port of Tests/LazyScanTests/PhotoDetailsTests.swift: the same cases.

public class PhotoDetailsTests
{
    [Fact]
    public void YearAlone_DatesTheFirstOfJanuary() =>
        Assert.Equal("1985:01:01 00:00:00", new PhotoDetails(Year: 1985).ExifDate);

    [Fact]
    public void YearMonthAndDay_AreWritten() =>
        Assert.Equal("1985:07:23 00:00:00", new PhotoDetails(1985, 7, 23).ExifDate);

    [Fact]
    public void MonthOrDayOutOfRange_CountAsOne()
    {
        Assert.Equal("1985:01:01 00:00:00", new PhotoDetails(1985, 13, 40).ExifDate);
        Assert.Equal("1985:02:01 00:00:00", new PhotoDetails(1985, 2, 30).ExifDate);
        Assert.Equal("1984:02:29 00:00:00", new PhotoDetails(1984, 2, 29).ExifDate);
        Assert.Equal("1985:02:01 00:00:00", new PhotoDetails(1985, 2, 29).ExifDate);
    }

    [Fact]
    public void NoFourDigitYear_HasNoDate()
    {
        Assert.Null(new PhotoDetails().ExifDate);
        Assert.Null(new PhotoDetails(Month: 5, Day: 5).ExifDate);
        Assert.Null(new PhotoDetails(85).ExifDate);
        Assert.Null(new PhotoDetails(10000).ExifDate);
    }

    [Fact]
    public void Caption_IsTrimmed_AndBlankHasNone()
    {
        Assert.Equal("Dad at the lake", new PhotoDetails(Caption: "  Dad at the lake\n").ExifCaption);
        Assert.Null(new PhotoDetails(Caption: " \t ").ExifCaption);
        Assert.Null(new PhotoDetails().ExifCaption);
    }
}
