using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

public class OcrLanguagePlanTests
{
    private static readonly OcrLanguagePlan.Pack English = new("en-US", "Latn");
    private static readonly OcrLanguagePlan.Pack German = new("de-DE", "Latn");
    private static readonly OcrLanguagePlan.Pack Turkish = new("tr-TR", "Latn");
    private static readonly OcrLanguagePlan.Pack Japanese = new("ja-JP", "Jpan");

    [Fact]
    public void Chosen_IsTheInstalledPack_WhateverTheCase()
    {
        Assert.Equal("de-DE", OcrLanguagePlan.Chosen("de-de", [English, German]));
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("fr-FR")]
    public void Chosen_IsNothingForAutomaticOrAPackThatIsGone(string? chosen)
    {
        Assert.Null(OcrLanguagePlan.Chosen(chosen, [English, German]));
    }

    [Fact]
    public void Automatic_OnePack_HasNothingToCompare()
    {
        Assert.Equal(["en-US"], OcrLanguagePlan.Automatic("en-US", [English], 5));
        Assert.Empty(OcrLanguagePlan.Automatic(null, [], 5));
    }

    [Fact]
    public void Automatic_StartsWithTheProfileLanguage_ThenTheOtherLatinPacks()
    {
        Assert.Equal(["en-US", "de-DE", "tr-TR"], OcrLanguagePlan.Automatic("en-US", [German, English, Turkish], 5));
    }

    [Fact]
    public void Automatic_LeavesOutOtherScripts_AndKeepsAProfileLanguageOfAnyScript()
    {
        Assert.Equal(["en-US"], OcrLanguagePlan.Automatic("en-US", [English, Japanese], 5));
        Assert.Equal(["ja-JP"], OcrLanguagePlan.Automatic("ja-JP", [English, Japanese], 5));
    }

    [Fact]
    public void Automatic_WithoutAProfilePack_ComparesTheLatinOnes()
    {
        Assert.Equal(["de-DE", "tr-TR"], OcrLanguagePlan.Automatic("fr-FR", [German, Turkish, Japanese], 5));
    }

    [Fact]
    public void Automatic_StopsAtTheLimit()
    {
        Assert.Equal(["en-US", "de-DE"], OcrLanguagePlan.Automatic("en-US", [English, German, Turkish], 2));
    }
}
