import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../rust/api/assets.dart' as rust_assets;
import '../rust/api/convert.dart' as rust_convert;
import '../rust/api/icon.dart' as rust_icon;

/// 原生能力封装层：
/// - 文件 / 目录选择交给 `file_picker`
/// - 业务逻辑全部由 Rust 提供（flutter_rust_bridge 生成的绑定）
abstract final class PicToolApi {
  /// 支持的图片扩展名（与 Rust 侧保持一致）
  static const List<String> imageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'gif',
  ];

  /* ------------------------------ 文件选择 ------------------------------ */

  /// 选择项目工程目录
  static Future<String?> pickProjectDir() =>
      FilePicker.getDirectoryPath(dialogTitle: '选择项目工程目录');

  /// 选择单张图片
  static Future<String?> pickImage() async {
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: '选择图片',
      type: FileType.custom,
      allowedExtensions: imageExtensions,
    );
    return file?.path;
  }

  /// 选择多张图片
  static Future<List<String>> pickImages() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      dialogTitle: '选择图片',
      type: FileType.custom,
      allowedExtensions: imageExtensions,
    );
    return files
        .map((PlatformFile file) => file.path)
        .whereType<String>()
        .toList();
  }

  /* ------------------------------ 素材槽位 ------------------------------ */

  /// 三个素材槽位的定义（登录页背景 / 加载页背景 / 闪屏图）
  static Future<List<rust_assets.SlotDefinition>> assetSlots() =>
      rust_assets.assetSlots();

  /// 扫描工程目录，返回三个槽位的现状与预览
  static Future<rust_assets.ProjectInspectResult> inspectProject(
    String projectDir,
  ) => rust_assets.inspectProject(projectDir: projectDir);

  /// 解析拖放进来的路径（图片或文件夹）
  static Future<rust_assets.ResolveDropResult> resolveDrop(
    List<String> paths,
  ) => rust_assets.resolveDrop(paths: paths);

  /// 读取图片缩略图字节，供界面直接渲染
  static Future<Uint8List?> readPreview(String path) =>
      rust_assets.readPreview(target: path);

  /// 读取放大查看用的较大预览（最长边 1600），比缩略图清晰
  static Future<Uint8List?> readLargePreview(String path) =>
      rust_assets.readLargePreview(target: path);

  /// 执行素材替换
  static Future<rust_assets.ApplyResult> applyAssets({
    required String projectDir,
    required bool backup,
    required bool keepExtension,
    required List<rust_assets.ApplyPayloadItem> items,
  }) {
    return rust_assets.applyAssets(
      payload: rust_assets.ApplyPayload(
        projectDir: projectDir,
        backup: backup,
        keepExtension: keepExtension,
        items: items,
      ),
    );
  }

  /* ------------------------------ 应用图标 ------------------------------ */

  /// 扫描 `src/main/res/drawable*` 下的图标现状
  static Future<rust_icon.IconInspectResult> inspectIcons(String projectDir) =>
      rust_icon.inspectIcons(projectDir: projectDir);

  /// 把源图按各 drawable 目录原有尺寸缩放后替换图标
  static Future<rust_icon.ApplyIconResult> applyIcon({
    required String projectDir,
    required String sourcePath,
  }) {
    return rust_icon.applyIcon(
      payload: rust_icon.ApplyIconPayload(
        projectDir: projectDir,
        sourcePath: sourcePath,
      ),
    );
  }

  /* ------------------------------ 格式转换 ------------------------------ */

  /// 批量转换图片格式
  static Future<rust_convert.ConvertResult> convertImages({
    required List<String> sourcePaths,
    required String format,
    int? width,
    int? height,
    bool deleteOriginal = false,
  }) {
    return rust_convert.convertImages(
      payload: rust_convert.ConvertPayload(
        sourcePaths: sourcePaths,
        format: format,
        width: width,
        height: height,
        deleteOriginal: deleteOriginal,
      ),
    );
  }
}
