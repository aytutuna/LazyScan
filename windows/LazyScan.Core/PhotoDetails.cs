namespace LazyScan.Core;

/// <summary>
/// When a picture was taken and a caption for it, written into saved images as EXIF DateTimeOriginal
/// and ImageDescription. Empty values write no tags. The Mac's twin is PhotoDetails.swift.
/// </summary>
public sealed record PhotoDetails(int? Year = null, int? Month = null, int? Day = null, string Caption = "")
{
    /// <summary>"yyyy:MM:dd 00:00:00", or null without a four-digit year. A month or day that is missing or out of range counts as 1.</summary>
    public string? ExifDate
    {
        get
        {
            if (Year is not (>= 1000 and <= 9999)) return null;
            int year = Year.Value;
            int month = Month is >= 1 and <= 12 ? Month.Value : 1;
            int day = Day is >= 1 && Day <= DateTime.DaysInMonth(year, month) ? Day.Value : 1;
            return $"{year:D4}:{month:D2}:{day:D2} 00:00:00";
        }
    }

    /// <summary>The caption without surrounding white space, or null when nothing is left.</summary>
    public string? ExifCaption => string.IsNullOrWhiteSpace(Caption) ? null : Caption.Trim();
}
