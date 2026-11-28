//! The size presets of saved PDFs and the per-page plan they lead to: downsampling, gray storage and JPEG quality. The page
//! size in the PDF never changes; only the stored image gets fewer pixels. Black and white pages are stored as CCITT G4 at
//! every size. The same table, rules and rounding as Lazy Scan's Swift and C# code.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PdfSizePreset {
    Standard,
    Best,
    Compact,
    Smallest,
}

impl PdfSizePreset {
    /// The sizes as the inspector lists them: largest file first.
    pub const DISPLAY_ORDER: [PdfSizePreset; 4] = [
        PdfSizePreset::Best,
        PdfSizePreset::Standard,
        PdfSizePreset::Compact,
        PdfSizePreset::Smallest,
    ];

    pub fn name(self) -> &'static str {
        match self {
            PdfSizePreset::Best => "Best",
            PdfSizePreset::Standard => "Standard",
            PdfSizePreset::Compact => "Compact",
            PdfSizePreset::Smallest => "Smallest",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ColorMode {
    Color,
    Grayscale,
    BlackWhite,
}

impl ColorMode {
    pub fn name(self) -> &'static str {
        match self {
            ColorMode::Color => "Color",
            ColorMode::Grayscale => "Grayscale",
            ColorMode::BlackWhite => "BlackWhite",
        }
    }
}

/// How a page image is stored in the PDF.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImageKind {
    /// A three-component (RGB) JPEG.
    JpegColor,
    /// A one-component JPEG, embedded as /DeviceGray.
    JpegGray,
    /// A 1-bit black and white image in CCITT G4.
    BilevelG4,
}

/// What one PDF size does.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SizeProfile {
    /// Pages scanned finer than this (with `DOWNSAMPLE_SLACK`) are downsampled to it; None keeps the scan resolution.
    pub max_dpi: Option<i32>,
    /// JPEG quality for color pages.
    pub color_quality: f64,
    /// JPEG quality for gray and black and white pages.
    pub gray_quality: f64,
    /// Pages scanned in color that have no color are stored as gray.
    pub auto_gray: bool,
    /// The limit for black and white pages, stored as CCITT G4; None keeps the scan resolution.
    pub bilevel_max_dpi: Option<i32>,
    /// Color pages are stored as a text mask over a low-resolution background, the mask at the black and white limit.
    pub text_mask: bool,
}

/// How to store one page image.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ImagePlan {
    /// The resolution of the stored image (the page's own when it is not downsampled).
    pub target_dpi: i32,
    pub kind: ImageKind,
    /// JPEG quality, 0 to 1. For a G4 page, which is lossless, the size's gray quality.
    pub quality: f64,
}

impl ImagePlan {
    /// The stored image has one gray component: a gray JPEG or a G4 page.
    pub fn is_gray(&self) -> bool {
        self.kind != ImageKind::JpegColor
    }

    /// The page is stored black and white, as CCITT G4.
    pub fn is_bilevel(&self) -> bool {
        self.kind == ImageKind::BilevelG4
    }
}

/// A page is downsampled only when it is finer than this many times the size's limit.
pub const DOWNSAMPLE_SLACK: f64 = 1.1;

/// A mask denser than this (G4 bytes against the 1-bit page's size) means the page is not text, and is stored as a plain
/// page.
pub const MAX_MASK_SHARE: f64 = 0.1;

/// The size table. The size alone sets the JPEG quality of PDF pages; the JPEG quality setting is for JPEG files. Best
/// stores the scan resolution at quality 0.9. Black and white pages keep up to 600 dpi at Standard and 300 dpi at
/// Compact and Smallest.
pub fn profile(size: PdfSizePreset) -> SizeProfile {
    match size {
        PdfSizePreset::Best => SizeProfile {
            max_dpi: None,
            color_quality: 0.90,
            gray_quality: 0.90,
            auto_gray: false,
            bilevel_max_dpi: None,
            text_mask: false,
        },
        PdfSizePreset::Compact => SizeProfile {
            max_dpi: Some(200),
            color_quality: 0.65,
            gray_quality: 0.70,
            auto_gray: true,
            bilevel_max_dpi: Some(300),
            text_mask: true,
        },
        PdfSizePreset::Smallest => SizeProfile {
            max_dpi: Some(150),
            color_quality: 0.50,
            gray_quality: 0.55,
            auto_gray: true,
            bilevel_max_dpi: Some(300),
            text_mask: true,
        },
        PdfSizePreset::Standard => SizeProfile {
            max_dpi: Some(300),
            color_quality: 0.80,
            gray_quality: 0.80,
            auto_gray: true,
            bilevel_max_dpi: Some(600),
            text_mask: false,
        },
    }
}

/// How to store a page. `image_dpi` is the resolution of the pixels at hand (see `effective_dpi`), `mode` the page's own
/// color mode, `looks_gray` whether a color page has no color; it only counts for sizes with `auto_gray`. Black and white
/// pages are G4 up to the size's `bilevel_max_dpi`.
pub fn plan(mode: ColorMode, image_dpi: i32, size: PdfSizePreset, looks_gray: bool) -> ImagePlan {
    let profile = profile(size);
    let dpi = image_dpi.max(1);
    let finer = |limit: Option<i32>| match limit {
        Some(limit) if dpi as f64 > DOWNSAMPLE_SLACK * limit as f64 => limit,
        _ => dpi,
    };
    if mode == ColorMode::BlackWhite {
        return ImagePlan {
            target_dpi: finer(profile.bilevel_max_dpi),
            kind: ImageKind::BilevelG4,
            quality: profile.gray_quality,
        };
    }
    let gray = mode != ColorMode::Color || (profile.auto_gray && looks_gray);
    ImagePlan {
        target_dpi: finer(profile.max_dpi),
        kind: if gray {
            ImageKind::JpegGray
        } else {
            ImageKind::JpegColor
        },
        quality: if gray {
            profile.gray_quality
        } else {
            profile.color_quality
        },
    }
}

/// The resolution of the pixels at hand: the page's own, or less when only a preview of the page is left.
pub fn effective_dpi(image_width: i32, page_pixel_width: i32, page_dpi: i32) -> i32 {
    if page_pixel_width <= 0 || image_width == page_pixel_width {
        return page_dpi;
    }
    1.max((page_dpi as f64 * image_width as f64 / page_pixel_width as f64).round() as i32)
}

/// The pixel size of an image of `width` x `height` at `image_dpi` stored at `target_dpi`; never larger.
pub fn target_size(width: i32, height: i32, image_dpi: i32, target_dpi: i32) -> (i32, i32) {
    if target_dpi >= image_dpi || image_dpi <= 0 {
        return (width, height);
    }
    let scale = target_dpi as f64 / image_dpi as f64;
    (
        1.max((width as f64 * scale).round() as i32),
        1.max((height as f64 * scale).round() as i32),
    )
}
