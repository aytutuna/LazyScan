using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Asks whether to trust a network scanner's certificate: the first time the app connects to
/// it over HTTPS, or, with a warning, when it has changed since it was trusted. For a new
/// certificate the trust button is the default; for a changed one, Cancel is.
/// </summary>
public partial class CertificateTrustWindow : Window
{
    /// <summary>
    /// <paramref name="byAddress"/> is the "Add scanner by address" dialog, which asks before the
    /// scanner's make and model are read, so its "name" is only the typed address.
    /// </summary>
    public CertificateTrustWindow(EsclCertificateException certificate, bool byAddress)
    {
        InitializeComponent();
        string name = certificate.DeviceName;
        bool changed = certificate.Verdict == EsclTrustVerdict.Changed;
        Title = changed ? Loc.T("Scanner certificate changed") : Loc.T("Trust this scanner?");
        HeaderGlyph.Text = changed ? "" : "";
        HeaderGlyph.SetResourceReference(ForegroundProperty,
            changed ? "SystemFillColorCautionBrush" : "AccentTextFillColorPrimaryBrush");
        HeaderText.Text = (changed, byAddress) switch
        {
            (true, true) => Loc.T("The certificate of the scanner at {0} has changed", certificate.Authority),
            (true, false) => Loc.T("The certificate of {0} has changed", name),
            (false, true) => Loc.T("Trust the scanner at {0}?", certificate.Authority),
            _ => Loc.T("Trust {0}?", name),
        };

        string different = certificate.Previous?.Trusted is { } date
            ? Loc.T("The scanner identified itself with a different certificate from the one you trusted on {0}.", date.LocalDateTime.ToString("d", CultureInfo.CurrentCulture))
            : Loc.T("The scanner identified itself with a different certificate from the one you trusted.");
        ExplanationText.Text = changed
            ? different + " " + Loc.T("A firmware update or a reset of the scanner can change it, but so can another device on the network that pretends to be your scanner.")
            : Loc.T("This scanner offers an encrypted connection and identifies itself with a certificate it made itself. Windows cannot vouch for such certificates; that is normal for scanners.");
        AdviceText.Text = changed
            ? Loc.T("Trust the new certificate only if you know why it changed. Otherwise choose Cancel and check the scanner.")
            : Loc.T("Trust it if this is your scanner. Lazy Scan remembers the certificate and warns you if it ever changes.");

        ScannerText.Text = name;
        AddressText.Text = certificate.Authority;
        if (byAddress)
        {
            ScannerLabel.Visibility = Visibility.Collapsed;
            ScannerText.Visibility = Visibility.Collapsed;
        }
        if (certificate.Subject.Length > 0)
        {
            SubjectText.Text = certificate.Subject;
        }
        else
        {
            SubjectLabel.Visibility = Visibility.Collapsed;
            SubjectText.Visibility = Visibility.Collapsed;
        }
        FingerprintLabel.Text = changed ? Loc.T("New fingerprint") : Loc.T("Fingerprint");
        FingerprintBox.Text = EsclCertificates.Format(certificate.Fingerprint, bytesPerLine: 16);
        AutomationProperties.SetHelpText(FingerprintBox, Loc.T("SHA-256 of the certificate's public key"));
        if (changed && certificate.Previous is { } previous)
        {
            PreviousLabel.Visibility = Visibility.Visible;
            PreviousBox.Visibility = Visibility.Visible;
            PreviousBox.Text = EsclCertificates.Format(previous.Fingerprint, bytesPerLine: 16);
        }

        TrustButton.Content = changed ? Loc.T("Trust the new certificate") : byAddress ? Loc.T("Trust and add") : Loc.T("Trust and connect");
        var defaultChoice = changed ? CancelButton : TrustButton;
        defaultChoice.IsDefault = true;
        defaultChoice.SetResourceReference(StyleProperty, "AccentButtonStyle");
        Loaded += (_, _) => defaultChoice.Focus();
    }

    private void Trust_Click(object sender, RoutedEventArgs e) => DialogResult = true;
}
