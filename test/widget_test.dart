import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterpictool/src/theme/app_theme.dart';
import 'package:flutterpictool/src/ui/widgets/gradient_button.dart';
import 'package:flutterpictool/src/ui/widgets/section_card.dart';

void main() {
  testWidgets('分区卡片展示步骤徽标与标题', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SectionCard(
            step: '1',
            title: '选择项目工程目录',
            subtitle: '说明文案',
            child: Text('内容'),
          ),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('选择项目工程目录'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('主按钮在禁用状态下不可点击', (WidgetTester tester) async {
    int taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: GradientButton(
              onPressed: null,
              label: '确认替换',
              icon: Icons.cloud_upload_rounded,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('确认替换'));
    await tester.pump();

    expect(taps, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: GradientButton(
              onPressed: () => taps++,
              label: '确认替换',
              icon: Icons.cloud_upload_rounded,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('确认替换'));
    await tester.pump();

    expect(taps, 1);
  });
}
