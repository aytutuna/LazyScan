using LazyScan.Core;

namespace LazyScan.App;

/// <summary>What the photo review's Date taken and Caption fields mean for the saved files.</summary>
public static class PhotoDetailsEntry
{
    /// <summary>The typed year when it is four digits from 1800 to <paramref name="currentYear"/>.</summary>
    public static int? Year(string text, int currentYear) =>
        text.Length == 4 && int.TryParse(text, out int year) && year >= 1800 && year <= currentYear ? year : null;

    /// <summary>Text is typed that is not a year, or a month or day is chosen with no year.</summary>
    public static bool YearProblem(string text, int month, int day, int currentYear) =>
        text.Length == 0 ? month != 0 || day != 0 : Year(text, currentYear) is null;

    /// <summary>How many days the Day list offers: 31 until a month is chosen.</summary>
    public static int DaysInMonth(int? year, int month) =>
        month is >= 1 and <= 12 ? DateTime.DaysInMonth(year ?? 2000, month) : 31;

    /// <summary>Month and day are 0 when not chosen. A date without a valid year is left out.</summary>
    public static PhotoDetails Details(string yearText, int month, int day, string caption, int currentYear)
    {
        if (Year(yearText, currentYear) is not { } year) return new PhotoDetails(Caption: caption);
        return new PhotoDetails(year, month == 0 ? null : month, month == 0 || day == 0 ? null : day, caption);
    }
}
