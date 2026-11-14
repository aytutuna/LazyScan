using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Mirrored by Tests/LazyScanTests/PairingSessionTests.swift (same clock steps, same answers).

public class PairingSessionTests
{
    private static readonly DateTimeOffset Opened = new(2026, 10, 20, 8, 30, 0, TimeSpan.Zero);

    private static PairingSession Session() => new(Opened, CompanionVectors.Token);

    [Fact]
    public void Token_IsTheGivenBytesOrRandom()
    {
        Assert.Equal(CompanionVectors.TokenText, Session().Token);
        var a = new PairingSession(Opened);
        var b = new PairingSession(Opened);
        Assert.NotEqual(a.Token, b.Token);
        Assert.Equal(16, CompanionProtocol.DecodeBase64Url(a.Token)!.Length);
        Assert.Throws<ArgumentException>(() => new PairingSession(Opened, new byte[15]));
    }

    [Fact]
    public void RightToken_IsAcceptedOnce()
    {
        var session = Session();
        Assert.Equal(PairingSessionState.Open, session.StateAt(Opened));
        Assert.Equal(PairingRedeemResult.Accepted, session.Redeem(CompanionVectors.TokenText, Opened.AddMinutes(1)));
        Assert.Equal(PairingSessionState.Used, session.StateAt(Opened.AddMinutes(1)));
        Assert.Equal(PairingRedeemResult.AlreadyUsed, session.Redeem(CompanionVectors.TokenText, Opened.AddMinutes(2)));
        Assert.Equal(PairingRedeemResult.AlreadyUsed, session.Redeem("wrong", Opened.AddMinutes(2)));
        Assert.Equal(TimeSpan.Zero, session.Remaining(Opened.AddMinutes(2)));
    }

    [Fact]
    public void Token_ExpiresAfterFiveMinutes()
    {
        var session = Session();
        Assert.Equal(TimeSpan.FromMinutes(5), session.Remaining(Opened));
        Assert.Equal(TimeSpan.FromSeconds(1), session.Remaining(Opened.AddMinutes(5).AddSeconds(-1)));
        Assert.Equal(PairingSessionState.Expired, session.StateAt(Opened.AddMinutes(5)));
        Assert.Equal(PairingRedeemResult.Expired, session.Redeem(CompanionVectors.TokenText, Opened.AddMinutes(5)));
        Assert.Equal(PairingRedeemResult.Expired, session.Redeem(CompanionVectors.TokenText, Opened.AddMinutes(1)));
        Assert.Equal(PairingRedeemResult.Accepted,
                     Session().Redeem(CompanionVectors.TokenText, Opened.AddMinutes(5).AddMilliseconds(-1)));
    }

    [Fact]
    public void WrongTokens_DoNotCloseTheSession()
    {
        var session = Session();
        string almost = CompanionVectors.TokenText[..^1] + "x";
        for (int i = 1; i <= 6; i++)
        {
            Assert.Equal(PairingRedeemResult.WrongToken, session.Redeem(almost, Opened));
            Assert.Equal(i, session.FailedAttempts);
            Assert.Equal(PairingSessionState.Open, session.StateAt(Opened));
        }
        Assert.Equal(PairingRedeemResult.Accepted, session.Redeem(CompanionVectors.TokenText, Opened));
    }

    [Fact]
    public void MalformedTokens_CountAsWrong()
    {
        var session = Session();
        Assert.Equal(PairingRedeemResult.WrongToken, session.Redeem("", Opened));
        Assert.Equal(PairingRedeemResult.WrongToken, session.Redeem("AAECAwQFBgcICQoLDA0ODw==", Opened));
        Assert.Equal(PairingRedeemResult.WrongToken, session.Redeem(CompanionVectors.TokenText + "AA", Opened));
        Assert.Equal(3, session.FailedAttempts);
        Assert.Equal(PairingRedeemResult.Accepted, session.Redeem(CompanionVectors.TokenText, Opened));
    }

    [Fact]
    public void Close_RefusesTheToken()
    {
        var session = Session();
        session.Close();
        Assert.Equal(PairingSessionState.Closed, session.StateAt(Opened));
        Assert.Equal(PairingRedeemResult.Closed, session.Redeem(CompanionVectors.TokenText, Opened));
        var used = Session();
        used.Redeem(CompanionVectors.TokenText, Opened);
        used.Close();
        Assert.Equal(PairingSessionState.Used, used.StateAt(Opened));
    }

    [Fact]
    public void Code_IsTheGivenDigitsOrRandom()
    {
        var session = new PairingSession(Opened, CompanionVectors.Token, "482913");
        Assert.Equal("482913", session.Code);
        Assert.Equal("482 913", session.FormattedCode);
        var random = new PairingSession(Opened);
        Assert.Equal(6, random.Code.Length);
        Assert.All(random.Code, c => Assert.InRange(c, '0', '9'));
        Assert.Equal("000 042", new PairingSession(Opened, code: "000042").FormattedCode);
        foreach (string bad in new[] { "", "12345", "1234567", "12a456", "12 456" })
        {
            Assert.Throws<ArgumentException>(() => new PairingSession(Opened, code: bad));
        }
    }

    [Fact]
    public void RightCode_KeepsTheSessionOpenForTheToken()
    {
        var session = new PairingSession(Opened, CompanionVectors.Token, "482913");
        Assert.Equal(PairingCodeResult.Right, session.CheckCode("482913", Opened.AddMinutes(1)));
        Assert.Equal(PairingCodeResult.Right, session.CheckCode("482 913", Opened.AddMinutes(2)));
        Assert.Equal(PairingSessionState.Open, session.StateAt(Opened.AddMinutes(2)));
        Assert.Equal(0, session.FailedCodes);
        Assert.Equal(PairingRedeemResult.Accepted, session.Redeem(CompanionVectors.TokenText, Opened.AddMinutes(3)));
        Assert.Equal(PairingCodeResult.AlreadyUsed, session.CheckCode("482913", Opened.AddMinutes(3)));
    }

    [Fact]
    public void WrongCodes_CloseTheSessionAtTheFifth()
    {
        var session = new PairingSession(Opened, CompanionVectors.Token, "482913");
        for (int i = 1; i <= 4; i++)
        {
            Assert.Equal(PairingCodeResult.Wrong, session.CheckCode("482914", Opened));
            Assert.Equal(i, session.FailedCodes);
            Assert.Equal(PairingSessionState.Open, session.StateAt(Opened));
        }
        Assert.Equal(PairingCodeResult.TooManyAttempts, session.CheckCode("000000", Opened));
        Assert.Equal(PairingSessionState.Closed, session.StateAt(Opened));
        Assert.Equal(PairingCodeResult.Closed, session.CheckCode("482913", Opened));
        Assert.Equal(PairingRedeemResult.Closed, session.Redeem(CompanionVectors.TokenText, Opened));
    }

    [Fact]
    public void RightCode_DoesNotWipeTheWrongOnes()
    {
        var session = new PairingSession(Opened, code: "482913");
        for (int i = 0; i < 4; i++)
        {
            Assert.Equal(PairingCodeResult.Wrong, session.CheckCode("111111", Opened));
        }
        Assert.Equal(PairingCodeResult.Right, session.CheckCode("482913", Opened));
        Assert.Equal(PairingCodeResult.TooManyAttempts, session.CheckCode("111111", Opened));
    }

    [Fact]
    public void MalformedCodes_CountAsWrong()
    {
        var session = new PairingSession(Opened, code: "482913");
        Assert.Equal(PairingCodeResult.Wrong, session.CheckCode(null, Opened));
        Assert.Equal(PairingCodeResult.Wrong, session.CheckCode("", Opened));
        Assert.Equal(PairingCodeResult.Wrong, session.CheckCode("48291", Opened));
        Assert.Equal(PairingCodeResult.Wrong, session.CheckCode("4829133", Opened));
        Assert.Equal(4, session.FailedCodes);
        Assert.Equal(0, session.FailedAttempts);
    }

    [Fact]
    public void Code_ExpiresWithTheSession()
    {
        var session = new PairingSession(Opened, code: "482913");
        Assert.Equal(PairingCodeResult.Expired, session.CheckCode("482913", Opened.AddMinutes(5)));
        Assert.Equal(PairingCodeResult.Expired, session.CheckCode("482913", Opened.AddMinutes(1)));
        Assert.Equal(0, session.FailedCodes);
    }
}
