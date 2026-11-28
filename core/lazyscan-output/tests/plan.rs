use lazyscan_output::plan::{
    ColorMode, ImageKind, PdfSizePreset, effective_dpi, plan, profile, target_size,
};
use sha2::{Digest, Sha256};

fn data(name: &str) -> String {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../testdata/output");
    let bytes = std::fs::read(dir.join(name)).unwrap();
    let sums = std::fs::read_to_string(dir.join("SHA256SUMS")).unwrap();
    let hash: String = Sha256::digest(&bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert!(sums.contains(&format!("{hash} *{name}")), "{name}");
    String::from_utf8(bytes).unwrap()
}

fn row(plan: lazyscan_output::plan::ImagePlan) -> String {
    let kind = match plan.kind {
        ImageKind::BilevelG4 => "G4",
        ImageKind::JpegGray => "Gray",
        ImageKind::JpegColor => "Color",
    };
    format!("{} {kind} {:.2}", plan.target_dpi, plan.quality)
}

#[test]
fn the_reference_table_of_plans() {
    let mut rows = String::new();
    for size in PdfSizePreset::DISPLAY_ORDER {
        for mode in [
            ColorMode::Color,
            ColorMode::Grayscale,
            ColorMode::BlackWhite,
        ] {
            for dpi in [0, 1, 75, 150, 300, 330, 331, 600, 660, 661, 1200] {
                for gray in [false, true] {
                    rows.push_str(&format!(
                        "{} {} {dpi} {}: {}\n",
                        size.name(),
                        mode.name(),
                        if gray { "True" } else { "False" },
                        row(plan(mode, dpi, size, gray))
                    ));
                }
            }
        }
    }
    for (iw, pw, dpi) in [
        (2550, 2550, 300),
        (1600, 2550, 300),
        (1275, 2550, 300),
        (1275, 0, 300),
        (1, 10000, 2),
        (3, 7, 100),
        (5, 2, 301),
    ] {
        rows.push_str(&format!(
            "effective {iw} {pw} {dpi}: {}\n",
            effective_dpi(iw, pw, dpi)
        ));
    }
    for (w, h, id, td) in [
        (2550, 3300, 300, 200),
        (5100, 6600, 600, 300),
        (3, 1, 300, 150),
        (1, 1, 600, 150),
        (2550, 3300, 300, 300),
        (100, 50, 150, 300),
        (7, 9, 0, 3),
        (101, 33, 300, 100),
    ] {
        let (tw, th) = target_size(w, h, id, td);
        rows.push_str(&format!("target {w} {h} {id} {td}: {tw} {th}\n"));
    }
    assert_eq!(rows, data("pdf-image-plan.txt"));
}

#[test]
fn the_size_table() {
    let p = |size| profile(size);
    assert_eq!(
        (
            p(PdfSizePreset::Best).max_dpi,
            p(PdfSizePreset::Best).color_quality
        ),
        (None, 0.90)
    );
    let standard = p(PdfSizePreset::Standard);
    assert_eq!(
        (
            standard.max_dpi,
            standard.color_quality,
            standard.gray_quality,
            standard.auto_gray,
            standard.bilevel_max_dpi,
            standard.text_mask
        ),
        (Some(300), 0.80, 0.80, true, Some(600), false)
    );
    let compact = p(PdfSizePreset::Compact);
    assert_eq!(
        (
            compact.max_dpi,
            compact.color_quality,
            compact.gray_quality,
            compact.bilevel_max_dpi,
            compact.text_mask
        ),
        (Some(200), 0.65, 0.70, Some(300), true)
    );
    let smallest = p(PdfSizePreset::Smallest);
    assert_eq!(
        (
            smallest.max_dpi,
            smallest.color_quality,
            smallest.gray_quality,
            smallest.bilevel_max_dpi,
            smallest.text_mask
        ),
        (Some(150), 0.50, 0.55, Some(300), true)
    );
}

#[test]
fn color_pages_without_color_are_gray_except_at_best() {
    let at = |mode, dpi, size, gray| row(plan(mode, dpi, size, gray));
    assert_eq!(
        at(ColorMode::Color, 300, PdfSizePreset::Best, true),
        "300 Color 0.90"
    );
    assert_eq!(
        at(ColorMode::Color, 300, PdfSizePreset::Standard, true),
        "300 Gray 0.80"
    );
    assert_eq!(
        at(ColorMode::Color, 300, PdfSizePreset::Compact, true),
        "200 Gray 0.70"
    );
    assert_eq!(
        at(ColorMode::Color, 300, PdfSizePreset::Smallest, true),
        "150 Gray 0.55"
    );
    assert_eq!(
        at(ColorMode::Grayscale, 300, PdfSizePreset::Best, false),
        "300 Gray 0.90"
    );
}

#[test]
fn black_and_white_is_g4_up_to_its_own_limit() {
    let target = |dpi, size| plan(ColorMode::BlackWhite, dpi, size, false).target_dpi;
    assert_eq!(target(660, PdfSizePreset::Standard), 660); // within 10 %
    assert_eq!(target(661, PdfSizePreset::Standard), 600);
    assert_eq!(target(1200, PdfSizePreset::Standard), 600);
    assert_eq!(target(330, PdfSizePreset::Compact), 330);
    assert_eq!(target(331, PdfSizePreset::Compact), 300);
    assert_eq!(target(600, PdfSizePreset::Smallest), 300);
    assert_eq!(target(1200, PdfSizePreset::Best), 1200);
    assert_eq!(target(75, PdfSizePreset::Smallest), 75); // never upsampled
    assert_eq!(target(0, PdfSizePreset::Standard), 1);
    assert!(plan(ColorMode::BlackWhite, 300, PdfSizePreset::Best, true).is_bilevel());
    assert!(!plan(ColorMode::Grayscale, 300, PdfSizePreset::Best, false).is_bilevel());
}

#[test]
fn the_effective_dpi_of_a_preview_is_lower() {
    assert_eq!(effective_dpi(2550, 2550, 300), 300);
    assert_eq!(effective_dpi(1600, 2550, 300), 188);
    assert_eq!(effective_dpi(1275, 2550, 300), 150);
    assert_eq!(effective_dpi(1275, 0, 300), 300);
    assert_eq!(effective_dpi(1, 10000, 2), 1);
}

#[test]
fn the_target_size_rounds_half_away_from_zero_and_keeps_a_pixel() {
    assert_eq!(target_size(2550, 3300, 300, 200), (1700, 2200));
    assert_eq!(target_size(5100, 6600, 600, 300), (2550, 3300));
    assert_eq!(target_size(3, 1, 300, 150), (2, 1)); // 1.5 -> 2, 0.5 -> 1
    assert_eq!(target_size(1, 1, 600, 150), (1, 1));
    assert_eq!(target_size(2550, 3300, 300, 300), (2550, 3300));
    assert_eq!(target_size(100, 50, 150, 300), (100, 50)); // never larger
}
