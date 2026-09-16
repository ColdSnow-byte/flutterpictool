//! 应用图标替换：把一张源图按 `src/main/res/drawable*` 各目录原有像素尺寸
//! 逐个缩放后写入 `icon.<源图扩展名>`。

use std::fs;
use std::path::{Path, PathBuf};

use image::{imageops, GenericImageView, ImageFormat};

use crate::api::assets::{ext_name_of, is_directory, open_image, read_preview};

/// icon 文件基础名
const ICON_STEM: &str = "icon";
const ICON_ROOT_RELATIVE: &str = "src/main/res";
const DRAWABLE_PREFIX: &str = "drawable";

/// 允许写入的扩展名（写入时保留源图扩展名）
const WRITABLE_EXTENSIONS: &[&str] = &[".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"];

pub struct IconTarget {
    pub dir_name: String,
    pub dir_path: String,
    pub existing_path: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    /// 现有 icon 的缩略图字节
    pub preview: Option<Vec<u8>>,
}

pub struct IconInspectResult {
    pub project_dir: String,
    pub exists: bool,
    pub icon_root: String,
    pub root_ok: bool,
    pub message: String,
    pub targets: Vec<IconTarget>,
}

pub struct ApplyIconPayload {
    pub project_dir: String,
    pub source_path: String,
}

pub struct ApplyIconItem {
    pub dir_name: String,
    pub target_path: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub ok: bool,
    pub message: String,
}

pub struct ApplyIconResult {
    pub success: bool,
    pub message: String,
    pub items: Vec<ApplyIconItem>,
}

fn is_drawable_dir_name(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.starts_with(DRAWABLE_PREFIX)
        && lower[DRAWABLE_PREFIX.len()..]
            .chars()
            .all(|c| c == '-' || c.is_ascii_alphanumeric())
}

fn icon_root_of(project_dir: &str) -> PathBuf {
    let mut path = PathBuf::from(project_dir);
    for segment in ICON_ROOT_RELATIVE.split('/') {
        path.push(segment);
    }
    path
}

/// 找出目录下任意扩展名的 icon 文件（icon / icon.png / icon.jpg ...）
fn find_icon_file(dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if name == ICON_STEM || name.starts_with(&format!("{ICON_STEM}.")) {
            return Some(entry.path());
        }
    }
    None
}

/// 只读文件头取出像素尺寸，避免整张图载入内存。
///
/// 工程里的 icon 可能是 `icon` 这种不带扩展名的文件，因此这里强制按文件头
/// 嗅探格式，而不是依赖扩展名。
fn read_icon_size(path: &Path) -> Option<(u32, u32)> {
    image::ImageReader::open(path)
        .ok()?
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()
}

/// 删除目录下所有以 icon 为名的文件（icon / icon.png / icon.jpg ...），返回被删文件名
fn remove_icon_files(dir: &Path) -> Vec<String> {
    let mut removed = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return removed,
    };
    for entry in entries.flatten() {
        if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        let lower = name.to_lowercase();
        if lower == ICON_STEM || lower.starts_with(&format!("{ICON_STEM}.")) {
            if fs::remove_file(entry.path()).is_ok() {
                removed.push(name);
            }
        }
    }
    removed
}

/// 收集 res 下所有 drawable* 子目录（按名称排序，保证输出稳定）
fn collect_drawable_dirs(root: &Path) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(_) => return dirs,
    };
    for entry in entries.flatten() {
        if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if is_drawable_dir_name(&name) {
            dirs.push(entry.path());
        }
    }
    dirs.sort_by(|a, b| a.to_string_lossy().cmp(&b.to_string_lossy()));
    dirs
}

/// 扫描 `src/main/res/drawable*` 下的 icon 现状
pub fn inspect_icons(project_dir: String) -> IconInspectResult {
    let project_dir = project_dir.trim().to_string();
    let root = icon_root_of(&project_dir);
    let exists = is_directory(Path::new(&project_dir));

    if !exists {
        return empty_inspect(&project_dir, "目录不存在或不是一个文件夹".to_string());
    }
    if !root.is_dir() {
        let message = format!("未找到 {ICON_ROOT_RELATIVE} 目录");
        return empty_inspect(&project_dir, message);
    }

    let dirs = collect_drawable_dirs(&root);
    let mut targets: Vec<IconTarget> = Vec::new();

    for dir in &dirs {
        let existing = find_icon_file(dir);
        let size = existing.as_deref().and_then(read_icon_size);
        let preview = existing
            .as_deref()
            .and_then(|path| read_preview(&path.to_string_lossy()));

        targets.push(IconTarget {
            dir_name: dir
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_default(),
            dir_path: dir.to_string_lossy().to_string(),
            existing_path: existing.map(|path| path.to_string_lossy().to_string()),
            width: size.map(|(width, _)| width),
            height: size.map(|(_, height)| height),
            preview,
        });
    }

    let message = if dirs.is_empty() {
        "未找到任何 drawable 目录".to_string()
    } else {
        format!("发现 {} 个 drawable 目录", dirs.len())
    };

    IconInspectResult {
        project_dir,
        exists: true,
        icon_root: root.to_string_lossy().to_string(),
        root_ok: true,
        message,
        targets,
    }
}

fn empty_inspect(project_dir: &str, message: String) -> IconInspectResult {
    IconInspectResult {
        project_dir: project_dir.to_string(),
        exists: false,
        icon_root: icon_root_of(project_dir).to_string_lossy().to_string(),
        root_ok: false,
        message,
        targets: Vec::new(),
    }
}

/// 把同一张源图按各 drawable 目录原有尺寸缩放后写入 `icon.<源扩展名>`
pub fn apply_icon(payload: ApplyIconPayload) -> ApplyIconResult {
    let project_dir = payload.project_dir.trim();

    if project_dir.is_empty() {
        return invalid("请先选择项目工程目录");
    }
    if !is_directory(Path::new(project_dir)) {
        return invalid("项目工程目录不存在");
    }

    let root = icon_root_of(project_dir);
    if !root.is_dir() {
        return invalid(&format!("未找到 {ICON_ROOT_RELATIVE} 目录"));
    }

    let dirs = collect_drawable_dirs(&root);
    if dirs.is_empty() {
        return invalid("未找到任何 drawable 目录");
    }

    let source_path = PathBuf::from(&payload.source_path);
    if !source_path.is_file() {
        return invalid("源图片不存在或不是文件");
    }

    // 目标文件名固定为 icon + 源图扩展名（图标.png -> icon.png）
    let ext = writable_ext(&payload.source_path);
    let source = match open_image(&source_path) {
        Some(source) => source,
        None => return invalid("无法解析源图片，文件可能已损坏或格式不受支持"),
    };

    let mut items: Vec<ApplyIconItem> = Vec::new();

    for dir in &dirs {
        let dir_name = dir
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_default();
        let target_path = dir.join(format!("{ICON_STEM}{ext}"));
        items.push(apply_icon_to_dir(&source, &dir_name, &target_path, dir, ext));
    }

    let failed = items.iter().filter(|item| !item.ok).count();

    ApplyIconResult {
        success: failed == 0,
        message: if failed == 0 {
            format!("已替换 {} 个 drawable 目录的图标", items.len())
        } else {
            format!("{failed} 个目录替换失败")
        },
        items,
    }
}

/// 源图扩展名归一化：.jpeg 保留，未识别或缺失时回退 .png
fn writable_ext(source_path: &str) -> &'static str {
    let ext = ext_name_of(source_path);
    WRITABLE_EXTENSIONS
        .iter()
        .find(|item| **item == ext)
        .copied()
        .unwrap_or(".png")
}

fn invalid(message: &str) -> ApplyIconResult {
    ApplyIconResult {
        success: false,
        message: message.to_string(),
        items: Vec::new(),
    }
}

/// 处理单个 drawable 目录：删旧 icon -> 按原尺寸缩放 -> 编码写回
fn apply_icon_to_dir(
    source: &image::DynamicImage,
    dir_name: &str,
    target_path: &Path,
    dir: &Path,
    ext: &str,
) -> ApplyIconItem {
    // 目标尺寸取自该目录原有的 icon；没有旧图标时沿用源图尺寸
    let (source_width, source_height) = source.dimensions();
    let (width, height) = find_icon_file(dir)
        .as_deref()
        .and_then(read_icon_size)
        .unwrap_or((source_width, source_height));

    let removed = remove_icon_files(dir);

    let resized = fit_into(source, width, height);

    if let Err(error) = save_image(&resized, target_path, ext) {
        return ApplyIconItem {
            dir_name: dir_name.to_string(),
            target_path: target_path.to_string_lossy().to_string(),
            width: None,
            height: None,
            ok: false,
            message: error,
        };
    }

    ApplyIconItem {
        dir_name: dir_name.to_string(),
        target_path: target_path.to_string_lossy().to_string(),
        width: Some(width),
        height: Some(height),
        ok: true,
        message: if removed.is_empty() {
            format!("按 {width}×{height} 写入")
        } else {
            format!("按 {width}×{height} 写入（清理旧 icon：{}）", removed.join("、"))
        },
    }
}

/// 等比缩放并居中填充到指定的目标像素尺寸（contain，保证图形完整不被裁切）
fn fit_into(source: &image::DynamicImage, width: u32, height: u32) -> image::DynamicImage {
    let (source_width, source_height) = source.dimensions();
    if width == 0 || height == 0 || source_width == 0 || source_height == 0 {
        return source.clone();
    }

    let scale = (width as f64 / source_width as f64).min(height as f64 / source_height as f64);
    let resized_width = ((source_width as f64 * scale).round() as u32).max(1);
    let resized_height = ((source_height as f64 * scale).round() as u32).max(1);

    let scaled = source
        .resize_exact(resized_width, resized_height, imageops::FilterType::Lanczos3)
        .to_rgba8();

    let mut canvas = image::RgbaImage::new(width, height);
    let offset_x = ((width - resized_width) / 2) as i64;
    let offset_y = ((height - resized_height) / 2) as i64;
    imageops::overlay(&mut canvas, &scaled, offset_x, offset_y);

    image::DynamicImage::ImageRgba8(canvas)
}

/// 按目标扩展名编码写盘；有损／不支持透明的格式先合成到白底
fn save_image(image: &image::DynamicImage, target: &Path, ext: &str) -> Result<(), String> {
    match ext {
        ".jpg" | ".jpeg" => flatten_on_white(image)
            .save_with_format(target, ImageFormat::Jpeg)
            .map_err(|error| error.to_string()),
        ".bmp" => flatten_on_white(image)
            .save_with_format(target, ImageFormat::Bmp)
            .map_err(|error| error.to_string()),
        ".webp" => image
            .save_with_format(target, ImageFormat::WebP)
            .map_err(|error| error.to_string()),
        ".gif" => image
            .save_with_format(target, ImageFormat::Gif)
            .map_err(|error| error.to_string()),
        _ => image
            .save_with_format(target, ImageFormat::Png)
            .map_err(|error| error.to_string()),
    }
}

/// 把带透明通道的图合成到白色背景上（JPEG / BMP 不支持 alpha）
#[flutter_rust_bridge::frb(ignore)]
pub fn flatten_on_white(image: &image::DynamicImage) -> image::DynamicImage {
    let rgba = image.to_rgba8();
    let (width, height) = rgba.dimensions();
    let mut canvas = image::RgbImage::from_pixel(width, height, image::Rgb([255, 255, 255]));
    for (x, y, pixel) in rgba.enumerate_pixels() {
        let alpha = pixel[3] as u16;
        let blend = |channel: u8| -> u8 {
            ((channel as u16 * alpha + 255u16 * (255 - alpha)) / 255) as u8
        };
        canvas.put_pixel(
            x,
            y,
            image::Rgb([blend(pixel[0]), blend(pixel[1]), blend(pixel[2])]),
        );
    }
    image::DynamicImage::ImageRgb8(canvas)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 建一个带 drawable / drawable-hdpi 的假工程
    fn setup(name: &str, sizes: &[(&str, u32, u32)]) -> PathBuf {
        let root = std::env::temp_dir().join(format!("pictool-icon-test-{name}"));
        let _ = fs::remove_dir_all(&root);
        let res = icon_root_of(&root.to_string_lossy());
        for (dir, width, height) in sizes {
            let target = res.join(dir);
            fs::create_dir_all(&target).unwrap();
            let image = image::RgbaImage::from_pixel(*width, *height, image::Rgba([255, 0, 0, 255]));
            image.save(target.join("icon.png")).unwrap();
        }
        root
    }

    #[test]
    fn resizes_each_drawable_to_its_own_pixel_size() {
        let root = setup("size", &[("drawable", 48, 48), ("drawable-hdpi", 72, 72)]);
        let source = root.join("source.png");
        image::RgbaImage::from_pixel(1000, 500, image::Rgba([0, 0, 255, 255]))
            .save(&source)
            .unwrap();

        let result = apply_icon(ApplyIconPayload {
            project_dir: root.to_string_lossy().to_string(),
            source_path: source.to_string_lossy().to_string(),
        });

        assert!(result.success, "{}", result.message);
        assert_eq!(result.items.len(), 2);

        let res = icon_root_of(&root.to_string_lossy());
        for (dir, expect) in [("drawable", 48u32), ("drawable-hdpi", 72u32)] {
            let written = res.join(dir).join("icon.png");
            let (width, height) = read_icon_size(&written).expect("未写入 icon.png");
            assert_eq!((width, height), (expect, expect), "{dir} 尺寸不符");
        }

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn keeps_source_extension_and_removes_old_icons() {
        let root = setup("ext", &[("drawable", 48, 48)]);
        let source = root.join("图标.jpg");
        image::RgbImage::from_pixel(200, 200, image::Rgb([0, 128, 0]))
            .save(&source)
            .unwrap();

        let result = apply_icon(ApplyIconPayload {
            project_dir: root.to_string_lossy().to_string(),
            source_path: source.to_string_lossy().to_string(),
        });

        assert!(result.success, "{}", result.message);

        let dir = icon_root_of(&root.to_string_lossy()).join("drawable");
        assert!(dir.join("icon.jpg").is_file(), "应写入 icon.jpg");
        assert!(!dir.join("icon.png").exists(), "旧的 icon.png 应被删除");

        let _ = fs::remove_dir_all(&root);
    }
}
