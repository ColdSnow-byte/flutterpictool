import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../rust/api/assets.dart';
import '../state/asset_page_controller.dart';
import '../state/convert_controller.dart';
import '../state/drop_zone.dart';
import '../theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/asset_slot_card.dart';
import 'widgets/convert_panel.dart';
import 'widgets/fade_slide_in.dart';
import 'widgets/gradient_button.dart';
import 'widgets/icon_replace_panel.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/project_path_field.dart';
import 'widgets/result_dialog.dart';
import 'widgets/section_card.dart';

enum _Tab { assets, convert }

class _TabSpec {
  const _TabSpec(this.tab, this.label, this.icon, this.description);

  final _Tab tab;
  final String label;
  final IconData icon;
  final String description;
}

const List<_TabSpec> _tabs = <_TabSpec>[
  _TabSpec(
    _Tab.assets,
    '素材配置',
    Icons.tune_rounded,
    '选择工程目录与三张图片，一键替换登录页 / 加载页 / 闪屏图，并同步替换应用图标（图片与文件夹均可直接拖入）',
  ),
  _TabSpec(
    _Tab.convert,
    '图片格式转换',
    Icons.swap_horiz_rounded,
    '批量转换图片格式，可指定目标宽高并按比例缩放，输出到原文件所在目录',
  ),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DropZoneRegistry _dropZones = DropZoneRegistry();
  final ScrollController _scrollController = ScrollController();

  late final AssetPageController _assets;
  late final ConvertController _convert;
  late final Listenable _allState;

  _Tab _tab = _Tab.assets;

  /// 页签序号与切换方向，用于让内容朝正确方向滑入滑出
  int _tabIndex = 0;
  bool _forward = true;

  /// 结果弹窗打开期间暂停接收拖放，避免误操作
  bool _dialogOpen = false;

  String get _tabKey => _tab == _Tab.assets ? 'assets' : 'convert';

  @override
  void initState() {
    super.initState();
    _assets = AssetPageController(onError: _showError);
    _convert = ConvertController(onError: _showError);
    _allState = Listenable.merge(<Listenable>[_assets, _convert, _dropZones]);
    _assets.initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _assets.dispose();
    _convert.dispose();
    _dropZones.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  Future<void> _handleDrop(String? zoneId, List<String> paths) async {
    if (zoneId == null || paths.isEmpty) return;
    if (zoneId == DropZoneIds.convert) {
      await _convert.handleDrop(paths);
      return;
    }
    await _assets.handleDrop(zoneId, paths);
  }

  Future<void> _applyAll() async {
    final ApplyResult? result = await _assets.applyAll();
    if (result == null || !mounted) return;

    setState(() => _dialogOpen = true);
    try {
      await showApplyResultDialog(context, result);
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  void _selectTab(_Tab tab) {
    if (tab == _tab) return;
    final int nextIndex = _tabs.indexWhere((_TabSpec item) => item.tab == tab);
    setState(() {
      _forward = nextIndex >= _tabIndex;
      _tabIndex = nextIndex;
      _tab = tab;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropZoneScope(
      registry: _dropZones,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: AmbientBackground()),
            Positioned.fill(
              child: DropTarget(
                enable: !_dialogOpen,
                onDragEntered: (DropEventDetails details) =>
                    _dropZones.hovered = _dropZones.hitTest(
                      details.globalPosition,
                    ),
                onDragUpdated: (DropEventDetails details) =>
                    _dropZones.hovered = _dropZones.hitTest(
                      details.globalPosition,
                    ),
                onDragExited: (_) => _dropZones.hovered = null,
                onDragDone: (DropDoneDetails details) {
                  final String? zone = _dropZones.hitTest(
                    details.globalPosition,
                  );
                  _dropZones.hovered = null;
                  final List<String> paths = details.files
                      .map((DropItem file) => file.path)
                      .whereType<String>()
                      .toList();
                  _handleDrop(zone, paths);
                },
                child: SafeArea(
                  child: ListenableBuilder(
                    listenable: _allState,
                    builder: (BuildContext context, Widget? child) => Column(
                      children: <Widget>[
                        _buildHeader(context),
                        Expanded(child: _buildContent(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ------------------------------ 顶部栏 ------------------------------ */

  Widget _buildHeader(BuildContext context) {
    final _TabSpec active = _tabs.firstWhere(
      (_TabSpec item) => item.tab == _tab,
    );

    return LiquidGlass(
      // 顶栏是全宽的，用直角；不画高光边框，让玻璃只体现在折射与底色上
      borderRadius: BorderRadius.zero,
      tint: const Color(0x78FFFFFF),
      refraction: 14,
      highlight: 0.3,
      showRim: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget title = _buildTitle(context, active);
                final Widget tabs = _buildTabs(context);
                final Widget actions = _buildActions(context);

                if (constraints.maxWidth >= 940) {
                  return Row(
                    children: <Widget>[
                      Expanded(child: title),
                      tabs,
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    title,
                    const SizedBox(height: 10),
                    Row(children: <Widget>[tabs, const Spacer(), actions]),
                  ],
                );
              },
            ),
          ),
          Container(
            height: 1,
            color: const Color(0xFFE2E9F5).withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context, _TabSpec active) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.auto_fix_high_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '图片处理工具',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // 切换页签时说明文案淡入淡出，而不是瞬间替换
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.28),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
          child: Text(
            active.description,
            key: ValueKey<String>(active.label),
            maxLines: 2,
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

  Widget _buildTabs(BuildContext context) {
    return SegmentedButton<_Tab>(
      segments: _tabs
          .map(
            (_TabSpec item) => ButtonSegment<_Tab>(
              value: item.tab,
              label: Text(item.label),
              icon: Icon(item.icon, size: 16),
            ),
          )
          .toList(),
      selected: <_Tab>{_tab},
      showSelectedIcon: false,
      onSelectionChanged: (Set<_Tab> selection) => _selectTab(selection.first),
    );
  }

  Widget _buildActions(BuildContext context) {
    final bool showReset =
        _assets.selectedCount > 0 || _assets.iconSource != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
          child: showReset
              ? Padding(
                  key: const ValueKey<String>('reset'),
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinedButton.icon(
                    onPressed: _assets.reset,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重置'),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('no-reset')),
        ),
        GradientButton(
          onPressed: _assets.canApplyAssets || _assets.canApplyIcons
              ? _applyAll
              : null,
          loading: _assets.applying,
          label: _assets.applying ? '替换中…' : '确认替换',
          icon: Icons.cloud_upload_rounded,
          count: _assets.totalCount,
        ),
      ],
    );
  }

  /* ------------------------------ 页面内容 ------------------------------ */

  Widget _buildContent(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder:
              (Widget? currentChild, List<Widget> previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: <Widget>[...previousChildren, ?currentChild],
              ),
          transitionBuilder: _buildTabTransition,
          child: _tab == _Tab.assets
              ? _assetPage(context)
              : _convertPage(context),
        ),
      ),
    );
  }

  /// 页签切换：新页从切换方向滑入，旧页朝反方向滑出并淡出
  Widget _buildTabTransition(Widget child, Animation<double> animation) {
    final bool incoming = child.key == ValueKey<String>(_tabKey);
    final double sign = _forward ? 1 : -1;
    final double shift =
        (incoming ? sign : -sign) * 0.035 * (1 - animation.value);

    return FadeTransition(
      opacity: animation,
      child: FractionalTranslation(translation: Offset(shift, 0), child: child),
    );
  }

  Widget _assetPage(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const Duration step = Duration(milliseconds: 70);

    return Column(
      key: const ValueKey<String>('assets'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FadeSlideIn(
          child: SectionCard(
            step: '1',
            title: '选择项目工程目录',
            subtitle: '支持手动输入、选择目录，或把工程文件夹直接拖进来',
            child: ProjectPathField(controller: _assets),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: step,
          child: SectionCard(
            step: '2',
            title: '选择三张图片',
            subtitle:
                '已选 ${_assets.selectedCount} / ${_assets.slots.length}，支持拖入图片或整个文件夹',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _slotGrid(context),
                const SizedBox(height: 12),
                _replaceOptions(context),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: step * 2,
          child: SectionCard(
            step: '3',
            title: '应用图标替换',
            subtitle: '按各 drawable 目录原有像素逐个缩放并保留源图扩展名，由右上角「确认替换」统一执行',
            child: IconReplacePanel(controller: _assets),
          ),
        ),
        const SizedBox(height: 10),
        FadeSlideIn(
          delay: step * 3,
          offset: 10,
          child: Text(
            '提示：素材替换与图标替换会在一次操作中串行执行，完成后统一展示结果。',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _slotGrid(BuildContext context) {
    final List<SlotDefinition> slots = _assets.slots;
    if (slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 12;
        final int columns = constraints.maxWidth >= 1080
            ? 3
            : (constraints.maxWidth >= 720 ? 2 : 1);
        final double itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (int index = 0; index < slots.length; index++)
              SizedBox(
                width: itemWidth,
                child: AssetSlotCard(
                  key: ValueKey<String>(slots[index].key),
                  slot: slots[index],
                  controller: _assets,
                  index: index,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _replaceOptions(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Wrap(
      spacing: 24,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Switch(
              value: _assets.keepExtension,
              onChanged: (bool value) => _assets.keepExtension = value,
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '关闭后按工程要求写入不带扩展名的文件（如 login_bg）',
              child: Text(
                '保留源图扩展名',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Switch(
              value: _assets.backupOriginal,
              onChanged: (bool value) => _assets.backupOriginal = value,
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '替换前把原文件另存为同名 *.bak',
              child: Text(
                '替换前备份原文件',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _convertPage(BuildContext context) {
    return Column(
      key: const ValueKey<String>('convert'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FadeSlideIn(
          child: SectionCard(
            step: '1',
            title: '图片格式转换',
            subtitle: '支持拖入多个文件或整个文件夹，输出到原文件所在目录',
            child: ConvertPanel(controller: _convert),
          ),
        ),
      ],
    );
  }
}
