import 'dart:typed_data';

import '../rust/api/assets.dart' as rust_assets;

/// 用户在界面上选中的一张图片：磁盘路径 + 已解码好的预览字节。
class PickedImage {
  const PickedImage({required this.path, required this.fileName, this.preview});

  final String path;
  final String fileName;
  final Uint8List? preview;
}

/// 取文件名（兼容 / 与 \ 两种分隔符）
String baseNameOf(String path) {
  final String normalized = path.replaceAll('\\', '/');
  final int index = normalized.lastIndexOf('/');
  return index == -1 ? normalized : normalized.substring(index + 1);
}

/// 取扩展名（小写，含点号），没有扩展名时返回空串
String extNameOf(String path) {
  final String name = baseNameOf(path);
  final int dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}

/// 读取图片预览字节；失败的图片返回不含预览的对象而不是抛异常。
Future<PickedImage?> readPickedImage(String path) async {
  final Uint8List? preview = await rust_assets.readPreview(target: path);
  return PickedImage(path: path, fileName: baseNameOf(path), preview: preview);
}
