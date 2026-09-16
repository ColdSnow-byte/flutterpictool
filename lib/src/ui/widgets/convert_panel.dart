import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/picked_image.dart';
import '../../rust/api/convert.dart';
import '../../state/convert_controller.dart';
import '../../state/drop_zone.dart';
import '../../theme/app_theme.dart';
import 'fade_slide_in.dart';
import 'gradient_button.dart';
import 'section_card.dart';

/// 图片格式转换面板：拖入 / 选择图片 → 设置目标格式与尺寸 → 批量转换。
class ConvertPanel extends StatelessWidget {
  const ConvertPanel({super.key, required this.controller});

  final ConvertController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _inputSection(context),
        const SizedBox(height: 12),
        _outputSection(context),
        const SizedBox(height: 14),
        _actions(context),
        const SizedBox(height: 14),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: controller.result == null
              ? const SizedBox(width: double.infinity)
              : _resultList(context, controller.result!),
        ),
      ],
    );
  }

  /* ------------------------------ 输入文件 ------------------------------ */

  Widget _inputSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasFiles = controller.files.isNotEmpty;

    return InnerPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '输入文件',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: hasFiles
                    ? TextButton.icon(
                        key: const ValueKey<String>('clear'),
                        onPressed: controller.clearFiles,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                        label: const Text('清空'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('none')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: DropZone(
                  id: DropZoneIds.convert,
                  builder: (BuildContext context, bool hovered) =>
                      _dropZone(context, hovered),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: controller.pickFiles,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('浏览'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: hasFiles
                ? _AnimatedFileList(
                    key: const ValueKey<String>('list'),
                    controller: controller,
                  )
                : Container(
                    key: const ValueKey<String>('empty'),
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E9F2)),
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                    child: Text(
                      '还没有待转换的图片',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dropZone(BuildContext context, bool hovered) {
    final ThemeData theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: controller.pickFiles,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.primary.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovered
                  ? theme.colorScheme.primary
                  : const Color(0xFFDCE4F2),
              width: hovered ? 1.4 : 1,
            ),
            boxShadow: hovered
                ? <BoxShadow>[
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              hovered ? '松开鼠标，加入待转换列表' : '拖放图片文件或文件夹到此处，或点击浏览选择',
              key: ValueKey<bool>(hovered),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: hovered
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ------------------------------ 输出设置 ------------------------------ */

  Widget _outputSection(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InnerPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '输出设置',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const _FieldLabel(text: '目标格式'),
              SizedBox(
                width: 176,
                child: DropdownButtonFormField<String>(
                  initialValue: controller.format,
                  isDense: true,
                  items: ConvertFormat.all
                      .map(
                        (ConvertFormat item) => DropdownMenuItem<String>(
                          value: item.value,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (String? value) {
                    if (value != null) controller.format = value;
                  },
                ),
              ),
              // 这里不用 CheckboxListTile：它要求最近的 Material 祖先没有背景色，
              // 而本面板外层是带背景的分区容器，会触发 ListTile 的断言。
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    controller.deleteOriginal = !controller.deleteOriginal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Checkbox(
                        value: controller.deleteOriginal,
                        onChanged: (bool? value) =>
                            controller.deleteOriginal = value ?? false,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '转换后删除原文件',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const _FieldLabel(text: '目标宽度'),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: controller.widthController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '保持原尺寸'),
                ),
              ),
              const _FieldLabel(text: '目标高度'),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: controller.heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '保持原尺寸'),
                ),
              ),
              Text(
                '只填一边时按原比例推算，两边都填时等比放入框内',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /* ------------------------------ 操作区 ------------------------------ */

  Widget _actions(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        GradientButton(
          onPressed: controller.canConvert ? controller.start : null,
          loading: controller.converting,
          label: controller.converting ? '转换中…' : '开始转换',
          icon: Icons.play_arrow_rounded,
          minWidth: 140,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Text(
              controller.statusText,
              key: ValueKey<String>(controller.statusText),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /* ------------------------------ 结果列表 ------------------------------ */

  Widget _resultList(BuildContext context, ConvertResult result) {
    final ThemeData theme = Theme.of(context);

    return InnerPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                result.success
                    ? Icons.check_circle_rounded
                    : Icons.error_rounded,
                size: 16,
                color: result.success
                    ? AppColors.success
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.message,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (result.items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (BuildContext context, int index) => FadeSlideIn(
                    key: ValueKey<String>(result.items[index].sourcePath),
                    delay: staggerDelay(
                      index,
                      step: const Duration(milliseconds: 35),
                    ),
                    offset: 12,
                    child: _ResultRow(item: result.items[index]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                        带动画的文件列表（增删过渡）                          */
/* -------------------------------------------------------------------------- */

/// 依据 [ConvertController.files] 的增删差异，驱动 [AnimatedList] 播放插入 /
/// 移除动画，避免文件被「啪」地一下加上或抹掉。
class _AnimatedFileList extends StatefulWidget {
  const _AnimatedFileList({super.key, required this.controller});

  final ConvertController controller;

  @override
  State<_AnimatedFileList> createState() => _AnimatedFileListState();
}

class _AnimatedFileListState extends State<_AnimatedFileList> {
  static const Duration _insertDuration = Duration(milliseconds: 280);
  static const Duration _removeDuration = Duration(milliseconds: 220);

  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<String> _items = <String>[];

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.controller.files);
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final List<String> next = widget.controller.files;

    // 1. 先处理被移除的条目（从后往前，避免下标错位）
    for (int index = _items.length - 1; index >= 0; index--) {
      final String path = _items[index];
      if (next.contains(path)) continue;

      _items.removeAt(index);
      _listKey.currentState?.removeItem(
        index,
        (BuildContext context, Animation<double> animation) =>
            _buildAnimatedRow(path, animation, removing: true),
        duration: _removeDuration,
      );
    }

    // 2. 再处理新增的条目（列表只追加，按位置插入即可）
    for (int index = 0; index < next.length; index++) {
      if (index < _items.length && _items[index] == next[index]) continue;
      if (_items.contains(next[index])) continue;

      _items.insert(index, next[index]);
      _listKey.currentState?.insertItem(index, duration: _insertDuration);
    }

    // 3. 兜底：出现意料之外的顺序变化时整体重建，保证状态一致
    if (!listEquals(_items, next)) {
      setState(() {
        _items
          ..clear()
          ..addAll(next);
        _listKey = GlobalKey<AnimatedListState>();
      });
    }
  }

  Widget _buildAnimatedRow(
    String path,
    Animation<double> animation, {
    required bool removing,
  }) {
    final CurvedAnimation curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: _FileRow(
          path: path,
          onRemove: () => widget.controller.removeFile(path),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 190),
      child: Scrollbar(
        child: AnimatedList(
          key: _listKey,
          shrinkWrap: true,
          initialItemCount: _items.length,
          padding: const EdgeInsets.symmetric(vertical: 2),
          itemBuilder:
              (BuildContext context, int index, Animation<double> animation) {
                if (index >= _items.length) return const SizedBox.shrink();
                return _buildAnimatedRow(
                  _items[index],
                  animation,
                  removing: false,
                );
              },
        ),
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                  小部件                                     */
/* -------------------------------------------------------------------------- */

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            size: 15,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: path,
              child: Text(
                baseNameOf(path),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 16),
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.item});

  final ConvertItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: item.ok
            ? Colors.white.withValues(alpha: 0.7)
            : theme.colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              baseNameOf(item.sourcePath),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_right_alt_rounded,
              size: 16,
              color: Color(0xFF9AA7BC),
            ),
          ),
          Expanded(
            child: Text(
              item.targetPath.isEmpty
                  ? item.message
                  : baseNameOf(item.targetPath),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: item.ok
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
          ),
          if (item.ok)
            Text(
              item.message,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }
}
