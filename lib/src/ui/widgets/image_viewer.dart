import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../bridge/pictool_api.dart';

/// 打开图片放大查看器。
///
/// 缩略图会通过 [Hero] 从原位「飞」到全屏，落位后再淡入一张更清晰的预览图
/// （由 Rust 侧按最长边 1600 重新编码），因此放大后不会发虚。
Future<void> showImageViewer(
  BuildContext context, {
  required String heroTag,
  required Uint8List thumbnail,
  required String title,
  String? subtitle,
  String? sourcePath,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    _HeroImageRoute(
      heroTag: heroTag,
      thumbnail: thumbnail,
      title: title,
      subtitle: subtitle,
      sourcePath: sourcePath,
    ),
  );
}

class _HeroImageRoute extends PageRouteBuilder<void> {
  _HeroImageRoute({
    required String heroTag,
    required Uint8List thumbnail,
    required String title,
    String? subtitle,
    String? sourcePath,
  }) : super(
         opaque: false,
         barrierDismissible: true,
         barrierColor: Colors.transparent,
         barrierLabel: '关闭图片预览',
         transitionDuration: const Duration(milliseconds: 340),
         reverseTransitionDuration: const Duration(milliseconds: 260),
         pageBuilder:
             (
               BuildContext context,
               Animation<double> animation,
               Animation<double> secondaryAnimation,
             ) => _ImageViewerPage(
               heroTag: heroTag,
               thumbnail: thumbnail,
               title: title,
               subtitle: subtitle,
               sourcePath: sourcePath,
             ),
       );
}

class _ImageViewerPage extends StatefulWidget {
  const _ImageViewerPage({
    required this.heroTag,
    required this.thumbnail,
    required this.title,
    this.subtitle,
    this.sourcePath,
  });

  final String heroTag;
  final Uint8List thumbnail;
  final String title;
  final String? subtitle;
  final String? sourcePath;

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  /// 更清晰的预览图，异步加载；加载完成前先展示缩略图
  Uint8List? _sharp;

  @override
  void initState() {
    super.initState();
    _loadSharp();
  }

  Future<void> _loadSharp() async {
    final String? path = widget.sourcePath;
    if (path == null || path.isEmpty) return;
    try {
      final Uint8List? bytes = await PicToolApi.readLargePreview(path);
      if (!mounted || bytes == null || bytes.isEmpty) return;
      setState(() => _sharp = bytes);
    } catch (_) {
      // 加载失败时保持缩略图，不影响查看
    }
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = ModalRoute.of(context)!.animation!;
    final Uint8List shown = _sharp ?? widget.thumbnail;

    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeOutCubic.transform(
            animation.value.clamp(0, 1),
          );
          return ColoredBox(
            color: const Color(0xFF0F1724).withValues(alpha: 0.82 * t),
            child: Opacity(opacity: t, child: child),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 76, 56, 64),
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      child: Image.memory(
                        shown,
                        key: ValueKey<Uint8List>(shown),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ),
              _topBar(context),
              _hint(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          widget.subtitle!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.66),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _CircleIconButton(
                icon: Icons.close_rounded,
                tooltip: '关闭（Esc）',
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Text(
          '点击空白处或按 Esc 关闭',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );

    final String? tip = tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}
