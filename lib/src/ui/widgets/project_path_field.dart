import 'package:flutter/material.dart';

import '../../rust/api/assets.dart';
import '../../state/asset_page_controller.dart';
import '../../state/drop_zone.dart';

/// 工程目录输入区：支持手动输入、选择目录，以及把工程文件夹直接拖进来。
class ProjectPathField extends StatelessWidget {
  const ProjectPathField({super.key, required this.controller});

  final AssetPageController controller;

  @override
  Widget build(BuildContext context) {
    return DropZone(
      id: DropZoneIds.project,
      builder: (BuildContext context, bool hovered) => _build(context, hovered),
    );
  }

  Widget _build(BuildContext context, bool hovered) {
    final ThemeData theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hovered ? theme.colorScheme.primary : Colors.transparent,
          width: 1.4,
        ),
        color: hovered
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        boxShadow: hovered
            ? <BoxShadow>[
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.22),
                  blurRadius: 22,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller.projectDirController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.folder_outlined, size: 18),
                    hintText: r'例如 E:\wb01_cn\sdk\android\avx，也可把工程文件夹拖到这里',
                    prefixIconConstraints: BoxConstraints(minWidth: 40),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: controller.pickProjectDir,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('选择目录'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatusRow(controller: controller, hovered: hovered),
        ],
      ),
    );
  }
}

/// 扫描状态标签 + 拖放提示
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.controller, required this.hovered});

  final AssetPageController controller;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final (Color, IconData, String) status = _resolve(theme);
    final Color color = status.$1;

    return Row(
      children: <Widget>[
        if (controller.inspecting)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            key: ValueKey<String>(status.$3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(status.$2, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  status.$3,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hovered) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            '松开即可设为项目目录',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  (Color, IconData, String) _resolve(ThemeData theme) {
    if (controller.projectDir.isEmpty) {
      return (theme.colorScheme.outline, Icons.info_outline, '未选择项目目录');
    }
    final ProjectInspectResult? inspect = controller.inspect;
    if (controller.inspecting || inspect == null) {
      return (theme.colorScheme.outline, Icons.hourglass_empty, '检测中…');
    }
    if (!inspect.exists) {
      return (theme.colorScheme.error, Icons.error_outline, '目录不存在');
    }
    if (!inspect.structureOk) {
      return (
        const Color(0xFFB7791F),
        Icons.warning_amber_rounded,
        inspect.message,
      );
    }
    return (const Color(0xFF1F9D63), Icons.verified_outlined, inspect.message);
  }
}
