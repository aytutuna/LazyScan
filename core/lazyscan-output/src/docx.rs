//! The Word document of a save: the recognized text of the pages, one Word paragraph per paragraph found, each page after
//! the first starting on a new page. The smallest package Word and LibreOffice open: "[Content_Types].xml", "_rels/.rels"
//! and "word/document.xml", stored in a zip. No styles part, so the text takes the reader's default font. The paper is the
//! first page's size, with one-inch margins (less on a page under 8 inches).
//!
//! With page pictures each page starts with its picture, an inline DrawingML picture in a centred paragraph of its own, at
//! the page's real size or shrunk to fit inside the margins with its shape kept, and its text follows: a full page's
//! picture fills the paper and its text starts on the next one. The pictures are "word/media/image1.jpeg" (or .png) and on,
//! linked from "word/_rels/document.xml.rels". Without pictures the package is byte for byte the text-only one.
//!
//! The paragraphs are given: the reading order of the recognized lines is another job.

use std::borrow::Cow;

use lazy_office_zip::{Error as ZipError, Writer};

/// One inch in twentieths of a point, Word's unit for page sizes.
pub const TWIPS_PER_INCH: i32 = 1440;
/// Word's smallest and largest paper side, in twips (0.1 in and 22 in).
pub const MIN_PAGE_TWIPS: i32 = 144;
pub const MAX_PAGE_TWIPS: i32 = 31680;
/// DrawingML's unit: English Metric Units per point and per twip (914,400 per inch).
pub const EMU_PER_POINT: i64 = 12700;
pub const EMU_PER_TWIP: i64 = 635;
/// The largest Word document a save writes, in bytes (2 GB): within what a zip without zip64 addresses.
pub const MAX_PACKAGE_BYTES: u64 = 2_000_000_000;

const IMAGE_RELATIONSHIP_TYPE: &str =
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image";

const CONTENT_TYPES_XML: &str = concat!(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n",
    "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">",
    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
    "<Default Extension=\"xml\" ContentType=\"application/xml\"/>",
    "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>",
    "</Types>"
);

const RELATIONSHIPS_XML: &str = concat!(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n",
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>",
    "</Relationships>"
);

/// The namespaces a document with pictures declares on its root, after w.
const PICTURE_NAMESPACES: &str = concat!(
    " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"",
    " xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\"",
    " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"",
    " xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\""
);

/// The largest page side taken as it is, in EMU (over 100,000 inches), so that the products in `picture_size_emu` stay
/// within 64 bits.
const MAX_EMU: f64 = 1e11;

/// One paragraph of recognized text; `rtl` says it is written right to left (more than half of its letters are from a
/// right-to-left script).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Paragraph {
    pub text: String,
    pub rtl: bool,
}

/// A page of the document: its size in points (zero or less for an unknown size) and its paragraphs.
#[derive(Clone, Debug, PartialEq)]
pub struct Page {
    pub width_points: f64,
    pub height_points: f64,
    pub paragraphs: Vec<Paragraph>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PictureFormat {
    /// Color and gray pages, as the PDF size stores them in a PDF.
    Jpeg,
    /// Black and white pages, one bit per pixel and lossless.
    Png,
}

impl PictureFormat {
    pub fn extension(self) -> &'static str {
        match self {
            PictureFormat::Jpeg => "jpeg",
            PictureFormat::Png => "png",
        }
    }

    pub fn content_type(self) -> &'static str {
        match self {
            PictureFormat::Jpeg => "image/jpeg",
            PictureFormat::Png => "image/png",
        }
    }
}

/// The picture of a page as it goes into a Word document: its encoded bytes and their format.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Picture {
    pub data: Vec<u8>,
    pub format: PictureFormat,
}

/// The file name of the `number`th picture (from 1) in "word/media": "image1.jpeg".
pub fn media_name(number: usize, format: PictureFormat) -> String {
    format!("image{number}.{}", format.extension())
}

/// The paper of the document in twips: the page's size in points x 20, each side kept within the limits; US Letter
/// without a page.
pub fn page_size_twips(page: Option<&Page>) -> (i32, i32) {
    match page {
        Some(p) if p.width_points > 0.0 && p.height_points > 0.0 => {
            (twips(p.width_points), twips(p.height_points))
        }
        _ => (12240, 15840),
    }
}

/// One inch, or an eighth of the shorter side of a smaller page.
pub fn margin_twips(width: i32, height: i32) -> i32 {
    TWIPS_PER_INCH.min(width.min(height) / 8)
}

fn twips(points: f64) -> i32 {
    ((points * 20.0).round() as i32).clamp(MIN_PAGE_TWIPS, MAX_PAGE_TWIPS)
}

fn emu(points: f64) -> i64 {
    (points * EMU_PER_POINT as f64).round().clamp(1.0, MAX_EMU) as i64
}

/// `text` made safe for an XML text node: &, < and > escaped, and the characters XML cannot hold (control characters
/// other than tab, line feed and carriage return, U+FFFE, U+FFFF) left out.
pub fn escape_xml(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '\t' | '\n' | '\r' => out.push(c),
            c if c < ' ' || c == '\u{FFFE}' || c == '\u{FFFF}' => {}
            c => out.push(c),
        }
    }
    out
}

/// The picture's size on the paper in EMU: the page's real size (points x 12,700), shrunk with its shape kept until it
/// fits inside the margins of a paper of `paper_width` x `paper_height` twips, never enlarged. Whole EMU, rounded down
/// where shrunk; a page without a size fills the space inside the margins.
pub fn picture_size_emu(page: &Page, paper_width: i32, paper_height: i32) -> (i64, i64) {
    let margin = margin_twips(paper_width, paper_height) as i64;
    let box_width = 1.max(paper_width as i64 - 2 * margin) * EMU_PER_TWIP;
    let box_height = 1.max(paper_height as i64 - 2 * margin) * EMU_PER_TWIP;
    if page.width_points.is_nan()
        || page.height_points.is_nan()
        || page.width_points <= 0.0
        || page.height_points <= 0.0
    {
        return (box_width, box_height);
    }
    let (width, height) = (emu(page.width_points), emu(page.height_points));
    if width <= box_width && height <= box_height {
        return (width, height);
    }
    if width * box_height >= height * box_width {
        return (box_width, 1.max(height * box_width / width));
    }
    (1.max(width * box_height / height), box_height)
}

fn picture_at(pictures: &[Option<Picture>], index: usize) -> Option<&Picture> {
    pictures.get(index).and_then(Option::as_ref)
}

/// The pictures that go into the document: one per page that has one, in page order.
fn placed_pictures<'a>(pages: &[Page], pictures: &'a [Option<Picture>]) -> Vec<&'a Picture> {
    (0..pages.len())
        .filter_map(|i| picture_at(pictures, i))
        .collect()
}

/// "[Content_Types].xml" for a package holding `pictures` (in document order): the plain content types with a default
/// content type for each picture format used, JPEG first, before the document's override.
pub fn package_content_types_xml(pictures: &[&Picture]) -> String {
    let jpeg = pictures.iter().any(|p| p.format == PictureFormat::Jpeg);
    let png = pictures.iter().any(|p| p.format == PictureFormat::Png);
    if !jpeg && !png {
        return CONTENT_TYPES_XML.to_string();
    }
    let default = |format: PictureFormat| {
        format!(
            "<Default Extension=\"{}\" ContentType=\"{}\"/>",
            format.extension(),
            format.content_type()
        )
    };
    let mut defaults = String::new();
    if jpeg {
        defaults.push_str(&default(PictureFormat::Jpeg));
    }
    if png {
        defaults.push_str(&default(PictureFormat::Png));
    }
    let at = CONTENT_TYPES_XML.find("<Override ").unwrap();
    format!(
        "{}{defaults}{}",
        &CONTENT_TYPES_XML[..at],
        &CONTENT_TYPES_XML[at..]
    )
}

/// "word/_rels/document.xml.rels": one image relationship per picture, "rId1" to "media/image1.jpeg" and on, in document
/// order.
pub fn document_relationships_xml(pictures: &[&Picture]) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
    out.push_str(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    );
    for (i, picture) in pictures.iter().enumerate() {
        out.push_str(&format!(
            "<Relationship Id=\"rId{}\" Type=\"{IMAGE_RELATIONSHIP_TYPE}\" Target=\"media/{}\"/>",
            i + 1,
            media_name(i + 1, picture.format)
        ));
    }
    out.push_str("</Relationships>");
    out
}

/// One paragraph: its text in one run, a line break (between the rows of a table) as w:br, a tab (between the pieces of a
/// row) as w:tab. Right-to-left text gets w:bidi and w:rtl.
fn append_paragraph(out: &mut String, text: &str, rtl: bool, page_break_before: bool) {
    out.push_str("<w:p>");
    if page_break_before || rtl {
        out.push_str("<w:pPr>");
        if page_break_before {
            out.push_str("<w:pageBreakBefore/>");
        }
        if rtl {
            out.push_str("<w:bidi/>");
        }
        out.push_str("</w:pPr>");
    }
    let clean = escape_xml(text).replace('\r', "");
    if !clean.is_empty() {
        out.push_str(if rtl {
            "<w:r><w:rPr><w:rtl/></w:rPr>"
        } else {
            "<w:r>"
        });
        for (l, line) in clean.split('\n').enumerate() {
            if l > 0 {
                out.push_str("<w:br/>");
            }
            for (i, piece) in line.split('\t').enumerate() {
                if i > 0 {
                    out.push_str("<w:tab/>");
                }
                if !piece.is_empty() {
                    out.push_str("<w:t xml:space=\"preserve\">");
                    out.push_str(piece);
                    out.push_str("</w:t>");
                }
            }
        }
        out.push_str("</w:r>");
    }
    out.push_str("</w:p>");
}

/// The paragraph holding a page's picture: centred, no space around it, the picture inline (it moves with the text) with
/// its shape locked, named after the page for screen readers.
fn append_picture(
    out: &mut String,
    number: usize,
    page_number: usize,
    format: PictureFormat,
    cx: i64,
    cy: i64,
    page_break_before: bool,
) {
    let extent = format!("cx=\"{cx}\" cy=\"{cy}\"");
    out.push_str("<w:p><w:pPr>");
    if page_break_before {
        out.push_str("<w:pageBreakBefore/>");
    }
    out.push_str("<w:spacing w:before=\"0\" w:after=\"0\"/><w:jc w:val=\"center\"/></w:pPr>");
    out.push_str("<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">");
    out.push_str(&format!(
        "<wp:extent {extent}/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>"
    ));
    out.push_str(&format!(
        "<wp:docPr id=\"{number}\" name=\"Page {page_number}\" descr=\"Page {page_number} as scanned\"/>"
    ));
    out.push_str(
        "<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>",
    );
    out.push_str("<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic>");
    out.push_str(&format!(
        "<pic:nvPicPr><pic:cNvPr id=\"{number}\" name=\"{}\"/><pic:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></pic:cNvPicPr></pic:nvPicPr>",
        media_name(number, format)
    ));
    out.push_str(&format!(
        "<pic:blipFill><a:blip r:embed=\"rId{number}\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
    ));
    out.push_str(&format!(
        "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext {extent}/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>"
    ));
    out.push_str("</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>");
}

/// "word/document.xml": the paragraphs of every page (after its picture, when it has one), then the paper and margins.
pub fn document_xml(pages: &[Page], pictures: &[Option<Picture>]) -> String {
    let (width, height) = page_size_twips(pages.first());
    let margin = margin_twips(width, height);
    let any_picture = !placed_pictures(pages, pictures).is_empty();

    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
    out.push_str(
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"",
    );
    if any_picture {
        out.push_str(PICTURE_NAMESPACES);
    }
    out.push_str("><w:body>");
    let mut picture_number = 0;
    for (index, page) in pages.iter().enumerate() {
        let mut break_before = index > 0;
        if let Some(picture) = picture_at(pictures, index) {
            picture_number += 1;
            let (cx, cy) = picture_size_emu(page, width, height);
            append_picture(
                &mut out,
                picture_number,
                index + 1,
                picture.format,
                cx,
                cy,
                break_before,
            );
            break_before = false;
        } else if page.paragraphs.is_empty() {
            append_paragraph(&mut out, "", false, break_before);
            continue;
        }
        for (p, paragraph) in page.paragraphs.iter().enumerate() {
            append_paragraph(
                &mut out,
                &paragraph.text,
                paragraph.rtl,
                break_before && p == 0,
            );
        }
    }
    if pages.is_empty() {
        append_paragraph(&mut out, "", false, false);
    }
    out.push_str(&format!(
        "<w:sectPr><w:pgSz w:w=\"{width}\" w:h=\"{height}\""
    ));
    if width > height {
        out.push_str(" w:orient=\"landscape\"");
    }
    out.push_str(&format!(
        "/><w:pgMar w:top=\"{margin}\" w:right=\"{margin}\" w:bottom=\"{margin}\" w:left=\"{margin}\" w:header=\"{}\" w:footer=\"{}\" w:gutter=\"0\"/></w:sectPr>",
        margin / 2,
        margin / 2
    ));
    out.push_str("</w:body></w:document>");
    out
}

/// The parts of the package, in the order they are stored; the pictures are not copied.
fn package_parts<'a>(
    pages: &[Page],
    pictures: &'a [Option<Picture>],
) -> Vec<(String, Cow<'a, [u8]>)> {
    let placed = placed_pictures(pages, pictures);
    let mut parts: Vec<(String, Cow<[u8]>)> = vec![
        (
            "[Content_Types].xml".to_string(),
            Cow::Owned(package_content_types_xml(&placed).into_bytes()),
        ),
        (
            "_rels/.rels".to_string(),
            Cow::Borrowed(RELATIONSHIPS_XML.as_bytes()),
        ),
        (
            "word/document.xml".to_string(),
            Cow::Owned(document_xml(pages, pictures).into_bytes()),
        ),
    ];
    if !placed.is_empty() {
        parts.push((
            "word/_rels/document.xml.rels".to_string(),
            Cow::Owned(document_relationships_xml(&placed).into_bytes()),
        ));
        for (i, picture) in placed.iter().enumerate() {
            parts.push((
                format!("word/media/{}", media_name(i + 1, picture.format)),
                Cow::Borrowed(picture.data.as_slice()),
            ));
        }
    }
    parts
}

/// The .docx file for `pages`; `pictures` holds each page's picture by index (None, or no entry, for a page without one).
pub fn make_docx(pages: &[Page], pictures: &[Option<Picture>]) -> Result<Vec<u8>, ZipError> {
    let mut writer = Writer::new(Vec::new());
    for (name, data) in package_parts(pages, pictures) {
        writer.add(&name, &data)?;
    }
    writer.finish()
}

/// The size in bytes of the .docx file `make_docx` writes, worked out without writing it; a save checks it against
/// `MAX_PACKAGE_BYTES` first.
pub fn docx_size(pages: &[Page], pictures: &[Option<Picture>]) -> u64 {
    let entries = package_parts(pages, pictures);
    // Each part has its local header and its central record, which both carry the name.
    22 + entries
        .iter()
        .map(|(name, data)| 30 + 46 + 2 * name.len() as u64 + data.len() as u64)
        .sum::<u64>()
}
