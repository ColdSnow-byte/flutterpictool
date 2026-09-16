import 'package:flutter/widgets.dart';

import '../bridge/pictool_api.dart';
import '../rust/api/assets.dart';
import '../rust/api/convert.dart';

/// 可选的目标格式
class ConvertFormat {
  const ConvertFormat(this.value, this.label);

  final String value;
  final String label;

  static const List<ConvertFormat> all = <ConvertFormat>[
    ConvertFormat('jpg', 'JPG'),
    ConvertFormat('png', 'PNG'),
    ConvertFormat('webp', 'WEBP'),
    ConvertFormat('bmp', 'BMP'),
  ];
}

/// 「图片格式转换」页的状态。
class ConvertController extends ChangeNotifier {
  ConvertController({this.onError});

  final void Function(String message)? onError;

  final List<String> _files = <String>[];

  List<String> get files => List<String>.unmodifiable(_files);

  String _format = 'jpg';

  String get format => _format;

  set format(String value) {
    if (_format == value) return;
    _format = value;
    notifyListeners();
  }

  final TextEditingController widthController = TextEditingController();
  final TextEditingController heightController = TextEditingController();

  bool _deleteOriginal = false;

  bool get deleteOriginal => _deleteOriginal;

  set deleteOriginal(bool value) {
    if (_deleteOriginal == value) return;
    _deleteOriginal = value;
    notifyListeners();
  }

  bool _converting = false;

  bool get converting => _converting;

  ConvertResult? _result;

  ConvertResult? get result => _result;

  bool get canConvert => _files.isNotEmpty && !_converting;

  String get statusText {
    if (_converting) return '转换中…';
    final ConvertResult? result = _result;
    if (result != null) return result.message;
    if (_files.isEmpty) return '就绪 · 先添加要转换的图片';
    return '已添加 ${_files.length} 张，等待转换';
  }

  @override
  void dispose() {
    widthController.dispose();
    heightController.dispose();
    super.dispose();
  }

  void _report(Object error) => onError?.call(error.toString());

  void addFiles(Iterable<String> paths) {
    bool changed = false;
    for (final String path in paths) {
      if (path.isEmpty || _files.contains(path)) continue;
      _files.add(path);
      changed = true;
    }
    if (changed) {
      _result = null;
      notifyListeners();
    }
  }

  void removeFile(String path) {
    if (_files.remove(path)) {
      _result = null;
      notifyListeners();
    }
  }

  void clearFiles() {
    if (_files.isEmpty) return;
    _files.clear();
    notifyListeners();
  }

  Future<void> pickFiles() async {
    try {
      final List<String> picked = await PicToolApi.pickImages();
      if (picked.isNotEmpty) addFiles(picked);
    } catch (error) {
      _report(error);
    }
  }

  /// 拖入的路径可能包含文件夹，交给 Rust 展开成图片列表
  Future<void> handleDrop(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final ResolveDropResult resolved = await PicToolApi.resolveDrop(paths);
      final List<String> images = resolved.images
          .map((image) => image.path)
          .toList();
      if (images.isEmpty) {
        _report('未识别到可用的图片文件');
        return;
      }
      addFiles(images);
    } catch (error) {
      _report(error);
    }
  }

  /// 空字符串代表保持原尺寸
  int? _parseSize(String raw) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<ConvertResult?> start() async {
    if (!canConvert) return null;

    _converting = true;
    notifyListeners();
    try {
      final ConvertResult result = await PicToolApi.convertImages(
        sourcePaths: _files,
        format: _format,
        width: _parseSize(widthController.text),
        height: _parseSize(heightController.text),
        deleteOriginal: _deleteOriginal,
      );
      _result = result;
      // 转换完成后原文件可能已被删除，清空待转列表避免重复操作
      if (result.success) _files.clear();
      return result;
    } catch (error) {
      _report(error);
      return null;
    } finally {
      _converting = false;
      notifyListeners();
    }
  }
}
