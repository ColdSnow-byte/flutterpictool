import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterpictool/src/theme/app_theme.dart';
import 'package:flutterpictool/src/ui/widgets/fade_slide_in.dart';
import 'package:flutterpictool/src/ui/widgets/image_preview_box.dart';
import 'package:flutterpictool/src/ui/widgets/image_viewer.dart';

/// 1×1 的透明 PNG，足够驱动 Image.memory 与 Hero 飞行
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('点击预览框通过 Hero 打开全屏查看器，再点击关闭', (WidgetTester tester) async {
    const String tag = 'slot-current-login';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: Builder(
                builder: (BuildContext context) => ImagePreviewBox(
                  bytes: _pngBytes,
                  placeholder: '暂无图片',
                  heroTag: tag,
                  onTap: () => showImageViewer(
                    context,
                    heroTag: tag,
                    thumbnail: _pngBytes,
                    title: '登录页背景 · 项目现有',
                    subtitle: r'E:\demo\login_bg.png',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Hero), findsOneWidget);
    expect(find.text('登录页背景 · 项目现有'), findsNothing);

    // 打开查看器：Hero 从原位飞到全屏
    await tester.tap(find.byType(ImagePreviewBox));
    await tester.pumpAndSettle();

    // 打开后源页与查看器各有一个 Hero（分属两条路由，Hero 才能在它们之间飞行）；
    // 若同名 Hero 出现在同一条路由上，pumpAndSettle 会直接抛错。
    expect(find.text('登录页背景 · 项目现有'), findsOneWidget);
    expect(find.text(r'E:\demo\login_bg.png'), findsOneWidget);
    expect(find.byType(Hero), findsNWidgets(2));

    // 点击空白处关闭
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('登录页背景 · 项目现有'), findsNothing);
    expect(find.byType(Hero), findsOneWidget);
  });

  testWidgets('错峰入场动画可以正常跑完并落定', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (int index = 0; index < 4; index++)
                  FadeSlideIn(
                    delay: staggerDelay(index),
                    child: Text('内容 $index'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    for (int index = 0; index < 4; index++) {
      expect(find.text('内容 $index'), findsOneWidget);
    }
  });
}
