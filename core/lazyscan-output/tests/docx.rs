use lazy_office_zip::crc32;
use lazyscan_output::docx::{
    MAX_PACKAGE_BYTES, Page, Paragraph, Picture, PictureFormat, document_xml, docx_size,
    escape_xml, make_docx, margin_twips, media_name, package_content_types_xml, page_size_twips,
    picture_size_emu,
};
use serde_json::Value;
use sha2::{Digest, Sha256};

fn data(name: &str) -> Vec<u8> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../testdata/output");
    let bytes = std::fs::read(dir.join(name)).unwrap();
    let sums = std::fs::read_to_string(dir.join("SHA256SUMS")).unwrap();
    let hash: String = Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert!(sums.contains(&format!("{hash} *{name}")), "{name}");
    bytes
}

fn page(width: f64, height: f64, texts: &[&str]) -> Page {
    Page {
        width_points: width,
        height_points: height,
        paragraphs: texts
            .iter()
            .map(|t| Paragraph {
                text: t.to_string(),
                rtl: false,
            })
            .collect(),
    }
}

fn blank() -> Page {
    page(1000.0, 1000.0, &[])
}

fn jpeg() -> Picture {
    Picture {
        data: data("docx-fixture.jpeg"),
        format: PictureFormat::Jpeg,
    }
}

fn png() -> Picture {
    Picture {
        data: data("docx-fixture.png"),
        format: PictureFormat::Png,
    }
}

/// The cases of docx-cases.json: the pages as the reading order made them, and the picture formats.
fn cases() -> Vec<(String, Vec<Page>, Vec<Option<Picture>>)> {
    let cases: Value = serde_json::from_slice(&data("docx-cases.json")).unwrap();
    cases
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            let pages = c["pages"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| Page {
                    width_points: p["width"].as_f64().unwrap(),
                    height_points: p["height"].as_f64().unwrap(),
                    paragraphs: p["paragraphs"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|x| Paragraph {
                            text: x["text"].as_str().unwrap().to_string(),
                            rtl: x["rtl"].as_bool().unwrap(),
                        })
                        .collect(),
                })
                .collect();
            let pictures = c["pictures"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| match p.as_str() {
                    Some("jpeg") => Some(jpeg()),
                    Some("png") => Some(png()),
                    _ => None,
                })
                .collect();
            (c["name"].as_str().unwrap().to_string(), pages, pictures)
        })
        .collect()
}

fn case(name: &str) -> (Vec<Page>, Vec<Option<Picture>>) {
    let (_, pages, pictures) = cases().into_iter().find(|c| c.0 == name).unwrap();
    (pages, pictures)
}

#[test]
fn every_case_is_the_reference_package_byte_for_byte() {
    let all = cases();
    assert_eq!(all.len(), 4);
    for (name, pages, pictures) in all {
        let docx = make_docx(&pages, &pictures).unwrap();
        assert!(docx == data(&format!("docx-{name}.docx")), "{name}");
        assert_eq!(docx.len() as u64, docx_size(&pages, &pictures), "{name}");
    }
}

#[test]
fn the_fingerprints_both_platforms_pin() {
    let (pages, _) = case("sample");
    let docx = make_docx(&pages, &[]).unwrap();
    assert_eq!((docx.len(), crc32(&docx)), (1996, 0x90AB548B));
    assert_eq!(make_docx(&pages, &[]).unwrap(), docx);
    let (pages, pictures) = case("sample-images");
    let docx = make_docx(&pages, &pictures).unwrap();
    assert_eq!((docx.len(), crc32(&docx)), (5529, 0xC8A4BDE4));
    assert_eq!(docx_size(&pages, &pictures), 5529);
    // The fixtures themselves, so a change to them shows here first.
    assert_eq!((jpeg().data.len(), png().data.len()), (421, 127));
    assert_eq!(
        (crc32(&jpeg().data), crc32(&png().data)),
        (0x58549185, 0xA6733A06)
    );
}

#[test]
fn no_pictures_is_the_text_only_package() {
    let (pages, _) = case("sample");
    let text_only = make_docx(&pages, &[]).unwrap();
    assert_eq!(make_docx(&pages, &[None, None]).unwrap(), text_only);
    assert_eq!(
        package_content_types_xml(&[]),
        package_content_types_xml(&[])
    );
    // Pictures past the last page are left out.
    assert_eq!(
        make_docx(&[blank()], &[None, Some(png())]).unwrap(),
        make_docx(&[blank()], &[]).unwrap()
    );
}

#[test]
fn right_to_left_paragraphs_are_bidi_with_rtl_runs() {
    let arabic = Page {
        width_points: 1000.0,
        height_points: 1000.0,
        paragraphs: vec![Paragraph {
            text: "\u{645}\u{631}\u{62D}\u{628}\u{627}".into(),
            rtl: true,
        }],
    };
    let xml = document_xml(&[arabic], &[]);
    assert!(xml.contains(
        "<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space=\"preserve\">"
    ));
    let latin = document_xml(&[page(1000.0, 1000.0, &["hello"])], &[]);
    assert!(!latin.contains("w:bidi") && !latin.contains("w:rtl"));
    let hebrew = Page {
        paragraphs: vec![Paragraph {
            text: "\u{5E9}\u{5DC}\u{5D5}\u{5DD}".into(),
            rtl: true,
        }],
        ..blank()
    };
    assert!(
        document_xml(&[blank(), hebrew], &[])
            .contains("<w:pPr><w:pageBreakBefore/><w:bidi/></w:pPr>")
    );
}

#[test]
fn markup_is_escaped_and_what_xml_cannot_hold_is_left_out() {
    let xml = document_xml(&[page(1000.0, 1000.0, &["A & B <tag> \"q\" 'a'"])], &[]);
    assert!(xml.contains("<w:t xml:space=\"preserve\">A &amp; B &lt;tag&gt; \"q\" 'a'</w:t>"));
    assert_eq!(escape_xml("A & B <tag>"), "A &amp; B &lt;tag&gt;");
    assert_eq!(escape_xml("a\u{1}b\u{8}\tc\u{FFFE}\u{FFFF}"), "ab\tc");
    assert_eq!(escape_xml("x\u{1F600}y"), "x\u{1F600}y");
    assert_eq!(escape_xml("\n\r"), "\n\r");
    let rows = document_xml(&[page(1000.0, 1000.0, &["a\tb\nc\td"])], &[]);
    assert!(rows.contains(
        "<w:p><w:r><w:t xml:space=\"preserve\">a</w:t><w:tab/><w:t xml:space=\"preserve\">b</w:t><w:br/><w:t xml:space=\"preserve\">c</w:t><w:tab/><w:t xml:space=\"preserve\">d</w:t></w:r></w:p>"
    ));
}

#[test]
fn the_paper_comes_from_the_first_page_in_twips_with_margins() {
    let a4 = page(595.28, 841.89, &[]);
    let xml = document_xml(&[a4, page(1000.0, 300.0, &[])], &[]);
    assert!(xml.contains(
        "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr>"
    ));
    assert_eq!(
        page_size_twips(Some(&page(792.0, 612.0, &[]))),
        (15840, 12240)
    );
    assert!(
        document_xml(&[page(792.0, 612.0, &[])], &[])
            .contains("<w:pgSz w:w=\"15840\" w:h=\"12240\" w:orient=\"landscape\"/>")
    );
    assert_eq!(page_size_twips(None), (12240, 15840));
    assert_eq!(page_size_twips(Some(&page(5000.0, 1.0, &[]))), (31680, 144));
    assert_eq!(margin_twips(4320, 20000), 540);
    assert_eq!(margin_twips(12240, 15840), 1440);
}

#[test]
fn empty_pages_still_give_a_paragraph_each() {
    assert_eq!(
        document_xml(&[], &[]),
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p></w:p><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
    );
    let xml = document_xml(&[blank(), blank()], &[]);
    assert_eq!(xml.matches("<w:p>").count(), 2);
    assert!(xml.contains("<w:p><w:pPr><w:pageBreakBefore/></w:pPr></w:p>"));
}

#[test]
fn the_picture_paragraph_is_the_exact_markup() {
    let xml = document_xml(&[page(612.0, 792.0, &[])], &[Some(jpeg())]);
    let expected = concat!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n",
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"",
        " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"",
        " xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\"",
        " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"",
        " xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>",
        "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/><w:jc w:val=\"center\"/></w:pPr>",
        "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">",
        "<wp:extent cx=\"5943600\" cy=\"7691717\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>",
        "<wp:docPr id=\"1\" name=\"Page 1\" descr=\"Page 1 as scanned\"/>",
        "<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>",
        "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic>",
        "<pic:nvPicPr><pic:cNvPr id=\"1\" name=\"image1.jpeg\"/><pic:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></pic:cNvPicPr></pic:nvPicPr>",
        "<pic:blipFill><a:blip r:embed=\"rId1\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>",
        "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"5943600\" cy=\"7691717\"/></a:xfrm>",
        "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>",
        "</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>",
        "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" ",
        "w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
    );
    assert_eq!(xml, expected);
}

#[test]
fn a_picture_is_real_size_or_shrunk_inside_the_margins_keeping_its_shape() {
    let size = |w: f64, h: f64, pw: i32, ph: i32| picture_size_emu(&page(w, h, &[]), pw, ph);
    assert_eq!(size(612.0, 792.0, 12240, 15840), (5943600, 7691717));
    assert_eq!(size(792.0, 612.0, 12240, 15840), (5943600, 4592781));
    assert_eq!(size(216.0, 2160.0, 12240, 15840), (822960, 8229600));
    assert_eq!(size(216.0, 360.0, 12240, 15840), (2743200, 4572000));
    assert_eq!(size(216.0, 360.0, 4320, 7200), (2057400, 3429000));
    assert_eq!(size(0.0, 792.0, 12240, 15840), (5943600, 8229600));
    assert_eq!(size(f64::NAN, 792.0, 12240, 15840), (5943600, 8229600));
    assert_eq!(size(1e300, 1e300, 12240, 15840), (5943600, 5943600));
}

#[test]
fn some_pages_with_pictures_number_them_in_order() {
    let pages = [page(1000.0, 1000.0, &["One"]), blank(), blank()];
    let pictures = [Some(png()), None, Some(jpeg())];
    let docx = make_docx(&pages, &pictures).unwrap();
    assert_eq!(docx.len() as u64, docx_size(&pages, &pictures));
    let xml = document_xml(&pages, &pictures);
    assert!(xml.contains("name=\"image1.png\""));
    assert!(xml.contains("name=\"image2.jpeg\""));
    assert!(xml.contains("<w:pageBreakBefore/><w:spacing"));
    let types = package_content_types_xml(&[&jpeg(), &png()]);
    let jpeg_at = types.find("Extension=\"jpeg\"").unwrap();
    let png_at = types.find("Extension=\"png\"").unwrap();
    assert!(jpeg_at < png_at && png_at < types.find("<Override ").unwrap());
    assert_eq!(media_name(12, PictureFormat::Png), "image12.png");
    assert_eq!(media_name(1, PictureFormat::Jpeg), "image1.jpeg");
}

#[test]
fn the_limit_fits_a_zip_without_zip64() {
    const { assert!(MAX_PACKAGE_BYTES < u32::MAX as u64) };
}
