//! 素材替换：登录页背景、加载页背景、闪屏图三个固定槽位的检测与替换。

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use image::codecs::jpeg::JpegEncoder;
use image::{imageops, ExtendedColorType, GenericImageView, ImageFormat};

/// 预览图最长边（超出则等比缩小后再编码，避免几 MB 的字节流走桥接层）
const PREVIEW_MAX_EDGE: u32 = 320;
/// 缩略图 JPEG 质量
const PREVIEW_JPEG_QUALITY: u8 = 80;
/// 放大查看时的最长边：比缩略图清晰得多，又不会把整张原图传过去
const LARGE_PREVIEW_MAX_EDGE: u32 = 1600;
/// 放大查看时的 JPEG 质量
const LARGE_PREVIEW_JPEG_QUALITY: u8 = 88;
/// 超过该大小的文件不再尝试解码（避免占用过多内存）
const MAX_PREVIEW_SIZE: u64 = 64 * 1024 * 1024;
/// 解码失败时回退原图直传的体积上限
const MAX_RAW_FALLBACK_SIZE: u64 = 2 * 1024 * 1024;
/// 扫描目录时最多收集的图片数量
const MAX_SCAN_IMAGES: usize = 50;
/// 扫描目录的最大层级
const MAX_SCAN_DEPTH: usize = 3;
/// 目录扫描时跳过的目录名
const IGNORED_DIRS: &[&str] = &[
    "node_modules",
    ".git",
    "build",
    ".gradle",
    ".idea",
    "captures",
    "outputs",
    "intermediates",
];

/// 支持的图片扩展名
const IMAGE_EXTENSIONS: &[&str] = &[".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"];

/* -------------------------------------------------------------------------- */
/*                                  槽位定义                                   */
/* -------------------------------------------------------------------------- */

#[flutter_rust_bridge::frb(ignore)]
pub struct AssetSlot {
    /// 槽位标识
    pub key: &'static str,
    /// 界面显示名称
    pub label: &'static str,
    /// 相对于项目根目录的目标路径，统一使用 / 分隔
    pub relative_path: &'static str,
    /// 项目要求的目标文件名（不含扩展名）
    pub file_name: &'static str,
    /// 目标文件所在目录（相对于项目根目录，用于界面展示）
    pub relative_dir: &'static str,
    /// 界面说明文案
    pub description: &'static str,
    /// 从原始文件名自动识别归属时使用的关键字，越靠前优先级越高
    pub keywords: &'static [&'static str],
}

pub const ASSET_SLOTS: &[AssetSlot] = &[
    AssetSlot {
        key: "login",
        label: "登录页背景",
        relative_path: "src/main/assets/AgentAssets/login_bg",
        file_name: "login_bg",
        relative_dir: "src/main/assets/AgentAssets",
        description: "登录界面的背景图",
        keywords: &["login_bg", "login", "denglu", "登录"],
    },
    AssetSlot {
        key: "loading",
        label: "加载页背景",
        relative_path: "src/main/assets/AgentAssets/loading_bg",
        file_name: "loading_bg",
        relative_dir: "src/main/assets/AgentAssets",
        description: "加载界面的背景图",
        keywords: &["loading_bg", "loading", "load", "jiazai", "加载"],
    },
    AssetSlot {
        key: "splash",
        label: "闪屏图",
        relative_path: "src/main/assets/splash_image_0",
        file_name: "splash_image_0",
        relative_dir: "src/main/assets",
        description: "启动闪屏图",
        keywords: &["splash_image_0", "splash_image", "splash", "shanping", "闪屏"],
    },
];

#[flutter_rust_bridge::frb(ignore)]
pub fn get_slot(key: &str) -> Option<&'static AssetSlot> {
    ASSET_SLOTS.iter().find(|item| item.key == key)
}

/* -------------------------------------------------------------------------- */
/*                                  数据类型                                   */
/* -------------------------------------------------------------------------- */

/// 一个槽位的界面定义（给前端渲染用）
pub struct SlotDefinition {
    pub key: String,
    pub label: String,
    pub relative_path: String,
    pub file_name: String,
    pub relative_dir: String,
    pub description: String,
}

/// 项目中某个槽位当前的状态
pub struct SlotInspectInfo {
    pub slot: String,
    /// 槽位显示名
    pub slot_label: String,
    /// 期望的目标路径（不带扩展名）
    pub target_path: String,
    /// 实际存在的文件路径（可能带扩展名），不存在为 None
    pub existing_path: Option<String>,
    pub exists: bool,
    /// 现有文件字节数
    pub size: Option<u64>,
    /// 现有图片的缩略图字节（PNG / JPEG），过大或不存在为 None
    pub preview: Option<Vec<u8>>,
}

/// 扫描项目目录的结果
pub struct ProjectInspectResult {
    pub project_dir: String,
    /// 目录是否存在
    pub exists: bool,
    /// 是否具备 src/main/assets 标准结构
    pub structure_ok: bool,
    /// 缺失的目录（相对项目根目录）
    pub missing_dirs: Vec<String>,
    /// 错误提示
    pub message: String,
    pub slots: Vec<SlotInspectInfo>,
}

/// 拖放解析后的图片项
pub struct DroppedImage {
    pub path: String,
    pub file_name: String,
    /// 根据文件名猜测应归属的槽位
    pub suggested_slot: Option<String>,
}

/// 拖放内容解析结果
pub struct ResolveDropResult {
    /// 拖入的内容中识别出的项目根目录
    pub project_dir: Option<String>,
    pub images: Vec<DroppedImage>,
}

pub struct ApplyPayloadItem {
    pub slot: String,
    pub source_path: String,
}

pub struct ApplyPayload {
    pub project_dir: String,
    /// 替换前备份原文件（备份为 *.bak）
    pub backup: bool,
    /// 目标文件是否保留源图片扩展名（默认按工程要求不带扩展名）
    pub keep_extension: bool,
    pub items: Vec<ApplyPayloadItem>,
}

pub struct ApplyResultItem {
    pub slot: String,
    pub slot_label: String,
    pub source_path: String,
    /// 实际写入的目标文件路径
    pub target_path: String,
    pub ok: bool,
    pub message: String,
    /// 备份文件路径
    pub backup_path: Option<String>,
}

pub struct ApplyResult {
    pub success: bool,
    pub message: String,
    pub items: Vec<ApplyResultItem>,
}

/* -------------------------------------------------------------------------- */
/*                                  工具函数                                   */
/* -------------------------------------------------------------------------- */

/// 取文件名（兼容 / 与 \ 两种分隔符）
#[flutter_rust_bridge::frb(ignore)]
pub fn base_name_of(file_path: &str) -> String {
    let normalized = file_path.replace('\\', "/");
    normalized.rsplit('/').next().unwrap_or("").to_string()
}

/// 取扩展名（小写，含点号）
#[flutter_rust_bridge::frb(ignore)]
pub fn ext_name_of(file_path: &str) -> String {
    let name = base_name_of(file_path);
    match name.rfind('.') {
        Some(index) => name[index..].to_lowercase(),
        None => String::new(),
    }
}

/// 判断是否为受支持的图片文件（按扩展名）
#[flutter_rust_bridge::frb(ignore)]
pub fn is_image_file_name(file_name: &str) -> bool {
    let ext = match file_name.rfind('.') {
        Some(index) => file_name[index..].to_lowercase(),
        None => return false,
    };
    IMAGE_EXTENSIONS.contains(&ext.as_str())
}

/// 把 `src/main/assets/AgentAssets/login_bg` 这类相对路径转成绝对路径
#[flutter_rust_bridge::frb(ignore)]
pub fn to_absolute(project_dir: &str, relative_path: &str) -> PathBuf {
    let mut path = PathBuf::from(project_dir);
    for segment in relative_path.split('/') {
        if !segment.is_empty() {
            path.push(segment);
        }
    }
    path
}

fn exists(target: &Path) -> bool {
    target.exists()
}

#[flutter_rust_bridge::frb(ignore)]
pub fn is_directory(target: &Path) -> bool {
    fs::metadata(target).map(|meta| meta.is_dir()).unwrap_or(false)
}

#[flutter_rust_bridge::frb(ignore)]
pub fn is_file(target: &Path) -> bool {
    fs::metadata(target).map(|meta| meta.is_file()).unwrap_or(false)
}

/// 打开并解码图片。
///
/// 工程里存在 `login_bg`、`splash_image_0` 这类**不带扩展名**的素材，
/// `image::open` 只按扩展名猜格式会直接失败，所以这里强制按文件头嗅探。
#[flutter_rust_bridge::frb(ignore)]
pub fn open_image(path: &Path) -> Option<image::DynamicImage> {
    image::ImageReader::open(path)
        .ok()?
        .with_guessed_format()
        .ok()?
        .decode()
        .ok()
}

/// 判断图片真实类型：优先用扩展名，扩展名缺失（工程里的 `login_bg` 这类无扩展名文件）
/// 或无法识别时，回退到按文件头判断。
fn guess_format(buffer: &[u8], file_path: &str) -> Option<ImageFormat> {
    match ext_name_of(file_path).as_str() {
        ".png" => return Some(ImageFormat::Png),
        ".jpg" | ".jpeg" => return Some(ImageFormat::Jpeg),
        ".webp" => return Some(ImageFormat::WebP),
        ".bmp" => return Some(ImageFormat::Bmp),
        ".gif" => return Some(ImageFormat::Gif),
        _ => {}
    }

    if buffer.starts_with(&[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
        return Some(ImageFormat::Png);
    }
    if buffer.len() >= 3 && buffer[0] == 0xff && buffer[1] == 0xd8 && buffer[2] == 0xff {
        return Some(ImageFormat::Jpeg);
    }
    if buffer.len() >= 12 && buffer.starts_with(b"RIFF") && &buffer[8..12] == b"WEBP" {
        return Some(ImageFormat::WebP);
    }
    if buffer.len() >= 6 && buffer.starts_with(b"GIF") {
        return Some(ImageFormat::Gif);
    }
    if buffer.len() >= 2 && buffer[0] == 0x42 && buffer[1] == 0x4d {
        return Some(ImageFormat::Bmp);
    }

    None
}

/// 读取图片为可直接渲染的字节流（缩略图）。
///
/// 大图直接回传原图会产生几 MB 的数据，桥接序列化与前端解码都会明显卡顿，
/// 因此这里统一缩放到 [`PREVIEW_MAX_EDGE`] 之内再编码。
pub fn read_preview(target: &str) -> Option<Vec<u8>> {
    let path = Path::new(target);
    let meta = fs::metadata(path).ok()?;

    if !meta.is_file() || meta.len() > MAX_PREVIEW_SIZE {
        return None;
    }

    if let Some(thumbnail) = build_scaled(path, PREVIEW_MAX_EDGE, PREVIEW_JPEG_QUALITY) {
        return Some(thumbnail);
    }

    // 解码失败（非常规图片）时才回退原图直传，并限制体积
    if meta.len() > MAX_RAW_FALLBACK_SIZE {
        return None;
    }
    let buffer = fs::read(path).ok()?;
    let _ = guess_format(&buffer, target)?;
    Some(buffer)
}

/// 读取放大查看用的较大预览。
///
/// 卡片上的缩略图只有 320px，放大后必然发虚；这里单独给一份最长边
/// [`LARGE_PREVIEW_MAX_EDGE`] 的版本，清晰度够用且体积可控。
pub fn read_large_preview(target: String) -> Option<Vec<u8>> {
    let path = Path::new(&target);
    let meta = fs::metadata(path).ok()?;
    if !meta.is_file() || meta.len() > MAX_PREVIEW_SIZE {
        return None;
    }

    build_scaled(path, LARGE_PREVIEW_MAX_EDGE, LARGE_PREVIEW_JPEG_QUALITY)
}

/// 等比缩放到指定最长边后编码
fn build_scaled(path: &Path, max_edge: u32, quality: u8) -> Option<Vec<u8>> {
    let image = open_image(path)?;
    let (width, height) = image.dimensions();
    if width == 0 || height == 0 {
        return None;
    }

    let longest = width.max(height);
    let scaled = if longest > max_edge {
        let scale = max_edge as f64 / longest as f64;
        image.resize(
            ((width as f64 * scale).round() as u32).max(1),
            ((height as f64 * scale).round() as u32).max(1),
            imageops::FilterType::Triangle,
        )
    } else {
        image
    };

    let mut bytes: Vec<u8> = Vec::new();
    if scaled.color().has_alpha() {
        scaled
            .write_to(&mut std::io::Cursor::new(&mut bytes), ImageFormat::Png)
            .ok()?;
    } else {
        // 不带透明通道时用 JPEG，体积通常只有 PNG 的十分之一
        let rgb = scaled.to_rgb8();
        JpegEncoder::new_with_quality(&mut bytes, quality)
            .encode(&rgb, rgb.width(), rgb.height(), ExtendedColorType::Rgb8)
            .ok()?;
    }

    Some(bytes)
}

/// 目标文件在工程里可能是 `login_bg`，也可能是 `login_bg.png`，
/// 这里做容错查找，保证替换的是工程真正在用的那个文件。
#[flutter_rust_bridge::frb(ignore)]
pub fn find_existing_file(target_path: &Path) -> Option<PathBuf> {
    if exists(target_path) {
        return Some(target_path.to_path_buf());
    }

    for ext in IMAGE_EXTENSIONS {
        let candidate = PathBuf::from(format!("{}{}", target_path.to_string_lossy(), ext));
        if exists(&candidate) {
            return Some(candidate);
        }
    }

    None
}

/// 删除目标目录下所有与该槽位同名的旧文件。
///
/// 匹配规则：主文件名等于目标名，即 `login_bg`、`login_bg.png`、`login_bg.jpg` 都会被清理，
/// `*.bak` 备份文件保留，即将写入的文件交由 copy 覆盖。
fn remove_same_name_files(target_file: &Path, slot_file_name: &str) -> Vec<String> {
    let mut removed = Vec::new();

    let dir = match target_file.parent() {
        Some(parent) => parent,
        None => return removed,
    };

    let base = slot_file_name.to_lowercase();
    let prefix = format!("{base}.");
    let target_lower = target_file.to_string_lossy().to_lowercase();

    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return removed,
    };

    for entry in entries.flatten() {
        let is_file = match entry.file_type() {
            Ok(file_type) => file_type.is_file(),
            Err(_) => false,
        };
        if !is_file {
            continue;
        }

        let name = entry.file_name().to_string_lossy().to_string();
        let lower = name.to_lowercase();

        if lower == base || lower.starts_with(&prefix) {
            if lower.ends_with(".bak") {
                continue;
            }
            let full = entry.path();
            if full.to_string_lossy().to_lowercase() == target_lower {
                continue;
            }
            if fs::remove_file(&full).is_ok() {
                removed.push(name);
            }
        }
    }

    removed
}

/// 根据文件名猜测所属槽位：命中的关键字越长优先级越高
#[flutter_rust_bridge::frb(ignore)]
pub fn guess_slot(file_name: &str) -> Option<String> {
    let name = base_name_of(file_name).to_lowercase();
    if name.is_empty() {
        return None;
    }

    let mut best_key: Option<String> = None;
    let mut best_score = 0usize;

    for slot in ASSET_SLOTS {
        for keyword in slot.keywords {
            if name.contains(keyword) && keyword.chars().count() > best_score {
                best_score = keyword.chars().count();
                best_key = Some(slot.key.to_string());
            }
        }
    }

    best_key
}

/// 文件名与目标文件名完全一致时（如 `login_bg`），即使没有扩展名也视为可用图片
fn match_slot_file(file_name: &str) -> Option<String> {
    let name = base_name_of(file_name).to_lowercase();
    ASSET_SLOTS
        .iter()
        .find(|item| item.file_name.to_lowercase() == name)
        .map(|slot| slot.key.to_string())
}

/// 递归收集目录下的图片文件
fn scan_images(dir: &Path, depth: usize, collected: &mut Vec<DroppedImage>) {
    if depth > MAX_SCAN_DEPTH || collected.len() >= MAX_SCAN_IMAGES {
        return;
    }

    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        if collected.len() >= MAX_SCAN_IMAGES {
            break;
        }

        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        let name = entry.file_name().to_string_lossy().to_string();

        if file_type.is_dir() {
            if IGNORED_DIRS.contains(&name.as_str()) {
                continue;
            }
            scan_images(&path, depth + 1, collected);
            continue;
        }

        let slot_key = match_slot_file(&name);
        if is_image_file_name(&name) || slot_key.is_some() {
            let suggested_slot = guess_slot(&name).or(slot_key);
            collected.push(DroppedImage {
                path: path.to_string_lossy().to_string(),
                file_name: name,
                suggested_slot,
            });
        }
    }
}

/// 判断目录是否像 Android 工程根目录（含 src/main/assets 或 AgentAssets）
fn looks_like_project_root(dir: &Path) -> bool {
    if dir.join("src").join("main").join("assets").exists() {
        return true;
    }

    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return false,
    };

    let mut sub_dirs: Vec<String> = Vec::new();

    for entry in entries.flatten() {
        let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
        if !is_dir {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name == "AgentAssets" || name == "src" || name == "main" {
            return true;
        }
        sub_dirs.push(name);
    }

    for name in sub_dirs {
        if IGNORED_DIRS.contains(&name.as_str()) {
            continue;
        }
        let sub_entries = match fs::read_dir(dir.join(&name)) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for sub in sub_entries.flatten() {
            let is_dir = sub.file_type().map(|t| t.is_dir()).unwrap_or(false);
            if !is_dir {
                continue;
            }
            let sub_name = sub.file_name().to_string_lossy().to_string();
            if sub_name == "AgentAssets" || sub_name == "src" {
                return true;
            }
        }
    }

    false
}

/* -------------------------------------------------------------------------- */
/*                                  对外接口                                   */
/* -------------------------------------------------------------------------- */

/// 三个素材槽位的界面定义
pub fn asset_slots() -> Vec<SlotDefinition> {
    ASSET_SLOTS
        .iter()
        .map(|slot| SlotDefinition {
            key: slot.key.to_string(),
            label: slot.label.to_string(),
            relative_path: slot.relative_path.to_string(),
            file_name: slot.file_name.to_string(),
            relative_dir: slot.relative_dir.to_string(),
            description: slot.description.to_string(),
        })
        .collect()
}

/// 扫描项目目录，返回三个槽位当前的状态与预览
pub fn inspect_project(project_dir: String) -> ProjectInspectResult {
    let project_dir = project_dir.trim().to_string();
    let mut missing_dirs: Vec<String> = Vec::new();
    let dir_exists = is_directory(Path::new(&project_dir));

    for relative_dir in ["src/main/assets", "src/main/assets/AgentAssets"] {
        if !exists(&to_absolute(&project_dir, relative_dir)) {
            missing_dirs.push(relative_dir.to_string());
        }
    }

    // 三个槽位的读盘与缩略图编码互不依赖，并行处理以缩短等待
    let slots: Vec<SlotInspectInfo> = std::thread::scope(|scope| {
        let handles: Vec<_> = ASSET_SLOTS
            .iter()
            .map(|slot| {
                let target_path = to_absolute(&project_dir, slot.relative_path);
                scope.spawn(move || build_slot_inspect(slot, &target_path, dir_exists))
            })
            .collect();

        handles
            .into_iter()
            .filter_map(|handle| handle.join().ok())
            .collect()
    });

    if !dir_exists {
        return ProjectInspectResult {
            project_dir,
            exists: false,
            structure_ok: false,
            missing_dirs,
            message: "目录不存在或不是一个文件夹".to_string(),
            slots,
        };
    }

    if !missing_dirs.is_empty() {
        return ProjectInspectResult {
            project_dir,
            exists: true,
            structure_ok: false,
            message: format!(
                "未检测到标准目录结构，缺失：{}（替换时会自动创建）",
                missing_dirs.join("、")
            ),
            missing_dirs,
            slots,
        };
    }

    let missing_files: Vec<String> = ASSET_SLOTS
        .iter()
        .filter(|slot| {
            !slots
                .iter()
                .find(|info| info.slot == slot.key)
                .map(|info| info.exists)
                .unwrap_or(false)
        })
        .map(|slot| slot.file_name.to_string())
        .collect();

    let message = if missing_files.is_empty() {
        "目录结构正常".to_string()
    } else {
        format!("目标图片缺失：{}（替换时会自动创建）", missing_files.join("、"))
    };

    ProjectInspectResult {
        project_dir,
        exists: true,
        structure_ok: true,
        missing_dirs,
        message,
        slots,
    }
}

/// 扫描单个槽位：找现有文件、取体积与缩略图
fn build_slot_inspect(slot: &AssetSlot, target_path: &Path, dir_exists: bool) -> SlotInspectInfo {
    let existing_path = if dir_exists {
        find_existing_file(target_path)
    } else {
        None
    };
    let size = existing_path
        .as_ref()
        .and_then(|path| fs::metadata(path).ok())
        .map(|meta| meta.len());
    let preview = existing_path
        .as_ref()
        .and_then(|path| read_preview(&path.to_string_lossy()));
    let exists = existing_path.is_some();

    SlotInspectInfo {
        slot: slot.key.to_string(),
        slot_label: slot.label.to_string(),
        target_path: target_path.to_string_lossy().to_string(),
        existing_path: existing_path.map(|path| path.to_string_lossy().to_string()),
        exists,
        size,
        preview,
    }
}

/// 解析拖放进来的路径（可能是图片文件，也可能是文件夹）
pub fn resolve_drop(paths: Vec<String>) -> ResolveDropResult {
    let mut images: Vec<DroppedImage> = Vec::new();
    let mut dirs: Vec<String> = Vec::new();
    let mut project_dir: Option<String> = None;

    for target in &paths {
        let path = Path::new(target);

        if is_directory(path) {
            dirs.push(target.clone());
            continue;
        }

        let slot_key = match_slot_file(target);
        if (is_image_file_name(target) || slot_key.is_some()) && is_file(path) {
            images.push(DroppedImage {
                path: target.clone(),
                file_name: base_name_of(target),
                suggested_slot: guess_slot(target).or(slot_key),
            });
        }
    }

    for dir in dirs {
        if project_dir.is_none() && looks_like_project_root(Path::new(&dir)) {
            project_dir = Some(dir);
            continue;
        }
        scan_images(Path::new(&dir), 1, &mut images);
    }

    // 拖入同一张图片多次时只保留一次
    let mut seen: HashSet<String> = HashSet::new();
    images.retain(|image| seen.insert(image.path.clone()));

    ResolveDropResult { project_dir, images }
}

/// 执行替换：按工程要求的名字写入目标位置
pub fn apply_assets(payload: ApplyPayload) -> ApplyResult {
    let project_dir = payload.project_dir.trim();

    if project_dir.is_empty() {
        return ApplyResult {
            success: false,
            message: "请先选择项目工程目录".to_string(),
            items: Vec::new(),
        };
    }
    if !is_directory(Path::new(project_dir)) {
        return ApplyResult {
            success: false,
            message: "项目工程目录不存在".to_string(),
            items: Vec::new(),
        };
    }
    if payload.items.is_empty() {
        return ApplyResult {
            success: false,
            message: "请先选择要替换的图片".to_string(),
            items: Vec::new(),
        };
    }

    let mut items: Vec<ApplyResultItem> = Vec::new();

    for item in &payload.items {
        let slot = match get_slot(&item.slot) {
            Some(slot) => slot,
            None => {
                items.push(ApplyResultItem {
                    slot: item.slot.clone(),
                    slot_label: item.slot.clone(),
                    source_path: item.source_path.clone(),
                    target_path: String::new(),
                    ok: false,
                    message: format!("未知的图片槽位: {}", item.slot),
                    backup_path: None,
                });
                continue;
            }
        };

        let base_target = to_absolute(project_dir, slot.relative_path);

        match apply_single(item, &payload, slot, &base_target) {
            Ok(result) => items.push(result),
            Err(error) => items.push(ApplyResultItem {
                slot: slot.key.to_string(),
                slot_label: slot.label.to_string(),
                source_path: item.source_path.clone(),
                target_path: base_target.to_string_lossy().to_string(),
                ok: false,
                message: error,
                backup_path: None,
            }),
        }
    }

    let failed = items.iter().filter(|item| !item.ok).count();

    ApplyResult {
        success: failed == 0,
        message: if failed == 0 {
            format!("已成功替换 {} 张图片", items.len())
        } else {
            format!("{failed} 张替换失败")
        },
        items,
    }
}

/// 写入单个槽位：按源图扩展名或工程要求命名，清理旧文件后落盘
fn apply_single(
    item: &ApplyPayloadItem,
    payload: &ApplyPayload,
    slot: &'static AssetSlot,
    base_target: &Path,
) -> Result<ApplyResultItem, String> {
    let source_path = Path::new(&item.source_path);
    if !is_file(source_path) {
        return Err("源图片不存在或不是文件".to_string());
    }

    // 工程不带扩展名时保持不变，保留扩展名时按源图的实际扩展名命名
    let ext = if payload.keep_extension {
        ext_name_of(&item.source_path)
    } else {
        String::new()
    };
    let target_file = PathBuf::from(format!("{}{}", base_target.to_string_lossy(), ext));

    if let Some(parent) = target_file.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    // 写入前清理该槽位下所有同名旧文件（login_bg、login_bg.png、login_bg.jpg …），避免新旧并存
    let removed = remove_same_name_files(&target_file, slot.file_name);

    let mut backup_path: Option<String> = None;
    if payload.backup && exists(&target_file) {
        let backup = PathBuf::from(format!("{}.bak", target_file.to_string_lossy()));
        fs::copy(&target_file, &backup).map_err(|error| error.to_string())?;
        backup_path = Some(backup.to_string_lossy().to_string());
    }

    fs::copy(source_path, &target_file).map_err(|error| error.to_string())?;

    Ok(ApplyResultItem {
        slot: slot.key.to_string(),
        slot_label: slot.label.to_string(),
        source_path: item.source_path.clone(),
        target_path: target_file.to_string_lossy().to_string(),
        ok: true,
        message: if removed.is_empty() {
            "替换成功".to_string()
        } else {
            format!("替换成功（已清理旧文件 {}）", removed.join("、"))
        },
        backup_path,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_is_downscaled_for_large_images() {
        let root = std::env::temp_dir().join("pictool-preview-test");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        // 构造一张大且压缩率低的图，模拟真实截图 / 照片
        let source = root.join("big.png");
        let mut image = image::RgbImage::new(2000, 1500);
        for (x, y, pixel) in image.enumerate_pixels_mut() {
            *pixel = image::Rgb([(x % 256) as u8, (y % 256) as u8, ((x + y) % 256) as u8]);
        }
        image.save(&source).unwrap();

        let preview = read_preview(&source.to_string_lossy()).expect("应生成预览");

        // 缩略图体积必须远小于原图，否则桥接与前端解码都会卡
        let original_size = fs::metadata(&source).unwrap().len() as usize;
        assert!(preview.len() < 100 * 1024, "缩略图体积过大：{} 字节", preview.len());
        assert!(preview.len() * 10 < original_size, "缩略图未显著压缩");

        // 解出来的像素尺寸必须落在预览上限内
        let (width, height) = image::load_from_memory(&preview).unwrap().dimensions();
        assert!(
            width.max(height) <= PREVIEW_MAX_EDGE,
            "缩略图最长边 {width}x{height} 超出上限"
        );

        let _ = fs::remove_dir_all(&root);
    }
}
