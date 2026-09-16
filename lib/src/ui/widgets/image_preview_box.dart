import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'dashed_border.dart';

/// 图片预览框。
///
/// - 图片内容变化时做淡入 + 轻微缩放过渡，不会生硬跳变
/// - 传入 [heroTag] 后可与全屏查看器共享 Hero 飞行
/// - 传入 [onTap] 后可点击放大
/// - [cornerAction] 用于在右上角挂一个小操作（例如图标源图的放大按钮）
class ImagePreviewBox extends StatelessWidget {
  const ImagePreviewBox({
    super.key,
    required this.bytes,
    required this.placeholder,
    this.height = 92,
    this.loading = false,
    this.loadingLabel = '读取中…',
    this.highlighted = false,
    this.dashed = false,
    this.rounded = 10,
    this.heroTag,
    this.onTap,
    this.tapTooltip = '点击放大查看',
    this.cornerAction,
  });

  final Uint8List? bytes;
  final String placeholder;
  final double height;
  final bool loading;
  final String loadingLabel;
  final bool highlighted;
  final bool dashed;
  final double rounded;

  /// 与全屏查看器共享的 Hero 标识
  final String? heroTag;

  /// 点击回调（通常用于放大查看），为空时不可点击
  final VoidCallback? onTap;
  final String tapTooltip;

  /// 右上角操作按钮
  final Widget? cornerAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Uint8List? data = bytes;

    final Color borderColor = highlighted
        ? AppColors.primary.withValues(alpha: 0.6)
        : const Color(0xFFE1E7F2);

    Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
      child: (data != null && data.isNotEmpty)
          ? Padding(
              key: ValueKey<Uint8List>(data),
              padding: const EdgeInsets.all(6),
              child: Image.memory(
                data,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _placeholder(theme, '无法预览'),
              ),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('empty'),
              child: _placeholder(theme, placeholder),
            ),
    );

    // Hero 包在 AnimatedSwitcher 外层，保证同一时刻只有一个同名 Hero
    final String? tag = heroTag;
    if (tag != null && data != null && data.isNotEmpty) {
      content = Hero(tag: tag, child: content);
    }

    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(rounded),
        border: dashed ? null : Border.all(color: borderColor),
        boxShadow: highlighted
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rounded - 1),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            content,
            if (loading) _loadingOverlay(theme),
            if (cornerAction != null)
              Positioned(top: 6, right: 6, child: cornerAction!),
          ],
        ),
      ),
    );

    if (dashed) {
      box = DashedRoundedBorder(
        radius: rounded,
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.65)
            : const Color(0xFFD5DEEE),
        child: box,
      );
    }

    final VoidCallback? tap = onTap;
    if (tap != null && data != null && data.isNotEmpty) {
      box = Tooltip(
        message: tapTooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: tap,
            behavior: HitTestBehavior.opaque,
            child: box,
          ),
        ),
      );
    }

    return box;
  }

  Widget _placeholder(ThemeData theme, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            size: 22,
            color: theme.colorScheme.outline.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingOverlay(ThemeData theme) {
    return ColoredBox(
      color: const Color(0xFFF3F7FF).withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 8),
            Text(
              loadingLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预览框右上角的小圆形操作按钮
class PreviewCornerButton extends StatelessWidget {
  const PreviewCornerButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE1E7F2)),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 14, color: AppColors.primary),
          ),
        ),
      ),
    );

    final String? tip = tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}
