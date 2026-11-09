App Store Connect notes (paste from here)

Name: Lazy Scan

Subtitle (30): Scan pages, IDs and photos
  = 26 chars

Promotional text (170):
Point the camera at a page: it finds the edges, straightens it and queues it. Save as PDF, JPEG or TIFF. No account; nothing leaves your phone unless you share it.
  = 163 chars

Description:
Lazy Scan is a document scanner. Point the camera at a page and it finds the edges, straightens the page and adds it to your queue. If the corners are off, drag them yourself.

Choose what you are scanning: Photo, Document, ID card or Book. The app sets itself up for it. Lay several receipts or prints on the table and they are split automatically.

Your pages sit in a grid. Open one to rotate, crop or filter it, delete the ones you don't want, add more. Save them as a PDF, with a password if you like, or as JPEG or TIFF images, and share them anywhere.

If you have a printer-scanner on your Wi-Fi (AirScan / eSCL), the app can scan from it instead of the camera. Pair the phone with Lazy Scan on your Mac or Windows PC and send pages straight to it.

There is no account, no ads and no analytics. Pages are processed on the phone and stay there unless you share them.

Keywords (100, comma separated, no spaces):
scanner,scan,pdf,document,receipt,id card,airscan,escl,tiff,jpeg,book,paper,page,camera
  = 87 chars

Primary category: Productivity
Age rating: 4+ (answer No to everything)
App Privacy: Data Not Collected
Copyright: 2026 Aytu Tuna
Support URL: https://alazy.app/scan/
Privacy policy URL: https://alazy.app/scan/privacy.html
Price: free (no in-app purchases)

Export compliance: Info.plist sets ITSAppUsesNonExemptEncryption to false, so App Store Connect
does not ask per build. If the questionnaire ever comes up: uses encryption yes, only standard
algorithms from Apple's frameworks (AES-256 PDF passwords via CommonCrypto, AES-GCM companion
packages via CryptoKit, TLS), so exempt, nothing to upload.

App Review notes:
Nothing to sign in to; there are no accounts.
Camera mode (the first screen) works on its own: photograph any sheet of paper, then Save.
Printer mode (printer icon, top right) needs an AirScan (eSCL) printer-scanner on the same Wi-Fi. We have no way to supply one, so the reviewer will see an empty scanner list; the Local Network prompt appears the first time the list opens.
Options > My computer pairs with the Lazy Scan desktop app on a Mac or Windows PC. It is optional and needs that PC.

macOS version (same record, its own listing)

Promotional text (170):
Scan from any scanner your Mac sees, USB or network. Searchable PDFs, photos found and straightened, blank pages skipped. No account, and your scans stay on your Mac.

Description:
Lazy Scan scans from the scanners your Mac already knows: USB, network and shared scanners, from the glass or the document feeder, one side or both.

Start with what you are scanning: a document to PDF, a stack from the feeder, photos, old photos, an ID card, receipts, a book or magazine, a document to Word, or a photocopy to your printer. The app sets itself up for it, and every setting is in the side panel if you want to change it.

Lay several photos on the glass and each one is found, straightened and saved on its own. Blank pages are skipped, and a long stack can be split into separate documents at a blank sheet, a separator sheet or a barcode.

Save as a searchable PDF, as PDF/A for archiving, with a password, or as JPEG, PNG, TIFF, text or Word. Add new pages to the end of a PDF you already have. Files are named with the date and a counter.

Pair your iPhone with Lazy Scan on the phone and send pages from its camera straight to the Mac over your Wi-Fi, encrypted, with no account. If you have Lazy Print, hand your scans to it in one click.

There is no account, no ads and no analytics. Scans are made and kept on your Mac.

Keywords (100):
scanner,scan,pdf,ocr,document,photo,receipt,id card,feeder,duplex,flatbed,tiff,image capture,airscan

App Review notes (macOS):
Nothing to sign in to; there are no accounts.
Without a scanner the app selects Demo Scanner, which makes sample pages so every scan kind can be tried: pick a kind on the start screen, then Scan. Import photos of documents... in the side panel also brings in images from disk.
Real scanners are reached only through ImageCaptureCore, as macOS lists them (USB, Bonjour network and shared scanners).
Entitlements: device.usb for USB scanners through ImageCaptureCore; network.client to talk to network scanners; network.server for the optional phone link, which listens on the local network for a paired iPhone running Lazy Scan; files.downloads.read-write for the default save folder, Downloads/Lazy Scan; files.user-selected.read-write and files.bookmarks.app-scope for a save folder, cloud folder or PDF the user picks; print for the Photocopy kind and printing scans.
The phone link is optional and needs the iPhone app on the same network.
