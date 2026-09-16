import 'dart:async';

import 'package:flutter/widgets.dart';

import '../bridge/pictool_api.dart';
import '../models/picked_image.dart';
import '../rust/api/assets.dart';
import '../rust/api/icon.dart';
import 'drop_zone.dart';

/// 「素材配置」页的状态：工程目录 → 三个素材槽位 → 应用图标替换。
///
/// 对应原 Tauri 前端的 `useAssetReplacer` + `useIconReplacer`，
/// 两者共享同一个工程目录，因此合并到一个控制器里统一编排替换流程。
class AssetPageController extends ChangeNotifier {
  AssetPageController({this.onError});

  /// 错误回调，由界面层转成 SnackBar 提示
  final void Function(String message)? onError;

  /* ------------------------------ 槽位定义 ------------------------------ */

  List<SlotDefinition> _slots = const <SlotDefinition>[];

  /// 三个素材槽位的定义，展示顺序与 Rust 侧一致
  List<SlotDefinition> get slots => _slots;

  /* ------------------------------ 工程目录 ------------------------------ */

  final TextEditingController projectDirController = TextEditingController();

  ProjectInspectResult? _inspect;

  ProjectInspectResult? get inspect => _inspect;

  bool _inspecting = false;

  bool get inspecting => _inspecting;

  String get projectDir => projectDirController.text.trim();

  bool _inspectImmediately = false;
  Timer? _inspectTimer;

  /* ------------------------------ 素材选择 ------------------------------ */

  final Map<String, PickedImage?> _selection = <String, PickedImage?>{};
  final Map<String, bool> _slotLoading = <String, bool>{};

  /// 槽位 key → 已选图片
  Map<String, PickedImage?> get selection => _selection;

  PickedImage? selectedOf(String slotKey) => _selection[slotKey];

  bool isSlotLoading(String slotKey) => _slotLoading[slotKey] ?? false;

  SlotInspectInfo? currentOf(String slotKey) {
    final ProjectInspectResult? result = _inspect;
    if (result == null) return null;
    for (final SlotInspectInfo info in result.slots) {
      if (info.slot == slotKey) return info;
    }
    return null;
  }

  bool _keepExtension = true;

  /// 是否保留源图片扩展名（工程默认不带扩展名）
  bool get keepExtension => _keepExtension;

  set keepExtension(bool value) {
    if (_keepExtension == value) return;
    _keepExtension = value;
    notifyListeners();
  }

  bool _backupOriginal = false;

  /// 替换前是否备份原文件为 *.bak
  bool get backupOriginal => _backupOriginal;

  set backupOriginal(bool value) {
    if (_backupOriginal == value) return;
    _backupOriginal = value;
    notifyListeners();
  }

  /* ------------------------------ 应用图标 ------------------------------ */

  IconInspectResult? _iconInspect;

  IconInspectResult? get iconInspect => _iconInspect;

  bool _iconInspecting = false;

  bool get iconInspecting => _iconInspecting;

  PickedImage? _iconSource;

  PickedImage? get iconSource => _iconSource;

  bool _iconSourceLoading = false;

  bool get iconSourceLoading => _iconSourceLoading;

  ApplyIconResult? _iconResult;

  ApplyIconResult? get iconResult => _iconResult;

  List<IconTarget> get iconTargets =>
      _iconInspect?.targets ?? const <IconTarget>[];

  /// 图标写入后使用的文件名，例如 `icon.png`
  String get iconTargetName {
    final String ext = _iconSource == null ? '' : extNameOf(_iconSource!.path);
    return 'icon${ext.isEmpty ? '.png' : ext}';
  }

  /* ------------------------------ 替换状态 ------------------------------ */

  bool _applying = false;

  bool get applying => _applying;

  ApplyResult? _result;

  ApplyResult? get result => _result;

  /* ------------------------------ 初始化 ------------------------------ */

  Future<void> initialize() async {
    projectDirController.addListener(_onProjectDirChanged);
    try {
      _slots = await PicToolApi.assetSlots();
      for (final SlotDefinition slot in _slots) {
        _selection[slot.key] = null;
        _slotLoading[slot.key] = false;
      }
    } catch (error) {
      _report(error);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _inspectTimer?.cancel();
    projectDirController.removeListener(_onProjectDirChanged);
    projectDirController.dispose();
    super.dispose();
  }

  void _report(Object error) {
    onError?.call(error.toString());
  }

  /* ------------------------------ 工程目录扫描 ------------------------------ */

  void _onProjectDirChanged() {
    if (_inspectImmediately) {
      _inspectImmediately = false;
      _inspectTimer?.cancel();
      unawaited(refreshProject());
      return;
    }
    // 手动输入时防抖，避免每敲一个字符就扫盘
    _inspectTimer?.cancel();
    _inspectTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(refreshProject()),
    );
  }

  /// 由选择器 / 拖放写入的目录无需防抖，直接扫描
  void setProjectDir(String dir) {
    final String next = dir.trim();
    if (next.isEmpty) return;
    if (next == projectDirController.text) {
      unawaited(refreshProject());
      return;
    }
    _inspectImmediately = true;
    projectDirController.text = next;
  }

  /// 素材槽位与图标目录一起重新扫描
  Future<void> refreshProject() async {
    await Future.wait(<Future<void>>[refreshInspect(), refreshIcons()]);
  }

  Future<void> refreshInspect() async {
    final String dir = projectDir;
    if (dir.isEmpty) {
      _inspect = null;
      notifyListeners();
      return;
    }

    _inspecting = true;
    notifyListeners();
    try {
      final ProjectInspectResult result = await PicToolApi.inspectProject(dir);
      // 扫描期间用户可能又改了目录，丢弃过期结果
      if (projectDir != dir) return;
      _inspect = result;
    } catch (error) {
      _inspect = null;
      _report(error);
    } finally {
      _inspecting = false;
      notifyListeners();
    }
  }

  Future<void> pickProjectDir() async {
    final String? dir = await PicToolApi.pickProjectDir();
    if (dir != null && dir.isNotEmpty) setProjectDir(dir);
  }

  /* ------------------------------ 图标扫描 ------------------------------ */

  Future<void> refreshIcons() async {
    final String dir = projectDir;
    if (dir.isEmpty) {
      _iconInspect = null;
      notifyListeners();
      return;
    }

    _iconInspecting = true;
    notifyListeners();
    try {
      final IconInspectResult result = await PicToolApi.inspectIcons(dir);
      if (projectDir != dir) return;
      _iconInspect = result;
    } catch (error) {
      _iconInspect = null;
      _report(error);
    } finally {
      _iconInspecting = false;
      notifyListeners();
    }
  }

  /* ------------------------------ 选择图片 ------------------------------ */

  Future<void> pickSlotImage(String slotKey) async {
    final String? path = await PicToolApi.pickImage();
    if (path != null) await setSlotImage(slotKey, path);
  }

  /// 读取预览（读盘 + 缩放编码）期间先展示加载态，读完再替换
  Future<void> setSlotImage(String slotKey, String path) async {
    _slotLoading[slotKey] = true;
    notifyListeners();
    try {
      _selection[slotKey] = await readPickedImage(path);
    } catch (error) {
      _report(error);
    } finally {
      _slotLoading[slotKey] = false;
      notifyListeners();
    }
  }

  void clearSlot(String slotKey) {
    _selection[slotKey] = null;
    notifyListeners();
  }

  Future<void> pickIconSource() async {
    final String? path = await PicToolApi.pickImage();
    if (path != null) await setIconSource(path);
  }

  Future<void> setIconSource(String path) async {
    _iconSourceLoading = true;
    notifyListeners();
    try {
      _iconSource = await readPickedImage(path);
    } catch (error) {
      _report(error);
    } finally {
      _iconSourceLoading = false;
      notifyListeners();
    }
  }

  void clearIconSource() {
    _iconSource = null;
    _iconResult = null;
    notifyListeners();
  }

  /* ------------------------------ 拖放处理 ------------------------------ */

  /// 处理拖放到素材页各区域的路径。
  ///
  /// - 落在某个卡片上：优先取文件名匹配该槽位的图片，否则取第一张
  /// - 落在其它位置：文件夹若像工程根目录则作为工程目录，图片按文件名自动分配
  Future<void> handleDrop(String? zoneId, List<String> paths) async {
    if (zoneId == null || paths.isEmpty) return;

    final ResolveDropResult resolved;
    try {
      resolved = await PicToolApi.resolveDrop(paths);
    } catch (error) {
      _report(error);
      return;
    }

    final String? slotKey = _slotKeyFromZone(zoneId);
    if (slotKey != null) {
      if (resolved.images.isEmpty) {
        _report('未识别到可用的图片文件');
        return;
      }
      DroppedImage matched = resolved.images.first;
      for (final DroppedImage image in resolved.images) {
        if (image.suggestedSlot == slotKey) {
          matched = image;
          break;
        }
      }
      await setSlotImage(slotKey, matched.path);
      return;
    }

    if (zoneId == DropZoneIds.iconSource) {
      if (resolved.images.isEmpty) {
        _report('未识别到可用的图片文件');
        return;
      }
      await setIconSource(resolved.images.first.path);
      return;
    }

    if (zoneId != DropZoneIds.project) return;

    final String? projectDir = resolved.projectDir;
    if (projectDir != null) setProjectDir(projectDir);

    if (resolved.images.isEmpty) {
      if (projectDir == null) _report('未识别到可用的图片文件');
      return;
    }

    for (final DroppedImage image in resolved.images) {
      final String? target = image.suggestedSlot ?? _nextEmptySlot();
      if (target != null) await setSlotImage(target, image.path);
    }
  }

  String? _slotKeyFromZone(String zoneId) {
    const String prefix = 'slot:';
    if (!zoneId.startsWith(prefix)) return null;
    return zoneId.substring(prefix.length);
  }

  /// 找到第一个还没选图的槽位，用于无法识别归属时的兜底分配
  String? _nextEmptySlot() {
    for (final SlotDefinition slot in _slots) {
      if (_selection[slot.key] == null) return slot.key;
    }
    return null;
  }

  /* ------------------------------ 派生状态 ------------------------------ */

  int get selectedCount =>
      _selection.values.where((PickedImage? image) => image != null).length;

  /// 计算某个槽位最终写入的文件名
  String targetNameFor(String slotKey) {
    final SlotInspectInfo? current = currentOf(slotKey);
    final String? existing = current?.existingPath;
    if (existing != null && existing.isNotEmpty) return baseNameOf(existing);

    final SlotDefinition? slot = _slotOf(slotKey);
    if (slot == null) return '';

    final PickedImage? source = _selection[slotKey];
    final String ext = source == null ? '' : extNameOf(source.path);
    return '${slot.fileName}$ext';
  }

  SlotDefinition? _slotOf(String key) {
    for (final SlotDefinition slot in _slots) {
      if (slot.key == key) return slot;
    }
    return null;
  }

  bool get canApplyAssets =>
      projectDir.isNotEmpty && selectedCount > 0 && !_applying;

  bool get canApplyIcons =>
      projectDir.isNotEmpty &&
      _iconSource != null &&
      iconTargets.isNotEmpty &&
      !_applying;

  /// 角标：待替换的背景图张数 + 待替换的 drawable 目录数
  int get totalCount => selectedCount + iconTargets.length;

  /* ------------------------------ 执行替换 ------------------------------ */

  /// 统一替换：素材与图标串行执行，最后合并成一份结果。
  Future<ApplyResult?> applyAll() async {
    final bool withAssets = canApplyAssets;
    final bool withIcons = canApplyIcons;
    if (!withAssets && !withIcons || _applying) return null;

    _applying = true;
    notifyListeners();
    try {
      final ApplyResult? assetsResult = withAssets
          ? await _applyAssets()
          : null;
      final ApplyIconResult? iconResult = withIcons
          ? await _applyIcons()
          : null;
      _result = _merge(assetsResult, iconResult);
      return _result;
    } finally {
      _applying = false;
      notifyListeners();
    }
  }

  Future<ApplyResult?> _applyAssets() async {
    final List<ApplyPayloadItem> items = <ApplyPayloadItem>[];
    for (final MapEntry<String, PickedImage?> entry in _selection.entries) {
      final PickedImage? image = entry.value;
      if (image != null) {
        items.add(ApplyPayloadItem(slot: entry.key, sourcePath: image.path));
      }
    }
    if (items.isEmpty) return null;

    try {
      return await PicToolApi.applyAssets(
        projectDir: projectDir,
        backup: _backupOriginal,
        keepExtension: _keepExtension,
        items: items,
      );
    } catch (error) {
      _report(error);
      return null;
    } finally {
      unawaited(refreshInspect());
    }
  }

  Future<ApplyIconResult?> _applyIcons() async {
    final PickedImage? source = _iconSource;
    if (source == null) return null;

    try {
      final ApplyIconResult result = await PicToolApi.applyIcon(
        projectDir: projectDir,
        sourcePath: source.path,
      );
      _iconResult = result;
      return result;
    } catch (error) {
      _report(error);
      return null;
    } finally {
      unawaited(refreshIcons());
    }
  }

  /// 把图标结果并入素材结果，形成统一的结果弹窗数据
  ApplyResult? _merge(ApplyResult? base, ApplyIconResult? icon) {
    if (icon == null) return base;

    final List<ApplyResultItem> iconItems = icon.items
        .map(
          (ApplyIconItem item) => ApplyResultItem(
            slot: 'icon:${item.dirName}',
            slotLabel: item.dirName,
            sourcePath: _iconSource?.path ?? '',
            targetPath: item.targetPath,
            ok: item.ok,
            message: item.message,
            backupPath: null,
          ),
        )
        .toList();

    final List<ApplyResultItem> items = <ApplyResultItem>[
      ...?base?.items,
      ...iconItems,
    ];
    final int failed = items.where((ApplyResultItem item) => !item.ok).length;
    final String message = <String>[
      if (base != null && base.message.isNotEmpty) base.message,
      if (icon.message.isNotEmpty) icon.message,
    ].join('；');

    return ApplyResult(success: failed == 0, message: message, items: items);
  }

  /* ------------------------------ 重置 ------------------------------ */

  void reset() {
    for (final String key in _selection.keys.toList()) {
      _selection[key] = null;
    }
    _iconSource = null;
    _iconResult = null;
    _result = null;
    notifyListeners();
  }
}
