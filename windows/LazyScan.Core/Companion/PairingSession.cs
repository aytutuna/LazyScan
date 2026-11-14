using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Companion/PairingSession.swift: the same lifetime, attempt
// limit and answers.

/// <summary>Where a pairing session is.</summary>
public enum PairingSessionState
{
    /// <summary>Waiting for a phone to present the token.</summary>
    Open,
    /// <summary>A phone presented the token; it cannot be used again.</summary>
    Used,
    /// <summary>Its five minutes are over.</summary>
    Expired,
    /// <summary>Closed by the desktop, or after too many wrong tokens.</summary>
    Closed,
}

/// <summary>The answer to a token presented to a pairing session.</summary>
public enum PairingRedeemResult
{
    Accepted,
    WrongToken,
    Expired,
    AlreadyUsed,
    Closed,
}

/// <summary>The answer to a short code presented to a pairing session.</summary>
public enum PairingCodeResult
{
    /// <summary>The right code while the session is open; the session stays open for the pairing itself.</summary>
    Right,
    Wrong,
    /// <summary>The wrong code that was the last one allowed: the session is closed.</summary>
    TooManyAttempts,
    Expired,
    AlreadyUsed,
    Closed,
}

/// <summary>
/// One pairing window on the desktop: a random 128-bit token shown in the QR code, good for one
/// pairing within <see cref="Lifetime"/>. Tokens are compared in constant time. Wrong ones are
/// counted but do not close the session, so another device cannot shut the code; the router limits
/// each address instead. The same session has a 6-digit code for a phone that cannot scan: it fetches
/// the pairing text with it, and <see cref="MaxCodeAttempts"/> wrong codes close the session, counted
/// for the session and not per address (a code has a million values, a token has 2^128). The clock is
/// passed in, so tests control it. Safe to use from any thread.
/// </summary>
public sealed class PairingSession
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);
    public const int CodeDigitCount = 6;
    public const int MaxCodeAttempts = 5;

    private readonly object _gate = new();
    private readonly byte[] _token;
    private PairingSessionState _state = PairingSessionState.Open;
    private int _failedAttempts;
    private readonly byte[] _code;
    private int _failedCodes;

    /// <param name="opened">When the session opens; it expires <see cref="Lifetime"/> later.</param>
    /// <param name="token">The token's 16 bytes; random when null (tests pass their own).</param>
    /// <param name="code">The 6 digits of the short code; random when null.</param>
    public PairingSession(DateTimeOffset opened, byte[]? token = null, string? code = null)
    {
        if (token is not null && token.Length != PairingUri.TokenByteCount)
        {
            throw new ArgumentException("A pairing token has 16 bytes.", nameof(token));
        }
        code ??= RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", CultureInfo.InvariantCulture);
        if (code.Length != CodeDigitCount || !code.All(c => c is >= '0' and <= '9'))
        {
            throw new ArgumentException("A pairing code has 6 digits.", nameof(code));
        }
        _token = token ?? RandomNumberGenerator.GetBytes(PairingUri.TokenByteCount);
        _code = Encoding.ASCII.GetBytes(code);
        Code = code;
        Token = CompanionProtocol.EncodeBase64Url(_token);
        Opened = opened;
        Expires = opened + Lifetime;
    }

    /// <summary>The token as the pairing code carries it (base64url, 22 characters).</summary>
    public string Token { get; }

    /// <summary>The short code as the desktop shows it, grouped in threes through <see cref="FormattedCode"/>.</summary>
    public string Code { get; }

    /// <summary>The code in two groups of three ("482 913").</summary>
    public string FormattedCode => Code[..3] + " " + Code[3..];

    public DateTimeOffset Opened { get; }

    public DateTimeOffset Expires { get; }

    public int FailedAttempts
    {
        get
        {
            lock (_gate) return _failedAttempts;
        }
    }

    public int FailedCodes
    {
        get
        {
            lock (_gate) return _failedCodes;
        }
    }

    /// <summary>Where the session is at <paramref name="now"/>.</summary>
    public PairingSessionState StateAt(DateTimeOffset now)
    {
        lock (_gate)
        {
            return _state == PairingSessionState.Open && now >= Expires ? PairingSessionState.Expired : _state;
        }
    }

    /// <summary>How long the session stays open after <paramref name="now"/>; zero once it is not open.</summary>
    public TimeSpan Remaining(DateTimeOffset now) =>
        StateAt(now) == PairingSessionState.Open ? Expires - now : TimeSpan.Zero;

    /// <summary>
    /// Presents <paramref name="token"/> at <paramref name="now"/>. The right token while the
    /// session is open is accepted once; a wrong one is counted and the session stays open.
    /// </summary>
    public PairingRedeemResult Redeem(string? token, DateTimeOffset now)
    {
        lock (_gate)
        {
            switch (_state)
            {
                case PairingSessionState.Used:
                    return PairingRedeemResult.AlreadyUsed;
                case PairingSessionState.Closed:
                    return PairingRedeemResult.Closed;
            }
            if (now >= Expires)
            {
                _state = PairingSessionState.Expired;
                return PairingRedeemResult.Expired;
            }
            if (_state == PairingSessionState.Expired) return PairingRedeemResult.Expired;
            byte[]? presented = CompanionProtocol.DecodeBase64Url(token);
            bool matches = presented is { Length: PairingUri.TokenByteCount }
                           && CryptographicOperations.FixedTimeEquals(presented, _token);
            if (!matches)
            {
                _failedAttempts++;
                return PairingRedeemResult.WrongToken;
            }
            _state = PairingSessionState.Used;
            return PairingRedeemResult.Accepted;
        }
    }

    /// <summary>
    /// Presents the short code at <paramref name="now"/>; spaces are ignored. The right code leaves the
    /// session open, since the phone still has to pair with the token it gets. A wrong one is counted,
    /// and the last one allowed closes the session.
    /// </summary>
    public PairingCodeResult CheckCode(string? presented, DateTimeOffset now)
    {
        lock (_gate)
        {
            switch (_state)
            {
                case PairingSessionState.Used:
                    return PairingCodeResult.AlreadyUsed;
                case PairingSessionState.Closed:
                    return PairingCodeResult.Closed;
            }
            if (now >= Expires)
            {
                _state = PairingSessionState.Expired;
                return PairingCodeResult.Expired;
            }
            if (_state == PairingSessionState.Expired) return PairingCodeResult.Expired;
            byte[] bytes = Encoding.UTF8.GetBytes((presented ?? "").Replace(" ", ""));
            if (bytes.Length == _code.Length && CryptographicOperations.FixedTimeEquals(bytes, _code))
            {
                return PairingCodeResult.Right;
            }
            _failedCodes++;
            if (_failedCodes >= MaxCodeAttempts)
            {
                _state = PairingSessionState.Closed;
                return PairingCodeResult.TooManyAttempts;
            }
            return PairingCodeResult.Wrong;
        }
    }

    /// <summary>Closes the session: no token is accepted any more.</summary>
    public void Close()
    {
        lock (_gate)
        {
            if (_state == PairingSessionState.Open) _state = PairingSessionState.Closed;
        }
    }
}
