import 'package:flutter/material.dart';

import '../../models/picked_image.dart';
import '../../rust/api/icon.dart';
import '../../state/asset_page_controller.dart';
import '../../state/drop_zone.dart';
import 'fade_slide_in.dart';
import 'image_preview_box.dart';
import 'image_viewer.dart';

/// 应用图标替换面板：一张源图 → 多个 drawable 目录。
///
/// 每个目录都会按它原有 icon 的像素尺寸缩放后写入，写入动作由顶部的
/// 「确认替换」统一触发（与素材替换合并成一次操作）。
class IconReplacePanel extends StatelessWidget {
  const IconReplacePanel({super.key, required this.controller});

  final AssetPageController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 720;
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: 196, child: _sourceColumn(context)),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 54,
                      ),
                      child: Icon(
                        Icons.arrow_right_alt_rounded,
                        size: 22,
                        color: Color(0xFF9AA7BC),
                      ),
                    ),
                    Expanded(child: _targetColumn(context)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _sourceColumn(context),
                    const SizedBox(height: 14),
                    _targetColumn(context),
                  ],
                ),
        );
      },
    );
  }

  /* ------------------------------ 源图 ------------------------------ */

  Widget _sourceColumn(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PickedImage? source = controller.iconSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '图标源图',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: source == null
                  ? const SizedBox.shrink(key: ValueKey<String>('none'))
                  : TextButton.icon(
                      key: const ValueKey<String>('clear'),
                      onPressed: controller.clearIconSource,
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text('清除'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropZone(
          id: DropZoneIds.iconSource,
          builder: (BuildContext context, bool hovered) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: controller.pickIconSource,
              child: ImagePreviewBox(
                bytes: source?.preview,
                placeholder: '拖入或点击选择',
                height: 104,
                loading: controller.iconSourceLoading,
                loadingLabel: '读取图标…',
                highlighted: hovered || source != null,
                dashed: source == null,
                heroTag: 'icon-source',
                cornerAction: source == null
                    ? null
                    : PreviewCornerButton(
                        icon: Icons.zoom_out_map_rounded,
                        tooltip: '放大查看',
                        onPressed: () => showImageViewer(
                          context,
                          heroTag: 'icon-source',
                          thumbnail: source.preview!,
                          title: '图标源图',
                          subtitle: source.path,
                          sourcePath: source.path,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            source?.fileName ?? '未选择',
            key: ValueKey<String>(source?.path ?? 'empty'),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /* ------------------------------ 目标列表 ------------------------------ */

  Widget _targetColumn(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<IconTarget> targets = controller.iconTargets;
    final bool inspecting = controller.iconInspecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'drawable 目录',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  targets.isEmpty
                      ? '按各目录原有像素缩放'
                      : '共 ${targets.length} 个 · 按原有像素缩放 · 写入 ${controller.iconTargetName}',
                  key: ValueKey<String>(
                    '${targets.length}-${controller.iconTargetName}',
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: targets.isEmpty
              ? _emptyState(context, inspecting)
              : _targetGrid(context, targets),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, bool inspecting) {
    final ThemeData theme = Theme.of(context);

    final String text;
    if (controller.projectDir.isEmpty) {
      text = '请先在上方「选择项目工程目录」选好工程';
    } else if (inspecting || controller.iconInspect == null) {
      text = '正在检测 drawable 目录…';
    } else {
      final IconInspectResult inspect = controller.iconInspect!;
      text = inspect.rootOk ? '该工程下没有 drawable 目录' : inspect.message;
    }

    return Container(
      height: 120,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4F2)),
        color: Colors.white.withValues(alpha: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (inspecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Icon(
              Icons.grid_view_rounded,
              size: 22,
              color: theme.colorScheme.outline,
            ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              text,
              key: ValueKey<String>(text),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetGrid(BuildContext context, List<IconTarget> targets) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 230),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int index = 0; index < targets.length; index++)
                FadeSlideIn(
                  key: ValueKey<String>(targets[index].dirPath),
                  delay: staggerDelay(
                    index,
                    step: const Duration(milliseconds: 30),
                  ),
                  offset: 12,
                  scaleFrom: 0.97,
                  child: _TargetTile(
                    target: targets[index],
                    controller: controller,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.target, required this.controller});

  final IconTarget target;
  final AssetPageController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final ApplyIconItem? applied = controller.iconResult?.items
        .where((ApplyIconItem item) => item.dirName == target.dirName)
        .firstOrNull;

    final bool hasPreview =
        target.preview != null && target.preview!.isNotEmpty;

    Widget thumb = Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8EDF6)),
      ),
      child: hasPreview
          ? Padding(
              padding: const EdgeInsets.all(3),
              child: Hero(
                tag: 'icon-target-${target.dirName}',
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Image.memory(
                    target.preview!,
                    key: ValueKey<String>(target.dirPath),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            )
          : Text(
              '无',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
    );

    if (hasPreview) {
      thumb = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showImageViewer(
            context,
            heroTag: 'icon-target-${target.dirName}',
            thumbnail: target.preview!,
            title: target.dirName,
            subtitle:
                '${target.width ?? '?'} × ${target.height ?? '?'} · ${target.existingPath ?? '无现有图标'}',
            sourcePath: target.existingPath,
          ),
          behavior: HitTestBehavior.opaque,
          child: thumb,
        ),
      );
    }

    return Tooltip(
      message: target.dirPath,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 208,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: applied == null
                ? const Color(0xFFE4E9F2)
                : (applied.ok
                      ? const Color(0xFF1F9D63).withValues(alpha: 0.4)
                      : theme.colorScheme.error.withValues(alpha: 0.4)),
          ),
          boxShadow: applied == null
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color:
                        (applied.ok
                                ? const Color(0xFF1F9D63)
                                : theme.colorScheme.error)
                            .withValues(alpha: 0.16),
                    blurRadius: 14,
                  ),
                ],
        ),
        child: Row(
          children: <Widget>[
            thumb,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    target.dirName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${target.width ?? '?'} × ${target.height ?? '?'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: applied == null
                  ? const SizedBox.shrink(key: ValueKey<String>('idle'))
                  : Icon(
                      applied.ok
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      key: ValueKey<String>(applied.ok ? 'ok' : 'fail'),
                      size: 16,
                      color: applied.ok
                          ? const Color(0xFF1F9D63)
                          : theme.colorScheme.error,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
