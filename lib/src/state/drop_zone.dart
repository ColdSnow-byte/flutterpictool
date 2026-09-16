import 'package:flutter/widgets.dart';

/// 拖放区域标识。
///
/// 原 Tauri 版本靠坐标命中判断「拖到了哪个模块」，这里保留同样的思路：
/// 所有可见的放置区把自己的 [GlobalKey] 注册到 [DropZoneRegistry]，
/// 拖拽悬停时用全局坐标做命中测试，取面积最小的那个作为当前目标。
class DropZoneIds {
  const DropZoneIds._();

  static const String project = 'project';
  static const String iconSource = 'icon-source';
  static const String convert = 'convert';

  static String slot(String slotKey) => 'slot:$slotKey';
}

class DropZoneRegistry extends ChangeNotifier {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  String? _hovered;

  /// 当前拖拽悬停的区域 id，为空表示没有落在任何放置区
  String? get hovered => _hovered;

  set hovered(String? value) {
    if (_hovered == value) return;
    _hovered = value;
    notifyListeners();
  }

  /// 取得（必要时创建）某个区域对应的 [GlobalKey]
  GlobalKey keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'drop-zone-$id'));

  /// 用全局坐标找出当前悬停的区域，嵌套时取最内层（面积最小）
  String? hitTest(Offset globalPosition) {
    String? best;
    double bestArea = double.infinity;

    for (final MapEntry<String, GlobalKey> entry in _keys.entries) {
      final BuildContext? context = entry.value.currentContext;
      if (context == null) continue;

      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }

      final Offset local = renderObject.globalToLocal(globalPosition);
      if (!renderObject.paintBounds.contains(local)) continue;

      final double area = renderObject.size.width * renderObject.size.height;
      if (area < bestArea) {
        bestArea = area;
        best = entry.key;
      }
    }

    return best;
  }
}

/// 把 [DropZoneRegistry] 传递给子树
class DropZoneScope extends InheritedWidget {
  const DropZoneScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final DropZoneRegistry registry;

  static DropZoneRegistry of(BuildContext context) {
    final DropZoneScope? scope = context
        .dependOnInheritedWidgetOfExactType<DropZoneScope>();
    assert(scope != null, '未找到 DropZoneScope，请检查组件树');
    return scope!.registry;
  }

  @override
  bool updateShouldNotify(DropZoneScope oldWidget) =>
      oldWidget.registry != registry;
}

/// 声明式放置区：自动注册坐标、并把悬停状态透出给 [builder]。
class DropZone extends StatelessWidget {
  const DropZone({
    super.key,
    required this.id,
    required this.builder,
    this.enabled = true,
  });

  final String id;
  final Widget Function(BuildContext context, bool hovered) builder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return builder(context, false);

    final DropZoneRegistry registry = DropZoneScope.of(context);
    final GlobalKey key = registry.keyFor(id);

    return ListenableBuilder(
      listenable: registry,
      builder: (BuildContext context, Widget? child) => KeyedSubtree(
        key: key,
        child: builder(context, registry.hovered == id),
      ),
    );
  }
}
