//! Lazy Scan's PDFs through the shared writers in LazyKit, against the values its Swift and C# tests pin: the same
//! bytes, by hash, so the apps' own output and this one cannot drift apart unseen.

use lazy_pdf_filters::g4::{encode_g4, stride};
use lazy_pdf_write::{Conformance, Date, G4Image, Image, OcrLine, Options, PageInput, Rect, make};
use sha2::{Digest, Sha256};

fn jpeg() -> Vec<u8> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../testdata/output");
    let bytes = std::fs::read(dir.join("jpeg-tiny-gray.jpg")).unwrap();
    let sums = std::fs::read_to_string(dir.join("SHA256SUMS")).unwrap();
    let hash: String = Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert!(sums.contains(&hash));
    bytes
}

fn sha(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect()
}

fn checkerboard() -> Vec<u8> {
    let stride = stride(37);
    let mut packed = vec![0xFFu8; stride * 23];
    for y in 0..23 {
        for x in 0..37 {
            if (x + y) & 1 == 0 {
                packed[y * stride + (x >> 3)] &= !(0x80 >> (x & 7));
            }
        }
    }
    packed
}

fn options(title: &str, conformance: Conformance, date: Date, id: [u8; 16]) -> Options {
    let mut options = Options::new("Lazy Scan");
    options.conformance = conformance;
    options.title = Some(title.to_string());
    options.date = Some(date);
    options.document_id = Some(id);
    options
}

fn date() -> Date {
    Date {
        year: 2026,
        month: 10,
        day: 19,
        hour: 21,
        minute: 30,
        second: 5,
        offset_minutes: 180,
    }
}

fn id() -> [u8; 16] {
    std::array::from_fn(|i| 0xA0 + i as u8)
}

fn line(text: &str, x: f64, y: f64, w: f64, h: f64) -> OcrLine {
    OcrLine {
        text: text.to_string(),
        bounds: Rect::new(x, y, w, h),
        words: vec![],
    }
}

fn letter_page(lines: Vec<OcrLine>) -> PageInput {
    PageInput {
        image: Image::Jpeg(jpeg()),
        pixel_width: 2550,
        pixel_height: 3300,
        dpi: 300,
        ocr_lines: lines,
    }
}

#[test]
fn the_checkerboard_g4_data_is_pinned() {
    let g4 = encode_g4(&checkerboard(), 37, 23).unwrap();
    assert_eq!(g4.len(), 335);
    assert_eq!(
        sha(&g4),
        "E8A046161C50C7D37EA4A44DC4A9F1DCE909940D388C27C8CCECCBE798DC43EC"
    );
}

#[test]
fn a_plain_pdf_with_a_turkish_line_is_the_pinned_file() {
    let text = line(
        "\u{c7}a\u{11f}r\u{131} I\u{15f}\u{131}k \u{130}zmir'de \u{f6}\u{11f}\u{fc}n \u{15f}\u{fc}pheli",
        0.1,
        0.8,
        0.6,
        0.04,
    );
    let options = options(
        "Tapu belgesi \u{2014} \u{c7}a\u{11f}r\u{131}",
        Conformance::Standard,
        date(),
        id(),
    );
    let pdf = make(&[letter_page(vec![text]), letter_page(vec![])], &options).unwrap();
    assert_eq!(pdf.len(), 7186);
    assert_eq!(
        sha(&pdf),
        "79CEAD5058F5ECA74778937FF13CEBC8BBC2DD19936EB4607F8404EE1A6A8577"
    );
}

#[test]
fn the_archival_pdf_is_the_pinned_file() {
    let text = line(
        "\u{c7}a\u{11f}r\u{131} I\u{15f}\u{131}k \u{130}zmir'de \u{f6}\u{11f}\u{fc}n \u{15f}\u{fc}pheli",
        0.1,
        0.8,
        0.6,
        0.04,
    );
    let options = options(
        "Tapu belgesi \u{2014} \u{c7}a\u{11f}r\u{131}",
        Conformance::PdfA2b,
        date(),
        id(),
    );
    let pdf = make(&[letter_page(vec![text])], &options).unwrap();
    assert_eq!(pdf.len(), 8451);
    assert_eq!(
        sha(&pdf),
        "4D1350CC42A4A7158A9EB3CCEC9E381DDD085B4E79895BFBA7C0099363158625"
    );
}

#[test]
fn a_g4_page_and_a_jpeg_page_are_the_pinned_file() {
    let g4 = G4Image {
        data: encode_g4(&checkerboard(), 37, 23).unwrap(),
        width: 37,
        height: 23,
    };
    let black_and_white = PageInput {
        image: Image::G4(g4),
        pixel_width: 37,
        pixel_height: 23,
        dpi: 100,
        ocr_lines: vec![line(
            "Siyah beyaz \u{2014} \u{c7}a\u{11f}r\u{131}",
            0.1,
            0.5,
            0.8,
            0.2,
        )],
    };
    let color = PageInput {
        image: Image::Jpeg(jpeg()),
        pixel_width: 850,
        pixel_height: 1100,
        dpi: 100,
        ocr_lines: vec![],
    };
    let options = options("Siyah beyaz", Conformance::Standard, date(), id());
    let pdf = make(&[black_and_white, color], &options).unwrap();
    assert_eq!(pdf.len(), 7154);
    assert_eq!(
        sha(&pdf),
        "C9CB40F60D03C4B573EA256FA926136D60F992022CC05FEB7C978B1147E8F55B"
    );
}
