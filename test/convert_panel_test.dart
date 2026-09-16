import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterpictool/src/state/convert_controller.dart';
import 'package:flutterpictool/src/state/drop_zone.dart';
import 'package:flutterpictool/src/theme/app_theme.dart';
import 'package:flutterpictool/src/ui/widgets/convert_panel.dart';

/// 还原真实页面结构：DropZoneScope + Scaffold + 外层 Scrollbar/SingleChildScrollView
Widget buildPage({required ConvertController controller}) {
  final ScrollController scrollController = ScrollController();
  final DropZoneRegistry registry = DropZoneRegistry();

  return MaterialApp(
    theme: buildAppTheme(),
    home: DropZoneScope(
      registry: registry,
      child: Scaffold(
        body: Scrollbar(
          controller: scrollController,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
            // 真实页面由 ListenableBuilder 包裹，控制器变化时整页重建
            child: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? child) =>
                  ConvertPanel(controller: controller),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('转换面板可以正常渲染', (WidgetTester tester) async {
    final ConvertController controller = ConvertController();

    await tester.pumpWidget(buildPage(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('输入文件'), findsOneWidget);
    expect(find.text('输出设置'), findsOneWidget);
    expect(find.text('开始转换'), findsOneWidget);
    expect(find.text('还没有待转换的图片'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('文件列表的增删会带动画地同步', (WidgetTester tester) async {
    final ConvertController controller = ConvertController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildPage(controller: controller));
    await tester.pumpAndSettle();

    // 新增：空态切到列表
    controller.addFiles(<String>[r'E:\demo\a.png', r'E:\demo\b.png']);
    await tester.pumpAndSettle();

    expect(find.text('还没有待转换的图片'), findsNothing);
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);

    // 追加
    controller.addFiles(<String>[r'E:\demo\c.png']);
    await tester.pumpAndSettle();
    expect(find.text('c.png'), findsOneWidget);

    // 移除中间一项，剩余的应保持正确
    controller.removeFile(r'E:\demo\b.png');
    await tester.pumpAndSettle();
    expect(find.text('b.png'), findsNothing);
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('c.png'), findsOneWidget);

    // 清空：回到空态
    controller.clearFiles();
    await tester.pumpAndSettle();
    expect(find.text('a.png'), findsNothing);
    expect(find.text('c.png'), findsNothing);
    expect(find.text('还没有待转换的图片'), findsOneWidget);
  });
}
