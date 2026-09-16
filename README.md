# 图片处理工具（Flutter + Rust + flutter_rust_bridge）

把原 `tauri-project/`（Tauri + Vue3 + Element Plus）的「背景 / 图标替换工具」完整移植为
**Flutter（Material 3 前端）+ Rust（核心能力）+ flutter_rust_bridge（桥接）** 的桌面应用。

- 界面：Flutter Material 3，单窗口、双页签、玻璃拟态卡片 + 柔光环境背景
- 业务：全部在 Rust 侧实现，通过 flutter_rust_bridge 生成的类型安全绑定调用
- 原生：文件 / 目录选择用 `file_picker`，文件拖放用 `desktop_drop`

## 功能

| 页签 | 能力 |
| --- | --- |
| 素材配置 | 扫描 Android 工程目录 → 替换 `login_bg` / `loading_bg` / `splash_image_0` 三个素材 → 同时按各 `drawable*` 目录原有像素替换应用图标，最后统一展示结果 |
| 图片格式转换 | 批量转换 JPG / PNG / WEBP / BMP，可只填单边按比例缩放或双填等比放入框内，可选转换后删除原文件 |

支持把**图片文件**或**整个文件夹**拖进窗口：拖到具体卡片上即替换该素材，拖到工程目录区即设为工程根目录，
落在其它位置则按文件名关键字自动分配槽位。

## 交互动效

所有状态变化都有过渡，没有生硬的瞬切：

| 场景 | 动效 |
| --- | --- |
| 预览图 → 全屏查看 | **Hero 飞行**：缩略图从卡片原位放大到全屏，落位后淡入一张最长边 1600 的清晰预览（Rust 侧按需生成）；点击空白或按 Esc 反向飞回。工程里的现有图、待替换图、图标源图、每个 drawable 目录的图标都可点开放大 |
| 页签切换 | 内容按切换方向滑入 / 滑出并交叉淡入（`FractionalTranslation` + `FadeTransition`），顶栏说明文案同步上浮淡入 |
| 卡片入场 | `FadeSlideIn` 错峰出现（工程目录 → 三张图片 → 图标替换 → 提示） |
| 图片替换 | 预览框内容交叉淡入 + 从 0.94 轻微放大，不是瞬间换图 |
| 拖放悬停 | 边框点亮、底色渐变、光晕扩散，脉冲点加速 |
| 格式转换列表 | `AnimatedList` 驱动增删：新条目展开淡入，移除条目收起淡出，整块区域高度平滑过渡 |
| 状态与标签 | 目录状态标签、目标文件名、结果行、drawable 计数均带过渡 |
| 主按钮 | 悬停上浮 + 光晕增强，按下缩放到 0.975 |
| 结果弹窗 | 逐条错峰入场，对勾描边逐段绘制 |

性能上做了收敛：纯装饰的环境背景把动画进度量化到 ~15fps 再重绘，箭头只在选中图片后才动，
列表动画跑完即释放，避免空闲时持续占用 GPU。

## 目录结构

```
lib/
  main.dart                       # 入口：先 RustLib.init() 再启动 UI
  src/
    app.dart                      # MaterialApp
    theme/app_theme.dart          # Material 3 主题与品牌配色
    bridge/pictool_api.dart       # 原生能力封装（文件选择 + Rust 调用）
    models/picked_image.dart      # 选中图片模型与路径工具
    state/
      asset_page_controller.dart  # 素材配置页状态（工程目录 / 槽位 / 图标 / 统一替换）
      convert_controller.dart     # 格式转换页状态
      drop_zone.dart              # 拖放区域注册与全局坐标命中测试
    ui/
      home_page.dart              # 顶栏、页签、拖放分发
      widgets/                    # 卡片、预览框、结果弹窗等组件
    rust/                         # flutter_rust_bridge 生成的 Dart 绑定（勿手改）

rust/
  src/lib.rs
  src/api/mod.rs                  # 模块导出、初始化与端到端流程测试
  src/api/assets.rs               # 素材槽位：扫描 / 拖放解析 / 预览 / 替换
  src/api/icon.rs                 # 应用图标：扫描 drawable* / 按原尺寸替换
  src/api/convert.rs              # 图片格式转换
  src/frb_generated.rs            # 生成的桥接代码（勿手改）

rust_builder/                     # cargokit 脚手架：把 Rust 编译产物接进各平台构建
flutter_rust_bridge.yaml          # 代码生成配置
```

## 开发

```bash
flutter pub get

# 修改 rust/src/api/** 后重新生成绑定
flutter_rust_bridge_codegen generate

# 运行
flutter run -d windows

# 测试
cargo test --manifest-path rust/Cargo.toml   # Rust 逻辑（含端到端流程）
flutter test                                 # Flutter 组件

# 发布构建
flutter build windows --release
```

## 与 Tauri 版本的对应关系

| Tauri 版本 | 本版本 |
| --- | --- |
| `#[tauri::command]` + `invoke()` | `rust/src/api/**` + `flutter_rust_bridge` 生成的 `lib/src/rust/api/**` |
| `login_bg` 等 base64 dataURL 预览 | Rust 直接回传缩略图 **字节流**，Flutter 用 `Image.memory` 渲染，省掉 base64 编解码 |
| `@tauri-apps/plugin-dialog` | `file_picker` |
| `webview.onDragDropEvent` + 坐标命中 | `desktop_drop` 的 `DropTarget` + `DropZoneRegistry` 坐标命中 |
| `useAssetReplacer` / `useIconReplacer` | `AssetPageController`（合并为一个控制器，统一编排替换） |
| Element Plus 组件 | Material 3 组件（`SegmentedButton` / `Switch` / `DataTable` / `SnackBar` …） |

Rust 侧的槽位定义、关键字识别、旧文件清理、缩略图生成、缩放策略等业务规则均与原版保持一致，
并额外让 `open_image()` 统一按文件头嗅探格式，使 `login_bg` 这类**不带扩展名**的素材也能正常
解码与生成缩略图（原版此处会退化成整张原图直传）。
