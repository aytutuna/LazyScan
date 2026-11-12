# Microsoft Store listing

Text for Partner Center. The limits are the Store's: name 100 characters, short description 100, description 10000, each feature 200, up to 7 search terms of 30 characters. The package is `Package.appxmanifest` in this folder, built by `scripts/make_msix.ps1` on the PC. Store ID 9N7TNX03ZBZ8, identity name `Aytu.LazyScan`.

## English

**Name:** Lazy Scan

**Short description:** Scan documents and photos into searchable PDFs and straightened files. Free, no account.

**Description:**

Lazy Scan scans paperwork and photos with the scanner you already have. It is free, it has no account, no ads and no analytics, and your scans stay on your PC.

Pages go into a queue and come out as one searchable PDF, or as JPEG, PNG or TIFF files, or as a Word document or text file made from the recognized text. Lay several photos on the glass, press Scan once, and the app finds each print, straightens it, cuts it out and lets you check the results before anything is saved. Fade, tilt and crooked edges can be fixed afterwards with sliders and a crop editor.

It works with the scanners Windows already knows: drivers that use WIA or TWAIN, including older scanners whose driver is 32-bit only, and network scanners that speak AirScan (eSCL) with no driver at all. There is a built-in Demo Scanner, so you can try everything without a scanner.

Each job has its own way through the app: letters and contracts, a stack in the document feeder (both sides, blank pages skipped), receipts, ID cards at real size, books and magazines, old faded photos, and copies sent straight to a printer. PDFs can be saved as PDF/A for long-term keeping, protected with an AES-256 password, or added to the end of a PDF you already have.

Pair your phone once with a QR code, and pages scanned with Lazy Scan on the phone arrive on the PC over your own network, encrypted, with no account and no server.

Lazy Scan is free, and its source is available under PolyForm Noncommercial 1.0.0. It is a sister app of Lazy Print and Lazy PDF.

Lazy Scan is new. If your scanner does not show up or a scan does not come out as it should, the app has a Troubleshoot button, and you can write to support@alazy.app.

**Features:**

- Scan with WIA and TWAIN scanners, including 32-bit TWAIN drivers, and with network scanners over AirScan (eSCL).
- Turn pages into one searchable PDF, or save JPEG, PNG or TIFF files, a Word document or a text file.
- Lay several photos on the glass and scan once: each is found, straightened and saved on its own.
- Document feeder support with two-sided scanning, blank pages skipped and paper sizes from A4 to Legal.
- Tasks for receipts, ID cards, books and magazines, old photos and copies to a printer.
- Fix brightness, contrast, color and sharpness, restore faded prints and crop by hand.
- Save PDF/A files, protect a PDF with a password, or add pages to a PDF you already have.
- Take pages from your phone over your own network, encrypted, and open Lazy Scan documents.
- Try it with the built-in Demo Scanner when no scanner is connected.

**Search terms:** scanner, scan to pdf, photo scanner, document scanner, ocr, twain, wia

**What's new in this version:** First release.

**Category:** Productivity.

**Support contact:** support@alazy.app

**Website:** https://alazy.app/scan/

**Privacy policy URL:** https://alazy.app/scan/privacy.html

**Screenshots:** none in this folder yet. Take them from a neutral folder with the Demo Scanner or public-domain scans, at 1920x1080, light, so that no local path or personal file name shows.

**Store logos:** `Listing/Logo-300x300.png` (1:1 app tile icon), `Listing/Box-1080x1080.png` (1:1 box art) and `Listing/Poster-720x1080.png` (2:3 poster art). Drawn by `scripts/make_store_assets.py`.

## Age rating

The IARC questionnaire in Partner Center. The rating this should give is 3+ (PEGI 3, ESRB Everyone); the questionnaire result is the Store's, not ours.

| Question | Answer |
|---|---|
| Violence, fear, sexual content, bad language, drugs, gambling | No |
| Users can talk to or share with each other | No |
| Shares the user's location | No |
| Shares personal information with others | No |
| Purchases, ads | No |
| Unrestricted web access | No |
| Collects or sends diagnostics | No |

## Privacy answers

- **Collects personal data:** No. Nothing is sent to the developer or to a server run for the app.
- **Network use:** Only on the local network: finding and talking to network scanners, and the listener for a paired phone, which runs only on networks the user trusts and only while a phone is paired or a pairing code is shown.
- **Account needed:** No.
- **Uses encryption:** Yes, for the pairing with a phone (TLS with a pinned certificate) and for PDF passwords (AES-256), through .NET and the Windows libraries.

## Restricted capability

The package declares `runFullTrust` and nothing else. Partner Center asks for a reason:

> Lazy Scan is a desktop app built with .NET and WPF. It talks to scanners through their WIA and TWAIN drivers, which load into the app's process, and starts a 32-bit helper process for drivers that exist only as 32-bit. It runs a local listener for a paired phone, and reads and saves the files the user picks anywhere on the PC. It cannot work inside the app sandbox, and it has no other capability.

## Notes for certification

> No account or sign-in is needed. To try the app without a scanner, pick Demo Scanner in the scanner list on the left, then press Scan: it produces sample pages and photos. The app listens for a phone only after a phone is paired, so nothing needs a second device. The package carries a 32-bit helper (Twain\LazyScan.TwainHelper.exe) that is started only when a scanner has a 32-bit TWAIN driver.

## What only the owner can do in Partner Center

1. Open the existing Lazy Scan product (Store ID 9N7TNX03ZBZ8) and check Product identity: the name `Aytu.LazyScan`, the publisher `CN=54BA56B9-1B6C-4B6E-886D-07694CF02BF5` and the display name `Aytu`.
2. Run `pwsh scripts/make_msix.ps1 -Out <folder> -IdentityName Aytu.LazyScan -Publisher 'CN=54BA56B9-1B6C-4B6E-886D-07694CF02BF5' -PublisherDisplayName Aytu` on the PC and upload the `LazyScan_1.0.0.msixupload` it writes.
3. Pricing: Free. Properties: category Productivity, the privacy policy URL and support contact above, system requirements Windows 10 version 2004 or later, x64 and arm64.
4. Age ratings: answer the questionnaire as in the table above.
5. Give the `runFullTrust` reason above when asked, paste the listing text and logos, add the certification notes.
6. Submit, set to publish manually after certification, so nothing goes live before a test on a real scanner.
