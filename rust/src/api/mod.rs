//! 图片处理工具的核心能力，按业务拆分为三块：
//!
//! - [`assets`]：Android 工程里登录页背景 / 加载页背景 / 闪屏图的替换
//! - [`icon`]：`src/main/res/drawable*` 下应用图标的批量替换
//! - [`convert`]：图片格式的批量转换与缩放

pub mod assets;
pub mod convert;
pub mod icon;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod integration {
    //! 端到端流程：扫描工程 → 替换素材 → 替换图标 → 转换格式。

    use std::fs;
    use std::path::{Path, PathBuf};

    use image::{GenericImageView, ImageFormat, Rgba, RgbaImage};

    use super::assets::{
        self, ApplyPayload, ApplyPayloadItem, ASSET_SLOTS,
    };
    use super::convert::{self, ConvertPayload};
    use super::icon::{self, ApplyIconPayload};

    /// 建一个带标准目录结构的假工程
    fn setup_project(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("pictool-e2e-{name}"));
        let _ = fs::remove_dir_all(&root);

        let assets_dir = root.join("src/main/assets/AgentAssets");
        fs::create_dir_all(&assets_dir).unwrap();
        fs::create_dir_all(root.join("src/main/res/drawable")).unwrap();
        fs::create_dir_all(root.join("src/main/res/drawable-xxhdpi")).unwrap();

        // 登录页背景带扩展名，加载页背景带透明通道，闪屏图用 jpg
        RgbaImage::from_pixel(120, 80, Rgba([10, 20, 200, 255]))
            .save(assets_dir.join("login_bg.png"))
            .unwrap();
        // 工程里真实存在不带扩展名的素材，这里同样写一个来覆盖容错查找
        RgbaImage::from_pixel(90, 60, Rgba([200, 40, 40, 128]))
            .save_with_format(assets_dir.join("loading_bg"), ImageFormat::Png)
            .unwrap();
        // JPEG 不支持透明通道，用 RGB 构造
        image::RgbImage::from_pixel(64, 64, image::Rgb([30, 180, 90]))
            .save(root.join("src/main/assets/splash_image_0.jpg"))
            .unwrap();

        for (dir, size) in [("drawable", 48u32), ("drawable-xxhdpi", 144u32)] {
            RgbaImage::from_pixel(size, size, Rgba([255, 255, 255, 255]))
                .save(root.join("src/main/res").join(dir).join("icon.png"))
                .unwrap();
        }

        root
    }

    fn write_source(root: &Path, name: &str, width: u32, height: u32) -> String {
        let path = root.join(name);
        RgbaImage::from_pixel(width, height, Rgba([120, 30, 220, 255]))
            .save(&path)
            .unwrap();
        path.to_string_lossy().to_string()
    }

    fn dimension_of(path: &Path) -> (u32, u32) {
        // 工程里的素材可能不带扩展名，统一按文件头嗅探
        assets::open_image(path).unwrap().dimensions()
    }

    #[test]
    fn full_workflow_on_a_fake_project() {
        let root = setup_project("flow");
        let project_dir = root.to_string_lossy().to_string();

        /* ---------------------- 1. 扫描工程 ---------------------- */
        let inspect = assets::inspect_project(project_dir.clone());
        assert!(inspect.exists && inspect.structure_ok, "{}", inspect.message);
        assert_eq!(inspect.slots.len(), ASSET_SLOTS.len());
        for slot in &inspect.slots {
            assert!(slot.exists, "槽位 {} 应检测到已有图片", slot.slot);
            assert!(slot.preview.is_some(), "槽位 {} 应返回预览字节", slot.slot);
        }

        /* ---------------------- 2. 拖入解析 ---------------------- */
        let login_source = write_source(&root, "login_bg_new.png", 300, 200);
        let splash_source = write_source(&root, "splash_image_0_new.png", 50, 50);
        let resolved = assets::resolve_drop(vec![login_source.clone(), splash_source.clone()]);
        assert_eq!(resolved.images.len(), 2);
        assert_eq!(
            resolved.images[0].suggested_slot.as_deref(),
            Some("login"),
            "login_bg_new.png 应识别为登录页背景"
        );
        assert_eq!(resolved.images[1].suggested_slot.as_deref(), Some("splash"));

        /* ---------------------- 3. 替换素材 ---------------------- */
        let apply = assets::apply_assets(ApplyPayload {
            project_dir: project_dir.clone(),
            backup: false,
            // 工程要求目标文件不带扩展名
            keep_extension: false,
            items: vec![
                ApplyPayloadItem {
                    slot: "login".to_string(),
                    source_path: login_source,
                },
                ApplyPayloadItem {
                    slot: "splash".to_string(),
                    source_path: splash_source,
                },
            ],
        });
        assert!(apply.success, "{}", apply.message);
        assert_eq!(apply.items.len(), 2);

        let assets_dir = root.join("src/main/assets/AgentAssets");
        assert!(assets_dir.join("login_bg").is_file(), "应写入不带扩展名的 login_bg");
        assert!(
            !assets_dir.join("login_bg.png").exists(),
            "旧的 login_bg.png 应被清理"
        );
        assert!(root.join("src/main/assets/splash_image_0").is_file());
        assert_eq!(
            dimension_of(&assets_dir.join("login_bg")),
            (300, 200),
            "替换后尺寸应与源图一致"
        );

        // 未替换的加载页背景应保持原样
        assert!(assets_dir.join("loading_bg").is_file());

        /* ---------------------- 4. 替换应用图标 ---------------------- */
        let icon_inspect = icon::inspect_icons(project_dir.clone());
        assert!(icon_inspect.root_ok, "{}", icon_inspect.message);
        assert_eq!(icon_inspect.targets.len(), 2);

        let icon_source = write_source(&root, "图标.png", 512, 512);
        let icon_result = icon::apply_icon(ApplyIconPayload {
            project_dir: project_dir.clone(),
            source_path: icon_source,
        });
        assert!(icon_result.success, "{}", icon_result.message);

        let res_dir = root.join("src/main/res");
        assert_eq!(dimension_of(&res_dir.join("drawable/icon.png")), (48, 48));
        assert_eq!(
            dimension_of(&res_dir.join("drawable-xxhdpi/icon.png")),
            (144, 144)
        );

        /* ---------------------- 5. 格式转换 ---------------------- */
        let convert_source = root.join("src/main/assets/splash_image_0");
        let convert = convert::convert_images(ConvertPayload {
            source_paths: vec![convert_source.to_string_lossy().to_string()],
            format: "jpg".to_string(),
            width: Some(32),
            height: None,
            delete_original: true,
        });
        assert!(convert.success, "{}", convert.message);

        let converted = root.join("src/main/assets/splash_image_0.jpg");
        assert!(converted.is_file(), "应输出同名 jpg");
        assert_eq!(dimension_of(&converted), (32, 32));
        assert!(!convert_source.exists(), "勾选后应删除原文件");

        let _ = fs::remove_dir_all(&root);
    }
}
