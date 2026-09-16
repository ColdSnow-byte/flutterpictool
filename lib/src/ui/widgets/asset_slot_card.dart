import 'package:flutter/material.dart';

import '../../models/picked_image.dart';
import '../../rust/api/assets.dart';
import '../../state/asset_page_controller.dart';
import '../../state/drop_zone.dart';
import '../../theme/app_theme.dart';
import 'fade_slide_in.dart';
import 'image_preview_box.dart';
import 'image_viewer.dart';

/// 单个素材槽位卡片：左边是工程里现有的图，右边是要替换成的图。
/// 两张图都可以点击放大（Hero 飞行到全屏查看器）。
class AssetSlotCard extends StatelessWidget {
  const AssetSlotCard({
    super.key,
    required this.slot,
    required this.controller,
    this.index = 0,
  });

  final SlotDefinition slot;
  final AssetPageController controller;

  /// 用于入场动画的错峰延迟
  final int index;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      delay: staggerDelay(index, step: const Duration(milliseconds: 60)),
      offset: 18,
      scaleFrom: 0.98,
      child: DropZone(
        id: DropZoneIds.slot(slot.key),
        builder: (BuildContext context, bool hovered) =>
            _build(context, hovered),
      ),
    );
  }

  Widget _build(BuildContext context, bool hovered) {
    final ThemeData theme = Theme.of(context);
    final SlotInspectInfo? current = controller.currentOf(slot.key);
    final PickedImage? selected = controller.selectedOf(slot.key);
    final bool ready = selected != null;
    final bool loadingCurrent = controller.inspecting;
    final bool loadingSelected = controller.isSlotLoading(slot.key);

    final Color borderColor = hovered
        ? theme.colorScheme.primary
        : ready
        ? AppColors.primary.withValues(alpha: 0.35)
        : AppColors.borderGlass;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hovered
              ? <Color>[
                  AppColors.primary.withValues(alpha: 0.16),
                  AppColors.violet.withValues(alpha: 0.12),
                ]
              : <Color>[
                  Colors.white.withValues(alpha: 0.68),
                  Colors.white.withValues(alpha: 0.44),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: hovered ? 1.4 : 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (hovered ? AppColors.primary : const Color(0xFF1F2D3D))
                .withValues(alpha: hovered ? 0.24 : 0.07),
            blurRadius: hovered ? 26 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _head(context, ready, hovered),
          const SizedBox(height: 10),
          _previewRow(
            context: context,
            current: current,
            selected: selected,
            loadingCurrent: loadingCurrent,
            loadingSelected: loadingSelected,
          ),
          const SizedBox(height: 10),
          _fileInfo(context, selected),
          const SizedBox(height: 10),
          _actions(context, selected),
        ],
      ),
    );
  }

  Widget _head(BuildContext context, bool ready, bool hovered) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        _PulseDot(active: ready || hovered),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            slot.label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: slot.description,
          child: Icon(
            Icons.help_outline_rounded,
            size: 15,
            color: theme.colorScheme.outline,
          ),
        ),
        const Spacer(),
        _PathTag(text: slot.relativeDir),
      ],
    );
  }

  Widget _previewRow({
    required BuildContext context,
    required SlotInspectInfo? current,
    required PickedImage? selected,
    required bool loadingCurrent,
    required bool loadingSelected,
  }) {
    final String? existingPath = current?.existingPath;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _PreviewLabel(text: '项目现有'),
              const SizedBox(height: 5),
              ImagePreviewBox(
                bytes: current?.preview,
                placeholder: (current?.exists ?? false) ? '预览过大' : '暂无图片',
                loading: loadingCurrent,
                loadingLabel: '读取工程图片…',
                heroTag: 'slot-current-${slot.key}',
                onTap: () => showImageViewer(
                  context,
                  heroTag: 'slot-current-${slot.key}',
                  thumbnail: current!.preview!,
                  title: '${slot.label} · 项目现有',
                  subtitle: existingPath,
                  sourcePath: existingPath,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 34, left: 4, right: 4),
          child: _BobbingArrow(active: selected != null),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _PreviewLabel(text: '替换为'),
              const SizedBox(height: 5),
              ImagePreviewBox(
                bytes: selected?.preview,
                placeholder: '拖入或选择图片',
                loading: loadingSelected,
                highlighted: selected != null,
                dashed: selected == null,
                heroTag: 'slot-selected-${slot.key}',
                onTap: () => showImageViewer(
                  context,
                  heroTag: 'slot-selected-${slot.key}',
                  thumbnail: selected!.preview!,
                  title: '${slot.label} · 待替换为',
                  subtitle: selected.path,
                  sourcePath: selected.path,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fileInfo(BuildContext context, PickedImage? selected) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _InfoLine(
          label: '源文件',
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Tooltip(
              key: ValueKey<String>(selected?.path ?? ''),
              message: selected?.path ?? '尚未选择图片',
              child: Text(
                selected?.fileName ?? '未选择',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _InfoLine(
          label: '写入为',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                controller.targetNameFor(slot.key),
                key: ValueKey<String>(controller.targetNameFor(slot.key)),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context, PickedImage? selected) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => controller.pickSlotImage(slot.key),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
            label: const Text('选择图片'),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: OutlinedButton(
            onPressed: selected == null
                ? null
                : () => controller.clearSlot(slot.key),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: 0.35),
              ),
            ),
            child: const Text('清除'),
          ),
        ),
      ],
    );
  }
}

/// 「项目现有 → 替换为」之间的箭头：有图时点亮并左右轻移
class _BobbingArrow extends StatefulWidget {
  const _BobbingArrow({required this.active});

  final bool active;

  @override
  State<_BobbingArrow> createState() => _BobbingArrowState();
}

class _BobbingArrowState extends State<_BobbingArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    // 只有选中图片后才让箭头动起来，空闲时不占用重绘
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BobbingArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? AppColors.primary
        : const Color(0xFF9AA7BC);

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(4 * t - 2, 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            child: Icon(Icons.arrow_right_alt_rounded, size: 20, color: color),
          ),
        );
      },
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ],
    );
  }
}

class _PathTag extends StatelessWidget {
  const _PathTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF6B7A90),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 状态脉冲点：选中或拖拽悬停时点亮并扩散脉冲
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.active});

  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.active
        ? AppColors.primary
        : const Color(0xFFB8C6DC);

    if (!widget.active) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 7 + 9 * _controller.value,
                height: 7 + 9 * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(
                    alpha: 0.45 * (1 - _controller.value),
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}
