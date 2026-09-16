//! 图片格式转换：批量换格式，可选按比例缩放，可选删除原文件。

use std::fs;
use std::path::{Path, PathBuf};

use image::{GenericImageView, ImageFormat};

use crate::api::assets::open_image;
use crate::api::icon::flatten_on_white;

pub struct ConvertPayload {
    pub source_paths: Vec<String>,
    /// jpg | jpeg | png | webp | bmp
    pub format: String,
    /// 目标宽度，留空保持原尺寸
    pub width: Option<u32>,
    /// 目标高度，留空保持原尺寸
    pub height: Option<u32>,
    /// 转换成功后删除原文件
    pub delete_original: bool,
}

pub struct ConvertItem {
    pub source_path: String,
    pub target_path: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub ok: bool,
    pub message: String,
}

pub struct ConvertResult {
    pub success: bool,
    pub message: String,
    pub items: Vec<ConvertItem>,
}

/// 目标格式 -> (扩展名, 编码格式)
fn format_of(format: &str) -> Option<(&'static str, ImageFormat)> {
    match format.trim().to_lowercase().as_str() {
        "jpg" | "jpeg" => Some((".jpg", ImageFormat::Jpeg)),
        "png" => Some((".png", ImageFormat::Png)),
        "webp" => Some((".webp", ImageFormat::WebP)),
        "bmp" => Some((".bmp", ImageFormat::Bmp)),
        _ => None,
    }
}

/// 计算缩放后的目标尺寸：只给单边时按原比例推算，两边都给时等比放入框内
fn target_size(
    width: Option<u32>,
    height: Option<u32>,
    source_width: u32,
    source_height: u32,
) -> (u32, u32) {
    let width = width.filter(|value| *value > 0);
    let height = height.filter(|value| *value > 0);
    if source_width == 0 || source_height == 0 {
        return (source_width, source_height);
    }

    let ratio = source_width as f64 / source_height as f64;
    match (width, height) {
        (None, None) => (source_width, source_height),
        (Some(target), None) => (target, ((target as f64 / ratio).round() as u32).max(1)),
        (None, Some(target)) => (((target as f64 * ratio).round() as u32).max(1), target),
        (Some(max_width), Some(max_height)) => {
            let scale = (max_width as f64 / source_width as f64)
                .min(max_height as f64 / source_height as f64);
            (
                ((source_width as f64 * scale).round() as u32).max(1),
                ((source_height as f64 * scale).round() as u32).max(1),
            )
        }
    }
}

/// 批量转换：输出到源文件同目录，文件名不变、只换扩展名
pub fn convert_images(payload: ConvertPayload) -> ConvertResult {
    let (ext, format) = match format_of(&payload.format) {
        Some(target) => target,
        None => return invalid(&format!("不支持的目标格式：{}", payload.format)),
    };

    if payload.source_paths.is_empty() {
        return invalid("请先添加要转换的图片");
    }

    let mut items: Vec<ConvertItem> = Vec::new();

    for source in &payload.source_paths {
        items.push(convert_single(
            source,
            ext,
            format,
            payload.width,
            payload.height,
            payload.delete_original,
        ));
    }

    let failed = items.iter().filter(|item| !item.ok).count();
    ConvertResult {
        success: failed == 0,
        message: if failed == 0 {
            format!("已转换 {} 张图片", items.len())
        } else {
            format!("{failed} 张转换失败")
        },
        items,
    }
}

fn invalid(message: &str) -> ConvertResult {
    ConvertResult {
        success: false,
        message: message.to_string(),
        items: Vec::new(),
    }
}

/// 同名换扩展名（a/b.png -> a/b.jpg）
fn with_extension(path: &Path, ext: &str) -> PathBuf {
    let stem = path
        .file_stem()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_default();
    path.with_file_name(format!("{stem}{ext}"))
}

fn save_as(image: &image::DynamicImage, target: &Path, format: ImageFormat) -> Result<(), String> {
    let result = match format {
        // JPEG / BMP 不支持透明通道，先合成到白底
        ImageFormat::Jpeg | ImageFormat::Bmp => {
            flatten_on_white(image).save_with_format(target, format)
        }
        _ => image.save_with_format(target, format),
    };
    result.map_err(|error| error.to_string())
}

fn convert_single(
    source: &str,
    ext: &str,
    format: ImageFormat,
    width: Option<u32>,
    height: Option<u32>,
    delete_original: bool,
) -> ConvertItem {
    let fail = |message: String| ConvertItem {
        source_path: source.to_string(),
        target_path: String::new(),
        width: None,
        height: None,
        ok: false,
        message,
    };

    let path = Path::new(source);
    if !path.is_file() {
        return fail("源文件不存在或不是文件".to_string());
    }

    let image = match open_image(path) {
        Some(image) => image,
        None => return fail("无法解析图片，文件可能已损坏或格式不受支持".to_string()),
    };

    let (source_width, source_height) = image.dimensions();
    let (target_width, target_height) = target_size(width, height, source_width, source_height);

    // 尺寸未变化时不重采样，避免画质无损损耗
    let output = if (target_width, target_height) == (source_width, source_height) {
        image
    } else {
        image.resize_exact(
            target_width,
            target_height,
            image::imageops::FilterType::Lanczos3,
        )
    };

    let target_path = with_extension(path, ext);
    if let Err(message) = save_as(&output, &target_path, format) {
        return fail(message);
    }

    let same_file =
        target_path.to_string_lossy().to_lowercase() == path.to_string_lossy().to_lowercase();
    if delete_original && !same_file {
        let _ = fs::remove_file(path);
    }

    ConvertItem {
        source_path: source.to_string(),
        target_path: target_path.to_string_lossy().to_string(),
        width: Some(target_width),
        height: Some(target_height),
        ok: true,
        message: format!("{target_width}×{target_height}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_aspect_ratio_for_partial_and_full_size() {
        // 不指定尺寸：保持原样
        assert_eq!(target_size(None, None, 800, 400), (800, 400));
        // 只给宽度：按比例推算高度
        assert_eq!(target_size(Some(400), None, 800, 400), (400, 200));
        // 只给高度：按比例推算宽度
        assert_eq!(target_size(None, Some(200), 800, 400), (400, 200));
        // 两边都给：等比放入框内，不拉伸变形
        assert_eq!(target_size(Some(200), Some(400), 800, 400), (200, 100));
        assert_eq!(target_size(Some(400), Some(400), 800, 400), (400, 200));
        // 0 视为未填写
        assert_eq!(target_size(Some(0), None, 800, 400), (800, 400));
    }

    #[test]
    fn converts_format_and_resizes_on_disk() {
        let root = std::env::temp_dir().join("pictool-convert-test");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        let source = root.join("sample.png");
        image::RgbaImage::from_pixel(200, 100, image::Rgba([10, 20, 30, 255]))
            .save(&source)
            .unwrap();

        let result = convert_images(ConvertPayload {
            source_paths: vec![source.to_string_lossy().to_string()],
            format: "jpg".to_string(),
            width: Some(100),
            height: None,
            delete_original: true,
        });

        assert!(result.success, "{}", result.message);
        assert_eq!(
            image::image_dimensions(root.join("sample.jpg")).unwrap(),
            (100, 50)
        );
        assert!(!source.exists(), "勾选后应删除原文件");

        let _ = fs::remove_dir_all(&root);
    }
}
